module Canon.AttachTest (tests) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Gen (genClosedGrammar)
import Canon.Antlr4.Pretty (prettyGrammar)
import Canon.Antlr4.Query (allRules, ruleAnn, ruleName)
import Canon.Antlr4.Read (ReadResult (..), readGrammar)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Attach
import Canon.Model.Gen (genSpan)
import Canon.Span
import Data.List (sortOn)
import qualified Data.Set as Set
import qualified Data.Text as T
import Hedgehog (Property, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "attach"
    [ testProperty "attachPreceding agrees with the brute-force definition" agreesWithBruteForce
    , testProperty "doc comments inserted before rules attach to exactly those rules" insertedCommentsAttach
    ]

agreesWithBruteForce :: Property
agreesWithBruteForce = property $ do
  comments <- forAll (Gen.list (Range.linear 0 8) ((`Located` ()) <$> genSpan))
  targets <- forAll (Gen.list (Range.linear 0 8) ((`Located` ()) <$> genSpan))
  let normalise (pairs, orphans) = (sortOn (locatedSpan . snd) pairs, sortOn locatedSpan orphans)
  normalise (attachPreceding comments targets) === normalise (attachPrecedingBruteForce comments targets)

insertedCommentsAttach :: Property
insertedCommentsAttach = property $ do
  grammar <- forAll genClosedGrammar
  let source = prettyGrammar grammar
  parsed <- either (fail . show) pure (readGrammar "gen" source)
  let rules = allRules (readResultGrammar parsed)
  chosen <- forAll (Gen.subsequence rules)
  let chosenLines = Set.fromList [positionLine (spanStart (ruleAnn r)) | r <- chosen]
      withComments =
        T.unlines
          (concat [(if Set.member n chosenLines then ["/** doc ref:KEY-" <> T.pack (show n) <> " */"] else []) ++ [l] | (n, l) <- zip [1 :: Int ..] (T.lines source)])
  reparsed <- either (fail . show) pure (readGrammar "gen" withComments)
  let docs = [c | c <- readResultComments reparsed, commentKind (locatedValue c) == DocComment]
      targets = [Located (ruleAnn r) (ruleName r) | r <- allRules (readResultGrammar reparsed)]
      (pairs, orphans) = attachPreceding docs targets
  Set.fromList (map (locatedValue . snd) pairs) === Set.fromList (map ruleName chosen)
  map (nameText . locatedValue . snd) pairs === map (nameText . locatedValue . snd) (sortOn (locatedSpan . snd) pairs)
  orphans === []
