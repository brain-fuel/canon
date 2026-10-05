-- | Gleam is read through canon's own Gleam grammar and the profile the Gleam sample ships, so these
-- properties check both against what a Gleam author means by an item and its documentation.
-- ref:DEC-gleam-grammar ref:REQ-gleam-support
module Canon.Extract.GleamTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Parse (treeRuleNodes)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (emptyRegistry)
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
    "gleam"
    [ testProperty "the Gleam grammar parses the stdlib sample into its items" prop_gleamGrammarParsesTheStdlibSampleIntoItsItems
    , testProperty "the Gleam profile binds item and module doc comments and recognises tests" prop_gleamProfileBindsItemAndModuleDocCommentsAndRecognisesTests
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/gleam-stdlib"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/gleam/GleamLexer.g4" "grammars/gleam/GleamParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Gleam project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "gleam" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | Real stdlib modules must parse whole, with every function, external function, type, and
-- constructor found where the Gleam compiler finds them, or a Gleam project's check would report
-- parse failures instead of findings. ref:REQ-gleam-support ref:DEC-gleam-grammar
prop_gleamGrammarParsesTheStdlibSampleIntoItsItems :: Property
prop_gleamGrammarParsesTheStdlibSampleIntoItsItems = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  order <- evalIO (interpretFile interpreter (Name "module") (sampleDir </> "source/src/gleam/order.gleam"))
  orderTree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure order
  length (treeRuleNodes (Name "publicFunction") orderTree) === 6
  length (treeRuleNodes (Name "publicType") orderTree) === 1
  length (treeRuleNodes (Name "constructor") orderTree) === 3
  bytes <- evalIO (interpretFile interpreter (Name "module") (sampleDir </> "source/src/gleam/bytes_tree.gleam"))
  bytesTree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure bytes
  length (treeRuleNodes (Name "publicFunction") bytesTree) === 14
  length (treeRuleNodes (Name "privateFunction") bytesTree) === 2
  length (treeRuleNodes (Name "attribute") bytesTree) === 7
  length (treeRuleNodes (Name "importStatement") bytesTree) === 3

fixture :: Text
fixture =
  T.unlines
    [ "//// Shapes exist to exercise the Gleam profile. ref:some-key"
    , ""
    , "import gleam/float.{type Float as F}"
    , ""
    , "// A plain comment is not documentation."
    , "fn helper() { Nil }"
    , ""
    , "/// A shape is a circle or a square."
    , "pub type Shape {"
    , "  /// A circle by its radius."
    , "  Circle("
    , "    /// The radius, never negative."
    , "    radius: Float,"
    , "  )"
    , "  Square(Float)"
    , "}"
    , ""
    , "/// Areas are what shapes are for."
    , "// The external is faster on Erlang."
    , "@external(erlang, \"shapes_ffi\", \"area\")"
    , "pub fn area(shape: Shape) -> Float"
    , ""
    , "pub const unit: Shape = Square(1.0)"
    , ""
    , "/// Orphaned by the blank line below."
    , ""
    , "pub fn perimeter(shape: Shape) -> Float {"
    , "  case shape { Circle(r) -> 2.0 *. r Square(w) -> 4.0 *. w }"
    , "}"
    , ""
    , "/// Squares have the area of their side squared. ref:REQ-1"
    , "pub fn square_area_test() { area(Square(2.0)) }"
    , ""
    , "pub fn uncommented_test() { Nil }"
    ]

-- | In Gleam /// documents the item below its attributes, //// documents the module, a plain //
-- comment documents nothing, and gleeunit runs the public functions named _test, so the profile
-- must bind and recognise each that way for the Why of a Gleam item to be its documentation.
-- ref:REQ-gleam-support ref:DEC-gleam-grammar
prop_gleamProfileBindsItemAndModuleDocCommentsAndRecognisesTests :: Property
prop_gleamProfileBindsItemAndModuleDocCommentsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "gleam" profile interpreter "shapes.gleam" "shapes.gleam" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("function", "helper")
        , ("type", "Shape")
        , ("constructor", "Circle")
        , ("field", "radius")
        , ("constructor", "Square")
        , ("function", "area")
        , ("const", "unit")
        , ("function", "perimeter")
        , ("function", "square_area_test")
        , ("function", "uncommented_test")
        ]
  whyOf "shapes.gleam" === ["Shapes exist to exercise the Gleam profile. ref:some-key"]
  whyOf "helper" === []
  whyOf "Shape" === ["A shape is a circle or a square."]
  whyOf "Circle" === ["A circle by its radius."]
  whyOf "radius" === ["The radius, never negative."]
  whyOf "area" === ["Areas are what shapes are for."]
  whyOf "perimeter" === []
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["square_area_test", "uncommented_test", "helper"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "gleam/shapes.gleam/const/unit"
        , "gleam/shapes.gleam/function/perimeter"
        , "gleam/shapes.gleam/function/uncommented_test"
        ]
