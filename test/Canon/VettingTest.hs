-- | The vetting file must round-trip, and verdicts, digests, and assessors must behave as rule 7
-- says. ref:DEC-comment-vetting
module Canon.VettingTest (tests) where

import Canon.Git.Commit
import Canon.Git.Provider (StaticGit (..), staticGitProvider, staticGitProviderWith)
import Canon.Model
import Canon.Model.Finding (Finding (..), Severity (..), findingSeverity)
import Canon.Decisions (DecisionEntry (entryQuestion), Ledger (..), emptyLedger)
import Canon.Model.Gen (genDecisionEntry, genDecisionId, genModel, genReference, genVetting, genVersion, genWhere, genWhy)
import Canon.Registry (Reference (..), Registry (..), emptyRegistry)
import Canon.Model.Yaml (decodeSorted)
import Canon.Span (Position (..), Span (..))
import Canon.Version (parseVersion)
import Canon.Vetting
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Hedgehog (Property, assert, evalIO, failure, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "vetting"
    [ testProperty "the rendered vetting file reads back to the same entries" renderRoundTrip
    , testProperty "every entry's verdict line is found in the rendered file" verdictLineScan
    , testProperty "ingest records only unknown decisions as pending and is idempotent" ingestPending
    , testProperty "findings follow the verdict and the comment digest" verdictFindings
    , testProperty "the assessor is the author of the commit that wrote the verdict" assessorFromBlame
    , testProperty "an entry whose decision no longer exists is an orphan verdict" orphanVerdicts
    , testProperty "ledger and registry entries are material: pending until signed, stale when edited" materialSignOff
    , testProperty "the old comment-only key form still reads" legacyKeys
    ]

materialSignOff :: Property
materialSignOff = property $ do
  entry <- forAll genDecisionEntry
  reference <- forAll genReference
  let key = ReferenceKey "DEC-x"
      refKey = ReferenceKey "paper-x"
      ledger = Ledger (Map.singleton key entry)
      registry = Registry (Map.singleton refKey reference)
      items = materials [] ledger registry
  map materialKey items === [LedgerKey key, RegistryKey refKey]
  map materialText items === [entryQuestion entry, referenceTitle reference]
  let (ingested, fresh) = ingest emptyVetting items
  Set.fromList fresh === Set.fromList [LedgerKey key, RegistryKey refKey]
  [k | MaterialPending k <- materialFindings Nothing ingested Map.empty ledger registry] === [LedgerKey key, RegistryKey refKey]
  let signed = Vetting (Map.map (\e -> e {entryVerdict = Good}) (vettingEntries ingested))
  materialFindings Nothing signed Map.empty ledger registry === []
  let edited = Ledger (Map.singleton key entry {entryQuestion = entryQuestion entry <> "?"})
  [k | MaterialStale k <- materialFindings Nothing signed Map.empty edited registry] === [LedgerKey key]
  [k | VerdictOrphan k <- orphanVerdictFindings signed (Set.singleton (LedgerKey key))] === [RegistryKey refKey]

legacyKeys :: Property
legacyKeys = withTests 1 $ property $ do
  let d = DecisionId (UnitId ("java" :| ["A.java", "class", "A"]))
  parseVettingKey "decision/java/A.java/class/A" === Just (CommentKey d)
  parseVettingKey "ledger/DEC-x" === Just (LedgerKey (ReferenceKey "DEC-x"))
  parseVettingKey "registry/paper-1" === Just (RegistryKey (ReferenceKey "paper-1"))
  parseVettingKey "elsewhere/x" === Nothing
  renderVettingKey (LedgerKey (ReferenceKey "DEC-x")) === "ledger/DEC-x"

renderRoundTrip :: Property
renderRoundTrip = property $ do
  vetting <- forAll genVetting
  decodeSorted (TE.encodeUtf8 (renderVetting vetting)) === Right vetting

verdictLineScan :: Property
verdictLineScan = property $ do
  vetting <- forAll genVetting
  let rendered = renderVetting vetting
      found = verdictLines rendered
  Map.keysSet found === Map.keysSet (vettingEntries vetting)
  assert (all (\n -> "verdict:" `T.isPrefixOf` T.stripStart (T.lines rendered !! (n - 1))) (Map.elems found))

ingestPending :: Property
ingestPending = property $ do
  model <- forAll genModel
  existing <- forAll genVetting
  let items = materials (modelDecisions model) emptyLedger emptyRegistry
      (once, fresh) = ingest existing items
      (twice, again) = ingest once items
  again === []
  twice === once
  Set.fromList fresh === Set.difference (Set.fromList (map (CommentKey . decisionId) (modelDecisions model))) (Map.keysSet (vettingEntries existing))
  assert (all (\d -> fmap entryVerdict (Map.lookup d (vettingEntries once)) == Just Pending) fresh)
  assert (all (\d -> Map.lookup d (vettingEntries once) == Map.lookup d (vettingEntries existing)) (Map.keys (vettingEntries existing)))

decisionWith :: DecisionId -> Why -> Where -> Decision Evidence
decisionWith d why w = Decision d (UnitId ("x" :| []) :| []) (Answer why (Asserted (Assertion "f" (whereSpan w)))) w Nothing

modelOf :: [Decision Evidence] -> Model Evidence
modelOf ds = Model "lang" (Just "0.2.0") Nothing [] ds

verdictFindings :: Property
verdictFindings = property $ do
  d <- forAll genDecisionId
  why <- forAll genWhy
  w <- forAll genWhere
  revisit <- forAll genVersion
  let decision = decisionWith d why w
      model = modelOf [decision]
      digest = commentDigest why
      entry verdict = Vetting (Map.singleton (CommentKey d) (VettingEntry verdict digest Nothing Nothing))
      kinds vetting = map kindOf (vettingFindings (Just "0.2.0") vetting Map.empty model)
  kinds emptyVetting === ["pending"]
  kinds (entry Pending) === ["pending"]
  kinds (entry Good) === []
  kinds (entry Bad) === ["bad"]
  kinds (Vetting (Map.singleton (CommentKey d) (VettingEntry Good (T.reverse digest <> "x") Nothing Nothing))) === ["stale"]
  kinds (entry Deferred) === ["withoutRevisit"]
  let deferredUntil v = Vetting (Map.singleton (CommentKey d) (VettingEntry Deferred digest (Just v) Nothing))
      now = maybe (error "version") id (parseVersion "0.2.0")
  kinds (deferredUntil revisit) === [if revisit <= now then "pastRevisit" else "deferred"]
  map findingSeverity (vettingFindings (Just "0.2.0") (deferredUntil revisit) Map.empty model) === [if revisit <= now then Failing else Informational]
  where
    kindOf f = case f of
      CommentPending {} -> "pending" :: String
      CommentStale {} -> "stale"
      CommentBad {} -> "bad"
      CommentDeferred {} -> "deferred"
      CommentDeferredPastRevisit {} -> "pastRevisit"
      VerdictWithoutRevisit {} -> "withoutRevisit"
      _ -> "other"

assessorFromBlame :: Property
assessorFromBlame = withTests 1 $ property $ do
  let alice = Person "Alice" "alice@example"
      committed = Commit (CommitHash (T.replicate 40 "a")) alice (posixSecondsToUTCTime 1000) alice (posixSecondsToUTCTime 1000) "vet"
      uncommitted = Commit (CommitHash (T.replicate 40 "0")) (Person "Not Committed Yet" "not.committed.yet") (posixSecondsToUTCTime 0) alice (posixSecondsToUTCTime 0) ""
      d1 = DecisionId (UnitId ("a" :| ["one"]))
      d2 = DecisionId (UnitId ("a" :| ["two"]))
      vetting = Vetting (Map.fromList [(CommentKey d1, VettingEntry Good "0123456789abcdef" Nothing Nothing), (CommentKey d2, VettingEntry Bad "0123456789abcdef" Nothing (Just "wrong"))])
      rendered = renderVetting vetting
      helper = Person "Claude" "noreply@anthropic.com"
      withMessages = staticGitProviderWith (StaticGit [committed] Map.empty Nothing (Map.singleton (commitHash committed) "vet\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n"))
  assessed <- evalIO (assess withMessages "canonical_vetting.yaml" rendered vetting)
  case Map.lookup (CommentKey d1) assessed of
    Just (Answer a ev) -> do
      assessmentVerdict a === Good
      assessmentBy a === Just alice
      assessmentCommit a === Just (CommitHash (T.replicate 40 "a"))
      assessmentCoAuthors a === [helper]
      assert (isDerivedFromGit ev)
    Nothing -> failure
  unassessed <- evalIO (assess (staticGitProvider [uncommitted]) "canonical_vetting.yaml" rendered vetting)
  case Map.lookup (CommentKey d2) unassessed of
    Just (Answer a ev) -> do
      assessmentVerdict a === Bad
      assessmentBy a === Nothing
      assert (isAsserted ev)
    Nothing -> failure
  let model = modelOf [decisionWith d2 (Why "" [] []) (Where "f" (Span (Position 1 1) (Position 1 1)) [] Nothing)]
      entry = Vetting (Map.singleton (CommentKey d2) (VettingEntry Bad (commentDigest (Why "" [] [])) Nothing (Just "wrong")))
  [k | VerdictUncommitted k <- vettingFindings Nothing entry unassessed model] === [CommentKey d2]
  [k | VerdictUncommitted k <- vettingFindings Nothing entry assessed model] === []

orphanVerdicts :: Property
orphanVerdicts = property $ do
  vetting <- forAll genVetting
  seen <- forAll (Gen.subsequence (Map.keys (vettingEntries vetting)))
  let orphans = [k | VerdictOrphan k <- orphanVerdictFindings vetting (Set.fromList seen)]
  Set.fromList orphans === Set.difference (Map.keysSet (vettingEntries vetting)) (Set.fromList seen)

isAsserted :: Evidence -> Bool
isAsserted ev = case ev of
  Asserted _ -> True
  _ -> False
