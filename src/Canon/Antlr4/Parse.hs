-- | The parser interprets parser rules over tokens with memoisation, precedence climbing for left
-- recursion, and one tree per rule and span, because the alternatives were exponential.
-- ref:DEC-precedence-climbing ref:DEC-one-tree-per-span ref:DEC-parser-generation ref:DEC-parser-memory
module Canon.Antlr4.Parse
  ( ParseTree (..)
  , ParseFailure (..)
  , ParseError (..)
  , PredicateHook
  , parseTokens
  , parseTokensWith
  , parseVisibleTokens
  , parseVisibleTokensWith
  , Recognized
  , Prepared
  , Tokens
  , prepareParser
  , preparedTokens
  , runPrepared
  , tokensList
  , tokenCount
  , tokenAt
  , removeTokens
  , sliceTokens
  , renderParseError
  , renderParseTree
  , renderParseTreeLazy
  , hPutParseTree
  , treeRuleNodes
  , treeTokens
  ) where

import Canon.Antlr4.Escape (decodeStringLiteral)
import Canon.Antlr4.Query (allRules, undefinedRuleReferences)
import Canon.Antlr4.RuleGraph (leftCornerGraph, stronglyConnectedRuleGroups)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token
import Data.Foldable (toList)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.IntMap.Lazy as LIntMap
import qualified Data.Map.Lazy as LMap
import Data.Traversable (mapAccumL)
import qualified Data.IntSet as IntSet
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Builder as TB
import qualified Data.Text.Lazy.IO as TLIO
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import System.IO (Handle, hGetEncoding)
import qualified Data.Vector as BV
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Unboxed as V
import System.IO.Unsafe (unsafePerformIO)
import Control.Exception (evaluate)
import Control.Monad (forM_, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import qualified Data.Vector.Unboxed.Mutable as UMV

-- | A tree of rule nodes, tokens, and labeled subtrees; labels are kept because the extraction rules
-- are labels. ref:DEC-grammar-carries-extraction-rules
data ParseTree
  = RuleNode Name Int [ParseTree]
  | TokenNode Token
  | Labeled Text ParseTree
  deriving (Eq, Show)

-- | Where a parse failed and what it expected, for the message a user sees.
data ParseFailure = ParseFailure
  { failureIndex :: Int
  , failureToken :: Maybe Token
  }
  deriving (Eq, Show)

-- | A parse failure or a grammar the parser cannot run.
data ParseError
  = ParseUnknownStartRule Name
  | ParseUndefinedRules [(Name, Name)]
  | ParseNoParse ParseFailure
  deriving (Eq, Show)

-- | Renders a parse failure with its token and position.
renderParseError :: ParseError -> Text
renderParseError e = case e of
  ParseUnknownStartRule n -> "unknown start rule " <> nameText n
  ParseUndefinedRules refs -> "undefined rule references: " <> T.intercalate ", " [nameText r <> " -> " <> nameText t | (r, t) <- refs]
  ParseNoParse (ParseFailure i tok) -> case tok of
    Just t ->
      let Position line column = tokenPosition t
       in T.concat [T.pack (show line), ":", T.pack (show column), ": no parse at token ", renderToken t]
    Nothing -> "no parse at token index " <> T.pack (show i)

-- | Renders a tree for the parse subcommand and for debugging.
renderParseTree :: ParseTree -> Text
renderParseTree = TL.toStrict . renderParseTreeLazy

-- | Renders a tree as lazy text, made as it is written, so a long file's rendering, which runs to
-- hundreds of megabytes for a generated file of 30,000 lines, is never held whole.
-- ref:DEC-parser-memory
renderParseTreeLazy :: ParseTree -> TL.Text
renderParseTreeLazy tree = TB.toLazyText (go 0 tree)
  where
    go :: Int -> ParseTree -> TB.Builder
    go depth t = case t of
      TokenNode tok -> indent depth <> TB.fromText (nameText (tokenType tok)) <> " " <> TB.fromString (show (tokenText tok))
      Labeled label inner -> indent depth <> TB.fromText label <> "=\n" <> go depth inner
      RuleNode name _ children -> indent depth <> "(" <> TB.fromText (nameText name) <> foldMap (\c -> "\n" <> go (depth + 1) c) children <> "\n" <> indent depth <> ")"
    indent depth = TB.fromText (T.replicate depth "  ")

-- | Writes a tree's rendering and a newline to a handle, as UTF-8 bytes made as they are written
-- when the handle writes UTF-8, since encoding the text a character at a time took a quarter of the
-- allocation of parsing a long file. ref:DEC-parser-memory
hPutParseTree :: Handle -> ParseTree -> IO ()
hPutParseTree h tree = do
  encoding <- hGetEncoding h
  case encoding of
    Just e | show e == "UTF-8" -> BB.hPutBuilder h (go 0 tree <> BB.char7 '\n')
    _ -> TLIO.hPutStrLn h (renderParseTreeLazy tree)
  where
    go :: Int -> ParseTree -> BB.Builder
    go depth t = case t of
      TokenNode tok -> indent depth <> TE.encodeUtf8Builder (nameText (tokenType tok)) <> BB.char7 ' ' <> BB.stringUtf8 (show (tokenText tok))
      Labeled label inner -> indent depth <> TE.encodeUtf8Builder label <> BB.string7 "=\n" <> go depth inner
      RuleNode name _ children -> indent depth <> BB.char7 '(' <> TE.encodeUtf8Builder (nameText name) <> foldMap (\c -> BB.char7 '\n' <> go (depth + 1) c) children <> BB.char7 '\n' <> indent depth <> BB.char7 ')'
    indent depth = BB.byteString (BS.replicate (2 * depth) 32)

-- | Finds every node of a rule, looking through labels.
treeRuleNodes :: Name -> ParseTree -> [ParseTree]
treeRuleNodes wanted tree = case tree of
  TokenNode _ -> []
  Labeled _ inner -> treeRuleNodes wanted inner
  RuleNode name _ children -> [tree | name == wanted] ++ concatMap (treeRuleNodes wanted) children

-- | The tokens of a subtree in order, looking through labels.
treeTokens :: ParseTree -> [Token]
treeTokens tree = case tree of
  TokenNode t -> [t]
  Labeled _ inner -> treeTokens inner
  RuleNode _ _ children -> concatMap treeTokens children

type Children = [ParseTree] -> [ParseTree]

-- | What the recognizer keeps of a rule at a position: the ends it reaches there, in preference
-- order, and the furthest index it reached. No tree is kept: the trees are built afterwards, along
-- the one parse that is returned, so a long file's table holds a few words per entry rather than
-- every tree of every rule tried at every token. Most entries reach one end or none, so those take
-- no vector, and every failure that reached no further than a position shares one entry.
-- ref:DEC-parser-memory ref:DEC-one-tree-per-span
data Entry
  = Failed {-# UNPACK #-} !Int
  | Ended {-# UNPACK #-} !Int {-# UNPACK #-} !Int
  | Ends !(V.Vector Int) {-# UNPACK #-} !Int

toEntry :: ([Int], Int) -> Entry
toEntry (es, f) = case es of
  [] -> Failed f
  [e] -> Ended e f
  _ -> Ends (V.fromList es) f

entryEnds :: Entry -> [Int]
entryEnds entry = case entry of
  Failed _ -> []
  Ended e _ -> [e]
  Ends es _ -> V.toList es

entryFurthest :: Entry -> Int
entryFurthest entry = case entry of
  Failed f -> f
  Ended _ f -> f
  Ends _ f -> f

-- | A recognizer's step: the ends reached from a position, in preference order, and the furthest
-- index reached.
type Step = Int -> ([Int], Int)

-- | A tree builder's step: the children read from a position to each end, in preference order.
type Build = Int -> [(Children, Int)]

data FirstSet = FirstSet
  { firstTypes :: Set Name
  , firstTexts :: Set Text
  , firstAny :: Bool
  }

emptyFirst :: FirstSet
emptyFirst = FirstSet Set.empty Set.empty False

unionFirst :: FirstSet -> FirstSet -> FirstSet
unionFirst (FirstSet a b c) (FirstSet x y z) = FirstSet (Set.union a x) (Set.union b y) (c || z)

canStart :: FirstSet -> Token -> Bool
canStart fs tok = firstAny fs || Set.member (tokenType tok) (firstTypes fs) || Set.member (tokenText tok) (firstTexts fs)

data CompiledAtom
  = CompiledTerminal (Token -> Bool)
  | CompiledRuleRef Int
  | CompiledNotSet [Token -> Bool]
  | CompiledAny

data CompiledElement
  = CompiledAtomElement CompiledAtom (Maybe EbnfSuffix) (Maybe Text) Int
  | CompiledBlockElement [CompiledAlternative] (Maybe EbnfSuffix) (Maybe Text) Int
  | CompiledActionElement
  | CompiledPredicateElement Text

-- | An alternative with its first set, and whether its first set admits each class of token, made
-- when first asked, so that the check made at every alternative tried is an index rather than a
-- search of sets of names and texts.
data CompiledAlternative = CompiledAlternative
  { alternativeFirst :: FirstSet
  , alternativeNullable :: Bool
  , alternativeAdmits :: V.Vector Bool
  , compiledAlternativeElements :: [CompiledElement]
  }

data Shape
  = ShapePrimary CompiledAlternative
  | ShapePrefix CompiledAlternative
  | ShapeBinary Bool CompiledAlternative
  | ShapeSuffix CompiledAlternative

data CompiledRule = CompiledRule
  { ruleName' :: Name
  , ruleAlternatives :: [CompiledAlternative]
  , ruleShapes :: Maybe [(Int, Shape, Int)]
  }

isExtension :: Shape -> Bool
isExtension sh = case sh of
  ShapeBinary _ _ -> True
  ShapeSuffix _ -> True
  _ -> False

-- | A semantic predicate as a parser base class would answer it: given the predicate's text, the
-- visible tokens, the index where the rule invoking it started, and the index the parse has reached,
-- whether the parse may go on. A predicate no base class knows holds. ref:DEC-parser-predicates
type PredicateHook = Text -> BV.Vector Token -> Int -> Int -> Bool

-- | Parses all tokens from a start rule, with every semantic predicate holding.
parseTokens :: Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseTokens grammar = parseTokensWith (\_ _ _ _ -> True) grammar

-- | Parses all tokens from a start rule, asking the hook about each semantic predicate.
parseTokensWith :: PredicateHook -> Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseTokensWith hook grammar start = parseVisibleTokensWith hook grammar start . filter ((== defaultChannelName) . tokenChannel)

-- | Parses only the tokens on the default channel, which is what a grammar with a hidden channel
-- expects.
parseVisibleTokens :: Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseVisibleTokens = parseVisibleTokensWith (\_ _ _ _ -> True)

-- | Parses the visible tokens with a predicate hook, in two passes. The recognizer finds, for each
-- rule asked for at each position, the ends it reaches in preference order and the furthest index
-- reached, which decides whether the file parses and where a failure is reported. The builder then
-- reads the one parse returned: it evaluates a rule at a position again only where that rule is a
-- node of the returned tree, reading the ends of every rule and loop below it from the recognizer's
-- table, and picks for each end the first child sequence that reaches it, which is the tree one
-- tree per end kept, built here once rather than for every rule tried at every token. The memo
-- table holds an entry only for the rules that can start at each token, by their first sets, so its
-- size follows what a token can begin rather than the number of rules: a rule that cannot start at a
-- token fails there without an entry. A failing parse runs the recognizer only.
-- ref:DEC-parser-memory ref:DEC-one-tree-per-span ref:DEC-loop-memo
parseVisibleTokensWith :: PredicateHook -> Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseVisibleTokensWith hook grammar start visible = case preparedTokens prepared visible of
  Just tokens -> fst (runPrepared prepared Nothing tokens)
  Nothing -> error "canon: a token list has a token its own preparation did not classify"
  where
    prepared = prepareParser hook grammar start visible

-- | The recognizer's table of a parse, handed to one later parse of the same tokens with some
-- removed, which takes it over. ref:DEC-stray-comments
newtype Recognized = Recognized Memo

-- | Visible tokens with the class of each, as a prepared parser classes them, and class 0 past the
-- last. ref:DEC-parser-memory
data Tokens = Tokens (BV.Vector Token) (V.Vector Int)

-- | The tokens in order. ref:DEC-stray-comments
tokensList :: Tokens -> [Token]
tokensList (Tokens toks _) = BV.toList toks

-- | How many tokens there are. ref:DEC-stray-comments
tokenCount :: Tokens -> Int
tokenCount (Tokens toks _) = BV.length toks

-- | The token at an index. ref:DEC-stray-comments
tokenAt :: Tokens -> Int -> Maybe Token
tokenAt (Tokens toks _) i = toks BV.!? i

-- | The tokens without those from the first index up to the second, as a dropped stray comment
-- leaves them. ref:DEC-stray-comments
removeTokens :: Int -> Int -> Tokens -> Tokens
removeTokens from to (Tokens toks classes) =
  Tokens (BV.take from toks <> BV.drop to toks) (V.take from classes <> V.drop to classes)

-- | The given number of tokens from an index, where a stray comment is read. ref:DEC-stray-comments
sliceTokens :: Int -> Int -> Tokens -> Tokens
sliceTokens from len (Tokens toks classes) = Tokens (BV.slice from len toks) (V.snoc (V.slice from len classes) 0)

-- | A parser grammar compiled once for a list of tokens and any list made of the same tokens: its
-- rules, their first sets, and the classes of the tokens, which a parse that removes a stray comment
-- and tries again would otherwise make again for each comment. ref:DEC-stray-comments
data Prepared = Prepared
  { preparedClass :: Token -> Maybe Int
  , preparedRun :: Maybe (Recognized, Int) -> Tokens -> (Either ParseError ParseTree, Recognized)
  }

-- | Tokens with the classes a prepared parser gives them, if it knows every token's class: it knows
-- those of the list it was prepared for. ref:DEC-stray-comments
preparedTokens :: Prepared -> [Token] -> Maybe Tokens
preparedTokens prepared toks = do
  classes <- mapM (preparedClass prepared) toks
  pure (Tokens (BV.fromList toks) (V.fromList (classes ++ [0])))

-- | How far past the token a predicate is asked at it may read: the token after it. A predicate
-- also looks past doc comment tokens, as the JavaScript and TypeScript ones do, which a removed
-- stray comment is. ref:DEC-stray-comments ref:DEC-parser-predicates
predicateReach :: Int
predicateReach = 2

-- | Parses tokens with a prepared parser and returns the recognizer's table with the result. Given
-- an earlier parse's table and an index, where the tokens before the index are the earlier
-- parse's, the parse takes over that table and keeps its entries that reached no closer than
-- predicateReach tokens to the index: an entry is what the tokens it read make it, so those are the
-- entries this parse would make, and only the entries that read the changed part are made again. A
-- parse that removes a stray comment and tries again then costs the rules around the comment and
-- the rest of the file rather than the whole file. ref:DEC-stray-comments ref:DEC-parser-memory
runPrepared :: Prepared -> Maybe (Recognized, Int) -> Tokens -> (Either ParseError ParseTree, Recognized)
runPrepared = preparedRun

-- | Compiles a parser grammar for a start rule and a list of visible tokens. ref:DEC-parser-memory
-- ref:DEC-stray-comments
prepareParser :: PredicateHook -> Grammar ann -> Name -> [Token] -> Prepared
prepareParser hook grammar start visible = Prepared (\tok -> Map.lookup (classKey tok) classIndex) run
  where
    stripped = fmap (const ()) grammar
    sourceRules = [p | RuleParser p <- allRules stripped]
    ruleIndex = Map.fromList (zip (map parserRuleName sourceRules) [0 ..])
    startIndex = ruleIndex Map.! start
    undefined' = [(r, t) | (r, t) <- undefinedRuleReferences stripped, Map.member r ruleIndex]
    ruleCount = length sourceRules

    firstTable = computeFirst sourceRules ruleIndex
    (_, numbered) = numberLoops (map (compileRule admitsOf ruleIndex firstTable) sourceRules)
    compiled = BV.fromList numbered
    loops = BV.fromList (concatMap ruleLoops numbered)
    -- The memo key of a rule at a precedence level: a left-recursive rule has an entry per level.
    precStride = 2 + maximum (0 : [length shapes | r <- numbered, Just shapes <- [ruleShapes r]])

    -- Tokens fall into classes by type, and by text where a parser rule or alternative names a
    -- literal, and each class has its candidate rules: those nullable or whose first set admits the
    -- token. Past the last token is class 0, where only nullable rules are candidates.
    -- The texts are read from a first compilation, whose alternatives' first sets are what the
    -- classes must tell apart.
    literalTexts = Set.unions (map firstTexts (concatMap compiledFirstSets (map (compileRule (const V.empty) ruleIndex firstTable) sourceRules)))
    classKey tok = (tokenType tok, if Set.member (tokenText tok) literalTexts then Just (tokenText tok) else Nothing)
    classIndex = Map.fromList (zip (Set.toList (Set.fromList (map classKey visible))) [1 ..])
    classRepresentative = Map.fromList [(classIndex Map.! classKey tok, tok) | tok <- visible]
    candidatesOf c = [r | r <- [0 .. ruleCount - 1], admits (firstTable BV.! r) (Map.lookup c classRepresentative)]
    admits (fs, nullable) representative = nullable || maybe False (canStart fs) representative
    classCandidates :: BV.Vector (V.Vector Bool)
    classCandidates = BV.generate (Map.size classIndex + 1) (\c -> V.replicate ruleCount False V.// [(r, True) | r <- candidatesOf c])
    admitsOf fs = V.generate (Map.size classIndex + 1) (\c -> c > 0 && maybe False (canStart fs) (Map.lookup c classRepresentative))

    groups =
      [ map (ruleIndex Map.!) (NonEmpty.toList g)
      | g <- stronglyConnectedRuleGroups (leftCornerGraph stripped)
      , all (`Map.member` ruleIndex) (toList g)
      , not (any (\m -> hasShapes (ruleIndex Map.! m)) (NonEmpty.toList g))
      ]
    hasShapes i = maybe False (const True) (ruleShapes (compiled BV.! i))
    groupOf = Map.fromList [(m, members) | members <- groups, m <- members]

    headOf xs = case xs of
      (x : _) -> x
      [] -> error "empty group"

    run earlier (Tokens toks classOfPos) = (result, Recognized memo)
      where
        result
          | not (Map.member start ruleIndex) = Left (ParseUnknownStartRule start)
          | not (null undefined') = Left (ParseUndefinedRules undefined')
          | n `elem` entryEnds startEntry = Right (buildTree startIndex 0 0 n)
          | otherwise = Left (ParseNoParse (ParseFailure furthest (toks BV.!? furthest)))
        n = BV.length toks
        startEntry = lookupR startIndex 0 0
        furthest = entryFurthest startEntry
        admitsAt alt p = alternativeNullable alt || V.unsafeIndex (alternativeAdmits alt) (V.unsafeIndex classOfPos p)

        -- The recognizer. --------------------------------------------------------------------------

        -- One table holds the rules' entries and the loops' walks, a loop's key following every rule's.
        memo = case earlier of
          Nothing -> newMemo (n + 1)
          Just (Recognized table, cut) -> seededMemo table (cut - predicateReach) (n + 1)
        loopKey i = ruleCount * precStride + i

        lookupR r prec p
          | p > n = Failed p
          | not (classCandidates BV.! (classOfPos V.! p) V.! r) = Failed p
          | otherwise = memoised memo p (r * precStride + prec) (entryAt r prec p)

        entryAt r prec p = case ruleShapes (compiled BV.! r) of
          Nothing -> computeR r p
          Just shapes -> leftRecursiveR r shapes prec p

        entryOfR r p = lookupR r 0 p

        computeR r p = case Map.lookup r groupOf of
          Just members -> Map.findWithDefault (Failed p) r (BV.last (fixTable Map.! headOf members BV.! p))
          Nothing -> evalRuleR True entryOfR r p

        -- A left-recursive group without precedence shapes is read at a position by iterating its
        -- members to a fixpoint. Every iteration is kept, the first all failures, because a tree of an
        -- iteration holds the trees of the iteration before it, and the builder reads them so.
        fixTable :: Map Int (BV.Vector (BV.Vector (Map Int Entry)))
        fixTable = Map.fromList [(headOf members, BV.generate (n + 1) (fixpoint members)) | members <- groups]

        fixpoint members p = BV.fromList (reverse (go [initial] initial (0 :: Int)))
          where
            initial = Map.fromList [(m, Failed p) | m <- members]
            go iterations current k =
              let next = Map.fromList [(m, evalRuleR False (override current) m p) | m <- members]
               in if signature next == signature current || k > n - p + 1 then next : iterations else go (next : iterations) next (k + 1)
            signature = Map.map entryEnds
            override current r q
              | q == p, Just entry <- Map.lookup r current = entry
              | otherwise = entryOfR r q

        evalRuleR cached look r p =
          let evals = [evalAlternativeR cached look alt p | alt <- ruleAlternatives (compiled BV.! r)]
           in toEntry (nubEnds (concatMap fst evals), maximum (p : map snd evals))

        evalAlternativeR cached look alt p = evalAlternativeFromR cached p look alt p

        evalAlternativeFromR cached from look alt p
          | admitsAt alt p = evalElementsR cached from look (compiledAlternativeElements alt) p
          | otherwise = ([], p)

        evalElementsR cached from look elements = foldr (\e rest -> seqR (evalElementR cached from look e) rest) emptyR elements

        -- A loop outside a left-recursive group's fixpoint is read through its memo table, which holds
        -- the linear walk of the loop from each position it is entered at, so a loop re-entered at a
        -- position by another alternative is not walked again. ref:DEC-loop-memo ref:DEC-parser-memory
        repeatedR cached loop suffix m
          | cached && loop >= 0 = case suffix of
              Just (EbnfSuffix OneOrMore _) -> seqR m (loopR loop)
              _ -> loopR loop
          | otherwise = suffixedR suffix m

        evalElementR cached from look e = case e of
          CompiledAtomElement atom suffix _ loop -> repeatedR cached loop suffix (evalAtomR look atom)
          CompiledBlockElement alts suffix _ loop -> repeatedR cached loop suffix (altR [evalAlternativeFromR cached from look a | a <- alts])
          CompiledActionElement -> emptyR
          CompiledPredicateElement predicate -> \p -> if hook predicate toks from p then emptyR p else ([], p)

        evalAtomR look atom p = case atom of
          CompiledTerminal predicate -> terminal predicate
          CompiledRuleRef i -> let entry = look i p in (entryEnds entry, entryFurthest entry)
          CompiledNotSet predicates -> terminal (\tok -> not (isEofToken tok) && not (any ($ tok) predicates))
          CompiledAny -> terminal (not . isEofToken)
          where
            terminal predicate = case toks BV.!? p of
              Just tok | predicate tok -> ([p + 1], p + 1)
              _ -> ([], p)

        -- Each loop's walks, one per position it is entered at, in a table kept like the rules' memo:
        -- a map per position, holding only what was asked for. ref:DEC-loop-memo
        -- A loop whose element cannot start at a position ends where it starts without a walk or an
        -- entry, as most operator loops of an expression grammar do after each operand.
        loopR i p
          | p > n = ([], p)
          | not (innerCanStart (loopInner i) p) = ([p], p)
          | otherwise = let entry = loopEntryR i p in (entryEnds entry, entryFurthest entry)

        innerCanStart inner p = case inner of
          Right alts -> any (`admitsAt` p) alts
          Left atom -> case atom of
            CompiledRuleRef r -> classCandidates BV.! (classOfPos V.! p) V.! r
            CompiledTerminal predicate -> maybe False predicate (toks BV.!? p)
            CompiledNotSet predicates -> maybe False (\tok -> not (isEofToken tok) && not (any ($ tok) predicates)) (toks BV.!? p)
            CompiledAny -> maybe False (not . isEofToken) (toks BV.!? p)

        loopEntryR i p = memoised memo p (loopKey i) (toEntry (manyR (loopGreedy i) (innerR (loopInner i)) p))

        loopGreedy i = case loops BV.! i of
          (EbnfSuffix _ greediness, _) -> greediness /= NonGreedy
        loopInner i = snd (loops BV.! i)

        innerR inner = case inner of
          Left atom -> evalAtomR entryOfR atom
          Right alts -> altR [evalAlternativeR True entryOfR a | a <- alts]

        refR r prec q = let entry = lookupR r prec q in (entryEnds entry, entryFurthest entry)

        leftRecursiveR r shapes prec pos =
          let baseEvals = [step pos | (_, sh, pr) <- shapes, Just step <- [baseR r sh pr]]
              base = nubEnds (concatMap fst baseEvals)
              -- How a tree ending at a position can be extended is the same for every tree ending
              -- there, so the climb is memoised by position.
              paths = foldl' climbFrom IntMap.empty base
              climbed = nubEnds [e | q <- base, e <- fst (paths IntMap.! q)]
              climbFrom seen q
                | IntMap.member q seen = seen
                | otherwise =
                    let attempts = [extensionR r sh pr q | (_, sh, pr) <- shapes, pr >= prec, isExtension sh]
                        extended = nubEnds [q' | (qs, _) <- attempts, q' <- qs, q' > q]
                        memo' = foldl' climbFrom seen extended
                        deeper = [e | q' <- extended, e <- fst (memo' IntMap.! q')]
                        reach = maximum (q : map snd attempts ++ [snd (memo' IntMap.! q') | q' <- extended])
                     in IntMap.insert q (nubEnds (deeper ++ [q]), reach) memo'
           in toEntry (climbed, maximum (pos : map snd baseEvals ++ [snd (paths IntMap.! q) | q <- base]))

        baseR r sh pr = case sh of
          ShapePrimary alt -> Just (evalAlternativeR True entryOfR alt)
          ShapePrefix alt -> Just (seqR (evalAlternativeR True entryOfR alt) (refR r pr))
          _ -> Nothing

        extensionR r sh pr q = case sh of
          ShapeBinary rightAssoc middle -> seqR (evalAlternativeR True entryOfR middle) (refR r (if rightAssoc then pr else pr + 1)) q
          ShapeSuffix rest -> evalAlternativeR True entryOfR rest q
          _ -> ([], q)

        -- The builder. -----------------------------------------------------------------------------
        -- It mirrors the recognizer step for step, with children in place of furthest indices, and
        -- reads every rule and loop below the node it builds from the recognizer's table, as trees made
        -- only when the parse returned holds them.

        lookupB r prec p = [(buildTree r prec p e, e) | e <- entryEnds (lookupR r prec p)]

        entryOfB r p = lookupB r 0 p

        buildTree r prec p e = pick e (treesAt r prec p)

        treesAt r prec p = case ruleShapes (compiled BV.! r) of
          Just shapes -> leftRecursiveB r shapes prec p
          Nothing -> case Map.lookup r groupOf of
            Just members -> groupTreesB members p r
            Nothing -> evalRuleB True entryOfB r p

        -- A member of a left-recursive group at a position is built from the iteration that settled,
        -- each iteration reading its members there from the iteration before, as the recognizer did.
        groupTreesB members p = \r -> LMap.findWithDefault [] r (levels BV.! (BV.length iterations - 1))
          where
            iterations = fixTable Map.! headOf members BV.! p
            levels = BV.generate (BV.length iterations) level
            level k
              | k == 0 = LMap.empty
              | otherwise = LMap.fromList [(m, evalRuleB False (override k) m p) | m <- members]
            override k r q
              | q == p, Just entry <- Map.lookup r (iterations BV.! (k - 1)) =
                  [(pick e (LMap.findWithDefault [] r (levels BV.! (k - 1))), e) | e <- entryEnds entry]
              | otherwise = entryOfB r q

        evalRuleB cached look r p =
          let rule = compiled BV.! r
           in oneTreePerEnd [(node (ruleName' rule) i (children []), e) | (i, alt) <- zip [0 ..] (ruleAlternatives rule), (children, e) <- evalAlternativeB cached look alt p]

        evalAlternativeB cached look alt p = evalAlternativeFromB cached p look alt p

        evalAlternativeFromB cached from look alt p
          | admitsAt alt p = evalElementsB cached from look (compiledAlternativeElements alt) p
          | otherwise = []

        evalElementsB cached from look elements = foldr (\e rest -> seqB (evalElementB cached from look e) rest) emptyB elements

        repeatedB cached loop suffix m
          | cached && loop >= 0 = case suffix of
              Just (EbnfSuffix OneOrMore _) -> seqB m (loopB loop)
              _ -> loopB loop
          | otherwise = suffixedB suffix m

        evalElementB cached from look e = case e of
          CompiledAtomElement atom suffix label loop -> labeled label (repeatedB cached loop suffix (evalAtomB look atom))
          CompiledBlockElement alts suffix label loop -> labeled label (repeatedB cached loop suffix (altB [evalAlternativeFromB cached from look a | a <- alts]))
          CompiledActionElement -> emptyB
          CompiledPredicateElement predicate -> \p -> if hook predicate toks from p then emptyB p else []

        labeled label step = case label of
          Nothing -> step
          Just name -> \p -> [(\rest -> map (\t -> t `seq` Labeled name t) (children []) ++ rest, e) | (children, e) <- step p]

        evalAtomB look atom p = case atom of
          CompiledTerminal predicate -> terminal predicate
          CompiledRuleRef i -> [((tree :), e) | (tree, e) <- look i p]
          CompiledNotSet predicates -> terminal (\tok -> not (isEofToken tok) && not (any ($ tok) predicates))
          CompiledAny -> terminal (not . isEofToken)
          where
            terminal predicate = case toks BV.!? p of
              Just tok | predicate tok -> [((TokenNode tok :), p + 1)]
              _ -> []

        -- A memoised loop's ends are the recognizer's; the children of each end are those of the
        -- iterations on the path its walk first reached the end by, the path the walk's prefixes
        -- followed, found by walking the loop again over the recognizer's table.
        loopB i p
          | p > n = []
          | not (innerCanStart (loopInner i) p) = [(id, p)]
          | otherwise =
              let parents = loopParents (innerR (loopInner i)) p
                  pathTo e = go e []
                    where
                      go q acc
                        | q == p = acc
                        | otherwise = let q0 = parents IntMap.! q in go q0 ((q0, q) : acc)
                  iteration (a, b) = pick b (innerB (loopInner i) a)
               in [(foldr ((.) . iteration) id (pathTo e), e) | e <- entryEnds (loopEntryR i p)]

        innerB inner = case inner of
          Left atom -> evalAtomB entryOfB atom
          Right alts -> altB [evalAlternativeB True entryOfB a | a <- alts]

        refB r prec q = [((t :), e) | (t, e) <- lookupB r prec q]

        leftRecursiveB r shapes prec pos =
          let name = ruleName' (compiled BV.! r)
              baseEvals = [(i, step pos) | (i, sh, pr) <- shapes, Just step <- [baseB r sh pr]]
              base = oneTreePerEnd [(node name i (children []), q) | (i, rs) <- baseEvals, (children, q) <- rs]
              paths = foldl' climbFrom IntMap.empty (map snd base)
              climbed = [(wrap tree, e) | (tree, q) <- base, (wrap, e) <- paths IntMap.! q]
              climbFrom seen q
                | IntMap.member q seen = seen
                | otherwise =
                    let attempts = [(i, extensionB r sh pr q) | (i, sh, pr) <- shapes, pr >= prec, isExtension sh]
                        extended = oneTreePerEnd [(\tree -> node name i (tree : children []), q') | (i, rs) <- attempts, (children, q') <- rs, q' > q]
                        memo' = foldl' climbFrom seen (map snd extended)
                        deeper = [(wrap . step, e) | (step, q') <- extended, (wrap, e) <- memo' IntMap.! q']
                     in LIntMap.insert q (oneTreePerEnd (deeper ++ [(id, q)])) memo'
           in oneTreePerEnd climbed

        baseB r sh pr = case sh of
          ShapePrimary alt -> Just (evalAlternativeB True entryOfB alt)
          ShapePrefix alt -> Just (seqB (evalAlternativeB True entryOfB alt) (refB r pr))
          _ -> Nothing

        extensionB r sh pr q = case sh of
          ShapeBinary rightAssoc middle -> seqB (evalAlternativeB True entryOfB middle) (refB r (if rightAssoc then pr else pr + 1)) q
          ShapeSuffix rest -> evalAlternativeB True entryOfB rest q
          _ -> []

-- | The first result reaching an end; the builder asks only for ends the recognizer found.
pick :: Int -> [(a, Int)] -> a
pick e results = case [x | (x, e') <- results, e' == e] of
  (x : _) -> x
  [] -> error "canon: the tree builder lost an end the recognizer found"

-- | The first sets of every alternative of a rule, its shapes' and its blocks' included.
compiledFirstSets :: CompiledRule -> [FirstSet]
compiledFirstSets r = concatMap alternative (ruleAlternatives r ++ maybe [] (map shapeAlternative) (ruleShapes r))
  where
    shapeAlternative (_, sh, _) = case sh of
      ShapePrimary a -> a
      ShapePrefix a -> a
      ShapeBinary _ a -> a
      ShapeSuffix a -> a
    alternative a = alternativeFirst a : concatMap element (compiledAlternativeElements a)
    element e = case e of
      CompiledBlockElement alts _ _ _ -> concatMap alternative alts
      _ -> []

-- | The walk of a loop as manyR makes it, recording for each position reached the position whose
-- iteration first reached it.
loopParents :: Step -> Int -> IntMap.IntMap Int
loopParents m start = snd (visit (IntSet.singleton start, IntMap.empty) start)
  where
    visit acc q = foldl (descend q) acc (fst (m q))
    descend q acc@(seen, parents) mid
      | mid == q || IntSet.member mid seen = acc
      | otherwise = visit (IntSet.insert mid seen, IntMap.insert mid q parents) mid

computeFirst :: [ParserRule ()] -> Map Name Int -> BV.Vector (FirstSet, Bool)
computeFirst rules ruleIndex = go (BV.replicate (length rules) (emptyFirst, False))
  where
    go current =
      let next = BV.fromList [ruleFirst current rule | rule <- rules]
       in if BV.and (BV.zipWith same current next) then next else go next
    same (a, na) (b, nb) = na == nb && Set.size (firstTypes a) == Set.size (firstTypes b) && Set.size (firstTexts a) == Set.size (firstTexts b) && firstAny a == firstAny b
    ruleFirst current rule =
      foldr (\alt (fs, nullable) -> let (afs, an) = sequenceFirst current (alternativeElements' alt) in (unionFirst fs afs, nullable || an)) (emptyFirst, False) (toList (parserRuleAlternatives rule))
    alternativeElements' = alternativeElements . labeledAlternativeBody
    sequenceFirst current elements = case elements of
      [] -> (emptyFirst, True)
      (e : rest) ->
        let (fs, nullable) = elementFirst current e
         in if nullable then let (rfs, rn) = sequenceFirst current rest in (unionFirst fs rfs, rn) else (fs, False)
    elementFirst current e = case e of
      ElementAtom _ _ atom suffix -> let (fs, nullable) = atomFirst current atom in (fs, nullable || suffixNullable suffix)
      ElementBlock _ _ block suffix ->
        let parts = map (sequenceFirst current . alternativeElements) (toList (blockAlternatives block))
         in (foldr (unionFirst . fst) emptyFirst parts, any snd parts || suffixNullable suffix)
      ElementAction {} -> (emptyFirst, True)
    atomFirst current atom = case atom of
      AtomTerminal t -> (terminalFirst t, False)
      AtomRuleRef name _ _ -> case Map.lookup name ruleIndex of
        Just i -> current BV.! i
        Nothing -> (emptyFirst {firstAny = True}, False)
      AtomNotSet _ -> (emptyFirst {firstAny = True}, False)
      AtomWildcard _ -> (emptyFirst {firstAny = True}, False)
    terminalFirst t = case t of
      TerminalToken name _ -> emptyFirst {firstTypes = Set.singleton name}
      TerminalLiteral lit _ -> emptyFirst {firstTexts = Set.fromList [either (const T.empty) id (decodeStringLiteral lit)]}
    suffixNullable suffix = case suffix of
      Just (EbnfSuffix Optional _) -> True
      Just (EbnfSuffix ZeroOrMore _) -> True
      _ -> False

compileRule :: (FirstSet -> V.Vector Bool) -> Map Name Int -> BV.Vector (FirstSet, Bool) -> ParserRule () -> CompiledRule
compileRule admitsOf ruleIndex firstTable rule = CompiledRule (parserRuleName rule) alternatives shapes
  where
    self = parserRuleName rule
    sourceAlts = toList (parserRuleAlternatives rule)
    alternatives = map (compileAlternative . alternativeElements . labeledAlternativeBody) sourceAlts
    total = length sourceAlts
    shapes =
      let classified = [(i, shapeOf alt, total - i) | (i, alt) <- zip [0 ..] sourceAlts]
       in if any (\(_, sh, _) -> isExtension sh) classified then Just classified else Nothing
    shapeOf alt =
      let es = alternativeElements (labeledAlternativeBody alt)
          isSelf e = case e of
            ElementAtom _ _ (AtomRuleRef name _ _) Nothing -> name == self
            _ -> False
          firstIsSelf = case es of
            (e : _) -> isSelf e
            [] -> False
          lastIsSelf = case reverse es of
            (e : _) -> isSelf e
            [] -> False
          rightAssoc = any isRightAssoc (alternativeOptions (labeledAlternativeBody alt))
       in if firstIsSelf && lastIsSelf && length es >= 2
            then ShapeBinary rightAssoc (compileAlternative (init (drop 1 es)))
            else
              if firstIsSelf
                then ShapeSuffix (compileAlternative (drop 1 es))
                else if lastIsSelf then ShapePrefix (compileAlternative (init es)) else ShapePrimary (compileAlternative es)
    isRightAssoc o = case o of
      ElementOptionAssign (Name "assoc") (OptionValueName (QualifiedName (Name "right" NonEmpty.:| []))) -> True
      _ -> False
    compileAlternative es =
      let (fs, nullable) = sequenceFirst es
       in CompiledAlternative fs nullable (admitsOf fs) (map compileElement es)
    sequenceFirst es = case es of
      [] -> (emptyFirst, True)
      (e : rest) ->
        let (fs, nullable) = elementFirst e
         in if nullable then let (rfs, rn) = sequenceFirst rest in (unionFirst fs rfs, rn) else (fs, False)
    elementFirst e = case e of
      ElementAtom _ _ atom suffix -> let (fs, nullable) = atomFirst atom in (fs, nullable || suffixNullable suffix)
      ElementBlock _ _ block suffix ->
        let parts = map (sequenceFirst . alternativeElements) (toList (blockAlternatives block))
         in (foldr (unionFirst . fst) emptyFirst parts, any snd parts || suffixNullable suffix)
      ElementAction {} -> (emptyFirst, True)
    atomFirst atom = case atom of
      AtomTerminal t -> (terminalFirst t, False)
      AtomRuleRef name _ _ -> maybe (emptyFirst {firstAny = True}, False) (firstTable BV.!) (Map.lookup name ruleIndex)
      AtomNotSet _ -> (emptyFirst {firstAny = True}, False)
      AtomWildcard _ -> (emptyFirst {firstAny = True}, False)
    terminalFirst t = case t of
      TerminalToken name _ -> emptyFirst {firstTypes = Set.singleton name}
      TerminalLiteral lit _ -> emptyFirst {firstTexts = Set.fromList [either (const T.empty) id (decodeStringLiteral lit)]}
    suffixNullable suffix = case suffix of
      Just (EbnfSuffix Optional _) -> True
      Just (EbnfSuffix ZeroOrMore _) -> True
      _ -> False
    compileElement e = case e of
      ElementAtom _ label atom suffix -> CompiledAtomElement (compileAtom atom) suffix (labelText label) noLoop
      ElementBlock _ label block suffix -> CompiledBlockElement (map (compileAlternative . alternativeElements) (toList (blockAlternatives block))) suffix (labelText label) noLoop
      ElementAction _ SemanticPredicate body _ -> CompiledPredicateElement (actionTextRaw body)
      ElementAction {} -> CompiledActionElement
    labelText = fmap (nameText . labelName)
    compileAtom atom = case atom of
      AtomTerminal t -> CompiledTerminal (terminalPredicate t)
      AtomRuleRef name _ _ -> maybe (CompiledTerminal (const False)) CompiledRuleRef (Map.lookup name ruleIndex)
      AtomNotSet (NotSet elements) -> CompiledNotSet [terminalPredicate t | SetTerminal t <- toList elements]
      AtomWildcard _ -> CompiledAny
    terminalPredicate t = case t of
      TerminalToken name _ -> (== name) . tokenType
      TerminalLiteral lit _ -> let text = either (const T.empty) id (decodeStringLiteral lit) in (== text) . tokenText

-- | A rule node with its children built now, so that a memo entry holds the tree rather than the
-- closures that would build it, which kept the intermediate results of every step alive.
-- ref:DEC-parser-memory
node :: Name -> Int -> [ParseTree] -> ParseTree
node name i children = foldr seq () children `seq` RuleNode name i children

-- | The recognizer's table. Each position has a row of (key, end, furthest) triples sorted by key,
-- in an unboxed array the collector does not scan, and the ends of an entry with more than one are
-- kept in one unboxed buffer shared by all positions. An entry is a few machine words, so a 31,000
-- line generated C# file, with seven million entries, keeps its table in a few hundred megabytes,
-- where a map per position of boxed entries took gigabytes. ref:DEC-parser-memory ref:DEC-loop-memo
data Memo = Memo
  { memoRows :: IORef (MV.IOVector (UMV.IOVector Int))
  , memoReach :: IORef (UMV.IOVector Int)
  , memoEnds :: IORef (UMV.IOVector Int)
  , memoEndsUsed :: IORef Int
  , memoEmptyRow :: UMV.IOVector Int
  , memoTaken :: IORef Bool
  }

-- | A table for a parse of the given number of positions, private to that parse. Every row starts as
-- one shared empty row, which is replaced, never written, when its first entry is made. Each
-- position also keeps the furthest index any of its entries reached, -1 for none.
newMemo :: Int -> Memo
{-# NOINLINE newMemo #-}
newMemo size = unsafePerformIO $ do
  emptyRow <- UMV.replicate 1 0
  rows <- MV.replicate size emptyRow
  reach <- UMV.replicate size (-1)
  ends <- UMV.new 1024
  Memo <$> newIORef rows <*> newIORef reach <*> newIORef ends <*> newIORef 0 <*> pure emptyRow <*> newIORef False

-- | The table of an earlier parse taken over for a parse of the given number of positions whose
-- tokens before an index are the earlier parse's: each entry at a position before the index that
-- reached no further than the index is kept, and the rest are dropped. Only the rows that reached the
-- index are read, by the furthest index each position keeps, so taking a table over costs the
-- entries around the change rather than the table. A table is taken over once; a second taking is a
-- misuse and fails. ref:DEC-stray-comments
seededMemo :: Memo -> Int -> Int -> Memo
{-# NOINLINE seededMemo #-}
seededMemo old cut size = unsafePerformIO $ do
  taken <- readIORef (memoTaken old)
  if taken then error "canon: a recognizer table was taken over twice" else writeIORef (memoTaken old) True
  rows0 <- readIORef (memoRows old)
  reach0 <- readIORef (memoReach old)
  let oldSize = MV.length rows0
  (rows, reach) <-
    if size <= oldSize
      then pure (rows0, reach0)
      else do
        rows' <- MV.grow rows0 (size - oldSize)
        reach' <- UMV.grow reach0 (size - oldSize)
        forM_ [oldSize .. size - 1] $ \q -> MV.unsafeWrite rows' q (memoEmptyRow old) >> UMV.unsafeWrite reach' q (-1)
        pure (rows', reach')
  forM_ [0 .. MV.length rows - 1] $ \q -> do
    furthest <- UMV.unsafeRead reach q
    if furthest < cut
      then pure ()
      else
        if q >= cut
          then MV.unsafeWrite rows q (memoEmptyRow old) >> UMV.unsafeWrite reach q (-1)
          else do
            row <- MV.unsafeRead rows q
            count <- UMV.unsafeRead row 0
            let keep j i furthestKept
                  | i >= count = pure (j, furthestKept)
                  | otherwise = do
                      end <- UMV.unsafeRead row (2 + 3 * i)
                      f <- UMV.unsafeRead row (3 + 3 * i)
                      if end /= inProgress && f < cut
                        then do
                          when (j /= i) $ forM_ [1 .. 3] $ \o -> UMV.unsafeRead row (o + 3 * i) >>= UMV.unsafeWrite row (o + 3 * j)
                          keep (j + 1) (i + 1) (max furthestKept f)
                        else keep j (i + 1) furthestKept
            (count', furthest') <- keep 0 0 (-1)
            UMV.unsafeWrite row 0 count'
            UMV.unsafeWrite reach q furthest'
  Memo <$> newIORef rows <*> newIORef reach <*> pure (memoEnds old) <*> pure (memoEndsUsed old) <*> pure (memoEmptyRow old) <*> newIORef False

-- | Appends an entry's ends to a table's buffer and returns the end field that points at them.
appendEnds :: Memo -> V.Vector Int -> IO Int
appendEnds memo es = do
  used <- readIORef (memoEndsUsed memo)
  buffer <- readIORef (memoEnds memo)
  let len = V.length es
  buffer' <-
    if used + len + 1 <= UMV.length buffer
      then pure buffer
      else do
        grown <- UMV.unsafeGrow buffer (max (len + 1) (UMV.length buffer))
        writeIORef (memoEnds memo) grown
        pure grown
  UMV.unsafeWrite buffer' used len
  V.imapM_ (\k e -> UMV.unsafeWrite buffer' (used + 1 + k) e) es
  writeIORef (memoEndsUsed memo) (used + len + 1)
  pure (negate used - 4)

-- | The end field of an entry being made, and of a failure.
inProgress, noEnd :: Int
inProgress = -3
noEnd = -1

-- | The entry of a key at a position, made on first request and kept after. The entry is evaluated
-- when made, which reads the entries below it; a request for an entry while it is being made is a
-- left recursion the parser did not find, and fails as GHC's loop detection failed it when entries
-- were stored unevaluated. The table is private to one parse, which runs on one thread, and an
-- entry is the same however often it is made.
memoised :: Memo -> Int -> Int -> Entry -> Entry
memoised memo p key made = unsafePerformIO $ do
  rows <- readIORef (memoRows memo)
  row <- MV.unsafeRead rows p
  count <- UMV.unsafeRead row 0
  i <- rowSlot row count key
  hit <- if i < count then (== key) <$> UMV.unsafeRead row (1 + 3 * i) else pure False
  if hit
    then readSlot row i
    else do
      insertSlot rows row count i
      entry <- evaluate made
      (end, furthest) <- encode entry
      row' <- MV.unsafeRead rows p
      count' <- UMV.unsafeRead row' 0
      j <- rowSlot row' count' key
      UMV.unsafeWrite row' (2 + 3 * j) end
      UMV.unsafeWrite row' (3 + 3 * j) furthest
      reach <- readIORef (memoReach memo)
      previous <- UMV.unsafeRead reach p
      when (furthest > previous) (UMV.unsafeWrite reach p furthest)
      pure entry
  where
    readSlot row i = do
      end <- UMV.unsafeRead row (2 + 3 * i)
      furthest <- UMV.unsafeRead row (3 + 3 * i)
      if end >= 0
        then pure (Ended end furthest)
        else
          if end == noEnd
            then pure (Failed furthest)
            else
              if end == inProgress
                then error "canon: a rule was asked for at a position while its entry there was being made"
                else do
                  buffer <- readIORef (memoEnds memo)
                  let offset = negate end - 4
                  len <- UMV.unsafeRead buffer offset
                  ends <- V.freeze (UMV.unsafeSlice (offset + 1) len buffer)
                  pure (Ends ends furthest)
    insertSlot rows row count i = do
      row' <-
        if 1 + 3 * (count + 1) <= UMV.length row
          then pure row
          else do
            grown <- UMV.unsafeGrow row (max 12 (UMV.length row))
            MV.unsafeWrite rows p grown
            pure grown
      UMV.unsafeMove (UMV.unsafeSlice (1 + 3 * (i + 1)) (3 * (count - i)) row') (UMV.unsafeSlice (1 + 3 * i) (3 * (count - i)) row')
      UMV.unsafeWrite row' (1 + 3 * i) key
      UMV.unsafeWrite row' (2 + 3 * i) inProgress
      UMV.unsafeWrite row' (3 + 3 * i) 0
      UMV.unsafeWrite row' 0 (count + 1)
    encode entry = case entry of
      Failed f -> pure (noEnd, f)
      Ended e f -> pure (e, f)
      Ends es f -> (\end -> (end, f)) <$> appendEnds memo es

-- | The index of the first triple of a row whose key is not below the given one.
rowSlot :: UMV.IOVector Int -> Int -> Int -> IO Int
rowSlot row count key = go 0 count
  where
    go lo hi
      | lo >= hi = pure lo
      | otherwise = do
          let mid = (lo + hi) `div` 2
          k <- UMV.unsafeRead row (1 + 3 * mid)
          if k < key then go (mid + 1) hi else go lo mid

-- | The id of an element that is not a loop.
noLoop :: Int
noLoop = -1

-- | Numbers every starred or plussed element of every rule, shapes included, so that each loop
-- has a memo table of its own: a loop re-entered at the same position is then read once, which
-- keeps a failing parse from re-reading every way a loop can split its input. ref:DEC-loop-memo
numberLoops :: [CompiledRule] -> (Int, [CompiledRule])
numberLoops = mapAccumL rule 0
  where
    rule k r =
      let (k1, alts) = mapAccumL alternative k (ruleAlternatives r)
          (k2, shapes) = case ruleShapes r of
            Nothing -> (k1, Nothing)
            Just ss -> fmap Just (mapAccumL shapeEntry k1 ss)
       in (k2, r {ruleAlternatives = alts, ruleShapes = shapes})
    shapeEntry k (i, sh, pr) =
      let (k', sh') = case sh of
            ShapePrimary a -> fmap ShapePrimary (alternative k a)
            ShapePrefix a -> fmap ShapePrefix (alternative k a)
            ShapeBinary right a -> fmap (ShapeBinary right) (alternative k a)
            ShapeSuffix a -> fmap ShapeSuffix (alternative k a)
       in (k', (i, sh', pr))
    alternative k a = let (k', es) = mapAccumL element k (compiledAlternativeElements a) in (k', a {compiledAlternativeElements = es})
    element k e = case e of
      CompiledAtomElement atom suffix label _ -> (next suffix k, CompiledAtomElement atom suffix label (idFor suffix k))
      CompiledBlockElement alts suffix label _
        | any predicated alts ->
            let (k', alts') = mapAccumL alternative k alts
             in (k', CompiledBlockElement alts' suffix label noLoop)
        | otherwise ->
            let (k', alts') = mapAccumL alternative (next suffix k) alts
             in (k', CompiledBlockElement alts' suffix label (idFor suffix k))
      CompiledActionElement -> (k, e)
      CompiledPredicateElement _ -> (k, e)
    -- A loop whose body asks a predicate is not memoised, since a predicate may read where the rule
    -- around it started, which differs between entries at one position.
    predicated a = any predicatedElement (compiledAlternativeElements a)
    predicatedElement e = case e of
      CompiledPredicateElement _ -> True
      CompiledBlockElement alts _ _ _ -> any predicated alts
      _ -> False
    isLoop suffix = case suffix of
      Just (EbnfSuffix ZeroOrMore _) -> True
      Just (EbnfSuffix OneOrMore _) -> True
      _ -> False
    next suffix k = if isLoop suffix then k + 1 else k
    idFor suffix k = if isLoop suffix then k else noLoop

-- | The loops of a rule in id order, each with its suffix and the element it repeats.
ruleLoops :: CompiledRule -> [(EbnfSuffix, Either CompiledAtom [CompiledAlternative])]
ruleLoops r = concatMap alternative (ruleAlternatives r) ++ concatMap shapeLoops (maybe [] id (ruleShapes r))
  where
    shapeLoops (_, sh, _) = case sh of
      ShapePrimary a -> alternative a
      ShapePrefix a -> alternative a
      ShapeBinary _ a -> alternative a
      ShapeSuffix a -> alternative a
    alternative a = concatMap element (compiledAlternativeElements a)
    element e = case e of
      CompiledAtomElement atom (Just suffix) _ loop | loop >= 0 -> [(suffix, Left atom)]
      CompiledBlockElement alts suffix _ loop ->
        [(s', Right alts) | loop >= 0, Just s' <- [suffix]] ++ concatMap alternative alts
      _ -> []

oneTreePerEnd :: [(a, Int)] -> [(a, Int)]
oneTreePerEnd = go IntSet.empty
  where
    go seen results = case results of
      [] -> []
      (r@(_, e) : rest)
        | IntSet.member e seen -> go seen rest
        | otherwise -> r : go (IntSet.insert e seen) rest

-- | Each end once, at its first place.
nubEnds :: [Int] -> [Int]
nubEnds ends = case ends of
  [] -> []
  [_] -> ends
  _ -> go IntSet.empty ends
  where
    go seen es = case es of
      [] -> []
      (e : rest)
        | IntSet.member e seen -> go seen rest
        | otherwise -> e : go (IntSet.insert e seen) rest

emptyR :: Step
emptyR p = ([p], p)

seqR :: Step -> Step -> Step
seqR a b p =
  let (mids, f) = a p
      continuations = map b mids
   in (nubEnds (concatMap fst continuations), maximum (f : map snd continuations))

altR :: [Step] -> Step
altR steps p =
  let evals = map ($ p) steps
   in (nubEnds (concatMap fst evals), maximum (p : map snd evals))

suffixedR :: Maybe EbnfSuffix -> Step -> Step
suffixedR suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> altR [m, emptyR]
  Just (EbnfSuffix Optional NonGreedy) -> altR [emptyR, m]
  Just (EbnfSuffix ZeroOrMore Greedy) -> manyR True m
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> manyR False m
  Just (EbnfSuffix OneOrMore Greedy) -> seqR m (manyR True m)
  Just (EbnfSuffix OneOrMore NonGreedy) -> seqR m (manyR False m)

-- | A loop as a depth-first walk over the positions its iterations reach, each position visited
-- once, emitting a position after the ones beyond it when greedy and before them when not. That is
-- the order, and with one tree per end the trees, that the loop written as a recursion of
-- alternatives gives, since a position reached again only repeats ends already emitted; but the
-- recursion built a result for every pair of an iteration and a later end, so a list of n items
-- cost n squared, and a 13,000-line C# initializer ran out of memory. ref:DEC-one-tree-per-span
-- ref:DEC-parser-memory
manyR :: Bool -> Step -> Step
manyR greedy m start =
  let (out, _, furthest) = visit (IntSet.singleton start) start
   in (out [], furthest)
  where
    visit seen q =
      let (results, f0) = m q
          (below, seen', f1) = foldl (descend q) (id, seen, f0) results
          here = (q :)
       in (if greedy then below . here else here . below, seen', f1)
    descend q (acc, seen, f) mid
      | mid == q || IntSet.member mid seen = (acc, seen, f)
      | otherwise =
          let (out, seen', f') = visit (IntSet.insert mid seen) mid
           in (acc . out, seen', max f f')

emptyB :: Build
emptyB p = [(id, p)]

seqB :: Build -> Build -> Build
seqB a b p = oneTreePerEnd [(c . cs, e) | (c, mid) <- a p, (cs, e) <- b mid]

altB :: [Build] -> Build
altB steps p = oneTreePerEnd (concatMap ($ p) steps)

suffixedB :: Maybe EbnfSuffix -> Build -> Build
suffixedB suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> altB [m, emptyB]
  Just (EbnfSuffix Optional NonGreedy) -> altB [emptyB, m]
  Just (EbnfSuffix ZeroOrMore Greedy) -> manyB True m
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> manyB False m
  Just (EbnfSuffix OneOrMore Greedy) -> seqB m (manyB True m)
  Just (EbnfSuffix OneOrMore NonGreedy) -> seqB m (manyB False m)

-- | manyR with the children of each end, each prefix of children shared with the one before it.
manyB :: Bool -> Build -> Build
manyB greedy m start = fst (visit (IntSet.singleton start) id start) []
  where
    visit seen prefix q =
      let (below, seen') = foldl (descend prefix q) (id, seen) (m q)
          here = ((prefix, q) :)
       in (if greedy then below . here else here . below, seen')
    descend prefix q (acc, seen) (c, mid)
      | mid == q || IntSet.member mid seen = (acc, seen)
      | otherwise =
          let (out, seen') = visit (IntSet.insert mid seen) (prefix . c) mid
           in (acc . out, seen')
