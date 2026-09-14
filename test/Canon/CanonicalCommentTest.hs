module Canon.CanonicalCommentTest (tests) where

import Canon.CanonicalComment
import Canon.Model.Gen (genReferenceKey)
import Canon.Model.Id (ReferenceKey (..))
import Data.List (nub)
import qualified Data.Text as T
import Hedgehog (Property, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "canonical comment"
    [ testProperty "reference tokens are extracted in order without duplicates" tokensExtracted
    , testProperty "doc comment delimiters and leading stars are stripped" bodyStripped
    , testProperty "trailing punctuation after a key is ignored" trailingPunctuation
    ]

tokensExtracted :: Property
tokensExtracted = property $ do
  keys <- forAll (Gen.list (Range.linear 0 5) genReferenceKey)
  prose <- forAll (Gen.list (Range.linear 0 6) (Gen.text (Range.linear 1 8) Gen.alpha))
  let pieces = map (("ref:" <>) . referenceKeyText) keys ++ prose
  shuffled <- forAll (Gen.shuffle pieces)
  let expected = nub [ReferenceKey rest | piece <- shuffled, Just rest <- [T.stripPrefix "ref:" piece]]
  referenceTokens (T.unwords shuffled) === expected

bodyStripped :: Property
bodyStripped = withTests 1 $ property $ do
  docCommentBody "/** Match stuff like @init {int i;} */" === "Match stuff like @init {int i;}"
  docCommentBody "/**\n * first line\n * second ref:REQ-42\n */" === "first line\nsecond ref:REQ-42"
  canonicalReferences (parseCanonicalComment "/** because of ref:REQ-42 and ref:warth-2008 */") === [ReferenceKey "REQ-42", ReferenceKey "warth-2008"]

trailingPunctuation :: Property
trailingPunctuation = withTests 1 $ property $ do
  referenceTokens "see ref:REQ-42, then ref:warth-2008." === [ReferenceKey "REQ-42", ReferenceKey "warth-2008"]
  referenceTokens "ref: nothing ref:bad/key ref:" === []
