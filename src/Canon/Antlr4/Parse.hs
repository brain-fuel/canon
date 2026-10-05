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
  , renderParseError
  , renderParseTree
  , treeRuleNodes
  , treeTokens
  ) where

import Canon.Antlr4.Escape (decodeStringLiteral)
import Canon.Antlr4.Query (allRules, undefinedRuleReferences)
import Canon.Antlr4.RuleGraph (leftCornerGraph, stronglyConnectedRuleGroups)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token
import Data.Foldable (toList)
import qualified Data.IntSet as IntSet
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as BV
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Unboxed as V
import qualified Data.IntMap.Strict as IntMap
import System.IO.Unsafe (unsafePerformIO)

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
renderParseTree = go 0
  where
    go depth tree = case tree of
      TokenNode t -> T.concat [indent depth, nameText (tokenType t), " ", T.pack (show (tokenText t))]
      Labeled label inner -> T.concat [indent depth, label, "=\n", go depth inner]
      RuleNode name _ children -> T.intercalate "\n" (T.concat [indent depth, "(", nameText name] : map (go (depth + 1)) children ++ [indent depth <> ")"])
    indent depth = T.replicate depth "  "

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

type Results = [(ParseTree, Int)]

-- | A memo entry: the trees of a rule at a position, one per end, and the furthest index reached.
-- It is strict and unpacked because a long file holds one for every rule tried at every token.
data Entry = Entry !Found {-# UNPACK #-} !Int

-- | The trees of a memo entry with their ends, in preference order.
data Found = FoundNone | Found !ParseTree {-# UNPACK #-} !Int !Found

toEntry :: (Results, Int) -> Entry
toEntry (rs, f) = Entry (foldr (\(t, e) acc -> Found t e acc) FoundNone rs) f

entryResults :: Entry -> Results
entryResults (Entry found _) = go found
  where
    go x = case x of
      FoundNone -> []
      Found t e rest -> (t, e) : go rest

entryFurthest :: Entry -> Int
entryFurthest (Entry _ f) = f

type Step = Int -> ([(Children, Int)], Int)

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
  = CompiledAtomElement CompiledAtom (Maybe EbnfSuffix) (Maybe Text)
  | CompiledBlockElement [CompiledAlternative] (Maybe EbnfSuffix) (Maybe Text)
  | CompiledActionElement
  | CompiledPredicateElement Text

data CompiledAlternative = CompiledAlternative
  { alternativeFirst :: FirstSet
  , alternativeNullable :: Bool
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

-- | Parses the visible tokens with a predicate hook. The memo table holds an entry only for the
-- rules that can start at each token, by their first sets, so its size follows what a token can
-- begin rather than the number of rules: a rule that cannot start at a token fails there without an
-- entry. On the C# grammar this cut the memory of a long collection initializer several times over.
-- ref:DEC-parser-memory
parseVisibleTokensWith :: PredicateHook -> Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseVisibleTokensWith hook grammar start visible
  | not (Map.member start ruleIndex) = Left (ParseUnknownStartRule start)
  | not (null undefined') = Left (ParseUndefinedRules undefined')
  | otherwise = case [t | (t, e) <- entryResults (entryOf startIndex 0), e == n] of
      (t : _) -> Right t
      [] -> Left (ParseNoParse (ParseFailure furthest (toks BV.!? furthest)))
  where
    stripped = fmap (const ()) grammar
    sourceRules = [p | RuleParser p <- allRules stripped]
    ruleIndex = Map.fromList (zip (map parserRuleName sourceRules) [0 ..])
    startIndex = ruleIndex Map.! start
    undefined' = [(r, t) | (r, t) <- undefinedRuleReferences stripped, Map.member r ruleIndex]
    toks = BV.fromList visible
    n = BV.length toks
    ruleCount = length sourceRules

    firstTable = computeFirst sourceRules ruleIndex
    compiled = BV.fromList (map (compileRule ruleIndex firstTable) sourceRules)

    -- Tokens fall into classes by type, and by text where a parser rule names a literal, and each
    -- class has its candidate rules: those nullable or whose first set admits the token. Position n,
    -- past the last token, is class 0, where only nullable rules are candidates.
    literalTexts = Set.unions [firstTexts fs | (fs, _) <- BV.toList firstTable]
    classKey tok = (tokenType tok, if Set.member (tokenText tok) literalTexts then Just (tokenText tok) else Nothing)
    classIndex = Map.fromList (zip (Set.toList (Set.fromList (map classKey visible))) [1 ..])
    classRepresentative = Map.fromList [(classIndex Map.! classKey tok, tok) | tok <- visible]
    classOfPos :: V.Vector Int
    classOfPos = V.generate (n + 1) (\p -> maybe 0 (\tok -> classIndex Map.! classKey tok) (toks BV.!? p))
    candidatesOf c = [r | r <- [0 .. ruleCount - 1], admits (firstTable BV.! r) (Map.lookup c classRepresentative)]
    admits (fs, nullable) representative = nullable || maybe False (canStart fs) representative
    classCandidates :: BV.Vector [Int]
    classCandidates = BV.generate (Map.size classIndex + 1) candidatesOf
    classSlots :: BV.Vector (V.Vector Int)
    classSlots = BV.map (\rs -> V.replicate ruleCount (-1) V.// zip rs [0 ..]) classCandidates

    memo = newMemo (n + 1)
    slotEntries r p = case ruleShapes (compiled BV.! r) of
      Nothing -> BV.singleton (compute r p)
      Just shapes -> BV.generate (length shapes + 2) (\prec -> evalLeftRecursive r shapes prec p)

    lookupEntry r prec p
      | p > n = Entry FoundNone p
      | otherwise =
          let slot = classSlots BV.! (classOfPos V.! p) V.! r
           in if slot < 0 then failures BV.! p else memoised memo p r slotEntries BV.! prec

    -- One shared entry per position for a rule that fails there without reaching further.
    failures :: BV.Vector Entry
    failures = BV.generate (n + 1) (Entry FoundNone)
    sharedFailure entry@(Entry found f) = case found of
      FoundNone | f <= n -> failures BV.! f
      _ -> entry

    groups =
      [ map (ruleIndex Map.!) (NonEmpty.toList g)
      | g <- stronglyConnectedRuleGroups (leftCornerGraph stripped)
      , all (`Map.member` ruleIndex) (toList g)
      , not (any (\m -> hasShapes (ruleIndex Map.! m)) (NonEmpty.toList g))
      ]
    hasShapes i = maybe False (const True) (ruleShapes (compiled BV.! i))
    groupOf = Map.fromList [(m, members) | members <- groups, m <- members]

    fixTable :: Map Int (BV.Vector (Map Int Entry))
    fixTable = Map.fromList [(headOf members, BV.generate (n + 1) (fixpoint members)) | members <- groups]

    headOf xs = case xs of
      (x : _) -> x
      [] -> error "empty group"

    entryOf r p = lookupEntry r 0 p
    precEntry r prec p = lookupEntry r prec p

    compute r p = case Map.lookup r groupOf of
          Just members -> Map.findWithDefault (Entry FoundNone p) r (fixTable Map.! headOf members BV.! p)
          Nothing -> evalRule entryOf r p

    fixpoint members p = go (Map.fromList [(m, Entry FoundNone p) | m <- members]) (0 :: Int)
      where
        go current k =
          let next = Map.fromList [(m, evalRule (override current) m p) | m <- members]
           in if signature next == signature current || k > n - p + 1 then next else go next (k + 1)
        signature = Map.map (map snd . entryResults)
        override current r q
          | q == p, Just entry <- Map.lookup r current = entry
          | otherwise = entryOf r q

    evalRule look r p =
      let rule = compiled BV.! r
          evals = [(i, evalAlternative look alt p) | (i, alt) <- zip [0 ..] (ruleAlternatives rule)]
       in sharedFailure
            ( toEntry
                ( oneTreePerEnd [(node (ruleName' rule) i (children []), e) | (i, (results, _)) <- evals, (children, e) <- results]
                , maximum (p : [f | (_, (_, f)) <- evals])
                )
            )

    evalAlternative look alt p = evalAlternativeFrom p look alt p

    evalAlternativeFrom from look alt p = case toks BV.!? p of
      Just tok | not (alternativeNullable alt) && not (canStart (alternativeFirst alt) tok) -> ([], p)
      Nothing | not (alternativeNullable alt) -> ([], p)
      _ -> evalElements from look (compiledAlternativeElements alt) p

    evalElements from look elements = foldr (\e rest -> seqStep (evalElement from look e) rest) emptyStep elements

    evalElement from look e = case e of
      CompiledAtomElement atom suffix label -> labeled label (suffixed suffix (evalAtom look atom))
      CompiledBlockElement alts suffix label -> labeled label (suffixed suffix (altStep [evalAlternativeFrom from look a | a <- alts]))
      CompiledActionElement -> emptyStep
      CompiledPredicateElement predicate -> \p -> if hook predicate toks from p then emptyStep p else ([], p)

    labeled label step = case label of
      Nothing -> step
      Just name -> \p -> let (rs, f) = step p in ([(\rest -> map (Labeled name) (children []) ++ rest, e) | (children, e) <- rs], f)

    evalAtom look atom p = case atom of
      CompiledTerminal predicate -> terminal predicate
      CompiledRuleRef i -> let entry = look i p in ([((tree :), e) | (tree, e) <- entryResults entry], entryFurthest entry)
      CompiledNotSet predicates -> terminal (\tok -> not (isEofToken tok) && not (any ($ tok) predicates))
      CompiledAny -> terminal (not . isEofToken)
      where
        terminal predicate = case toks BV.!? p of
          Just tok | predicate tok -> ([((TokenNode tok :), p + 1)], p + 1)
          _ -> ([], p)

    refStep r prec q = let entry = precEntry r prec q in ([((t :), e) | (t, e) <- entryResults entry], entryFurthest entry)

    evalLeftRecursive r shapes prec pos =
      let name = ruleName' (compiled BV.! r)
          baseEvals = [(i, step pos) | (i, sh, pr) <- shapes, Just step <- [baseStep r sh pr]]
          base = oneTreePerEnd [(node name i (children []), q) | (i, (rs, _)) <- baseEvals, (children, q) <- rs]
          climbed = map climb base
          climb (tree, q) =
            let attempts = [(i, extensionStep r sh pr q) | (i, sh, pr) <- shapes, pr >= prec, isExtension sh]
                extended = oneTreePerEnd [(node name i (tree : children []), q') | (i, (rs, _)) <- attempts, (children, q') <- rs, q' > q]
                deeper = map climb extended
             in (oneTreePerEnd (concatMap fst deeper ++ [(tree, q)]), maximum (q : [f | (_, (_, f)) <- attempts] ++ map snd deeper))
       in sharedFailure (toEntry (oneTreePerEnd (concatMap fst climbed), maximum (pos : [f | (_, (_, f)) <- baseEvals] ++ map snd climbed)))

    baseStep r sh pr = case sh of
      ShapePrimary alt -> Just (evalAlternative entryOf alt)
      ShapePrefix alt -> Just (seqStep (evalAlternative entryOf alt) (refStep r pr))
      _ -> Nothing

    extensionStep r sh pr q = case sh of
      ShapeBinary rightAssoc middle -> seqStep (evalAlternative entryOf middle) (refStep r (if rightAssoc then pr else pr + 1)) q
      ShapeSuffix rest -> evalAlternative entryOf rest q
      _ -> ([], q)

    furthest = entryFurthest (entryOf startIndex 0)

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

compileRule :: Map Name Int -> BV.Vector (FirstSet, Bool) -> ParserRule () -> CompiledRule
compileRule ruleIndex firstTable rule = CompiledRule (parserRuleName rule) alternatives shapes
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
       in CompiledAlternative fs nullable (map compileElement es)
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
      ElementAtom _ label atom suffix -> CompiledAtomElement (compileAtom atom) suffix (labelText label)
      ElementBlock _ label block suffix -> CompiledBlockElement (map (compileAlternative . alternativeElements) (toList (blockAlternatives block))) suffix (labelText label)
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

-- | A memo table with one map per position, filled as entries are asked for, so a rule that could
-- start at a token but is never tried there costs nothing. ref:DEC-parser-memory
newMemo :: Int -> MV.IOVector (IntMap.IntMap a)
newMemo size = unsafePerformIO (MV.replicate size IntMap.empty)

-- | The entry of a rule at a position, made on first request and shared after. The entry is stored
-- unevaluated, so a request made while it is being evaluated finds the same thunk, as a lazy table
-- would; the table is private to one parse, which runs on one thread, and a request that runs twice
-- makes the same entry, so the result is the same however often GHC evaluates it.
memoised :: MV.IOVector (IntMap.IntMap a) -> Int -> Int -> (Int -> Int -> a) -> a
memoised table p r make = unsafePerformIO $ do
  entries <- MV.read table p
  case IntMap.lookup r entries of
    Just found -> pure found
    Nothing -> do
      let made = make r p
      MV.write table p (IntMap.insert r made entries)
      pure made

oneTreePerEnd :: [(a, Int)] -> [(a, Int)]
oneTreePerEnd = go IntSet.empty
  where
    go seen results = case results of
      [] -> []
      (r@(_, e) : rest)
        | IntSet.member e seen -> go seen rest
        | otherwise -> r : go (IntSet.insert e seen) rest

emptyStep :: Step
emptyStep p = ([(id, p)], p)

seqStep :: Step -> Step -> Step
seqStep a b p =
  let (rs, f) = a p
      continuations = [(b mid, c) | (c, mid) <- rs]
   in ( oneTreePerEnd [(c . cs, e) | ((crs, _), c) <- continuations, (cs, e) <- crs]
      , maximum (f : [cf | ((_, cf), _) <- continuations])
      )

altStep :: [Step] -> Step
altStep steps p =
  let evals = map ($ p) steps
   in (oneTreePerEnd (concatMap fst evals), maximum (p : map snd evals))

suffixed :: Maybe EbnfSuffix -> Step -> Step
suffixed suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> altStep [m, emptyStep]
  Just (EbnfSuffix Optional NonGreedy) -> altStep [emptyStep, m]
  Just (EbnfSuffix ZeroOrMore Greedy) -> manyStep True m
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> manyStep False m
  Just (EbnfSuffix OneOrMore Greedy) -> seqStep m (manyStep True m)
  Just (EbnfSuffix OneOrMore NonGreedy) -> seqStep m (manyStep False m)

-- | A loop as a depth-first walk over the positions its iterations reach, each position visited
-- once, emitting a position after the ones beyond it when greedy and before them when not. That is
-- the order, and with one tree per end the trees, that the loop written as a recursion of
-- alternatives gives, since a position reached again only repeats ends already emitted; but the
-- recursion built a result for every pair of an iteration and a later end, so a list of n items
-- cost n squared, and a 13,000-line C# initializer ran out of memory. Each prefix of children here
-- is shared with the one before it. ref:DEC-one-tree-per-span ref:DEC-parser-memory
manyStep :: Bool -> Step -> Step
manyStep greedy m start =
  let (out, _, furthest) = visit (IntSet.singleton start) id start
   in (out [], furthest)
  where
    visit seen prefix q =
      let (results, f0) = m q
          (below, seen', f1) = foldl (descend prefix q) (id, seen, f0) results
          here = ((prefix, q) :)
       in (if greedy then below . here else here . below, seen', f1)
    descend prefix q (acc, seen, f) (c, mid)
      | mid == q || IntSet.member mid seen = (acc, seen, f)
      | otherwise =
          let (out, seen', f') = visit (IntSet.insert mid seen) (prefix . c) mid
           in (acc . out, seen', max f f')
