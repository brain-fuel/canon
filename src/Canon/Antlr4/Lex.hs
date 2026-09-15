-- | The lexer interprets lexer rules with ANTLR semantics, longest match with ties by rule order,
-- and compiles them once because lexing dominated the time before it did.
-- ref:DEC-parser-generation
module Canon.Antlr4.Lex
  ( HookEffect (..)
  , LexerHooks (..)
  , SomeHooks (..)
  , noHooks
  , LexError (..)
  , renderLexError
  , LexerTable
  , buildLexerTable
  , tokenize
  , tokenizeWith
  ) where

import Canon.Antlr4.Escape (CharSetItem (..), decodeCharSet, decodeStringLiteral)
import Canon.Antlr4.Lexical (LineTable, lineTable, positionAt)
import Canon.Antlr4.Query (KnownLexerCommand (..), grammarOptions, implicitLiteralTokens, knownLexerCommand, lexerRuleElements)
import Data.Char (toLower, toUpper)
import Data.List.NonEmpty (NonEmpty (..))
import Canon.Antlr4.RuleGraph (leftRecursiveRules)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token
import Data.Foldable (toList)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as BV
import qualified Data.Vector.Unboxed as V

-- | The effects a lexer action or command may have, as data, so that target-language base lexers are
-- ported as hooks rather than as code inside the lexer.
data HookEffect
  = EffectPushMode Name
  | EffectPopMode
  | EffectMode Name
  | EffectMore
  | EffectSkip
  | EffectSetType Name
  | EffectSetTypeIfNested Name
  | EffectChannel Name
  deriving (Eq, Show)

-- | The hook interface a base lexer port implements: initial state, an action handler, and an emit
-- handler.
data LexerHooks s = LexerHooks
  { hooksInitial :: s
  , hooksOnAction :: Name -> ActionText -> Text -> s -> (s, [HookEffect])
  , hooksOnEmit :: Token -> s -> ([Token], s)
  }

-- | Hides the hook state type so a grammar can select any port by its superClass option.
data SomeHooks = forall s. SomeHooks (LexerHooks s)

-- | The hooks for a grammar with no base lexer, which do nothing.
noHooks :: LexerHooks ()
noHooks = LexerHooks () (\_ _ _ s -> (s, [])) (\t s -> ([t], s))

-- | Lexing fails at a position when no rule matches, and that position is what a user sees.
data LexError
  = LexNoMatch Position Name
  | LexEmptyMatch Position Name
  | LexLeftRecursive [Name]
  | LexUnknownMode Position Name
  | LexEmptyModeStack Position
  | LexUnknownCommand Name Name
  | LexInvalidLiteral Name Text
  deriving (Eq, Show)

-- | Renders a lexing failure with its position.
renderLexError :: LexError -> Text
renderLexError e = case e of
  LexNoMatch pos mode -> at pos ("no lexer rule of mode " <> nameText mode <> " matches")
  LexEmptyMatch pos rule -> at pos ("lexer rule " <> nameText rule <> " matched the empty string")
  LexLeftRecursive rules -> "left-recursive lexer rules: " <> T.intercalate ", " (map nameText rules)
  LexUnknownMode pos mode -> at pos ("unknown lexer mode " <> nameText mode)
  LexEmptyModeStack pos -> at pos "popMode with an empty mode stack"
  LexUnknownCommand rule command -> T.concat ["lexer rule ", nameText rule, " uses unknown command ", nameText command]
  LexInvalidLiteral rule literal -> T.concat ["lexer rule ", nameText rule, " has an invalid literal '", literal, "'"]
  where
    at (Position line column) message = T.concat [T.pack (show line), ":", T.pack (show column), ": ", message]

-- | The compiled form of a lexer grammar: decoded literals, character predicates, and start filters,
-- built once per grammar.
data LexerTable = LexerTable
  { tableModes :: Map Name [Int]
  , tableRules :: BV.Vector CompiledRule
  , tableCaseInsensitive :: Bool
  }

data CompiledAtom
  = CompiledLiteral (V.Vector Char)
  | CompiledRef Int
  | CompiledEof
  | CompiledChar (Char -> Bool)
  | CompiledNotSet [Either (Char -> Bool) Int]
  | CompiledFail

data CompiledElement
  = CompiledAtomElement CompiledAtom (Maybe EbnfSuffix)
  | CompiledBlock [[CompiledElement]] (Maybe EbnfSuffix)
  | CompiledAction

data CompiledAlternative = CompiledAlternative
  { compiledElements :: [CompiledElement]
  , compiledCommands :: [LexerCommand]
  , compiledActions :: [ActionText]
  }

data CompiledRule = CompiledRule
  { compiledName :: Name
  , compiledFragment :: Bool
  , compiledAlternatives :: [CompiledAlternative]
  , compiledCanStart :: Char -> Bool
  }

defaultMode :: Name
defaultMode = Name "DEFAULT_MODE"

-- | Compiles a lexer grammar, rejecting rules the interpreter cannot run.
buildLexerTable :: Grammar ann -> Either LexError LexerTable
buildLexerTable grammar = do
  let stripped = fmap (const ()) grammar
      implicit =
        [ LexerRule () (Name (T.pack ("T__" ++ show i))) False [] (LexerAlternative () [LexerElementAtom () (LexerAtomTerminal (TerminalLiteral lit [])) Nothing] [] :| [])
        | (i, lit) <- zip [0 :: Int ..] (implicitLiteralTokens stripped)
        ]
      topLevel = implicit ++ [l | RuleLexer l <- grammarRules stripped]
      modeGroups = (defaultMode, topLevel) : [(modeName m, modeRules m) | m <- grammarModes stripped]
      allLexerRules = topLevel ++ concatMap modeRules (grammarModes stripped)
      indexOf = Map.fromList (zip (map lexerRuleName allLexerRules) [0 ..])
      recursive = [n | n <- Set.toList (leftRecursiveRules stripped), Map.member n indexOf]
      ci = caseInsensitiveOption (grammarOptions stripped)
  if null recursive then Right () else Left (LexLeftRecursive recursive)
  mapM_ validateRule allLexerRules
  let compiled = BV.fromList (map (compileRule ci indexOf) allLexerRules)
      withStart = BV.imap (\i r -> r {compiledCanStart = startPredicate compiled i}) compiled
      modes = Map.fromList [(m, [indexOf Map.! lexerRuleName l | l <- rs]) | (m, rs) <- modeGroups]
  Right (LexerTable modes withStart ci)
  where
    validateRule l = mapM_ (validateElement (lexerRuleName l)) (lexerRuleElements l)
    validateElement rule e = case e of
      LexerElementAtom _ atom _ -> validateAtom rule atom
      _ -> Right ()
    validateAtom rule atom = case atom of
      LexerAtomTerminal (TerminalLiteral s _) -> validateLiteral rule s
      LexerAtomRange (CharRange lo hi) -> validateLiteral rule lo >> validateLiteral rule hi
      LexerAtomCharSet cs -> either (const (Left (LexInvalidLiteral rule (charSetRaw cs)))) (const (Right ())) (decodeCharSet cs)
      LexerAtomNotSet (NotSet elements) -> mapM_ (validateSetElement rule) (toList elements)
      LexerAtomWildcard _ -> Right ()
      LexerAtomTerminal (TerminalToken _ _) -> Right ()
    validateSetElement rule s = case s of
      SetTerminal (TerminalLiteral lit _) -> validateLiteral rule lit
      SetRange (CharRange lo hi) -> validateLiteral rule lo >> validateLiteral rule hi
      SetCharSet cs -> either (const (Left (LexInvalidLiteral rule (charSetRaw cs)))) (const (Right ())) (decodeCharSet cs)
      SetTerminal (TerminalToken _ _) -> Right ()
    validateLiteral rule s = either (const (Left (LexInvalidLiteral rule (stringLiteralRaw s)))) (const (Right ())) (decodeStringLiteral s)

compileRule :: Bool -> Map Name Int -> LexerRule () -> CompiledRule
compileRule ci indexOf rule =
  CompiledRule (lexerRuleName rule) (lexerRuleIsFragment rule) (map compileAlternative (toList (lexerRuleAlternatives rule))) (const True)
  where
    compileAlternative alt =
      CompiledAlternative
        (map compileElement (lexerAlternativeElements alt))
        (lexerAlternativeCommands alt)
        [t | LexerElementAction _ _ t <- alternativeElementsDeep alt]
    compileElement e = case e of
      LexerElementAtom _ atom suffix -> CompiledAtomElement (compileAtom atom) suffix
      LexerElementBlock _ alts suffix -> CompiledBlock [map compileElement (lexerAlternativeElements a) | a <- toList alts] suffix
      LexerElementAction {} -> CompiledAction
    compileAtom atom = case atom of
      LexerAtomTerminal (TerminalLiteral lit _) -> CompiledLiteral (V.fromList (T.unpack (decodedText lit)))
      LexerAtomTerminal (TerminalToken name _)
        | name == eofTokenName -> CompiledEof
        | otherwise -> maybe CompiledFail CompiledRef (Map.lookup name indexOf)
      LexerAtomRange range -> CompiledChar (insensitive (rangePredicate range))
      LexerAtomCharSet cs -> CompiledChar (insensitive (charSetPredicate cs))
      LexerAtomNotSet (NotSet elements) -> CompiledNotSet (map compileSetElement (toList elements))
      LexerAtomWildcard _ -> CompiledChar (const True)
    compileSetElement s = case s of
      SetTerminal (TerminalLiteral lit _) -> Left (insensitive (\c -> decodedChar lit == Just c))
      SetTerminal (TerminalToken name _) -> maybe (Left (const False)) Right (Map.lookup name indexOf)
      SetRange range -> Left (insensitive (rangePredicate range))
      SetCharSet cs -> Left (insensitive (charSetPredicate cs))
    insensitive predicate c
      | ci = predicate c || predicate (toLower c) || predicate (toUpper c)
      | otherwise = predicate c

decodedText :: StringLiteral -> Text
decodedText = either (const T.empty) id . decodeStringLiteral

decodedChar :: StringLiteral -> Maybe Char
decodedChar lit = case decodeStringLiteral lit of
  Right t | T.length t == 1 -> Just (T.head t)
  _ -> Nothing

rangePredicate :: CharRange -> Char -> Bool
rangePredicate (CharRange lo hi) = case (decodedChar lo, decodedChar hi) of
  (Just l, Just h) -> \c -> c >= l && c <= h
  _ -> const False

charSetPredicate :: CharSet -> Char -> Bool
charSetPredicate cs = case decodeCharSet cs of
  Right items -> \c -> any (itemMatches c) items
  Left _ -> const False
  where
    itemMatches c item = case item of
      CharSetSingle x -> c == x
      CharSetRange lo hi -> c >= lo && c <= hi
      CharSetProperty _ _ -> False

startPredicate :: BV.Vector CompiledRule -> Int -> Char -> Bool
startPredicate rules index = case startOfRule Set.empty index of
  Nothing -> const True
  Just (chars, nullable) -> if nullable then const True else \c -> Set.member c chars || Set.member (toLower c) chars || Set.member (toUpper c) chars
  where
    startOfRule visited i
      | Set.member i visited = Nothing
      | otherwise = unionAlternatives (map (startOfElements (Set.insert i visited) . compiledElements) (compiledAlternatives (rules BV.! i)))
    unionAlternatives = foldr combine (Just (Set.empty, False))
    combine a b = case (a, b) of
      (Just (x, nx), Just (y, ny)) -> Just (Set.union x y, nx || ny)
      _ -> Nothing
    startOfElements visited elements = case elements of
      [] -> Just (Set.empty, True)
      (e : rest) -> case startOfElement visited e of
        Nothing -> Nothing
        Just (chars, nullable)
          | nullable || suffixNullable e -> combine (Just (chars, False)) (startOfElements visited rest)
          | otherwise -> Just (chars, False)
    suffixNullable e = case e of
      CompiledAtomElement _ (Just (EbnfSuffix q _)) -> q /= OneOrMore
      CompiledBlock _ (Just (EbnfSuffix q _)) -> q /= OneOrMore
      _ -> False
    startOfElement visited e = case e of
      CompiledAction -> Just (Set.empty, True)
      CompiledBlock alts _ -> unionAlternatives (map (startOfElements visited) alts)
      CompiledAtomElement atom _ -> case atom of
        CompiledLiteral t -> case V.toList (V.take 1 t) of
          (c : _) -> Just (Set.fromList [c, toLower c, toUpper c], False)
          [] -> Just (Set.empty, True)
        CompiledRef i -> startOfRule visited i
        CompiledEof -> Just (Set.empty, True)
        CompiledChar _ -> Nothing
        CompiledNotSet _ -> Nothing
        CompiledFail -> Just (Set.empty, False)

data Env = Env
  { envInput :: V.Vector Char
  , envRules :: BV.Vector CompiledRule
  , envCaseInsensitive :: Bool
  }

type Match = Int -> (Int -> [Int]) -> [Int]

matchRuleAlternatives :: Env -> CompiledRule -> Int -> [(Int, Int)]
matchRuleAlternatives env rule p =
  [(e, i) | (i, alt) <- zip [0 ..] (compiledAlternatives rule), e <- matchElements env (compiledElements alt) p (\e -> [e])]

matchElements :: Env -> [CompiledElement] -> Match
matchElements env elements p k = case elements of
  [] -> k p
  (e : rest) -> matchElement env e p (\p' -> matchElements env rest p' k)

matchElement :: Env -> CompiledElement -> Match
matchElement env e = case e of
  CompiledAtomElement atom suffix -> withSuffix suffix (matchAtom env atom)
  CompiledBlock alts suffix -> withSuffix suffix (\p k -> concat [matchElements env a p k | a <- alts])
  CompiledAction -> \p k -> k p

withSuffix :: Maybe EbnfSuffix -> Match -> Match
withSuffix suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> \p k -> m p k ++ k p
  Just (EbnfSuffix Optional NonGreedy) -> \p k -> firstNonEmpty (k p) (m p k)
  Just (EbnfSuffix ZeroOrMore Greedy) -> greedyMany
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> lazyMany
  Just (EbnfSuffix OneOrMore Greedy) -> \p k -> m p (\p' -> if p' == p then k p' else greedyMany p' k)
  Just (EbnfSuffix OneOrMore NonGreedy) -> \p k -> m p (\p' -> if p' == p then k p' else lazyMany p' k)
  where
    greedyMany p k = m p (\p' -> if p' == p then [] else greedyMany p' k) ++ k p
    lazyMany p k = firstNonEmpty (k p) (m p (\p' -> if p' == p then [] else lazyMany p' k))
    firstNonEmpty xs ys = case xs of
      [] -> ys
      _ -> xs

charAt :: Env -> Int -> Maybe Char
charAt env p = envInput env V.!? p

caseInsensitiveOption :: [Option] -> Bool
caseInsensitiveOption opts =
  case [v | Option (Name "caseInsensitive") (OptionValueName (QualifiedName (Name v :| []))) <- opts] of
    (v : _) -> v == "true"
    [] -> False

sameChar :: Env -> Char -> Char -> Bool
sameChar env a b
  | envCaseInsensitive env = a == b || toLower a == toLower b
  | otherwise = a == b

matchAtom :: Env -> CompiledAtom -> Match
matchAtom env atom p k = case atom of
  CompiledLiteral text
    | matchesText env text p -> k (p + V.length text)
    | otherwise -> []
  CompiledRef i -> matchRuleReference env i p k
  CompiledEof -> if p == V.length (envInput env) then k p else []
  CompiledChar predicate -> singleChar predicate
  CompiledNotSet elements -> singleChar (\c -> not (any (setElementMatches env p c) elements))
  CompiledFail -> []
  where
    singleChar predicate = case charAt env p of
      Just c | predicate c -> k (p + 1)
      _ -> []

matchRuleReference :: Env -> Int -> Match
matchRuleReference env i p k = concat [matchElements env (compiledElements alt) p k | alt <- compiledAlternatives (envRules env BV.! i)]

matchesText :: Env -> V.Vector Char -> Int -> Bool
matchesText env text p =
  p + len <= V.length input && go 0
  where
    input = envInput env
    len = V.length text
    go i = i >= len || (sameChar env (V.unsafeIndex text i) (V.unsafeIndex input (p + i)) && go (i + 1))

setElementMatches :: Env -> Int -> Char -> Either (Char -> Bool) Int -> Bool
setElementMatches env p c element = case element of
  Left predicate -> predicate c
  Right i -> not (null [e | e <- matchRuleReference env i p (\e -> [e]), e == p + 1])

data LexState s = LexState
  { stateOffset :: Int
  , stateModes :: [Name]
  , stateMoreStart :: Maybe Int
  , stateHooks :: s
  }

-- | Tokenizes with the hooks the grammar selects, which is what every caller wants.
tokenize :: Grammar ann -> Text -> Either LexError [Token]
tokenize grammar source = do
  table <- buildLexerTable grammar
  tokenizeWith noHooks table source

-- | Tokenizes with explicit hooks, for tests and for grammars whose adaptor is chosen by the caller.
tokenizeWith :: LexerHooks s -> LexerTable -> Text -> Either LexError [Token]
tokenizeWith hooks table source = go (LexState 0 [defaultMode] Nothing (hooksInitial hooks))
  where
    input = V.fromList (T.unpack source)
    env = Env input (tableRules table) (tableCaseInsensitive table)
    lines' = lineTable source
    n = V.length input

    go st
      | stateOffset st >= n =
          let (emitted, _) = hooksOnEmit hooks (mkToken lines' input eofTokenName n n defaultChannelName) (stateHooks st)
           in Right emitted
      | otherwise = do
          mode <- currentMode st
          rules <- maybe (Left (LexUnknownMode (positionAt lines' (stateOffset st)) mode)) Right (Map.lookup mode (tableModes table))
          let p = stateOffset st
              current = input V.! p
              candidates =
                [ (e, i, rule)
                | index <- rules
                , let rule = tableRules table BV.! index
                , not (compiledFragment rule)
                , compiledCanStart rule current
                , (e, i) <- matchRuleAlternatives env rule p
                ]
          case longest candidates of
            Nothing -> Left (LexNoMatch (positionAt lines' p) mode)
            Just (e, altIndex, rule)
              | e == p -> Left (LexEmptyMatch (positionAt lines' p) (compiledName rule))
              | otherwise -> emit st rule altIndex e

    longest candidates = foldl' better Nothing candidates
      where
        better acc c@(e, _, _) = case acc of
          Just (e', _, _) | e' >= e -> acc
          _ -> Just c

    currentMode st = maybe (Left (LexEmptyModeStack (positionAt lines' (stateOffset st)))) Right (listToMaybe (stateModes st))

    emit st rule altIndex end = do
      let alternative = compiledAlternatives rule !! altIndex
          start = fromMaybe (stateOffset st) (stateMoreStart st)
          matched = T.pack (V.toList (V.slice start (end - start) input))
          (hookState, actionEffects) = foldl' runAction (stateHooks st, []) (compiledActions alternative)
          runAction (s, effects) text = let (s', more) = hooksOnAction hooks (compiledName rule) text matched s in (s', effects ++ more)
      commandEffects <- mapM (commandEffect (compiledName rule)) (compiledCommands alternative)
      applied <- applyEffects (positionAt lines' (stateOffset st)) (actionEffects ++ commandEffects) (Applied (compiledName rule) defaultChannelName False False (stateModes st))
      let text = T.pack (V.toList (V.slice start (end - start) input))
          token = mkToken lines' input (appliedType applied) start end (appliedChannel applied)
          next more = LexState end (appliedModes applied) more
      if appliedSkip applied
        then go (next Nothing hookState)
        else
          if appliedMore applied
            then go (next (Just start) hookState)
            else do
              let (emitted, hookState') = hooksOnEmit hooks token {tokenText = text} hookState
              rest <- go (next Nothing hookState')
              Right (emitted ++ rest)

    commandEffect rule command = case knownLexerCommand command of
      Just LexerSkip -> Right EffectSkip
      Just LexerMore -> Right EffectMore
      Just LexerPopMode -> Right EffectPopMode
      Just (LexerType t) -> Right (EffectSetType t)
      Just (LexerChannel c) -> Right (EffectChannel c)
      Just (LexerMode m) -> Right (EffectMode m)
      Just (LexerPushMode m) -> Right (EffectPushMode m)
      Nothing -> Left (LexUnknownCommand rule (lexerCommandName command))

data Applied = Applied
  { appliedType :: Name
  , appliedChannel :: Name
  , appliedSkip :: Bool
  , appliedMore :: Bool
  , appliedModes :: [Name]
  }

applyEffects :: Position -> [HookEffect] -> Applied -> Either LexError Applied
applyEffects pos effects applied = case effects of
  [] -> Right applied
  (e : rest) -> applyOne e >>= applyEffects pos rest
  where
    applyOne e = case e of
      EffectPushMode m -> Right applied {appliedModes = m : appliedModes applied}
      EffectPopMode -> case appliedModes applied of
        (_ : remaining@(_ : _)) -> Right applied {appliedModes = remaining}
        _ -> Left (LexEmptyModeStack pos)
      EffectMode m -> case appliedModes applied of
        (_ : remaining) -> Right applied {appliedModes = m : remaining}
        [] -> Right applied {appliedModes = [m]}
      EffectMore -> Right applied {appliedMore = True}
      EffectSkip -> Right applied {appliedSkip = True}
      EffectSetType t -> Right applied {appliedType = t}
      EffectSetTypeIfNested t -> Right (if length (appliedModes applied) > 1 then applied {appliedType = t} else applied)
      EffectChannel c -> Right applied {appliedChannel = c}

alternativeElementsDeep :: LexerAlternative () -> [LexerElement ()]
alternativeElementsDeep = concatMap deep . lexerAlternativeElements
  where
    deep e = e : case e of
      LexerElementBlock _ alts _ -> concatMap alternativeElementsDeep (toList alts)
      _ -> []

mkToken :: LineTable -> V.Vector Char -> Name -> Int -> Int -> Name -> Token
mkToken lines' input ty start end channel =
  Token ty (T.pack (V.toList (V.slice start (end - start) input))) start end channel (positionAt lines' start)
