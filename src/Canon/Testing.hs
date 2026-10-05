-- | canon recognises test units from the grammar's marker labels and a fixed table per language,
-- because a grammar cannot match an annotation by name. ref:DEC-test-requirement-check
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

-- | A rule is a conjunction of an optional kind, marker, name glob, and path pattern.
data TestRule = TestRule
  { ruleKind :: Maybe Text
  , ruleMarker :: Maybe Text
  , ruleName :: Maybe Text
  , rulePath :: Maybe Text
  }
  deriving (Eq, Show)

-- | The languages the table covers.
knownLanguages :: [Text]
knownLanguages = ["java", "erlang", "clojure", "prolog", "haskell", "rust", "csharp", "fsharp", "elixir", "gleam", "javascript", "typescript", "python", "go", "kotlin"]

-- | The rules of a language. Rust's, C#'s, and F#'s rules are attributes, which their grammars label
-- marker on every item. An F# test list bound with Expecto's [<Tests>] is the test, because the
-- testCase and testProperty inside it are expressions, not declarations. ref:DEC-rust-grammar
-- ref:DEC-csharp-grammar ref:DEC-fsharp-grammar Elixir's tests are the units its profile makes of
-- ExUnit's test calls, and Gleam's are gleeunit's functions named for it. ref:DEC-elixir-grammar
-- ref:DEC-gleam-grammar A Prolog test is a clause of plunit's test, which the plain profile names test
-- and the dialect makes a unit of kind test. ref:DEC-prolog-dialect
testRules :: Text -> [TestRule]
testRules language = case language of
  "java" ->
    [TestRule (Just "method") (Just marker) Nothing Nothing | marker <- javaMarkers]
      ++ [TestRule (Just "method") Nothing (Just "test*") (Just "**/src/test/**")]
  "erlang" -> [TestRule (Just "function") Nothing (Just name) Nothing | name <- ["*_test", "*_test_"]]
  "clojure" -> [TestRule (Just "deftest") Nothing Nothing Nothing, TestRule (Just "definition") Nothing (Just "*-test") Nothing]
  "prolog" -> [TestRule (Just "clause") Nothing (Just "test") Nothing, TestRule (Just "test") Nothing Nothing Nothing]
  "haskell" -> [TestRule (Just "function") Nothing (Just name) Nothing | name <- ["prop_*", "test_*"]]
  "rust" -> [TestRule (Just "function") (Just marker) Nothing Nothing | marker <- ["#[test]", "#[tokio::test]", "#[async_std::test]", "#[rstest]", "#[quickcheck]"]]
  "csharp" -> [TestRule (Just "method") (Just marker) Nothing Nothing | marker <- csharpMarkers]
  "fsharp" ->
    [TestRule (Just kind) (Just marker) Nothing Nothing | kind <- ["function", "member"], marker <- fsharpMarkers]
      ++ [TestRule (Just kind) (Just marker) Nothing Nothing | kind <- ["function", "value"], marker <- ["Tests", "Expecto.Tests"]]
  "elixir" -> [TestRule (Just "test") Nothing Nothing Nothing]
  "gleam" -> [TestRule (Just "function") Nothing (Just "*_test") Nothing]
  -- JavaScript and TypeScript tests are calls, not declarations, so a unit is a test by where it lives.
  "javascript" -> [TestRule Nothing Nothing Nothing (Just path) | path <- scriptTestPaths]
  "typescript" -> [TestRule Nothing Nothing Nothing (Just path) | path <- scriptTestPaths]
  "python" -> [TestRule (Just "function") Nothing (Just "test_*") Nothing, TestRule (Just "class") Nothing (Just "Test*") Nothing]
  "go" -> [TestRule (Just "function") Nothing (Just name) (Just "**/*_test.go") | name <- ["Test*", "Benchmark*", "Example*", "Fuzz*"]]
  -- Kotlin test names are often backticked sentences, so the source set names the tests, and the
  -- grammar labels annotations marker, so a function marked as a kotlin.test or JUnit test is one
  -- wherever it lives. ref:DEC-kotlin-dialect
  "kotlin" ->
    [TestRule (Just "function") Nothing Nothing (Just path) | path <- ["**/src/test/**", "**/src/*Test/**"]]
      ++ [TestRule (Just "function") (Just marker) Nothing Nothing | marker <- kotlinMarkers]
  _ -> []
  where
    scriptTestPaths = ["**/test/**", "**/tests/**", "**/__tests__/**", "**/*.test.*", "**/*.spec.*"]
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
    csharpMarkers =
      [ "Fact"
      , "Theory"
      , "Xunit.Fact"
      , "Xunit.Theory"
      , "Test"
      , "TestCase"
      , "TestCaseSource"
      , "NUnit.Framework.Test"
      , "NUnit.Framework.TestCase"
      , "NUnit.Framework.TestCaseSource"
      , "TestMethod"
      , "DataTestMethod"
      , "Microsoft.VisualStudio.TestTools.UnitTesting.TestMethod"
      ]
    kotlinMarkers = ["@Test", "@kotlin.test.Test", "@org.junit.Test", "@org.junit.jupiter.api.Test"]
    fsharpMarkers =
      [ "Fact"
      , "Theory"
      , "Xunit.Fact"
      , "Xunit.Theory"
      , "Test"
      , "TestCase"
      , "TestCaseSource"
      , "NUnit.Framework.Test"
      , "Property"
      , "FsCheck.Xunit.Property"
      , "FsCheck.NUnit.Property"
      ]

-- | Whether a unit is a test: some rule of its language matches.
isTestUnit :: Text -> Text -> Text -> FilePath -> [Text] -> Bool
isTestUnit language kind name path markers = any (matchesRule kind name path markers) (testRules language)

-- | Whether one rule matches, every given field agreeing.
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
