module Canon.Testing
  ( TestRule (..)
  , testRules
  , knownLanguages
  , isTestUnit
  , matchesRule
  ) where

import Canon.Ignore (matchesPattern, parseIgnorePattern)
import Canon.Ignore (globMatches)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (splitDirectories)

data TestRule = TestRule
  { ruleKind :: Maybe Text
  , ruleMarker :: Maybe Text
  , ruleName :: Maybe Text
  , rulePath :: Maybe Text
  }
  deriving (Eq, Show)

knownLanguages :: [Text]
knownLanguages = ["java", "erlang", "clojure", "prolog", "haskell"]

testRules :: Text -> [TestRule]
testRules language = case language of
  "java" ->
    [TestRule (Just "method") (Just marker) Nothing Nothing | marker <- javaMarkers]
      ++ [TestRule (Just "method") Nothing (Just "test*") (Just "**/src/test/**")]
  "erlang" -> [TestRule (Just "function") Nothing (Just name) Nothing | name <- ["*_test", "*_test_"]]
  "clojure" -> [TestRule (Just "deftest") Nothing Nothing Nothing, TestRule (Just "definition") Nothing (Just "*-test") Nothing]
  "prolog" -> [TestRule (Just "clause") Nothing (Just "test") Nothing]
  "haskell" -> [TestRule (Just "function") Nothing (Just name) Nothing | name <- ["prop_*", "test_*"]]
  _ -> []
  where
    javaMarkers =
      [ "@Test"
      , "@org.junit.Test"
      , "@org.junit.jupiter.api.Test"
      , "@ParameterizedTest"
      , "@RepeatedTest"
      , "@TestFactory"
      , "@TestTemplate"
      , "@Property"
      , "@Example"
      , "@net.jqwik.api.Property"
      , "@net.jqwik.api.Example"
      ]

isTestUnit :: Text -> Text -> Text -> FilePath -> [Text] -> Bool
isTestUnit language kind name path markers = any (matchesRule kind name path markers) (testRules language)

matchesRule :: Text -> Text -> FilePath -> [Text] -> TestRule -> Bool
matchesRule kind name path markers rule =
  maybe True (== kind) (ruleKind rule)
    && maybe True (\m -> any (markerMatches m) markers) (ruleMarker rule)
    && maybe True (`globMatches` name) (ruleName rule)
    && maybe True pathMatches (rulePath rule)
  where
    markerMatches wanted marker = marker == wanted || (wanted <> "(") `T.isPrefixOf` marker
    pathMatches pattern = fromMaybe False $ do
      parsed <- parseIgnorePattern pattern
      pure (matchesPattern parsed False [T.pack d | d <- splitDirectories path, d /= "."])
