-- | A model must survive a YAML round trip with sorted keys. ref:DEC-parser-foundation
module Canon.Model.YamlTest (tests) where

import Canon.Model
import Canon.Model.Gen
import Canon.Model.Yaml
import qualified Data.ByteString.Char8 as BS8
import Data.List (sort)
import Hedgehog (Property, assert, forAll, property, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "model yaml"
    [ testProperty "decode after encode is identity" decodeAfterEncode
    , testProperty "top-level keys are emitted in alphabetical order" topLevelKeysSorted
    , testProperty "another schema version is rejected" wrongSchemaRejected
    , testProperty "span round trip" spanRoundTrip
    , testProperty "unit id parse after render" unitIdRoundTrip
    , testProperty "decision id parse after render" decisionIdRoundTrip
    , testProperty "reference keys reject separators" referenceKeyRejects
    ]

decodeAfterEncode :: Property
decodeAfterEncode = property $ do
  m <- forAll genModel
  decodeModel (encodeModel m) === Right m

topLevelKeysSorted :: Property
topLevelKeysSorted = property $ do
  m <- forAll genModel
  let keys = [BS8.takeWhile (/= ':') l | l <- BS8.lines (encodeModel m), not (BS8.null l), BS8.head l /= ' ', BS8.head l /= '-']
  keys === sort keys
  assert (BS8.pack "schemaVersion" `elem` keys)

wrongSchemaRejected :: Property
wrongSchemaRejected = property $ do
  m <- forAll genModel
  let bytes = encodeModel m
      altered = BS8.unlines [if l == BS8.pack "schemaVersion: 1" then BS8.pack "schemaVersion: 2" else l | l <- BS8.lines bytes]
  assert (altered /= bytes)
  assert (either (const True) (const False) (decodeModel altered))

spanRoundTrip :: Property
spanRoundTrip = property $ do
  s <- forAll genSpan
  decodeSorted (encodeSorted s) === Right s

unitIdRoundTrip :: Property
unitIdRoundTrip = property $ do
  u <- forAll genUnitId
  parseUnitId (renderUnitId u) === Just u

decisionIdRoundTrip :: Property
decisionIdRoundTrip = property $ do
  d <- forAll genDecisionId
  parseDecisionId (renderDecisionId d) === Just d

referenceKeyRejects :: Property
referenceKeyRejects = property $ do
  ReferenceKey k <- forAll genReferenceKey
  assert (isReferenceKey k)
  assert (not (isReferenceKey (k <> "/x")))
  assert (not (isReferenceKey (k <> " x")))
  assert (not (isReferenceKey ""))
  assert (not (isReferenceKey (k <> ".")))
