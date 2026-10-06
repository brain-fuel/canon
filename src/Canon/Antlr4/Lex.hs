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
import Data.Char (GeneralCategory (..), generalCategory, isAlpha, isSpace, toLower, toUpper)
import Data.List.NonEmpty (NonEmpty (..))
import Canon.Antlr4.RuleGraph (leftRecursiveRules)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token
import Data.Foldable (toList)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe)
import qualified Data.IntSet as IntSet
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
  , hooksOnAction :: Name -> ActionText -> Text -> Text -> s -> (s, [HookEffect])
  , hooksOnPredicate :: Name -> ActionText -> Text -> Int -> s -> Bool
  , hooksOnEmit :: Token -> s -> ([Token], s)
  }

-- | Hides the hook state type so a grammar can select any port by its superClass option.
data SomeHooks = forall s. SomeHooks (LexerHooks s)

-- | The hooks for a grammar with no base lexer, which do nothing.
noHooks :: LexerHooks ()
noHooks = LexerHooks () (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) (\t s -> ([t], s))

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
  , tableStarters :: Map Name (BV.Vector [CompiledRule])
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
  | CompiledPredicate ActionText

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
  let compiled = foldCharClasses ci (BV.fromList (map (compileRule ci indexOf) allLexerRules))
      withStart = BV.imap (\i r -> r {compiledCanStart = startPredicate compiled i}) compiled
      modes = Map.fromList [(m, [indexOf Map.! lexerRuleName l | l <- rs]) | (m, rs) <- modeGroups]
  Right (LexerTable modes withStart ci (Map.map (starters withStart) modes))
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
        [t | LexerElementAction _ EmbeddedAction t <- alternativeElementsDeep alt]
    compileElement e = case e of
      LexerElementAtom _ atom suffix -> CompiledAtomElement (compileAtom atom) suffix
      LexerElementBlock _ alts suffix -> CompiledBlock [map compileElement (lexerAlternativeElements a) | a <- toList alts] suffix
      LexerElementAction _ SemanticPredicate t -> CompiledPredicate t
      LexerElementAction _ EmbeddedAction _ -> CompiledAction
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

-- | Folds every element that matches one character into one character test: a one-character
-- literal, a range or set, a negated set of such, a block of alternatives that are each one, and a
-- reference to a rule whose alternatives are each one. The grammars-v4 lexers spell Unicode classes
-- as fragments of hundreds of ranges, which the matcher read as hundreds of alternatives for every
-- character of every identifier; generated C# of 31,000 lines spent four fifths of its time there.
-- A folded test answers ASCII from a table. Only duplicate ends of the same length are lost, which
-- neither the longest match nor the rule it comes from depends on. ref:DEC-lexer-performance
foldCharClasses :: Bool -> BV.Vector CompiledRule -> BV.Vector CompiledRule
foldCharClasses ci rules = folded
  where
    folded = BV.map foldRule rules
    -- A fragment's alternatives that each match one character become one, tried first: a fragment
    -- is matched only by reference, where the order of its alternatives changes no token, as
    -- JavaScript's IdentifierPart, a Unicode class or an escape, is.
    foldRule r
      | compiledFragment r = case mergeClasses (map compiledElements (compiledAlternatives r)) of
          Just merged -> r {compiledAlternatives = [CompiledAlternative (map foldElement es) [] [] | es <- merged]}
          Nothing -> r {compiledAlternatives = map foldAlternative (compiledAlternatives r)}
      | otherwise = r {compiledAlternatives = map foldAlternative (compiledAlternatives r)}
    mergeClasses alts = case [(t, es) | es <- alts, Just t <- [classOfElements IntSet.empty es]] of
      tests@(_ : _ : _) -> Just ([CompiledAtomElement (CompiledChar (asciiTable (anyOf (map fst tests)))) Nothing] : [es | es <- alts, Nothing <- [classOfElements IntSet.empty es]])
      _ -> Nothing
    -- Each rule's class, from the folded rules, so a fragment of fragments folds; a reference cycle
    -- is cut by the visited set and stays a reference.
    classes = BV.generate (BV.length rules) (classOfRule IntSet.empty)
    classOfRule visited i
      | IntSet.member i visited = Nothing
      | otherwise = do
          tests <- mapM (classOfElements (IntSet.insert i visited) . compiledElements) (compiledAlternatives (rules BV.! i))
          if null tests then Nothing else Just (anyOf tests)
    classOfElements visited es = case es of
      [e] -> classOfElement visited e
      _ -> Nothing
    classOfElement visited e = case e of
      CompiledAtomElement atom Nothing -> classOfAtom visited atom
      CompiledBlock alts Nothing -> do
        tests <- mapM (classOfElements visited) alts
        if null tests then Nothing else Just (anyOf tests)
      _ -> Nothing
    classOfAtom visited atom = case atom of
      CompiledLiteral text | V.length text == 1 -> let x = V.head text in Just (if ci then \c -> c == x || toLower c == toLower x else (== x))
      CompiledChar test -> Just test
      CompiledRef i -> classOfRule visited i
      CompiledNotSet elements -> do
        tests <- mapM (either Just (classOfRule visited)) elements
        Just (\c -> not (any ($ c) tests))
      _ -> Nothing
    anyOf tests = case tests of
      [t] -> t
      _ -> \c -> any ($ c) tests
    foldAlternative alt = alt {compiledElements = map foldElement (compiledElements alt)}
    foldElement e = case e of
      CompiledAtomElement atom suffix -> case foldAtom atom of
        Just test -> CompiledAtomElement (CompiledChar test) suffix
        Nothing -> e
      CompiledBlock alts suffix -> case mapM (classOfElements IntSet.empty) alts of
        Just tests@(_ : _) -> CompiledAtomElement (CompiledChar (asciiTable (anyOf tests))) suffix
        _ -> CompiledBlock (map (map foldElement) (fromMaybe alts (mergeClasses alts))) suffix
      _ -> e
    foldAtom atom = case atom of
      CompiledRef i -> asciiTable <$> classes BV.! i
      CompiledNotSet _ -> asciiTable <$> classOfAtom IntSet.empty atom
      CompiledChar test -> Just (asciiTable test)
      _ -> Nothing

-- | A character test that answers ASCII from a table made once.
asciiTable :: (Char -> Bool) -> Char -> Bool
asciiTable test = \c -> if c < '\128' then V.unsafeIndex table (fromEnum c) else test c
  where
    table = V.generate 128 (test . toEnum)

-- | The rules of a mode that can start at each ASCII character, in rule order, made once, so a token
-- is not tried against every rule of its mode: the TypeScript lexer spent a sixth of a parse
-- asking each of its rules whether it could start. ref:DEC-lexer-performance
starters :: BV.Vector CompiledRule -> [Int] -> BV.Vector [CompiledRule]
starters rules indices = BV.generate 128 (\c -> [rule | rule <- ruleList, compiledCanStart rule (toEnum c)])
  where
    ruleList = [rule | i <- indices, let rule = rules BV.! i, not (compiledFragment rule)]

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
      CharSetProperty positive name -> propertyMatches name c == positive

-- | A Unicode property class in a character set, by general category or by the few named
-- properties the grammars-v4 lexers use, so a grammar written for identifiers in any script, such
-- as Rust's or Kotlin's, lexes as its author meant. ref:DEC-rust-grammar ref:DEC-more-languages
propertyMatches :: Text -> Char -> Bool
propertyMatches name c = case name of
  "L" -> cat `elem` [UppercaseLetter, LowercaseLetter, TitlecaseLetter, ModifierLetter, OtherLetter]
  "Lu" -> cat == UppercaseLetter
  "Ll" -> cat == LowercaseLetter
  "Lt" -> cat == TitlecaseLetter
  "Lm" -> cat == ModifierLetter
  "Lo" -> cat == OtherLetter
  "M" -> cat `elem` [NonSpacingMark, SpacingCombiningMark, EnclosingMark]
  "Mn" -> cat == NonSpacingMark
  "Mc" -> cat == SpacingCombiningMark
  "Me" -> cat == EnclosingMark
  "N" -> cat `elem` [DecimalNumber, LetterNumber, OtherNumber]
  "Nd" -> cat == DecimalNumber
  "Nl" -> cat == LetterNumber
  "No" -> cat == OtherNumber
  "P" -> cat `elem` [ConnectorPunctuation, DashPunctuation, OpenPunctuation, ClosePunctuation, InitialQuote, FinalQuote, OtherPunctuation]
  "Pc" -> cat == ConnectorPunctuation
  "Pd" -> cat == DashPunctuation
  "Ps" -> cat == OpenPunctuation
  "Pe" -> cat == ClosePunctuation
  "Pi" -> cat == InitialQuote
  "Pf" -> cat == FinalQuote
  "Po" -> cat == OtherPunctuation
  "S" -> cat `elem` [MathSymbol, CurrencySymbol, ModifierSymbol, OtherSymbol]
  "Sm" -> cat == MathSymbol
  "Sc" -> cat == CurrencySymbol
  "Sk" -> cat == ModifierSymbol
  "So" -> cat == OtherSymbol
  "Z" -> cat `elem` [Space, LineSeparator, ParagraphSeparator]
  "Zs" -> cat == Space
  "Zl" -> cat == LineSeparator
  "Zp" -> cat == ParagraphSeparator
  "C" -> cat `elem` [Control, Format, Surrogate, PrivateUse, NotAssigned]
  "Cc" -> cat == Control
  "Cf" -> cat == Format
  "Cs" -> cat == Surrogate
  "Co" -> cat == PrivateUse
  "Cn" -> cat == NotAssigned
  "Other_ID_Start" -> c `elem` ("\x1885\x1886\x2118\x212E\x309B\x309C" :: String)
  "Other_ID_Continue" -> c `elem` ("\x00B7\x0387\x1369\x136A\x136B\x136C\x136D\x136E\x136F\x1370\x1371\x19DA" :: String)
  "White_Space" -> isSpace c
  "Alphabetic" -> isAlpha c
  _ -> False
  where
    cat = generalCategory c

-- | Whether a rule can start at a character: by the first characters of its literals and the tests
-- of its character classes, so that a rule starting with a class, as an identifier does, is not
-- tried at every character. ref:DEC-lexer-performance
startPredicate :: BV.Vector CompiledRule -> Int -> Char -> Bool
startPredicate rules index = case startOfRule Set.empty index of
  Nothing -> const True
  Just (Start chars tests nullable)
    | nullable -> const True
    | otherwise -> asciiTable (\c -> Set.member c chars || Set.member (toLower c) chars || Set.member (toUpper c) chars || any ($ c) tests)
  where
    startOfRule visited i
      | Set.member i visited = Nothing
      | otherwise = unionAlternatives (map (startOfElements (Set.insert i visited) . compiledElements) (compiledAlternatives (rules BV.! i)))
    unionAlternatives = foldr combine (Just (Start Set.empty [] False))
    combine a b = case (a, b) of
      (Just (Start x tx nx), Just (Start y ty ny)) -> Just (Start (Set.union x y) (tx ++ ty) (nx || ny))
      _ -> Nothing
    startOfElements visited elements = case elements of
      [] -> Just (Start Set.empty [] True)
      (e : rest) -> case startOfElement visited e of
        Nothing -> Nothing
        Just (Start chars tests nullable)
          | nullable || suffixNullable e -> combine (Just (Start chars tests False)) (startOfElements visited rest)
          | otherwise -> Just (Start chars tests False)
    suffixNullable e = case e of
      CompiledAtomElement _ (Just (EbnfSuffix q _)) -> q /= OneOrMore
      CompiledBlock _ (Just (EbnfSuffix q _)) -> q /= OneOrMore
      _ -> False
    startOfElement visited e = case e of
      CompiledAction -> Just (Start Set.empty [] True)
      CompiledPredicate _ -> Just (Start Set.empty [] True)
      CompiledBlock alts _ -> unionAlternatives (map (startOfElements visited) alts)
      CompiledAtomElement atom _ -> case atom of
        CompiledLiteral t -> case V.toList (V.take 1 t) of
          (c : _) -> Just (Start (Set.fromList [c, toLower c, toUpper c]) [] False)
          [] -> Just (Start Set.empty [] True)
        CompiledRef i -> startOfRule visited i
        CompiledEof -> Just (Start Set.empty [] True)
        CompiledChar test -> Just (Start Set.empty [test] False)
        CompiledNotSet _ -> Nothing
        CompiledFail -> Just (Start Set.empty [] False)

-- | The characters and character tests a rule may start with, and whether it may match nothing.
data Start = Start (Set.Set Char) [Char -> Bool] Bool

-- | A semantic predicate is decided where it sits in the rule, by the position reached, so a
-- predicate inside one alternative of a block gates only that alternative, as in ANTLR.
data Env = Env
  { envInput :: V.Vector Char
  , envRules :: BV.Vector CompiledRule
  , envCaseInsensitive :: Bool
  , envPredicate :: ActionText -> Int -> Bool
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
  CompiledAtomElement (CompiledChar test) (Just (EbnfSuffix ZeroOrMore Greedy)) -> \p k -> concatMap k [p .. classRun env test p]
  CompiledAtomElement (CompiledChar test) (Just (EbnfSuffix OneOrMore Greedy)) -> \p k -> case charAt env p of
    Just c | test c -> concatMap k [p + 1 .. classRun env test (p + 1)]
    _ -> []
  CompiledAtomElement atom suffix -> withSuffix suffix (matchAtom env atom)
  CompiledBlock alts suffix -> withSuffix suffix (\p k -> concatMatches [matchElements env a p k | a <- alts])
  CompiledAction -> \p k -> k p
  CompiledPredicate t -> \p k -> if envPredicate env t p then k p else []

-- | Applies an EBNF suffix to a match. A greedy loop lists the shorter end first: the caller takes
-- the longest match, so the order of ends does not matter, and appending the deeper ends last keeps
-- a loop over n characters linear rather than quadratic, which a 20 KB string literal in a Plug
-- module made visible. ref:DEC-elixir-grammar
withSuffix :: Maybe EbnfSuffix -> Match -> Match
withSuffix suffix m = case suffix of
  Nothing -> m
  Just (EbnfSuffix Optional Greedy) -> \p k -> m p k ++ k p
  Just (EbnfSuffix Optional NonGreedy) -> \p k -> firstNonEmpty (k p) (m p k)
  Just (EbnfSuffix ZeroOrMore Greedy) -> greedyMany
  Just (EbnfSuffix ZeroOrMore NonGreedy) -> lazyMany
  Just (EbnfSuffix OneOrMore Greedy) -> \p k -> concatMap (\p' -> greedyMany p' k) (IntSet.toList (IntSet.fromList (m p (\p' -> [p']))))
  Just (EbnfSuffix OneOrMore NonGreedy) -> \p k -> m p (\p' -> if p' == p then k p' else lazyMany p' k)
  where
    -- A greedy loop continues once from each position its iterations reach, however many ways
    -- reach it, so a body whose alternatives match the same characters, as an identifier part that
    -- is both a letter and a connector, stays linear rather than doubling with each character.
    -- ref:DEC-lexer-performance
    greedyMany p k = concatMap k (IntSet.toList (reach IntSet.empty [p]))
    reach seen todo = case todo of
      [] -> seen
      (q : rest)
        | IntSet.member q seen -> reach seen rest
        | otherwise -> reach (IntSet.insert q seen) ([q' | q' <- m q (\q' -> [q']), q' /= q] ++ rest)
    lazyMany p k = firstNonEmpty (k p) (m p (\p' -> if p' == p then [] else lazyMany p' k))
    firstNonEmpty xs ys = case xs of
      [] -> ys
      _ -> xs

-- | Where a run of characters passing a test ends. A greedy loop over one character test reaches
-- every position of the run and no other, which is what the general loop finds a position at a time.
-- ref:DEC-lexer-performance
classRun :: Env -> (Char -> Bool) -> Int -> Int
classRun env test = go
  where
    input = envInput env
    go q
      | q < V.length input && test (V.unsafeIndex input q) = go (q + 1)
      | otherwise = q

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
matchRuleReference env i p k = concatMatches [matchElements env (compiledElements alt) p k | alt <- compiledAlternatives (envRules env BV.! i)]

-- | The ends of several alternatives, with the last that matched returned as it is rather than
-- copied, so a loop whose body is a block of alternatives stays linear in its length. A 20 KB string
-- literal in an Elixir module took seconds to lex while each iteration copied the ends of the
-- iterations after it. ref:DEC-elixir-grammar
concatMatches :: [[Int]] -> [Int]
concatMatches xss = case filter (not . null) xss of
  [] -> []
  [xs] -> xs
  (xs : rest) -> xs ++ concatMatches rest

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
    env = Env input (tableRules table) (tableCaseInsensitive table) (\_ _ -> True)
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
              startable = case Map.lookup mode (tableStarters table) of
                Just byChar | current < '\128' -> byChar BV.! fromEnum current
                _ -> [rule | index <- rules, let rule = tableRules table BV.! index, not (compiledFragment rule), compiledCanStart rule current]
              candidates = [(e, i, rule) | rule <- startable, (e, i) <- matchRuleAlternatives (envFor st rule p) rule p]
          case longest candidates of
            Nothing -> Left (LexNoMatch (positionAt lines' p) mode)
            Just (e, altIndex, rule) -> emit st rule altIndex e

    -- A semantic predicate is asked of the hooks, which know the base lexer's state, with the text
    -- matched up to the predicate; a grammar without hooks has every predicate hold, as before.
    envFor st rule s = env {envPredicate = \predicate q -> hooksOnPredicate hooks (compiledName rule) predicate (T.pack (V.toList (V.slice s (q - s) input))) s (stateHooks st)}

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
          lookahead = T.pack (V.toList (V.slice end (min 2 (n - end)) input))
          (hookState, actionEffects) = foldl' runAction (stateHooks st, []) (compiledActions alternative)
          runAction (s, effects) text = let (s', more) = hooksOnAction hooks (compiledName rule) text matched lookahead s in (s', effects ++ more)
      commandEffects <- mapM (commandEffect (compiledName rule)) (compiledCommands alternative)
      applied <- applyEffects (positionAt lines' (stateOffset st)) (actionEffects ++ commandEffects) (Applied (compiledName rule) defaultChannelName False False (stateModes st))
      -- An empty match is progress only if it changes mode, as Go's grammar relies on; otherwise
      -- it would repeat forever.
      if end == stateOffset st && appliedModes applied == stateModes st
        then Left (LexEmptyMatch (positionAt lines' (stateOffset st)) (compiledName rule))
        else Right ()
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
