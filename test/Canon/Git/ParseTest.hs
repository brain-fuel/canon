-- | The git parsers must invert the renderers over generated history.
module Canon.Git.ParseTest (tests) where

import Canon.Git.Commit
import Canon.Git.Derive
import Canon.Git.Gen
import Canon.Git.Parse
import Canon.Model.Answer (Attribution (..), Change (..), When (..), Who (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Set as Set
import Hedgehog (Property, assert, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "git"
    [ testProperty "log parse after render is identity" logRoundTrip
    , testProperty "blame parse after render is identity" blameRoundTrip
    , testProperty "empty output parses to no commits" emptyLog
    , testProperty "who lists exactly the commit authors and committers" whoMatchesCommits
    , testProperty "when is ordered and independent of input order" whenOrdered
    ]

logRoundTrip :: Property
logRoundTrip = property $ do
  commits <- forAll (Gen.list (Range.linear 0 5) genCommit)
  parseGitLog (renderGitLog commits) === Right commits

blameRoundTrip :: Property
blameRoundTrip = property $ do
  entries <- forAll (Gen.list (Range.linear 0 5) genBlameLine)
  parseBlamePorcelain (renderBlamePorcelain entries) === Right entries

emptyLog :: Property
emptyLog = property $ do
  parseGitLog "" === Right []
  parseBlamePorcelain "" === Right []

whoMatchesCommits :: Property
whoMatchesCommits = property $ do
  commits <- forAll (Gen.list (Range.linear 1 6) genCommit)
  case whoFromHistory commits of
    Nothing -> fail "no who for non-empty history"
    Just (Who authors committers) -> do
      Set.fromList (map attributionPerson authors) === Set.fromList (map commitAuthor commits)
      Set.fromList (map attributionPerson committers) === Set.fromList (map commitCommitter commits)
      Set.fromList (concatMap attributionCommits authors) === Set.fromList (map commitHash commits)
  whoFromHistory [] === Nothing

whenOrdered :: Property
whenOrdered = property $ do
  commits <- forAll (Gen.list (Range.linear 1 6) genCommit)
  shuffled <- forAll (Gen.shuffle commits)
  case (whenFromHistory Nothing commits, whenFromHistory Nothing shuffled) of
    (Just a, Just b) -> do
      a === b
      assert (changeAt (whenFirst a) <= changeAt (whenLast a))
      changeAt (whenFirst a) === minimum (NonEmpty.fromList (map commitAuthoredAt commits))
    _ -> fail "no when for non-empty history"
