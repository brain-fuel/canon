-- | Generators for whole grammars, closed so that every reference resolves, which is what round-trip
-- and interpreter properties need.
module Canon.Antlr4.Gen
  ( GenEnv (..)
  , openEnv
  , genRuleName
  , genTokenName
  , genAnyName
  , genQualifiedName
  , genStringLiteral
  , genCharSet
  , genActionText
  , genArgumentText
  , genInteger
  , genGrammar
  , genGrammarOfKind
  , genClosedGrammar
  , genPrequel
  , genOption
  , genOptionValue
  , genParserRule
  , genLexerRule
  , genMode
  , genAlternative
  , genElement
  , genAtom
  , genBlock
  , genLexerAlternative
  , genLexerElement
  , genLexerAtom
  , genLexerCommand
  , genElementOption
  , genEbnfSuffix
  ) where

import Canon.Antlr4.Syntax
import Data.Char (isAlphaNum)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Gen)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

-- | The names in scope while generating, so references can be closed.
data GenEnv = GenEnv
  { envRuleNames :: [Name]
  , envTokenNames :: [Name]
  , envLexerRuleNames :: [Name]
  }

-- | An environment with no names, for open grammars.
openEnv :: GenEnv
openEnv = GenEnv [] [] []

avoidedNames :: Set.Set Text
avoidedNames = Set.union reservedWords (Set.fromList ["options", "tokens", "channels"])

genNameWith :: Gen Char -> Gen Name
genNameWith genFirst =
  Gen.filter (\(Name t) -> not (Set.member t avoidedNames)) $
    Name <$> (T.cons <$> genFirst <*> Gen.text (Range.linear 0 8) genNameTail)
  where
    genNameTail = Gen.frequency [(10, Gen.alphaNum), (1, pure '_')]

-- | A parser rule name.
genRuleName :: Gen Name
genRuleName = genNameWith Gen.lower

-- | A token name.
genTokenName :: Gen Name
genTokenName = genNameWith Gen.upper

-- | A name of either kind.
genAnyName :: Gen Name
genAnyName = Gen.choice [genRuleName, genTokenName]

envRuleName :: GenEnv -> Gen Name
envRuleName env = case envRuleNames env of
  [] -> genRuleName
  names -> Gen.element names

envTokenName :: GenEnv -> Gen Name
envTokenName env = case envTokenNames env of
  [] -> genTokenName
  names -> Gen.element names

envLexerRuleName :: GenEnv -> Gen Name
envLexerRuleName env = case envLexerRuleNames env of
  [] -> genTokenName
  names -> Gen.element names

-- | A dotted name.
genQualifiedName :: Gen QualifiedName
genQualifiedName = QualifiedName <$> nonEmptyList (Range.linear 1 3) genAnyName

-- | A literal with escapes.
genStringLiteral :: Gen StringLiteral
genStringLiteral = StringLiteral . T.concat <$> Gen.list (Range.linear 1 8) genStringLiteralPiece

genStringLiteralPiece :: Gen Text
genStringLiteralPiece =
  Gen.frequency
    [ (12, T.singleton <$> Gen.filter (\c -> c /= '\'' && c /= '\\') genPrintableAscii)
    , (2, Gen.element ["\\b", "\\t", "\\n", "\\f", "\\r", "\\\"", "\\'", "\\\\"])
    , (1, genUnicodeEscape)
    ]

genUnicodeEscape :: Gen Text
genUnicodeEscape = T.append "\\u" <$> Gen.text (Range.singleton 4) Gen.hexit

-- | A character set with ranges and escapes.
genCharSet :: Gen CharSet
genCharSet = CharSet . T.concat <$> Gen.list (Range.linear 1 6) genCharSetPiece

genCharSetPiece :: Gen Text
genCharSetPiece =
  Gen.frequency
    [ (12, T.singleton <$> genCharSetChar)
    , (3, genCharSetRange)
    , (2, Gen.element ["\\]", "\\\\", "\\-", "\\n", "\\t"])
    , (1, genUnicodeEscape)
    ]

genCharSetChar :: Gen Char
genCharSetChar = Gen.filter (\c -> c /= ']' && c /= '\\' && c /= '-') genPrintableAscii

genCharSetRange :: Gen Text
genCharSetRange = do
  lo <- genCharSetChar
  hi <- Gen.filter (>= lo) genCharSetChar
  pure (T.pack [lo, '-', hi])

-- | Balanced action text.
genActionText :: Gen ActionText
genActionText = ActionText <$> genBalanced '{' '}'

-- | Balanced argument text.
genArgumentText :: Gen ArgumentText
genArgumentText = ArgumentText <$> genBalanced '[' ']'

genBalanced :: Char -> Char -> Gen Text
genBalanced open close =
  Gen.recursive
    Gen.choice
    [T.concat <$> Gen.list (Range.linear 0 6) genSafePiece]
    [ (\inner outer -> T.concat [outer, T.singleton open, inner, T.singleton close])
        <$> genBalanced open close
        <*> (T.concat <$> Gen.list (Range.linear 0 3) genSafePiece)
    ]
  where
    genSafePiece =
      Gen.frequency
        [ (10, T.singleton <$> Gen.filter isSafeChar genPrintableAscii)
        , (1, genQuoted '"')
        , (1, genQuoted '\'')
        ]
    isSafeChar c = isAlphaNum c || c `elem` (" ;=(),.<>:+-*&|!" :: String)
    genQuoted q =
      (\body -> T.concat [T.singleton q, body, T.singleton q])
        <$> Gen.text (Range.linear 0 5) (Gen.filter (\c -> isAlphaNum c || c == ' ') genPrintableAscii)

genPrintableAscii :: Gen Char
genPrintableAscii = Gen.enum ' ' '~'

-- | An integer.
genInteger :: Gen Integer
genInteger = Gen.integral (Range.linear 0 1000)

nonEmptyList :: Range.Range Int -> Gen a -> Gen (NonEmpty a)
nonEmptyList range gen = NonEmpty.fromList <$> Gen.list (Range.linear 1 (Range.upperBound 99 range)) gen

-- | A grammar of any kind.
genGrammar :: Gen (Grammar ())
genGrammar = Gen.enumBounded >>= genGrammarOfKind

-- | A grammar of a given kind.
genGrammarOfKind :: GrammarKind -> Gen (Grammar ())
genGrammarOfKind kind =
  Grammar kind
    <$> genAnyName
    <*> Gen.list (Range.linear 0 3) genPrequel
    <*> Gen.list (Range.linear 0 6) (genRuleOfKind openEnv kind)
    <*> (if kind == LexerGrammar then Gen.list (Range.linear 0 2) (genMode openEnv) else pure [])

-- | A grammar whose references all resolve.
genClosedGrammar :: Gen (Grammar ())
genClosedGrammar = do
  kind <- Gen.enumBounded
  ruleNames <- Set.toList <$> Gen.set (Range.linear 1 5) genRuleName
  lexerNames <- Set.toList <$> Gen.set (Range.linear 1 5) genTokenName
  fragmentFlags <- traverse (const Gen.bool) lexerNames
  declared <- Set.toList <$> Gen.set (Range.linear 0 3) genTokenName
  let parserNames = if kind == LexerGrammar then [] else ruleNames
      lexerRuleNames = if kind == ParserGrammar then [] else zip lexerNames fragmentFlags
      tokenNames = [n | (n, isFragment) <- lexerRuleNames, not isFragment] ++ declared ++ [Name "EOF"]
      env = GenEnv parserNames (Set.toList (Set.fromList tokenNames)) (map fst lexerRuleNames ++ [Name "EOF"])
  parserRules <- traverse (\n -> RuleParser <$> genParserRuleNamed env n) parserNames
  lexerRules <- traverse (\(n, isFragment) -> RuleLexer <$> genLexerRuleNamedWith env n isFragment) lexerRuleNames
  rules <- Gen.shuffle (parserRules ++ lexerRules)
  name <- genAnyName
  pure (Grammar kind name [PrequelTokens declared | not (null declared)] rules [])

genRuleOfKind :: GenEnv -> GrammarKind -> Gen (Rule ())
genRuleOfKind env kind = case kind of
  LexerGrammar -> RuleLexer <$> genLexerRule env
  ParserGrammar -> RuleParser <$> genParserRule env
  CombinedGrammar -> Gen.choice [RuleLexer <$> genLexerRule env, RuleParser <$> genParserRule env]

-- | A prequel construct.
genPrequel :: Gen Prequel
genPrequel =
  Gen.choice
    [ PrequelOptions <$> Gen.list (Range.linear 0 3) genOption
    , PrequelImports <$> nonEmptyList (Range.linear 1 3) genImport
    , PrequelTokens <$> Gen.list (Range.linear 0 4) genTokenName
    , PrequelChannels <$> Gen.list (Range.linear 0 3) genTokenName
    , PrequelAction <$> Gen.maybe (Gen.element [Name "lexer", Name "parser"]) <*> genNamedAction
    ]

genImport :: Gen Import
genImport = Import <$> Gen.maybe genAnyName <*> genAnyName

genNamedAction :: Gen NamedAction
genNamedAction = NamedAction <$> genAnyName <*> genActionText

-- | An option.
genOption :: Gen Option
genOption = Option <$> genAnyName <*> genOptionValue

-- | An option value.
genOptionValue :: Gen OptionValue
genOptionValue =
  Gen.choice
    [ OptionValueName <$> genQualifiedName
    , OptionValueString <$> genStringLiteral
    , OptionValueAction <$> genActionText
    , OptionValueInt <$> genInteger
    ]

-- | A parser rule.
genParserRule :: GenEnv -> Gen (ParserRule ())
genParserRule env = genRuleName >>= genParserRuleNamed env

genParserRuleNamed :: GenEnv -> Name -> Gen (ParserRule ())
genParserRuleNamed env name =
  ParserRule ()
    name
    <$> Gen.list (Range.linear 0 2) Gen.enumBounded
    <*> Gen.maybe genArgumentText
    <*> Gen.maybe genArgumentText
    <*> Gen.list (Range.linear 0 2) genQualifiedName
    <*> Gen.maybe genArgumentText
    <*> Gen.list (Range.linear 0 2) genRulePrequel
    <*> nonEmptyList (Range.linear 1 4) (genLabeledAlternative env)
    <*> Gen.list (Range.linear 0 2) (ExceptionHandler <$> genArgumentText <*> genActionText)
    <*> Gen.maybe genActionText

genRulePrequel :: Gen RulePrequel
genRulePrequel =
  Gen.choice
    [ RulePrequelOptions <$> Gen.list (Range.linear 0 2) genOption
    , RulePrequelAction <$> genNamedAction
    ]

genLabeledAlternative :: GenEnv -> Gen (LabeledAlternative ())
genLabeledAlternative env = LabeledAlternative <$> genAlternative env <*> Gen.maybe genAnyName

-- | An alternative.
genAlternative :: GenEnv -> Gen (Alternative ())
genAlternative env = do
  elements <- Gen.list (Range.linear 0 5) (genElement env)
  opts <- if null elements then pure [] else Gen.list (Range.linear 0 2) genElementOption
  pure (Alternative () opts elements)

-- | An element.
genElement :: GenEnv -> Gen (Element ())
genElement env =
  Gen.recursive
    Gen.choice
    [ ElementAtom () <$> Gen.maybe genLabel <*> genAtom env <*> Gen.maybe genEbnfSuffix
    , ElementAction () <$> Gen.enumBounded <*> genActionText <*> Gen.list (Range.linear 0 2) genPredicateOption
    ]
    [ElementBlock () <$> Gen.maybe genLabel <*> genBlock env <*> Gen.maybe genEbnfSuffix]

genLabel :: Gen Label
genLabel = Label <$> genAnyName <*> Gen.enumBounded

-- | An atom.
genAtom :: GenEnv -> Gen Atom
genAtom env =
  Gen.choice
    [ AtomTerminal <$> genTerminal env
    , AtomRuleRef <$> envRuleName env <*> Gen.maybe genArgumentText <*> Gen.list (Range.linear 0 2) genElementOption
    , AtomNotSet . NotSet <$> nonEmptyList (Range.linear 1 3) (SetTerminal <$> genTerminal env)
    , AtomWildcard <$> Gen.list (Range.linear 0 2) genElementOption
    ]

genTerminal :: GenEnv -> Gen Terminal
genTerminal env =
  Gen.choice
    [ TerminalToken <$> envTokenName env <*> Gen.list (Range.linear 0 2) genElementOption
    , TerminalLiteral <$> genStringLiteral <*> Gen.list (Range.linear 0 2) genElementOption
    ]

-- | A block.
genBlock :: GenEnv -> Gen (Block ())
genBlock env =
  Block
    <$> Gen.list (Range.linear 0 2) genOption
    <*> Gen.list (Range.linear 0 2) genNamedAction
    <*> nonEmptyList (Range.linear 1 3) (genAlternative env)

-- | A suffix.
genEbnfSuffix :: Gen EbnfSuffix
genEbnfSuffix = EbnfSuffix <$> Gen.enumBounded <*> Gen.enumBounded

-- | An element option.
genElementOption :: Gen ElementOption
genElementOption =
  Gen.choice
    [ ElementOptionFlag <$> genQualifiedName
    , ElementOptionAssign <$> genAnyName <*> Gen.filter (not . isActionValue) genOptionValue
    ]
  where
    isActionValue v = case v of
      OptionValueAction _ -> True
      _ -> False

genPredicateOption :: Gen ElementOption
genPredicateOption =
  Gen.choice
    [ genElementOption
    , ElementOptionAssign <$> genAnyName <*> (OptionValueAction <$> genActionText)
    ]

-- | A lexer rule.
genLexerRule :: GenEnv -> Gen (LexerRule ())
genLexerRule env = genTokenName >>= genLexerRuleNamed env

genLexerRuleNamed :: GenEnv -> Name -> Gen (LexerRule ())
genLexerRuleNamed env name = Gen.bool >>= genLexerRuleNamedWith env name

genLexerRuleNamedWith :: GenEnv -> Name -> Bool -> Gen (LexerRule ())
genLexerRuleNamedWith env name isFragment =
  LexerRule ()
    name
    isFragment
    <$> Gen.list (Range.linear 0 2) genOption
    <*> nonEmptyList (Range.linear 1 4) (genLexerAlternative env)

-- | A lexer alternative.
genLexerAlternative :: GenEnv -> Gen (LexerAlternative ())
genLexerAlternative env =
  LexerAlternative ()
    <$> Gen.list (Range.linear 0 5) (genLexerElement env)
    <*> Gen.list (Range.linear 0 2) genLexerCommand

-- | A lexer element.
genLexerElement :: GenEnv -> Gen (LexerElement ())
genLexerElement env =
  Gen.recursive
    Gen.choice
    [ LexerElementAtom () <$> genLexerAtom env <*> Gen.maybe genEbnfSuffix
    , LexerElementAction () <$> Gen.enumBounded <*> genActionText
    ]
    [LexerElementBlock () <$> nonEmptyList (Range.linear 1 3) (genLexerAlternative env) <*> Gen.maybe genEbnfSuffix]

-- | A lexer atom.
genLexerAtom :: GenEnv -> Gen LexerAtom
genLexerAtom env =
  Gen.choice
    [ LexerAtomTerminal <$> genLexerTerminal env
    , LexerAtomRange <$> genCharRange
    , LexerAtomCharSet <$> genCharSet
    , LexerAtomNotSet . NotSet <$> nonEmptyList (Range.linear 1 3) (genLexerSetElement env)
    , LexerAtomWildcard <$> Gen.list (Range.linear 0 2) genElementOption
    ]

genCharRange :: Gen CharRange
genCharRange = CharRange <$> genStringLiteral <*> genStringLiteral

genLexerTerminal :: GenEnv -> Gen Terminal
genLexerTerminal env =
  Gen.choice
    [ TerminalToken <$> envLexerRuleName env <*> Gen.list (Range.linear 0 2) genElementOption
    , TerminalLiteral <$> genStringLiteral <*> Gen.list (Range.linear 0 2) genElementOption
    ]

genLexerSetElement :: GenEnv -> Gen SetElement
genLexerSetElement env =
  Gen.choice
    [ SetTerminal <$> genLexerTerminal env
    , SetRange <$> genCharRange
    , SetCharSet <$> genCharSet
    ]

-- | A lexer command.
genLexerCommand :: Gen LexerCommand
genLexerCommand =
  Gen.choice
    [ LexerCommand <$> Gen.element [Name "skip", Name "more", Name "popMode"] <*> pure Nothing
    , LexerCommand
        <$> Gen.element [Name "type", Name "channel", Name "mode", Name "pushMode"]
        <*> (Just <$> Gen.choice [CommandArgumentName <$> genAnyName, CommandArgumentInt <$> genInteger])
    ]

-- | A mode.
genMode :: GenEnv -> Gen (Mode ())
genMode env = Mode () <$> genAnyName <*> Gen.list (Range.linear 0 3) (genLexerRule env)
