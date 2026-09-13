module Canon.Antlr4.VendoredTest (tests) where

import Canon.Antlr4.Grammar (parseGrammarText)
import Canon.Antlr4.Pretty (prettyGrammar)
import Canon.Antlr4.Read
import Canon.Antlr4.Syntax
import Data.Functor (void)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, assert, evalEither, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "vendored"
    [ testProperty "lexer meta-grammar reads with expected structure" lexerMetaGrammar
    , testProperty "parser meta-grammar reads with expected structure" parserMetaGrammar
    , testProperty "pretty printing the lexer meta-grammar is idempotent" (idempotent lexerPath)
    , testProperty "pretty printing the parser meta-grammar is idempotent" (idempotent parserPath)
    ]

lexerPath :: FilePath
lexerPath = "grammars/antlr4/ANTLRv4Lexer.g4"

parserPath :: FilePath
parserPath = "grammars/antlr4/ANTLRv4Parser.g4"

readOrFail :: FilePath -> PropertyT IO ReadResult
readOrFail path = do
  result <- evalIO (readGrammarFile path)
  case result of
    Left err -> annotate (T.unpack (renderReadError err)) >> failure
    Right r -> pure r

lexerMetaGrammar :: Property
lexerMetaGrammar = withTests 1 $ property $ do
  ReadResult g comments <- readOrFail lexerPath
  grammarKind g === LexerGrammar
  grammarName g === Name "ANTLRv4Lexer"
  [o | PrequelOptions o <- grammarPrequel g] === [[Option (Name "superClass") (OptionValueName (QualifiedName (NonEmpty.fromList [Name "LexerAdaptor"])))]]
  map length [t | PrequelTokens t <- grammarPrequel g] === [26]
  [c | PrequelChannels c <- grammarPrequel g] === [[Name "OFF_CHANNEL", Name "COMMENT"]]
  length (grammarRules g) === 50
  map modeName (grammarModes g) === [Name "Argument", Name "LexerCharSet"]
  map (length . modeRules) (grammarModes g) === [7, 11]
  length [() | RuleLexer r <- grammarRules g ++ concatMap (map RuleLexer . modeRules) (grammarModes g), lexerRuleIsFragment r] === 9
  case grammarRules g of
    RuleLexer first : _ -> do
      lexerRuleName first === Name "DOC_COMMENT"
      lexerAlternativeCommands (NonEmpty.head (lexerRuleAlternatives first))
        === [LexerCommand (Name "channel") (Just (CommandArgumentName (Name "COMMENT")))]
    _ -> failure
  assert (any (\l -> "BSD" `T.isInfixOf` T.pack (show l)) comments)

parserMetaGrammar :: Property
parserMetaGrammar = withTests 1 $ property $ do
  ReadResult g _ <- readOrFail parserPath
  grammarKind g === ParserGrammar
  grammarName g === Name "ANTLRv4Parser"
  [o | PrequelOptions o <- grammarPrequel g] === [[Option (Name "tokenVocab") (OptionValueName (QualifiedName (NonEmpty.fromList [Name "ANTLRv4Lexer"])))]]
  length (grammarRules g) === 67
  grammarModes g === []
  take 1 (map ruleNameOf (grammarRules g)) === [Name "grammarSpec"]
  take 1 (reverse (map ruleNameOf (grammarRules g))) === [Name "qualifiedIdentifier"]
  length [() | RuleLexer _ <- grammarRules g] === 0

ruleNameOf :: Rule ann -> Name
ruleNameOf r = case r of
  RuleParser p -> parserRuleName p
  RuleLexer l -> lexerRuleName l

idempotent :: FilePath -> Property
idempotent path = withTests 1 $ property $ do
  ReadResult g _ <- readOrFail path
  let once = prettyGrammar g
  reparsed <- evalEither (parseGrammarText once)
  void reparsed === void g
  prettyGrammar reparsed === once
