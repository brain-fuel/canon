module Canon.Extract.GrammarTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (defaultConfig)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Commit
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (emptyRegistry)
import Data.Foldable (toList)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "extract"
    [ testProperty "the parser meta-grammar yields its rules as units in order" parserUnits
    , testProperty "every rule of the parser meta-grammar carries a decision" parserDecisions
    , testProperty "a static git provider fills Who and When with git evidence" gitEvidence
    , testProperty "an unresolved reference key is reported" unresolvedKey
    , testProperty "the lexer meta-grammar yields modes with nested rules and optional fragments" lexerUnits
    , testProperty "the license header binds to the grammar unit" fileLevelLicense
    , testProperty "the dialect grammar's extraction rules are labeled alternatives" dialectPlans
    ]

dialectDir :: FilePath
dialectDir = "grammars/antlr4/canonically_commented"

parserPath :: FilePath
parserPath = "grammars/antlr4/ANTLRv4Parser.g4"

lexerPath :: FilePath
lexerPath = "grammars/antlr4/ANTLRv4Lexer.g4"

antlrProfile :: Profile
antlrProfile = Profile [".g4"] (SplitGrammarFiles (dialectDir ++ "/ANTLRv4Lexer.g4") (dialectDir ++ "/ANTLRv4Parser.g4")) (Name "grammarSpec") [] defaultCommentSyntax

sampleCommits :: [Commit]
sampleCommits =
  [ Commit (CommitHash (T.replicate 40 "a")) alice (posixSecondsToUTCTime 1000) alice (posixSecondsToUTCTime 1000) "first"
  , Commit (CommitHash (T.replicate 40 "b")) bob (posixSecondsToUTCTime 2000) alice (posixSecondsToUTCTime 2000) "second"
  ]
  where
    alice = Person "Alice" "alice@example"
    bob = Person "Bob" "bob@example"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadProfileInterpreter antlrProfile)
  case loaded of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right interpreter -> pure interpreter

extractOrFail :: [Commit] -> FilePath -> PropertyT IO Extraction
extractOrFail commits path = do
  interpreter <- interpreterOrFail
  result <- evalIO (extractWithProfile (staticGitProvider commits) defaultConfig "antlr4" antlrProfile interpreter path)
  case result of
    Left err -> annotate (T.unpack (renderGrammarExtractError err)) >> failure
    Right extraction -> pure extraction

extractTextOrFail :: FilePath -> Text -> PropertyT IO Extraction
extractTextOrFail path source = do
  interpreter <- interpreterOrFail
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "antlr4" antlrProfile interpreter path source)
  case result of
    Left err -> annotate (T.unpack (renderGrammarExtractError err)) >> failure
    Right extraction -> pure extraction

grammarUnit :: Model ev -> PropertyT IO (CodeUnit ev)
grammarUnit model = case modelUnits model of
  [file] | [grammar] <- unitChildren file -> do
    unitKindText (whatKind (answerValue (unitWhat grammar))) === "grammarDefinition"
    pure grammar
  _ -> failure

kindOf :: CodeUnit ev -> Text
kindOf = unitKindText . whatKind . answerValue . unitWhat

parserUnits :: Property
parserUnits = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] parserPath
  findings === []
  modelLanguage model === "antlr4"
  grammar <- grammarUnit model
  renderUnitId (unitId grammar) === "antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser"
  length (unitChildren grammar) === 67
  take 2 (map (renderUnitId . unitId) (unitChildren grammar)) === ["antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/grammarSpec", "antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/grammarDecl"]
  assert (all ((== Required) . unitRequirement) (unitChildren grammar))
  assert (all ((== "parserRule") . kindOf) (unitChildren grammar))
  case unitChildren grammar of
    (first : _) -> case answerValue (unitHow first) of
      HowText body -> assert (T.isPrefixOf "grammarDecl prequelConstruct*" body)
      _ -> failure
    [] -> failure

parserDecisions :: Property
parserDecisions = withTests 1 $ property $ do
  Extraction model _ <- extractOrFail [] parserPath
  length (modelDecisions model) === 68
  case [d | d <- modelDecisions model, renderDecisionId (decisionId d) == "decision/antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/ruleAction"] of
    [d] -> do
      assert (T.isPrefixOf "Match stuff like @init {int i;}" (whyText (answerValue (decisionWhy d))))
      assert (case answerEvidence (decisionWhy d) of Asserted _ -> True; _ -> False)
    other -> annotate (show (length other)) >> failure
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

gitEvidence :: Property
gitEvidence = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail sampleCommits parserPath
  findings === []
  let units = modelAllUnits model
  assert (all (isJust . unitWho) units)
  assert (all (isJust . unitWhen) units)
  assert (all isDerivedFromGit (concatMap (toList . answerEvidenceOf) units))
  case unitWhen (head' units) of
    Just (Answer w _) -> do
      changeCommit (whenFirst w) === CommitHash (T.replicate 40 "a")
      changeCommit (whenLast w) === CommitHash (T.replicate 40 "b")
    Nothing -> failure
  where
    answerEvidenceOf u = maybe [] (pure . answerEvidence) (unitWho u) ++ maybe [] (pure . answerEvidence) (unitWhen u)
    head' us = case us of
      (u : _) -> u
      [] -> error "no units"

unresolvedKey :: Property
unresolvedKey = withTests 1 $ property $ do
  let source = "grammar Tiny;\n\n/** exists because of ref:missing, see license:MIT. */\nstart\n    : 'a'\n    ;\n"
  Extraction model findings <- extractTextOrFail "tiny.g4" source
  findings === []
  [k | UnresolvedReference _ _ k <- checkModel emptyRegistry emptyLedger model] === [ReferenceKey "missing", ReferenceKey "MIT"]
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []
  map (whyText . answerValue . decisionWhy) (modelDecisions model) === ["exists because of ref:missing, see license:MIT."]

lexerUnits :: Property
lexerUnits = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] lexerPath
  findings === []
  grammar <- grammarUnit model
  length (unitChildren grammar) === 52
  length (modelAllUnits model) === 72
  map kindOf (drop 50 (unitChildren grammar)) === ["lexerMode", "lexerMode"]
  map (length . unitChildren) (drop 50 (unitChildren grammar)) === [7, 11]
  length [() | u <- modelAllUnits model, kindOf u == "fragmentRule"] === 9
  assert (all (\u -> (unitRequirement u == Optional) == (kindOf u `elem` ["file", "grammarDefinition", "lexerMode", "fragmentRule"])) (modelAllUnits model))
  length (modelDecisions model) === 60
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

fileLevelLicense :: Property
fileLevelLicense = withTests 1 $ property $ do
  Extraction model _ <- extractOrFail [] parserPath
  grammar <- grammarUnit model
  case [d | d <- modelDecisions model, decisionUnits d == NonEmpty.fromList [unitId grammar]] of
    [d] -> do
      whyLicenses (answerValue (decisionWhy d)) === [ReferenceKey "BSD-3-Clause"]
      assert (T.isInfixOf "BSD license" (whyText (answerValue (decisionWhy d))))
    other -> annotate (show (length other)) >> failure

dialectPlans :: Property
dialectPlans = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let plans = alternativePlans (interpreterParser interpreter)
  Map.lookup (Name "grammarSpec") plans === Just [Just (AlternativePlan "grammarDefinition" False)]
  Map.lookup (Name "parserRuleSpec") plans === Just [Just (AlternativePlan "parserRule" True)]
  Map.lookup (Name "lexerRuleSpec") plans === Just [Just (AlternativePlan "fragmentRule" False), Just (AlternativePlan "lexerRule" True)]
  Map.lookup (Name "modeSpec") plans === Just [Just (AlternativePlan "lexerMode" False)]
  Map.lookup (Name "ruleSpec") plans === Just [Nothing, Nothing]
