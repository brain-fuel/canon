-- | The repository facts are read from batched git output, so the readers are checked against a
-- direct reading of what each answer means: the first release of a commit is the first tag, in
-- version order, whose history holds it, and a path's last change is the newest commit naming it.
module Canon.Git.FactsTest (tests) where

import Canon.Git.Commit (BlameLine, CommitHash (..))
import Canon.Git.Facts (lastChangesFrom, releaseOf, releasesFrom)
import Canon.Git.Gen (genBlameLine)
import Data.Aeson (decode, encode)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Gen, Property, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "facts"
    [ testProperty "a commit's release is the first tag whose history holds it" releasesMatchReachability
    , testProperty "an annotated tag releases the commit it points at" annotatedTags
    , testProperty "a path's last change is the newest commit that names it" lastChangeIsNewest
    , testProperty "a cached blame line reads back as it was written" blameLinesRoundTrip
    ]

-- | A commit graph: commit i's parents are among the commits before it, so it has no cycle.
data Graph = Graph
  { graphParents :: [[Int]]
  , graphTags :: [(Int, Text)]
  }
  deriving (Show)

genGraph :: Gen Graph
genGraph = do
  size <- Gen.int (Range.linear 1 40)
  parents <- mapM (\i -> if i == 0 then pure [] else Gen.subsequence [max 0 (i - 6) .. i - 1] >>= \ps -> pure (take 2 ps)) [0 .. size - 1]
  tagged <- Gen.subsequence [0 .. size - 1]
  order <- Gen.shuffle tagged
  pure (Graph parents [(c, "v" <> T.pack (show n)) | (n, c) <- zip [(1 :: Int) ..] order])

hashOf :: Int -> Text
hashOf i = "c" <> T.pack (show i)

-- | Renders the graph as `git rev-list --parents` does, newest first, and the tags as the
-- for-each-ref line canon asks for, in version order.
renderGraph :: Graph -> (Text, Text)
renderGraph (Graph parents tags) =
  ( T.unlines ["commit " <> hashOf c <> "   " <> name | (c, name) <- tags]
  , T.unlines (reverse [T.unwords (hashOf i : map hashOf ps) | (i, ps) <- zip [0 ..] parents])
  )

-- | Every commit a commit's history holds, itself included.
ancestors :: [[Int]] -> Int -> Set.Set Int
ancestors parents = go Set.empty
  where
    go seen c
      | Set.member c seen = seen
      | otherwise = foldl go (Set.insert c seen) (parents !! c)

releasesMatchReachability :: Property
releasesMatchReachability = property $ do
  graph <- forAll genGraph
  let (tagText, graphText) = renderGraph graph
      releases = releasesFrom tagText graphText
      expected c = listToMaybe [name | (t, name) <- graphTags graph, Set.member c (ancestors (graphParents graph) t)]
  [releaseOf releases (CommitHash (hashOf c)) | c <- [0 .. length (graphParents graph) - 1]]
    === [expected c | c <- [0 .. length (graphParents graph) - 1]]

annotatedTags :: Property
annotatedTags = property $ do
  let releases = releasesFrom "tag t1 commit c1 v1.0\ntree t2   not-a-commit\n" "c1 c0\nc0\n"
  (releaseOf releases (CommitHash "c0"), releaseOf releases (CommitHash "c1")) === (Just "v1.0", Just "v1.0")

lastChangeIsNewest :: Property
lastChangeIsNewest = property $ do
  history <- forAll (Gen.list (Range.linear 0 12) (Gen.subsequence ["a.hs", "b/c.hs", "d e.md", "f"]))
  let commits = zip [hashOf i | i <- [0 :: Int ..]] history
      rendered = T.concat [T.concat (("\1" <> hash <> "\0\n") : [T.pack p <> "\0" | p <- paths]) | (hash, paths) <- commits]
      expected = Map.fromList [(p, hash) | (hash, paths) <- reverse commits, p <- paths]
  lastChangesFrom rendered === expected

blameLinesRoundTrip :: Property
blameLinesRoundTrip = property $ do
  entries <- forAll (Gen.list (Range.linear 0 5) genBlameLine)
  decode (encode entries) === Just (entries :: [BlameLine])
