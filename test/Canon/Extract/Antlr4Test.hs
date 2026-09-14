module Canon.Extract.Antlr4Test (tests) where

import Canon.Config (defaultConfig)
import Canon.Extract.Antlr4
import Canon.Git.Commit
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Decisions (emptyLedger)
import Canon.Registry (emptyRegistry)
import Data.Foldable (toList)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (isJust)
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
    , testProperty "the parser meta-grammar yields exactly one decision" parserDecision
    , testProperty "a static git provider fills Who and When with git evidence" gitEvidence
    , testProperty "an unresolved reference key is reported" unresolvedKey
    , testProperty "the lexer meta-grammar has one orphan doc comment" lexerOrphan
    , testProperty "the canonical grammar's license header binds to the grammar unit" fileLevelLicense
    ]

parserPath :: FilePath
parserPath = "grammars/antlr4/ANTLRv4Parser.g4"

lexerPath :: FilePath
lexerPath = "grammars/antlr4/ANTLRv4Lexer.g4"

sampleCommits :: [Commit]
sampleCommits =
  [ Commit (CommitHash (T.replicate 40 "a")) alice (posixSecondsToUTCTime 1000) alice (posixSecondsToUTCTime 1000) "first"
  , Commit (CommitHash (T.replicate 40 "b")) bob (posixSecondsToUTCTime 2000) alice (posixSecondsToUTCTime 2000) "second"
  ]
  where
    alice = Person "Alice" "alice@example"
    bob = Person "Bob" "bob@example"

extractOrFail :: [Commit] -> FilePath -> PropertyT IO Extraction
extractOrFail commits path = do
  result <- evalIO (extractGrammarModel (staticGitProvider commits) defaultConfig path)
  case result of
    Left err -> annotate (T.unpack (renderExtractError err)) >> failure
    Right extraction -> pure extraction

parserUnits :: Property
parserUnits = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] parserPath
  findings === []
  modelLanguage model === "antlr4"
  case modelUnits model of
    [root] -> do
      unitId root === UnitId (NonEmpty.fromList ["grammar", "ANTLRv4Parser"])
      length (unitChildren root) === 67
      take 2 (map (renderUnitId . unitId) (unitChildren root)) === ["grammar/ANTLRv4Parser/rule/grammarSpec", "grammar/ANTLRv4Parser/rule/grammarDecl"]
      map (whereIndex . answerValue . unitWhere) (unitChildren root) === map Just [0 .. 66]
      assert (all ((== Required) . unitRequirement) (unitChildren root))
      assert (all (isJust . lookupUnitIn model . unitId) (unitChildren root))
    _ -> failure
  where
    lookupUnitIn m i = lookupUnit i (modelUnits m)

parserDecision :: Property
parserDecision = withTests 1 $ property $ do
  Extraction model _ <- extractOrFail [] parserPath
  case modelDecisions model of
    [d] -> do
      renderDecisionId (decisionId d) === "decision/grammar/ANTLRv4Parser/rule/ruleAction"
      whyText (answerValue (decisionWhy d)) === "Match stuff like @init {int i;}"
      whyReferences (answerValue (decisionWhy d)) === []
      assert (case answerEvidence (decisionWhy d) of Asserted _ -> True; _ -> False)
    other -> annotate (show (length other)) >> failure
  length (checkModel emptyRegistry emptyLedger model) === 66

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
  let source = "grammar Tiny;\n\n/** exists because of ref:missing */\nstart\n    : 'a'\n    ;\n"
  result <- evalIO (extractGrammarText (staticGitProvider []) defaultConfig "tiny.g4" source)
  case result of
    Left err -> annotate (T.unpack (renderExtractError err)) >> failure
    Right (Extraction model findings) -> do
      findings === []
      [k | UnresolvedReference _ _ k <- checkModel emptyRegistry emptyLedger model] === [ReferenceKey "missing"]
      [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

lexerOrphan :: Property
lexerOrphan = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] lexerPath
  length [() | OrphanDocComment _ _ <- findings] === 1
  case modelUnits model of
    [root] -> do
      length (unitChildren root) === 52
      length (modelAllUnits model) === 71
      map (unitKindText . whatKind . answerValue . unitWhat) (drop 50 (unitChildren root)) === ["mode", "mode"]
    _ -> failure

fileLevelLicense :: Property
fileLevelLicense = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] "grammars/antlr4/canonically_commented/ANTLRv4Parser.g4"
  findings === []
  length (modelDecisions model) === 68
  case [d | d <- modelDecisions model, decisionUnits d == NonEmpty.fromList [UnitId (NonEmpty.fromList ["grammar", "ANTLRv4Parser"])]] of
    [d] -> do
      whyLicenses (answerValue (decisionWhy d)) === [ReferenceKey "BSD-3-Clause"]
      assert (T.isInfixOf "BSD license" (whyText (answerValue (decisionWhy d))))
    other -> annotate (show (length other)) >> failure
