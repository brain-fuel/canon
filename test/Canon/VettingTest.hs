module Canon.VettingTest (tests) where

import Canon.Git.Commit
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Finding (Finding (..), Severity (..), findingSeverity)
import Canon.Model.Gen (genDecisionId, genModel, genVetting, genVersion, genWhere, genWhy)
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
    ]

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
  let (once, fresh) = ingest existing (modelDecisions model)
      (twice, again) = ingest once (modelDecisions model)
  again === []
  twice === once
  Set.fromList fresh === Set.difference (Set.fromList (map decisionId (modelDecisions model))) (Map.keysSet (vettingEntries existing))
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
      entry verdict = Vetting (Map.singleton d (VettingEntry verdict digest Nothing Nothing))
      kinds vetting = map kindOf (vettingFindings (Just "0.2.0") vetting Map.empty model)
  kinds emptyVetting === ["pending"]
  kinds (entry Pending) === ["pending"]
  kinds (entry Good) === []
  kinds (entry Bad) === ["bad"]
  kinds (Vetting (Map.singleton d (VettingEntry Good (T.reverse digest <> "x") Nothing Nothing))) === ["stale"]
  kinds (entry Deferred) === ["withoutRevisit"]
  let deferredUntil v = Vetting (Map.singleton d (VettingEntry Deferred digest (Just v) Nothing))
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
      vetting = Vetting (Map.fromList [(d1, VettingEntry Good "0123456789abcdef" Nothing Nothing), (d2, VettingEntry Bad "0123456789abcdef" Nothing (Just "wrong"))])
      rendered = renderVetting vetting
  assessed <- evalIO (assess (staticGitProvider [committed]) "canonical_vetting.yaml" rendered vetting)
  case Map.lookup d1 assessed of
    Just (Answer a ev) -> do
      assessmentVerdict a === Good
      assessmentBy a === Just alice
      assessmentCommit a === Just (CommitHash (T.replicate 40 "a"))
      assert (isDerivedFromGit ev)
    Nothing -> failure
  unassessed <- evalIO (assess (staticGitProvider [uncommitted]) "canonical_vetting.yaml" rendered vetting)
  case Map.lookup d2 unassessed of
    Just (Answer a ev) -> do
      assessmentVerdict a === Bad
      assessmentBy a === Nothing
      assert (case ev of Asserted _ -> True; _ -> False)
    Nothing -> failure
  let model = modelOf [decisionWith d2 (Why "" [] []) (Where "f" (Span (Position 1 1) (Position 1 1)) [] Nothing)]
      entry = Vetting (Map.singleton d2 (VettingEntry Bad (commentDigest (Why "" [] [])) Nothing (Just "wrong")))
  [d | VerdictUncommitted d <- vettingFindings Nothing entry unassessed model] === [d2]
  [d | VerdictUncommitted d <- vettingFindings Nothing entry assessed model] === []

orphanVerdicts :: Property
orphanVerdicts = property $ do
  vetting <- forAll genVetting
  seen <- forAll (Gen.subsequence (Map.keys (vettingEntries vetting)))
  let orphans = [d | VerdictOrphan d <- orphanVerdictFindings vetting (Set.fromList seen)]
  Set.fromList orphans === Set.difference (Map.keysSet (vettingEntries vetting)) (Set.fromList seen)
