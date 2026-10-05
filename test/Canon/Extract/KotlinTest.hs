-- | Kotlin is read through the vendored grammars-v4 Kotlin grammar with the profile the Turbine sample
-- ships, and through its canonically commented dialect, so these properties check both against what
-- a Kotlin author means by a declaration and its KDoc. ref:DEC-kotlin-dialect ref:REQ-kotlin-support
module Canon.Extract.KotlinTest (tests) where

import Canon.Antlr4.Interpret (interpretText, loadInterpreter, renderInterpretError)
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
    , testProperty "a KDoc comment inside an expression is an orphan and the file still parses" prop_aKDocCommentInsideAnExpressionIsAnOrphanAndTheFileStillParses
    , testProperty "the members of a local class need no KDoc" prop_theMembersOfALocalClassNeedNoKDoc
    , testProperty "an unnamed companion object and secondary constructors are named by their keywords" prop_anUnnamedCompanionObjectAndSecondaryConstructorsAreNamedByTheirKeywords
    , testProperty "the Kotlin grammar and dialect read the Kotlin 1.4 to 2.4 syntax widely used projects write" prop_theKotlinGrammarAndDialectReadTheKotlin14To24SyntaxWidelyUsedProjectsWrite
    , testProperty "a Kotlin script whose last statement ends the file without a newline parses" prop_aKotlinScriptWhoseLastStatementEndsTheFileWithoutANewlineParses
    , testProperty "a comment nested in a KDoc comment does not close it" prop_aCommentNestedInAKDocCommentDoesNotCloseIt
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

-- | KDoc may stand anywhere a comment may, and one inside an expression documents nothing, so it must
-- not stop a Kotlin project's check: the file parses, every declaration keeps its own KDoc, and each
-- misplaced comment is reported as an orphan. ref:REQ-kotlin-support ref:DEC-kotlin-dialect
-- ref:DEC-stray-comments
prop_aKDocCommentInsideAnExpressionIsAnOrphanAndTheFileStillParses :: Property
prop_aKDocCommentInsideAnExpressionIsAnOrphanAndTheFileStillParses = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "Odd.kt"
      ( T.unlines
          [ "package odd"
          , ""
          , "/** Sums with comments in odd places. */"
          , "fun sum(a: Int, b: Int): Int {"
          , "    val c = listOf(a, /** between arguments */ b) + /** between operands */ 3"
          , "    val d = c.map { /** before a lambda's parameters */ it -> it + 1 }"
          , "    return when (a) { 1 -> /** in a when branch */ 2 else -> d.size }"
          , "}"
          , ""
          , "/** Still documented. */"
          , "val answer: Int = 42 * /** in an initializer */ 1"
          ]
      )
  whysOf model
    === [ ("kotlin/Odd.kt/function/sum", "Sums with comments in odd places.")
        , ("kotlin/Odd.kt/property/answer", "Still documented.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 5

-- | A class declared inside a function body is local to it, so no caller outside the function sees
-- its members, and KDoc on them is not API documentation; they must not take the requirement of the
-- public function around them. ref:REQ-kotlin-support ref:DEC-kotlin-dialect
prop_theMembersOfALocalClassNeedNoKDoc :: Property
prop_theMembersOfALocalClassNeedNoKDoc = withTests 1 $ property $ do
  Extraction model _ <-
    extractText
      dialectProfile
      "Local.kt"
      ( T.unlines
          [ "/** Counts with a local helper class. */"
          , "fun count(): Int {"
          , "    class Counter(val start: Int) {"
          , "        fun next(): Int = start + 1"
          , "        val twice: Int get() = start * 2"
          , "    }"
          , "    return Counter(1).next()"
          , "}"
          ]
      )
  [(k, n) | (k, n) <- unitsOf model] === [("function", "count"), ("property", "start"), ("function", "next"), ("property", "twice")]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

-- | A unit is named by what its source writes, so a companion object written without a name is named
-- by its companion keyword, not by the Companion Kotlin gives it, and secondary constructors by their
-- constructor keyword, numbered after the first, so each has an id of its own. ref:REQ-kotlin-support
-- ref:DEC-kotlin-dialect
prop_anUnnamedCompanionObjectAndSecondaryConstructorsAreNamedByTheirKeywords :: Property
prop_anUnnamedCompanionObjectAndSecondaryConstructorsAreNamedByTheirKeywords = withTests 1 $ property $ do
  Extraction model _ <-
    extractText
      dialectProfile
      "Point.kt"
      ( T.unlines
          [ "/** A point. */"
          , "class Point(val x: Int) {"
          , "    /** From a string. */"
          , "    constructor(s: String) : this(s.toInt())"
          , "    /** From a double. */"
          , "    constructor(d: Double) : this(d.toInt())"
          , "    /** Factories. */"
          , "    companion object {"
          , "        /** The origin. */"
          , "        fun origin(): Point = Point(0)"
          , "    }"
          , "    /** Named factories. */"
          , "    companion object Named"
          , "}"
          ]
      )
  [renderUnitId (unitId u) | u <- drop 1 (modelAllUnits model)]
    === [ "kotlin/Point.kt/class/Point"
        , "kotlin/Point.kt/class/Point/property/x"
        , "kotlin/Point.kt/class/Point/constructor/constructor"
        , "kotlin/Point.kt/class/Point/constructor/constructor#2"
        , "kotlin/Point.kt/class/Point/object/companion"
        , "kotlin/Point.kt/class/Point/object/companion/function/origin"
        , "kotlin/Point.kt/class/Point/object/Named"
        ]

-- | kotlinx.coroutines, ktor, OkHttp, Compose Multiplatform, and the Kotlin standard library write
-- fun interfaces, value classes, unsigned literals, the ..< range, definitely non-nullable types,
-- multi-dollar strings, guards and trailing commas in when entries, trailing commas in function
-- types, context parameters, destructuring by position and by name, companion blocks, and names in
-- any script. The profile and the dialect must read each, and the dialect find the declarations
-- among them. ref:REQ-kotlin-support ref:DEC-kotlin-grammar
prop_theKotlinGrammarAndDialectReadTheKotlin14To24SyntaxWidelyUsedProjectsWrite :: Property
prop_theKotlinGrammarAndDialectReadTheKotlin14To24SyntaxWidelyUsedProjectsWrite = withTests 1 $ property $ do
  let source =
        T.unlines
          [ "package modern"
          , ""
          , "/** Runs. */"
          , "fun interface Task { fun run() }"
          , ""
          , "/** Holds a result. */"
          , "@JvmInline public value class Result<out T>(val value: Any?)"
          , ""
          , "/** Has a companion block. */"
          , "interface Seq<out T> {"
          , "    companion {"
          , "        /** Makes an empty one. */"
          , "        fun <T> empty(): Seq<T> = TODO()"
          , "    }"
          , "}"
          , ""
          , "/** Logs in a context. */"
          , "context(logger: Logger) fun log(message: String) { logger.log(message) }"
          , ""
          , "/** Runs a block in a context. */"
          , "fun <T, R> within(with: T, block: context(T) () -> R): R = block(with)"
          , ""
          , "/** Exercises the expressions. */"
          , "fun <T> f(t: T & Any, v: Any?, data: List<Pair<Int, Int>>): Int {"
          , "    val mask = 0xFFu + 1uL"
          , "    for (i in 0..<10) {}"
          , "    for ([a, b] in data) {}"
          , "    (val first, val second = other) = data.first()"
          , "    val [x, y] = data.first()"
          , "    data.forEach { [index, _] -> index }"
          , "    val handler: ((Int, String,) -> Unit)? = null"
          , "    val π = 3.14"
          , "    val s = $$\"runTest$default $${t}\" + \"${"
          , "        v.hashCode()"
          , "    }\""
          , "    return when (v) {"
          , "        null if t == null -> 1"
          , "        is String if v.isEmpty() -> 2"
          , "        1,"
          , "        2,"
          , "        -> 3"
          , "        else -> 4"
          , "    }"
          , "}"
          ]
  profile <- sampleProfile
  Extraction plainModel _ <- extractText profile "Modern.kt" source
  map fst (unitsOf plainModel) === ["class", "function", "class", "class", "function", "function", "function", "function", "property", "property", "property", "property", "property"]
  Extraction model findings <- extractText dialectProfile "Modern.kt" source
  [renderUnitId (unitId u) | u <- drop 1 (modelAllUnits model)]
    === [ "kotlin/Modern.kt/class/Task"
        , "kotlin/Modern.kt/class/Task/function/run"
        , "kotlin/Modern.kt/class/Result"
        , "kotlin/Modern.kt/class/Result/property/value"
        , "kotlin/Modern.kt/class/Seq"
        , "kotlin/Modern.kt/class/Seq/object/companion"
        , "kotlin/Modern.kt/class/Seq/object/companion/function/empty"
        , "kotlin/Modern.kt/function/log"
        , "kotlin/Modern.kt/function/within"
        , "kotlin/Modern.kt/function/f"
        ]
  length [() | OrphanDocComment _ _ <- findings] === 0

-- | A Gradle build script often ends without a newline after its last statement, and kotlinc reads
-- it, so the script rule must too; a script's statements may declare an enum class, which the
-- dialect reads as a local class. ref:REQ-kotlin-support ref:DEC-kotlin-grammar
prop_aKotlinScriptWhoseLastStatementEndsTheFileWithoutANewlineParses :: Property
prop_aKotlinScriptWhoseLastStatementEndsTheFileWithoutANewlineParses = withTests 1 $ property $ do
  let parsed dir = do
        loaded <- evalIO (loadInterpreter (dir </> "KotlinLexer.g4") (dir </> "KotlinParser.g4"))
        interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
        pure [either (Left . T.unpack . renderInterpretError) (const (Right ())) (interpretText interpreter (Name "script") "build.gradle.kts" s) | s <- scripts]
      scripts =
        [ "include(\":publishing\")"
        , "plugins {\n    java\n}\n\ntasks.jar.configure {\n}"
        , "#!/usr/bin/env kotlin\nenum class Platform(val id: String) {\n    MACOS(\"macos\"),\n    LINUX(\"linux\"),\n}\n"
        ]
  plain <- parsed "grammars/kotlin"
  dialect <- parsed "grammars/kotlin/canonically_commented"
  plain === map (const (Right ())) scripts
  dialect === map (const (Right ())) scripts

-- | Kotlin's block comments nest, and kotlinx.coroutines writes a /* ... */ inside the code sample
-- of a KDoc comment, so the dialect must not take the nested comment's end for the KDoc's, and
-- must read the KDoc whole as the Why of the declaration below. ref:REQ-kotlin-support
-- ref:DEC-kotlin-dialect
prop_aCommentNestedInAKDocCommentDoesNotCloseIt :: Property
prop_aCommentNestedInAKDocCommentDoesNotCloseIt = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "Nested.kt"
      ( T.unlines
          [ "/**"
          , " * Sends without suspending:"
          , " * ```"
          , " * events.trySend(event).onClosed { /* already closed */ }"
          , " * ```"
          , " */"
          , "fun send() {}"
          ]
      )
  whysOf model === [("kotlin/Nested.kt/function/send", "Sends without suspending:\n```\nevents.trySend(event).onClosed { /* already closed */ }\n```")]
  length [() | OrphanDocComment _ _ <- findings] === 0
