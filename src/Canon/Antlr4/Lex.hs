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
import Canon.Antlr4.Query (KnownLexerCommand (..), allRules, grammarOptions, implicitLiteralTokens, knownLexerCommand, lexerRuleElements)
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
import qualified Data.Vector.Unboxed as V

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

data LexerHooks s = LexerHooks
  { hooksInitial :: s
  , hooksOnAction :: Name -> ActionText -> Text -> s -> (s, [HookEffect])
  , hooksOnEmit :: Token -> s -> ([Token], s)
  }

data SomeHooks = forall s. SomeHooks (LexerHooks s)

noHooks :: LexerHooks ()
noHooks = LexerHooks () (\_ _ _ s -> (s, [])) (\t s -> ([t], s))

data LexError
  = LexNoMatch Position Name
  | LexEmptyMatch Position Name
  | LexLeftRecursive [Name]
  | LexUnknownMode Position Name
  | LexEmptyModeStack Position
  | LexUnknownCommand Name Name
  | LexInvalidLiteral Name Text
  deriving (Eq, Show)

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

data LexerTable = LexerTable
  { tableModes :: Map Name [LexerRule ()]
  , tableRules :: Map Name (LexerRule ())
  , tableCaseInsensitive :: Bool
  }

defaultMode :: Name
defaultMode = Name "DEFAULT_MODE"

buildLexerTable :: Grammar ann -> Either LexError LexerTable
buildLexerTable grammar = do
  let stripped = fmap (const ()) grammar
      implicit =
        [ LexerRule () (Name (T.pack ("T__" ++ show i))) False [] (LexerAlternative () [LexerElementAtom () (LexerAtomTerminal (TerminalLiteral lit [])) Nothing] [] :| [])
        | (i, lit) <- zip [0 :: Int ..] (implicitLiteralTokens stripped)
        ]
      topLevel = implicit ++ [l | RuleLexer l <- grammarRules stripped]
      modes = Map.fromList ((defaultMode, topLevel) : [(modeName m, modeRules m) | m <- grammarModes stripped])
      rules = Map.fromList [(lexerRuleName l, l) | RuleLexer l <- allRules stripped]
      recursive = [n | n <- Set.toList (leftRecursiveRules stripped), Map.member n rules]
  if null recursive then Right () else Left (LexLeftRecursive recursive)
  mapM_ validateRule (Map.elems rules)
  Right (LexerTable modes rules (caseInsensitiveOption (grammarOptions stripped)))
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

data Env = Env
  { envInput :: V.Vector Char
  , envRules :: Map Name (LexerRule ())
  , envCaseInsensitive :: Bool
  }

type Match = Int -> (Int -> [Int]) -> [Int]

matchRuleAlternatives :: Env -> LexerRule () -> Int -> [(Int, Int)]
matchRuleAlternatives env rule p =
  [(e, i) | (i, alt) <- zip [0 ..] (toList (lexerRuleAlternatives rule)), e <- matchAlternative env alt p (\e -> [e])]

matchAlternative :: Env -> LexerAlternative () -> Match
matchAlternative env alt = matchElements env (lexerAlternativeElements alt)

matchElements :: Env -> [LexerElement ()] -> Match
matchElements env elements p k = case elements of
  [] -> k p
  (e : rest) -> matchElement env e p (\p' -> matchElements env rest p' k)

matchElement :: Env -> LexerElement () -> Match
matchElement env e = case e of
  LexerElementAtom _ atom suffix -> withSuffix suffix (matchAtom env atom)
  LexerElementBlock _ alts suffix -> withSuffix suffix (\p k -> concat [matchAlternative env a p k | a <- toList alts])
  LexerElementAction {} -> \p k -> k p

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

charPredicate :: Env -> (Char -> Bool) -> Char -> Bool
charPredicate env predicate c
  | envCaseInsensitive env = predicate c || predicate (toLower c) || predicate (toUpper c)
  | otherwise = predicate c

matchAtom :: Env -> LexerAtom -> Match
matchAtom env atom p k = case atom of
  LexerAtomTerminal (TerminalLiteral lit _) -> case decodeStringLiteral lit of
    Right text | matchesText env text p -> k (p + T.length text)
    _ -> []
  LexerAtomTerminal (TerminalToken name _)
    | name == eofTokenName -> if p == V.length (envInput env) then k p else []
    | otherwise -> matchRuleReference env name p k
  LexerAtomRange range -> singleChar (charPredicate env (rangeMatches range))
  LexerAtomCharSet cs -> singleChar (charPredicate env (charSetMatches cs))
  LexerAtomNotSet (NotSet elements) -> singleChar (\c -> not (any (setElementMatches env p c) (toList elements)))
  LexerAtomWildcard _ -> singleChar (const True)
  where
    singleChar predicate = case charAt env p of
      Just c | predicate c -> k (p + 1)
      _ -> []

matchRuleReference :: Env -> Name -> Match
matchRuleReference env name p k = case Map.lookup name (envRules env) of
  Just rule -> concat [matchAlternative env alt p k | alt <- toList (lexerRuleAlternatives rule)]
  Nothing -> []

matchesText :: Env -> Text -> Int -> Bool
matchesText env text p = all (\(i, c) -> maybe False (sameChar env c) (charAt env (p + i))) (zip [0 ..] (T.unpack text))

rangeMatches :: CharRange -> Char -> Bool
rangeMatches (CharRange lo hi) c = case (decodedChar lo, decodedChar hi) of
  (Just l, Just h) -> c >= l && c <= h
  _ -> False

decodedChar :: StringLiteral -> Maybe Char
decodedChar lit = case decodeStringLiteral lit of
  Right t | T.length t == 1 -> Just (T.head t)
  _ -> Nothing

charSetMatches :: CharSet -> Char -> Bool
charSetMatches cs c = case decodeCharSet cs of
  Right items -> any itemMatches items
  Left _ -> False
  where
    itemMatches item = case item of
      CharSetSingle x -> c == x
      CharSetRange lo hi -> c >= lo && c <= hi
      CharSetProperty _ _ -> False

setElementMatches :: Env -> Int -> Char -> SetElement -> Bool
setElementMatches env p c s = case s of
  SetTerminal (TerminalLiteral lit _) -> maybe False (sameChar env c) (decodedChar lit)
  SetTerminal (TerminalToken name _) -> not (null [e | e <- matchRuleReference env name p (\e -> [e]), e == p + 1])
  SetRange range -> charPredicate env (rangeMatches range) c
  SetCharSet cs -> charPredicate env (charSetMatches cs) c

data LexState s = LexState
  { stateOffset :: Int
  , stateModes :: [Name]
  , stateMoreStart :: Maybe Int
  , stateHooks :: s
  }

tokenize :: Grammar ann -> Text -> Either LexError [Token]
tokenize grammar source = do
  table <- buildLexerTable grammar
  tokenizeWith noHooks table source

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
              candidates = [(e, i, rule) | rule <- rules, not (lexerRuleIsFragment rule), (e, i) <- matchRuleAlternatives env rule p]
          case longest candidates of
            Nothing -> Left (LexNoMatch (positionAt lines' p) mode)
            Just (e, altIndex, rule)
              | e == p -> Left (LexEmptyMatch (positionAt lines' p) (lexerRuleName rule))
              | otherwise -> emit st rule altIndex e

    longest candidates = foldl' better Nothing candidates
      where
        better acc c@(e, _, _) = case acc of
          Just (e', _, _) | e' >= e -> acc
          _ -> Just c

    currentMode st = maybe (Left (LexEmptyModeStack (positionAt lines' (stateOffset st)))) Right (listToMaybe (stateModes st))

    emit st rule altIndex end = do
      let alternative = toList (lexerRuleAlternatives rule) !! altIndex
          actions = [t | LexerElementAction _ _ t <- alternativeElementsDeep alternative]
          start = fromMaybe (stateOffset st) (stateMoreStart st)
          matched = T.pack (V.toList (V.slice start (end - start) input))
          (hookState, actionEffects) = foldl' runAction (stateHooks st, []) actions
          runAction (s, effects) text = let (s', more) = hooksOnAction hooks (lexerRuleName rule) text matched s in (s', effects ++ more)
      commandEffects <- mapM (commandEffect (lexerRuleName rule)) (lexerAlternativeCommands alternative)
      applied <- applyEffects (positionAt lines' (stateOffset st)) (actionEffects ++ commandEffects) (Applied (lexerRuleName rule) defaultChannelName False False (stateModes st))
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
