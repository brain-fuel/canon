-- | Escape decoding and encoding must round-trip, or a printed grammar changes its language.
module Canon.Antlr4.EscapeTest (tests) where

import Canon.Antlr4.Escape
import Canon.Antlr4.Gen
import Canon.Antlr4.Syntax
import Hedgehog (Gen, Property, assert, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "escape"
    [ testProperty "decode after encode is identity" decodeAfterEncode
    , testProperty "generated string literals decode" generatedStringLiteralsDecode
    , testProperty "generated string literals are well formed" (wellFormed stringLiteralRaw isWellFormedStringLiteralRaw genStringLiteral)
    , testProperty "generated char sets are well formed" (wellFormed charSetRaw isWellFormedCharSetRaw genCharSet)
    , testProperty "generated char sets decode" generatedCharSetsDecode
    , testProperty "generated actions are well formed" (wellFormed actionTextRaw isWellFormedActionRaw genActionText)
    , testProperty "generated arguments are well formed" (wellFormed argumentTextRaw isWellFormedArgumentRaw genArgumentText)
    , testProperty "unbalanced action is not well formed" unbalancedActionRejected
    ]

decodeAfterEncode :: Property
decodeAfterEncode = property $ do
  t <- forAll (Gen.text (Range.linear 0 40) Gen.unicode)
  decodeStringLiteral (encodeStringLiteral t) === Right t

generatedStringLiteralsDecode :: Property
generatedStringLiteralsDecode = property $ do
  lit <- forAll genStringLiteral
  assert (either (const False) (const True) (decodeStringLiteral lit))

generatedCharSetsDecode :: Property
generatedCharSetsDecode = property $ do
  cs <- forAll genCharSet
  assert (either (const False) (const True) (decodeCharSet cs))

wellFormed :: Show a => (a -> t) -> (t -> Bool) -> Gen a -> Property
wellFormed raw predicate gen = property $ do
  x <- forAll gen
  assert (predicate (raw x))

unbalancedActionRejected :: Property
unbalancedActionRejected = property $ do
  ActionText body <- forAll genActionText
  assert (not (isWellFormedActionRaw (body <> "}")))
  assert (not (isWellFormedActionRaw ("{" <> body)))
