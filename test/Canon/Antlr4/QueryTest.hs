module Canon.Antlr4.QueryTest (tests) where

import Canon.Antlr4.Gen (genClosedGrammar, genGrammar)
import Canon.Antlr4.Query
import Canon.Antlr4.Read
import Canon.Antlr4.Syntax
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "query"
    [ testProperty "every rule of a closed grammar is found by name" lookupFindsEveryRule
    , testProperty "rule names preserve source order" ruleNamesPreserveOrder
    , testProperty "token names are unique and start with declared tokens" tokenNamesShape
    , testProperty "closed grammars have no undefined rule references" closedGrammarsResolve
    , testProperty "renaming a referenced rule produces exactly the expected missing references" renamingBreaksReferences
    , testProperty "generated grammars are well formed" generatedGrammarsWellFormed
    , testProperty "vendored lexer grammar token vocabulary" vendoredLexerVocabulary
    , testProperty "vendored parser grammar references resolve against the lexer grammar" vendoredReferencesResolve
    ]

lookupFindsEveryRule :: Property
lookupFindsEveryRule = property $ do
  g <- forAll genClosedGrammar
  mapM_ (\r -> fmap ruleName (lookupRule (ruleName r) g) === Just (ruleName r)) (allRules g)

ruleNamesPreserveOrder :: Property
ruleNamesPreserveOrder = property $ do
  g <- forAll genGrammar
  ruleNames g === map ruleName (grammarRules g) ++ concatMap (map lexerRuleName . modeRules) (grammarModes g)
  mapM_ (\(i, n) -> ruleIndex n g === Just i) (zip [0 ..] (nub (ruleNames g)))

tokenNamesShape :: Property
tokenNamesShape = property $ do
  g <- forAll genClosedGrammar
  let names = tokenNames g
  names === nub names
  take (length (nub (declaredTokens g))) names === nub (declaredTokens g)
  Map.keys (tokenTypes g) === Set.toList (Set.fromList names)

closedGrammarsResolve :: Property
closedGrammarsResolve = property $ do
  g <- forAll genClosedGrammar
  undefinedRuleReferences g === []
  undefinedTokenReferences g === []

renamingBreaksReferences :: Property
renamingBreaksReferences = property $ do
  g <- forAll genClosedGrammar
  let referenced = [n | (n, refs) <- Map.toList (referencesByRule g), not (Set.null refs)]
      candidates = nub (concatMap Set.toList (Map.elems (referencesByRule g)))
  case candidates of
    [] -> pure ()
    _ -> do
      victim <- forAll (Gen.element candidates)
      let renamed = g {grammarRules = map (renameDefinition victim) (grammarRules g)}
          referrerName n = if n == victim then renamedName victim else n
          expected = [(referrerName referrer, victim) | referrer <- map ruleName (allRules g), Set.member victim (Map.findWithDefault Set.empty referrer (referencesByRule g))]
      annotate (show referenced)
      undefinedRuleReferences renamed === expected

renameDefinition :: Name -> Rule ann -> Rule ann
renameDefinition victim r = case r of
  RuleParser p | parserRuleName p == victim -> RuleParser p {parserRuleName = fresh}
  RuleLexer l | lexerRuleName l == victim -> RuleLexer l {lexerRuleName = fresh}
  _ -> r
  where
    fresh = renamedName victim

renamedName :: Name -> Name
renamedName n = Name (nameText n <> "_renamed")

generatedGrammarsWellFormed :: Property
generatedGrammarsWellFormed = property $ do
  g <- forAll genGrammar
  wellFormed g === []

readOrFail :: FilePath -> PropertyT IO (Grammar Span)
readOrFail path = do
  result <- evalIO (readGrammarFile path)
  case result of
    Left err -> annotate (T.unpack (renderReadError err)) >> failure
    Right r -> pure (readResultGrammar r)

vendoredLexerVocabulary :: Property
vendoredLexerVocabulary = withTests 1 $ property $ do
  g <- readOrFail "grammars/antlr4/ANTLRv4Lexer.g4"
  length (tokenNames g) === 80
  Map.lookup (StringLiteral "import") (literalTokenTypes g) === Just (Name "IMPORT")
  Map.lookup (Name "DOC_COMMENT") (tokenTypes g) === Just 27
  modeNames g === [defaultModeName, Name "Argument", Name "LexerCharSet"]
  modeOfLexerRule (Name "END_ARGUMENT") g === Just (Name "Argument")
  modeOfLexerRule (Name "DOC_COMMENT") g === Just defaultModeName
  length (fragmentRules g) === 9
  undefinedRuleReferences g === []
  assert (any ((== Just LexerMore) . knownLexerCommand) (concatMap lexerAlternativeCommandsOf (lexerRules g)))
  where
    lexerAlternativeCommandsOf l = concatMap lexerAlternativeCommands (foldr (:) [] (lexerRuleAlternatives l))

vendoredReferencesResolve :: Property
vendoredReferencesResolve = withTests 1 $ property $ do
  lexer <- readOrFail "grammars/antlr4/ANTLRv4Lexer.g4"
  parser <- readOrFail "grammars/antlr4/ANTLRv4Parser.g4"
  undefinedRuleReferences parser === []
  tokenReferencesUndefinedIn parser lexer === []
  assert (not (null (undefinedTokenReferences parser)))
