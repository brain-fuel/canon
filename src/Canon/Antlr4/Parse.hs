module Canon.Antlr4.Parse
  ( ParseTree (..)
  , ParseFailure (..)
  , ParseError (..)
  , parseTokens
  , parseVisibleTokens
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
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Lazy (Map)
import qualified Data.Map.Lazy as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as BV

data ParseTree
  = RuleNode Name Int [ParseTree]
  | TokenNode Token
  deriving (Eq, Show)

data ParseFailure = ParseFailure
  { failureIndex :: Int
  , failureToken :: Maybe Token
  }
  deriving (Eq, Show)

data ParseError
  = ParseUnknownStartRule Name
  | ParseUndefinedRules [(Name, Name)]
  | ParseNoParse ParseFailure
  deriving (Eq, Show)

renderParseError :: ParseError -> Text
renderParseError e = case e of
  ParseUnknownStartRule n -> "unknown start rule " <> nameText n
  ParseUndefinedRules refs -> "undefined rule references: " <> T.intercalate ", " [nameText r <> " -> " <> nameText t | (r, t) <- refs]
  ParseNoParse (ParseFailure i tok) -> case tok of
    Just t ->
      let Position line column = tokenPosition t
       in T.concat [T.pack (show line), ":", T.pack (show column), ": no parse at token ", renderToken t]
    Nothing -> "no parse at token index " <> T.pack (show i)

renderParseTree :: ParseTree -> Text
renderParseTree = go 0
  where
    go depth tree = case tree of
      TokenNode t -> T.concat [indent depth, nameText (tokenType t), " ", T.pack (show (tokenText t))]
      RuleNode name _ children -> T.intercalate "\n" (T.concat [indent depth, "(", nameText name] : map (go (depth + 1)) children ++ [indent depth <> ")"])
    indent depth = T.replicate depth "  "

treeRuleNodes :: Name -> ParseTree -> [ParseTree]
treeRuleNodes wanted tree = case tree of
  TokenNode _ -> []
  RuleNode name _ children -> [tree | name == wanted] ++ concatMap (treeRuleNodes wanted) children

treeTokens :: ParseTree -> [Token]
treeTokens tree = case tree of
  TokenNode t -> [t]
  RuleNode _ _ children -> concatMap treeTokens children

type Results = [(ParseTree, Int)]

data AltShape
  = Primary [Element ()]
  | Prefix [Element ()]
  | Binary Bool [Element ()]
  | Suffix [Element ()]

isExtension :: AltShape -> Bool
isExtension sh = case sh of
  Binary _ _ -> True
  Suffix _ -> True
  _ -> False

type Step = Int -> ([([ParseTree], Int)], Int)

parseTokens :: Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseTokens grammar start = parseVisibleTokens grammar start . filter ((== defaultChannelName) . tokenChannel)

parseVisibleTokens :: Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseVisibleTokens grammar start visible
  | not (Map.member start rules) = Left (ParseUnknownStartRule start)
  | not (null undefined') = Left (ParseUndefinedRules undefined')
  | otherwise = case [t | (t, e) <- lookupTable start 0, e == n] of
      (t : _) -> Right t
      [] -> Left (ParseNoParse (ParseFailure furthest (toks BV.!? furthest)))
  where
    stripped = fmap (const ()) grammar
    rules = Map.fromList [(parserRuleName p, p) | RuleParser p <- allRules stripped]
    undefined' = [(r, t) | (r, t) <- undefinedRuleReferences stripped, Map.member r rules]
    toks = BV.fromList visible
    n = BV.length toks

    groups = [g | g <- stronglyConnectedRuleGroups (leftCornerGraph stripped), all (`Map.member` rules) (toList g)]
    groupOf = Map.fromList [(m, NonEmpty.toList g) | g <- groups, m <- NonEmpty.toList g, not (Map.member m directLR)]

    directLR :: Map Name [(Int, AltShape, Int)]
    directLR = Map.fromList [(r, shapes) | (r, rule) <- Map.toList rules, let shapes = classify r rule, any (isExtension . shapeOf) shapes]
    shapeOf (_, sh, _) = sh

    table :: Map (Name, Int) (Results, Int)
    table = Map.fromList [((r, p), compute r p) | r <- Map.keys rules, p <- [0 .. n]]

    precTable :: Map (Name, Int, Int) (Results, Int)
    precTable =
      Map.fromList
        [ ((r, prec, p), evalLR r shapes prec p)
        | (r, shapes) <- Map.toList directLR
        , prec <- [0 .. length shapes + 1]
        , p <- [0 .. n]
        ]

    fixTable :: Map (Name, Int) (Map Name (Results, Int))
    fixTable = Map.fromList [((NonEmpty.head g, p), fixpoint (NonEmpty.toList g) p) | g <- groups, p <- [0 .. n], not (Map.member (NonEmpty.head g) directLR)]

    lookupTable r p = fst (lookupEntry r p)
    lookupEntry r p = Map.findWithDefault ([], p) (r, p) table
    precEntry r prec p = Map.findWithDefault ([], p) (r, prec, p) precTable

    compute r p
      | Map.member r directLR = precEntry r 0 p
      | otherwise = case Map.lookup r groupOf of
          Just members -> Map.findWithDefault ([], p) r (fixTable Map.! (head' members, p))
          Nothing -> evalRule lookupEntry r p

    head' xs = case xs of
      (x : _) -> x
      [] -> error "empty group"

    classify self rule =
      let alts = toList (parserRuleAlternatives rule)
          total = length alts
       in [(i, shape self alt, total - i) | (i, alt) <- zip [0 ..] alts]
    shape self alt =
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
            then Binary rightAssoc (init (drop 1 es))
            else
              if firstIsSelf
                then Suffix (drop 1 es)
                else if lastIsSelf then Prefix (init es) else Primary es
    isRightAssoc o = case o of
      ElementOptionAssign (Name "assoc") (OptionValueName (QualifiedName (Name "right" NonEmpty.:| []))) -> True
      _ -> False

    refStep r prec q = let (rs, f) = precEntry r prec q in ([([t], e) | (t, e) <- rs], f)

    evalLR r shapes prec pos =
      let baseEvals =
            [ (i, step pos)
            | (i, sh, pr) <- shapes
            , Just step <- [baseStep r sh pr]
            ]
          base = [(RuleNode r i children, q) | (i, (rs, _)) <- baseEvals, (children, q) <- rs]
          climbed = map climb base
          climb (tree, q) =
            let attempts = [(i, extensionStep r sh pr q) | (i, sh, pr) <- shapes, pr >= prec, isExtension sh]
                extended = [(RuleNode r i (tree : children), q') | (i, (rs, _)) <- attempts, (children, q') <- rs, q' > q]
                deeper = map climb extended
             in (concatMap fst deeper ++ [(tree, q)], maximum (q : [f | (_, (_, f)) <- attempts] ++ map snd deeper))
       in (concatMap fst climbed, maximum (pos : [f | (_, (_, f)) <- baseEvals] ++ map snd climbed))

    baseStep r sh pr = case sh of
      Primary es -> Just (evalElements lookupEntry es)
      Prefix es -> Just (seqStep (evalElements lookupEntry es) (refStep r pr))
      _ -> Nothing

    extensionStep r sh pr q = case sh of
      Binary rightAssoc middle -> seqStep (evalElements lookupEntry middle) (refStep r (if rightAssoc then pr else pr + 1)) q
      Suffix rest -> evalElements lookupEntry rest q
      _ -> ([], q)

    fixpoint members p = go (Map.fromList [(m, ([], p)) | m <- members]) (0 :: Int)
      where
        go current k =
          let next = Map.fromList [(m, evalRule (override current) m p) | m <- members]
           in if signature next == signature current || k > n - p + 1 then next else go next (k + 1)
        signature = Map.map (map snd . fst)
        override current r q
          | q == p, Just entry <- Map.lookup r current = entry
          | otherwise = lookupEntry r q

    evalRule look r p = case Map.lookup r rules of
      Nothing -> ([], p)
      Just rule ->
        let evals = [(i, evalElements look (alternativeElements (labeledAlternativeBody alt)) p) | (i, alt) <- zip [0 ..] (toList (parserRuleAlternatives rule))]
         in ( [(RuleNode r i children, e) | (i, (results, _)) <- evals, (children, e) <- results]
            , maximum (p : [f | (_, (_, f)) <- evals])
            )

    evalElements look elements = foldr (\e rest -> seqStep (evalElement look e) rest) emptyStep elements

    evalElement look e = case e of
      ElementAtom _ _ atom suffix -> suffixed suffix (evalAtom look atom)
      ElementBlock _ _ block suffix ->
        suffixed suffix (altStep [evalElements look (alternativeElements a) | a <- toList (blockAlternatives block)])
      ElementAction {} -> emptyStep

    evalAtom look atom p = case atom of
      AtomTerminal t -> terminal (terminalMatches t)
      AtomRuleRef name _ _ -> let (results, f) = look name p in ([([tree], e) | (tree, e) <- results], f)
      AtomNotSet (NotSet elements) -> terminal (\tok -> not (isEofToken tok) && not (any (`setMatches` tok) (toList elements)))
      AtomWildcard _ -> terminal (not . isEofToken)
      where
        terminal predicate = case toks BV.!? p of
          Just tok | predicate tok -> ([([TokenNode tok], p + 1)], p + 1)
          _ -> ([], p)

    terminalMatches t tok = case t of
      TerminalToken name _ -> tokenType tok == name
      TerminalLiteral lit _ -> either (const False) (== tokenText tok) (decodeStringLiteral lit)

    setMatches s tok = case s of
      SetTerminal t -> terminalMatches t tok
      SetRange _ -> False
      SetCharSet _ -> False

    furthest = snd (lookupEntry start 0)

emptyStep :: Step
emptyStep p = ([([], p)], p)

seqStep :: Step -> Step -> Step
seqStep a b p =
  let (rs, f) = a p
      continuations = [(b mid, c) | (c, mid) <- rs]
   in ( [(c ++ cs, e) | ((crs, _), c) <- continuations, (cs, e) <- crs]
      , maximum (f : [cf | ((_, cf), _) <- continuations])
      )

altStep :: [Step] -> Step
altStep steps p =
  let evals = map ($ p) steps
   in (concatMap fst evals, maximum (p : map snd evals))

guarded :: Step -> Step
guarded m p = let (rs, f) = m p in ([r | r@(_, q) <- rs, q /= p], f)

suffixed :: Maybe EbnfSuffix -> Step -> Step
suffixed suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> altStep [m, emptyStep]
  Just (EbnfSuffix Optional NonGreedy) -> altStep [emptyStep, m]
  Just (EbnfSuffix ZeroOrMore Greedy) -> greedyMany
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> lazyMany
  Just (EbnfSuffix OneOrMore Greedy) -> seqStep m greedyMany
  Just (EbnfSuffix OneOrMore NonGreedy) -> seqStep m lazyMany
  where
    greedyMany p = altStep [seqStep (guarded m) greedyMany, emptyStep] p
    lazyMany p = altStep [emptyStep, seqStep (guarded m) lazyMany] p
