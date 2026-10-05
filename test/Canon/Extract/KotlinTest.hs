-- | Kotlin is read through the vendored grammars-v4 Kotlin grammar with the profile the Turbine sample
-- ships, and through its canonically commented dialect, so these properties check both against what
-- a Kotlin author means by a declaration and its KDoc. ref:DEC-kotlin-dialect ref:REQ-kotlin-support
module Canon.Extract.KotlinTest (tests) where

import Canon.Antlr4.Interpret (renderInterpretError)
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
import Control.Monad (filterM, forM)
import Data.List (isSuffixOf, sort)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (makeRelative, normalise, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "kotlin"
    [ testProperty "the Kotlin grammar and profile parse every file of the Turbine sample" prop_theKotlinGrammarAndProfileParseEveryFileOfTheTurbineSample
    , testProperty "the Kotlin profile binds KDoc comments and recognises tests by annotation and source set" prop_theKotlinProfileBindsKDocCommentsAndRecognisesTestsByAnnotationAndSourceSet
    , testProperty "the Kotlin dialect parses every file of the Turbine sample with its KDoc comments" prop_theKotlinDialectParsesEveryFileOfTheTurbineSampleWithItsKDocComments
    , testProperty "the Kotlin dialect binds KDoc to declarations, requires it on public API, and reports misplaced KDoc" prop_theKotlinDialectBindsKDocToDeclarationsRequiresItOnPublicApiAndReportsMisplacedKDoc
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/kotlin-turbine"

-- | Every Kotlin file of the sample's sources, relative to them, in a stable order.
sampleFiles :: IO [FilePath]
sampleFiles = sort . map (makeRelative root) <$> go root
  where
    root = sampleDir </> "source"
    go dir = do
      entries <- map (dir </>) <$> listDirectory dir
      dirs <- filterM doesDirectoryExist entries
      nested <- concat <$> mapM go dirs
      pure ([e | e <- entries, e `notElem` dirs, ".kt" `isSuffixOf` e] ++ nested)

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Kotlin project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "kotlin" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the Kotlin grammar, with no units of a profile, so every
-- unit comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".kt"] (SplitGrammarFiles "grammars/kotlin/canonically_commented/KotlinLexer.g4" "grammars/kotlin/canonically_commented/KotlinParser.g4") (Name "kotlinFile") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | Extracts every file of the sample through a profile, failing on the first that does not parse.
extractSample :: Profile -> PropertyT IO [(FilePath, Extraction)]
extractSample profile = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  files <- evalIO sampleFiles
  forM files $ \file -> do
    source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
    result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "kotlin" profile interpreter file file source)
    either (\e -> annotate file >> annotate (T.unpack (renderGrammarExtractError e)) >> failure) (\x -> pure (file, x)) result

-- | Extracts one source text through a profile.
extractText :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractText profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "kotlin" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The units of a model below its file, as kind and name.
unitsOf :: Model Evidence -> [(Text, Text)]
unitsOf model = [(unitKindText (whatKind w), whatName w) | w <- map (answerValue . unitWhat) (drop 1 (modelAllUnits model))]

-- | Each decision of a model as the unit it binds to and its Why.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]

-- | A Kotlin project's check reports findings only if every file parses, with the functions,
-- classes, objects, type aliases, and properties the compiler sees, so the grammar and the profile a
-- Kotlin project copies must read all of Turbine. ref:REQ-kotlin-support ref:DEC-more-languages
prop_theKotlinGrammarAndProfileParseEveryFileOfTheTurbineSample :: Property
prop_theKotlinGrammarAndProfileParseEveryFileOfTheTurbineSample = withTests 1 $ property $ do
  profile <- sampleProfile
  extracted <- extractSample profile
  length extracted === 18
  let kinds = [k | (_, Extraction model _) <- extracted, (k, _) <- unitsOf model]
      count k = length (filter (== k) kinds)
  map count ["function", "class", "object", "type", "property"] === [241, 24, 1, 0, 274]

-- | KDoc is a block comment directly above a declaration, and a Kotlin test is a function marked
-- with a test annotation whatever its source set, so the profile must bind each KDoc comment to the
-- declaration below it and recognise each test of the sample. ref:REQ-kotlin-support
-- ref:DEC-kotlin-dialect
prop_theKotlinProfileBindsKDocCommentsAndRecognisesTestsByAnnotationAndSourceSet :: Property
prop_theKotlinProfileBindsKDocCommentsAndRecognisesTestsByAnnotationAndSourceSet = withTests 1 $ property $ do
  profile <- sampleProfile
  extracted <- extractSample profile
  let models = [model | (_, Extraction model _) <- extracted]
      testUnits = [u | model <- models, u <- modelAllUnits model, unitTest u]
      fileIds = [unitId (head' (modelAllUnits model)) | model <- models]
      head' xs = case xs of
        (x : _) -> x
        [] -> error "a model has its file unit"
      unitDecisions = [d | model <- models, d <- modelDecisions model, NonEmpty.head (decisionUnits d) `notElem` fileIds]
  length testUnits === 155
  length unitDecisions === 51
  length [() | (_, Extraction _ findings) <- extracted, OrphanDocComment _ _ <- findings] === 27
  Extraction fixture _ <-
    extractText
      profile
      "src/main/kotlin/Checks.kt"
      ( T.unlines
          [ "package checks"
          , ""
          , "/** Squares are what checks are for. */"
          , "fun square(x: Int): Int = x * x"
          , ""
          , "@Test fun squareOfTwoIsFour() { }"
          , ""
          , "@kotlin.test.Test"
          , "fun squareOfThreeIsNine() { }"
          ]
      )
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- drop 1 (modelAllUnits fixture)]
    === [("square", False), ("squareOfTwoIsFour", True), ("squareOfThreeIsNine", True)]
  whysOf fixture === [("kotlin/src/main/kotlin/Checks.kt/function/square", "Squares are what checks are for.")]

-- | KDoc comments are tokens of the dialect, so real Kotlin must still parse whole with them above
-- declarations, on constructor properties, and in interfaces, every comment binding to the unit it
-- documents. ref:REQ-kotlin-support ref:DEC-kotlin-dialect
prop_theKotlinDialectParsesEveryFileOfTheTurbineSampleWithItsKDocComments :: Property
prop_theKotlinDialectParsesEveryFileOfTheTurbineSampleWithItsKDocComments = withTests 1 $ property $ do
  extracted <- extractSample dialectProfile
  length extracted === 18
  let models = [model | (_, Extraction model _) <- extracted]
      kinds = [k | model <- models, (k, _) <- unitsOf model]
      count k = length (filter (== k) kinds)
  map count ["function", "class", "object", "type", "property", "constructor", "entry"] === [241, 24, 4, 0, 25, 0, 0]
  sum (map (length . modelDecisions) models) === 45
  length [() | (_, Extraction _ findings) <- extracted, OrphanDocComment _ _ <- findings] === 0
  length [() | model <- models, u <- modelAllUnits model, unitTest u] === 155
  length [() | model <- models, MissingCanonicalComment _ _ <- checkModel emptyRegistry emptyLedger model] === 169

-- | In the dialect the grammar says where KDoc binds and what needs it: above a declaration and its
-- annotations, on a member, an enum entry, a companion object, a secondary constructor, and a
-- constructor property; the file's own above its package directive; after an annotation, before a
-- statement, on a parameter, or on an accessor it binds to nothing and is reported. A public or
-- protected declaration needs KDoc, a member as its class does, and a private, internal, overriding,
-- or actual one does not. ref:REQ-kotlin-support ref:DEC-kotlin-dialect
prop_theKotlinDialectBindsKDocToDeclarationsRequiresItOnPublicApiAndReportsMisplacedKDoc :: Property
prop_theKotlinDialectBindsKDocToDeclarationsRequiresItOnPublicApiAndReportsMisplacedKDoc = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "Shapes.kt"
      ( T.unlines
          [ "/** Shapes and their areas. ref:some-key license:MIT */"
          , "package shapes"
          , ""
          , "import kotlin.math.PI"
          , ""
          , "// A plain comment is not documentation."
          , "/* Nor is a plain block comment. */"
          , "/** A shape has an area. */"
          , "@Suppress(\"unused\")"
          , "public interface Shape {"
          , "  /** The area of the shape. @return a positive number */"
          , "  public fun area(): Double"
          , ""
          , "  public val name: String"
          , "}"
          , ""
          , "/**"
          , " * A circle, by its radius."
          , " *"
          , " * @property radius the distance from the centre."
          , " */"
          , "class Circle("
          , "  /** The radius. */"
          , "  val radius: Double,"
          , "  /** On a plain parameter, so an orphan. */"
          , "  scale: Double,"
          , ") : Shape {"
          , "  override fun area(): Double = PI * radius * radius"
          , "  override val name: String get() = \"circle\""
          , ""
          , "  /** Made from a diameter. */"
          , "  constructor(diameter: Int) : this(diameter / 2.0, 1.0)"
          , ""
          , "  fun grow(): Circle {"
          , "    /** Before a statement, so an orphan. */"
          , "    val bigger = radius * 2"
          , "    return Circle(bigger, 1.0)"
          , "  }"
          , ""
          , "  private fun helper() = 0"
          , ""
          , "  /** The circle's factory. */"
          , "  companion object {"
          , "    fun unit(): Circle = Circle(1.0, 1.0)"
          , "  }"
          , "}"
          , ""
          , "/** Colours a shape may have. */"
          , "enum class Colour {"
          , "  /** The colour red. */"
          , "  RED,"
          , "  GREEN,"
          , "}"
          , ""
          , "@Deprecated(\"old\")"
          , "/** After the annotation, so an orphan. */"
          , "fun legacy() = 1"
          , ""
          , "internal fun hidden() = 2"
          , ""
          , "/** Internal declarations may have KDoc. */"
          , "internal object Registry"
          , ""
          , "typealias Area = Double"
          , ""
          , "actual fun platform(): String = \"jvm\""
          , ""
          , "@Test fun aCircleOfRadiusOneHasAreaPi() { }"
          ]
      )
  whysOf model
    === [ ("kotlin/Shapes.kt", "Shapes and their areas. ref:some-key license:MIT")
        , ("kotlin/Shapes.kt/class/Shape", "A shape has an area.")
        , ("kotlin/Shapes.kt/class/Shape/function/area", "The area of the shape. @return a positive number")
        , ("kotlin/Shapes.kt/class/Circle", "A circle, by its radius.\n\n@property radius the distance from the centre.")
        , ("kotlin/Shapes.kt/class/Circle/property/radius", "The radius.")
        , ("kotlin/Shapes.kt/class/Circle/constructor/constructor", "Made from a diameter.")
        , ("kotlin/Shapes.kt/class/Circle/object/companion", "The circle's factory.")
        , ("kotlin/Shapes.kt/class/Colour", "Colours a shape may have.")
        , ("kotlin/Shapes.kt/class/Colour/entry/RED", "The colour red.")
        , ("kotlin/Shapes.kt/object/Registry", "Internal declarations may have KDoc.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "kotlin/Shapes.kt/class/Shape/property/name"
        , "kotlin/Shapes.kt/class/Circle/function/grow"
        , "kotlin/Shapes.kt/class/Circle/object/companion/function/unit"
        , "kotlin/Shapes.kt/class/Colour/entry/GREEN"
        , "kotlin/Shapes.kt/function/legacy"
        , "kotlin/Shapes.kt/type/Area"
        , "kotlin/Shapes.kt/function/aCircleOfRadiusOneHasAreaPi"
        ]
