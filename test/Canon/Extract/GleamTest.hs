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
    , testProperty "the Gleam profile reads pre-1.0 syntax and hides internal items" prop_gleamProfileReadsPre10SyntaxAndHidesInternalItems
    , testProperty "the Gleam dialect reads /// and //// as canonical comments as Gleam joins them" prop_gleamDialectReadsDocAndModuleCommentsAsCanonicalCommentsAsGleamJoinsThem
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
    , "/// Bound across the blank line below, as Gleam binds it."
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

-- | In Gleam /// documents the item below its attributes, across blank lines, //// documents the
-- module, a plain // comment documents nothing, and gleeunit runs the public functions named _test,
-- so the profile must bind and recognise each that way for the Why of a Gleam item to be its documentation.
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
  whyOf "perimeter" === ["Bound across the blank line below, as Gleam binds it."]
  length [() | OrphanDocComment _ _ <- findings] === 0
  map testsOf ["square_area_test", "uncommented_test", "helper"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "gleam/shapes.gleam/const/unit"
        , "gleam/shapes.gleam/function/uncommented_test"
        ]

-- | Gleam code written before 1.0 declares external functions and types with the external keyword
-- and groups items by target with if erlang { ... }, and @internal hides a public item from the
-- documentation, so an older project must parse into the same units as a current one, and an
-- internal item must be marked hidden rather than missing its comment. ref:REQ-gleam-support
-- ref:DEC-gleam-grammar ref:DEC-hidden-label
prop_gleamProfileReadsPre10SyntaxAndHidesInternalItems :: Property
prop_gleamProfileReadsPre10SyntaxAndHidesInternalItems = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "if erlang {"
          , "  import gleam/erlang/internal"
          , "}"
          , ""
          , "/// Dynamic data comes from the outside world."
          , "pub external type Dynamic"
          , ""
          , "external type Opaque(a)"
          , ""
          , "if erlang {"
          , "  /// Identity on the Erlang target."
          , "  pub external fn from(anything) -> Dynamic ="
          , "    \"gleam_stdlib\" \"identity\""
          , "}"
          , ""
          , "if javascript {"
          , "  pub external fn from(anything) -> Dynamic ="
          , "    \"../gleam_stdlib.js\" \"identity\""
          , "}"
          , ""
          , "pub fn parse(text: String) -> Result(Int, Nil) {"
          , "  try value = do_parse(text)"
          , "  assert Ok(x) = value"
          , "  Ok(x)"
          , "}"
          , ""
          , "@internal"
          , "pub fn internal_helper(external: Int) -> Int { external }"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "gleam" profile interpreter "old.gleam" "old.gleam" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u, unitRequirement u) | u <- units, kindOf u /= "file"]
    === [ ("type", "Dynamic", Required)
        , ("type", "Opaque", Optional)
        , ("function", "from", Required)
        , ("function", "from", Required)
        , ("function", "parse", Required)
        , ("function", "internal_helper", Hidden)
        ]
  whyOf "Dynamic" === ["Dynamic data comes from the outside world."]
  whyOf "from" === ["Identity on the Erlang target."]
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["gleam/old.gleam/function/from#2", "gleam/old.gleam/function/parse"]

-- | The Gleam dialect, under grammars/gleam/canonically_commented, as a project names it.
dialectProfile :: Profile
dialectProfile = Profile [".gleam"] (SplitGrammarFiles "grammars/gleam/canonically_commented/GleamLexer.g4" "grammars/gleam/canonically_commented/GleamParser.g4") (Name "module") [] defaultCommentSyntax

-- | A canonically commented grammar must say in grammar form what the Gleam profile says in
-- canon.yaml, and say it as the Gleam compiler does: every /// line since the previous item documents
-- the item below its attributes, blank lines and plain comments included, every //// comment joins
-- the documentation of the module, @internal hides an item, a /// before an import documents nothing,
-- and the stdlib sample parses whole. ref:REQ-gleam-support ref:DEC-gleam-dialect ref:DEC-hidden-label
prop_gleamDialectReadsDocAndModuleCommentsAsCanonicalCommentsAsGleamJoinsThem :: Property
prop_gleamDialectReadsDocAndModuleCommentsAsCanonicalCommentsAsGleamJoinsThem = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  bytes <- evalIO (interpretFile interpreter (Name "module") (sampleDir </> "source/src/gleam/bytes_tree.gleam"))
  _ <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure bytes
  let source =
        T.unlines
          [ "//// Shapes exist to exercise the Gleam dialect."
          , "//// They cite ref:some-key."
          , ""
          , "/// Not documentation of an import."
          , "import gleam/float"
          , ""
          , "/// A shape is a circle"
          , ""
          , "/// or a square."
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
          , "//// The module documentation goes on here."
          , ""
          , "@internal"
          , "pub fn internal_area(shape: Shape) -> Float { area(shape) }"
          , ""
          , "pub const unit: Shape = Square(1.0)"
          , ""
          , "fn helper() { Nil }"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "gleam" dialectProfile interpreter "shapes.gleam" "shapes.gleam" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
      refsOf n = [whyReferences (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u, unitRequirement u) | u <- units, kindOf u /= "file"]
    === [ ("type", "Shape", Required)
        , ("constructor", "Circle", Optional)
        , ("field", "radius", Optional)
        , ("constructor", "Square", Optional)
        , ("function", "area", Required)
        , ("function", "internal_area", Hidden)
        , ("const", "unit", Required)
        , ("function", "helper", Optional)
        ]
  whyOf "shapes.gleam" === ["Shapes exist to exercise the Gleam dialect.\nThey cite ref:some-key.\n\nThe module documentation goes on here."]
  refsOf "shapes.gleam" === [[ReferenceKey "some-key"]]
  whyOf "Shape" === ["A shape is a circle\n\nor a square."]
  whyOf "Circle" === ["A circle by its radius."]
  whyOf "radius" === ["The radius, never negative."]
  whyOf "area" === ["Areas are what shapes are for."]
  length [() | OrphanDocComment _ _ <- findings] === 1
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["gleam/shapes.gleam/const/unit"]
