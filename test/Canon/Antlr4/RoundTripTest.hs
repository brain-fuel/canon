module Canon.Antlr4.RoundTripTest (tests) where

import Canon.Antlr4.Gen (genGrammar)
import Canon.Antlr4.Grammar (parseGrammarText)
import Canon.Antlr4.Pretty (prettyGrammar)
import Data.Functor (void)
import Hedgehog (Property, forAll, property, tripping)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "round trip"
    [testProperty "parse after pretty is identity" parseAfterPretty]

parseAfterPretty :: Property
parseAfterPretty = property $ do
  g <- forAll genGrammar
  tripping g prettyGrammar (fmap void . parseGrammarText)
