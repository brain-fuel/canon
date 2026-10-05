-- | Rust is read through the vendored grammars-v4 Rust grammar and the profile the Rust sample ships,
-- so these properties check both against what a Rust author means by an item and its documentation.
-- ref:DEC-rust-grammar ref:REQ-rust-support
module Canon.Extract.RustTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (treeRuleNodes, treeTokens)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..), hiddenChannelName, isEofToken)
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Canon.Decisions (emptyLedger)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.FilePath (normalise, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "rust"
    [ testProperty "the Rust grammar parses the scopeguard sample into its items" prop_rustGrammarParsesTheScopeguardSampleIntoItsItems
    , testProperty "the Rust lexer tells ranges, method calls, tuple indices, and escaped backslashes apart" prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart
    , testProperty "the Rust profile binds doc comments across attributes and recognises tests" prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/rust-scopeguard"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/rust/RustLexer.g4" "grammars/rust/RustParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Rust project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "rust" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | A real crate must parse whole, with every function, impl, and macro it defines found where
-- rustc finds them, or a Rust project's check would report parse failures instead of findings.
-- ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustGrammarParsesTheScopeguardSampleIntoItsItems :: Property
prop_rustGrammarParsesTheScopeguardSampleIntoItsItems = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  result <- evalIO (interpretFile interpreter (Name "crate") (sampleDir </> "source/src/lib.rs"))
  tree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure result
  length (treeRuleNodes (Name "function_") tree) === 21
  length (treeRuleNodes (Name "traitImpl") tree) === 8
  length (treeRuleNodes (Name "inherentImpl") tree) === 1
  length (treeRuleNodes (Name "macroRulesDefinition") tree) === 3
  length (treeRuleNodes (Name "enumeration") tree) === 3

-- | The upstream lexer told these apart with base-class predicates that canon cannot run; the
-- grammar's replacements must keep 1..2 a range, 1.max(2) a call, x.0.1 two tuple indices, and a
-- string ending in an escaped backslash a single string. ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart :: Property
prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t /= hiddenChannelName]
  typesOf "1..2" === Right [("INTEGER_LITERAL", "1"), ("DOTDOT", ".."), ("INTEGER_LITERAL", "2")]
  typesOf "1.max(2)" === Right [("INTEGER_LITERAL", "1"), ("DOT", "."), ("NON_KEYWORD_IDENTIFIER", "max"), ("LPAREN", "("), ("INTEGER_LITERAL", "2"), ("RPAREN", ")")]
  typesOf "1.5e3" === Right [("FLOAT_LITERAL", "1.5e3")]
  typesOf "\"a\\\\\" \"b\"" === Right [("STRING_LITERAL", "\"a\\\\\""), ("STRING_LITERAL", "\"b\"")]
  typesOf "#![no_std]" === Right [("POUND", "#"), ("NOT", "!"), ("LSQUAREBRACKET", "["), ("NON_KEYWORD_IDENTIFIER", "no_std"), ("RSQUAREBRACKET", "]")]
  case interpretText interpreter (Name "crate") "f.rs" "fn f() { let t = x.0.1; let u = a.union(b); _ = &&t; }" of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "letStatement") tree) === 2
      [tokenText t | node <- treeRuleNodes (Name "tupleIndex") tree, t <- treeTokens node] === ["0.1"]

fixture :: Text
fixture =
  T.unlines
    [ "#![no_std]"
    , "//! The crate exists to exercise the Rust profile. ref:some-key"
    , ""
    , "use core::fmt;"
    , ""
    , "// A plain comment is not documentation."
    , "fn helper() {}"
    , ""
    , "/// A shape is a circle or a square."
    , "#[derive(Debug, Clone)]"
    , "pub enum Shape {"
    , "    Circle(f64),"
    , "    Square(f64),"
    , "}"
    , ""
    , "/// Areas are what shapes are for."
    , "pub trait Area {"
    , "    /// The area of the shape."
    , "    fn area(&self) -> f64;"
    , "}"
    , ""
    , "impl Area for Shape {"
    , "    fn area(&self) -> f64 {"
    , "        match self {"
    , "            Shape::Circle(r) => 3.0 * r * r,"
    , "            Shape::Square(w) => w * w,"
    , "        }"
    , "    }"
    , "}"
    , ""
    , "pub mod nested {"
    , "    //! The nested module's own documentation."
    , ""
    , "    /// Limits keep the range small."
    , "    pub const LIMIT: u32 = 10;"
    , "}"
    , ""
    , "/// Orphaned by the blank line below."
    , ""
    , "pub struct Point(pub f64, pub f64);"
    , ""
    , "macro_rules! twice { ($e:expr) => { $e + $e }; }"
    , ""
    , "#[cfg(test)]"
    , "mod tests {"
    , "    /// Squares have the area of their side squared. ref:REQ-1"
    , "    #[test]"
    , "    fn square_area_is_side_squared() {}"
    , ""
    , "    #[test]"
    , "    fn uncommented_test() {}"
    , "}"
    ]

-- | In Rust a doc comment sits above an item's attributes, //! documents the module or file around
-- it, a plain // comment documents nothing, and #[test] makes a function a test, so the profile must
-- bind and recognise each that way for the Why of a Rust item to be its documentation.
-- ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests :: Property
prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "rust" profile interpreter "lib.rs" "lib.rs" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("function", "helper")
        , ("enum", "Shape")
        , ("trait", "Area")
        , ("function", "area")
        , ("impl", "Shape")
        , ("function", "area")
        , ("module", "nested")
        , ("const", "LIMIT")
        , ("struct", "Point")
        , ("macro", "twice")
        , ("module", "tests")
        , ("function", "square_area_is_side_squared")
        , ("function", "uncommented_test")
        ]
  whyOf "lib.rs" === ["The crate exists to exercise the Rust profile. ref:some-key"]
  whyOf "helper" === []
  whyOf "Shape" === ["A shape is a circle or a square."]
  whyOf "Area" === ["Areas are what shapes are for."]
  whyOf "area" === ["The area of the shape."]
  whyOf "nested" === ["The nested module's own documentation."]
  whyOf "LIMIT" === ["Limits keep the range small."]
  whyOf "Point" === []
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["square_area_is_side_squared", "uncommented_test", "helper"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "rust/lib.rs/function/helper"
        , "rust/lib.rs/impl/Shape/function/area"
        , "rust/lib.rs/struct/Point"
        , "rust/lib.rs/macro/twice"
        , "rust/lib.rs/module/tests/function/uncommented_test"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []
