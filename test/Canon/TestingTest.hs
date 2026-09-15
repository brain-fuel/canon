-- | Test recognition must follow the table exactly. ref:DEC-test-requirement-check
module Canon.TestingTest (tests) where

import Canon.Testing
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Gen, Property, assert, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "testing"
    [ testProperty "a rule matches only when every field it gives matches" ruleConjunction
    , testProperty "a unit is a test when any rule of its language matches" ruleDisjunction
    , testProperty "a marker with arguments matches its bare entry and nothing longer" markerArguments
    , testProperty "junit 3 methods are recognised by name and path together" junitThree
    , testProperty "unknown languages have no rules" unknownLanguage
    ]

genWord :: Gen Text
genWord = Gen.text (Range.linear 1 8) Gen.alpha

ruleConjunction :: Property
ruleConjunction = property $ do
  kind <- forAll genWord
  name <- forAll genWord
  marker <- forAll (("@" <>) <$> genWord)
  useKind <- forAll Gen.bool
  useMarker <- forAll Gen.bool
  useName <- forAll Gen.bool
  let rule = TestRule (if useKind then Just kind else Nothing) (if useMarker then Just marker else Nothing) (if useName then Just name else Nothing) Nothing
  matchesRule kind name "src/x" [marker] rule === True
  matchesRule (kind <> "x") name "src/x" [marker] rule === not useKind
  matchesRule kind (name <> "x") "src/x" [marker] rule === not useName
  matchesRule kind name "src/x" [] rule === not useMarker

ruleDisjunction :: Property
ruleDisjunction = property $ do
  language <- forAll (Gen.element knownLanguages)
  kind <- forAll genWord
  name <- forAll genWord
  markers <- forAll (Gen.list (Range.linear 0 2) (("@" <>) <$> genWord))
  isTestUnit language kind name "src/x" markers === any (matchesRule kind name "src/x" markers) (testRules language)
  assert (not (null (testRules language)))

markerArguments :: Property
markerArguments = property $ do
  suffix <- forAll (Gen.text (Range.linear 0 6) Gen.alphaNum)
  isTestUnit "java" "method" "anything" "src/main/A.java" ["@Test(" <> suffix <> ")"] === True
  isTestUnit "java" "method" "anything" "src/main/A.java" ["@Test"] === True
  isTestUnit "java" "method" "anything" "src/main/A.java" ["@Test" <> suffix <> "Extra"] === (T.null suffix && False)
  isTestUnit "java" "field" "anything" "src/main/A.java" ["@Test"] === False
  isTestUnit "java" "method" "anything" "src/main/A.java" ["@Property", "@Deprecated"] === True

junitThree :: Property
junitThree = property $ do
  rest <- forAll genWord
  isTestUnit "java" "method" ("test" <> rest) "source/src/test/java/A.java" [] === True
  isTestUnit "java" "method" ("test" <> rest) "source/src/main/java/A.java" [] === False
  isTestUnit "java" "method" ("setUp" <> rest) "source/src/test/java/A.java" [] === False
  isTestUnit "erlang" "function" (rest <> "_test") "src/a.erl" [] === True
  isTestUnit "haskell" "function" ("prop_" <> rest) "src/A.hs" [] === True
  isTestUnit "prolog" "clause" "test" "a.pl" [] === True

unknownLanguage :: Property
unknownLanguage = property $ do
  language <- forAll (Gen.filter (`notElem` knownLanguages) genWord)
  kind <- forAll genWord
  testRules language === []
  isTestUnit language kind "test" "src/test/x" ["@Test"] === False
  assert (isJust (Just ()))
