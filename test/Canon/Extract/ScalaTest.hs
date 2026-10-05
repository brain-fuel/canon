-- | Scala 3 is read through the grammars-v4 Scala 3 grammar, whose lexer hook turns optional braces
-- into layout tokens, and the profile the Iron sample ships, so these properties check both against
-- what a Scala author means by a definition and its Scaladoc. ref:DEC-scala-grammar
-- ref:DEC-scala-indentation ref:REQ-scala-support
module Canon.Extract.ScalaTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (treeRuleNodes)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..), defaultChannelName, isEofToken)
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Control.Monad (forM, forM_)
import qualified Data.List.NonEmpty as NonEmpty
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
    "scala"
    [ testProperty "the Scala lexer hook turns indentation into layout tokens" prop_theScalaLexerHookTurnsIndentationIntoLayoutTokens
    , testProperty "the Scala grammar parses every file of the Iron sample into its definitions" prop_theScalaGrammarParsesEveryFileOfTheIronSampleIntoItsDefinitions
    , testProperty "the Scala profile binds Scaladoc across annotations, exempts private and overriding members, and recognises tests" prop_theScalaProfileBindsScaladocAcrossAnnotationsExemptsPrivateAndOverridingMembersAndRecognisesTests
    , testProperty "the Scala dialect parses the Iron sample with its doc comments as the profile reads it" prop_theScalaDialectParsesTheIronSampleWithItsDocCommentsAsTheProfileReadsIt
    , testProperty "the Scala dialect binds Scaladoc to definitions and reports misplaced comments" prop_theScalaDialectBindsScaladocToDefinitionsAndReportsMisplacedComments
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/scala-iron"

-- | The sample's files below source/, which the grammar must each parse whole.
sampleFiles :: [FilePath]
sampleFiles =
  [ "main/src/io/github/iltotore/iron/Constraint.scala"
  , "main/src/io/github/iltotore/iron/Implication.scala"
  , "main/src/io/github/iltotore/iron/InvalidValue.scala"
  , "main/src/io/github/iltotore/iron/MapLogic.scala"
  , "main/src/io/github/iltotore/iron/RefinedType.scala"
  , "main/src/io/github/iltotore/iron/RuntimeConstraint.scala"
  , "main/src/io/github/iltotore/iron/constraint/all.scala"
  , "main/src/io/github/iltotore/iron/constraint/any.scala"
  , "main/src/io/github/iltotore/iron/constraint/char.scala"
  , "main/test/src/io/github/iltotore/iron/testing/AnySuite.scala"
  , "main/test/src/io/github/iltotore/iron/testing/CharSuite.scala"
  , "main/test/src/io/github/iltotore/iron/testing/package.scala"
  ]

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/scala/Scala3Lexer.g4" "grammars/scala/Scala3Parser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Scala project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "scala" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The parser sees where a block ends only through the tokens the hook emits, so it must open a
-- block after a token that may start one, close it at a line to the left, separate statements on
-- the same column, keep an indented enum body open across the commas of a case list, close a
-- lambda's body at the comma of the argument list it is passed in, continue a line that starts
-- with a dot, and read a file indented as a whole as one that is not, as the Scala 3 reference
-- describes optional braces. ref:REQ-scala-support
-- ref:DEC-scala-indentation ref:scala3-indentation
prop_theScalaLexerHookTurnsIndentationIntoLayoutTokens :: Property
prop_theScalaLexerHookTurnsIndentationIntoLayoutTokens = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [nameText (tokenType t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "object A:\n  def f(x: Int): Int =\n    x + 1\n\n  val y = 2\ndef g = 3\n"
    === Right
      [ "OBJECT", "Id", "COLON", "INDENT", "DEF", "Varid", "LPAREN", "Varid", "COLON", "Id", "RPAREN", "COLON", "Id", "ASSIGN"
      , "INDENT", "Varid", "Op", "IntegerLiteral", "DEDENT", "NEWLINE", "VAL", "Varid", "ASSIGN", "IntegerLiteral", "DEDENT"
      , "NEWLINE", "DEF", "Varid", "ASSIGN", "IntegerLiteral"
      ]
  typesOf "enum Color:\n  case Red, Green\n  case Blue\n"
    === Right ["ENUM", "Id", "COLON", "INDENT", "CASE", "Id", "COMMA", "Id", "NEWLINE", "CASE", "Id", "DEDENT"]
  typesOf "val z = f(x =>\n  x + 1, y)\n"
    === Right ["VAL", "Varid", "ASSIGN", "Varid", "LPAREN", "Varid", "ARROW", "INDENT", "Varid", "Op", "IntegerLiteral", "DEDENT", "COMMA", "Varid", "RPAREN"]
  typesOf "val w = xs\n  .map(f)\n  .sum\n"
    === Right ["VAL", "Varid", "ASSIGN", "Varid", "DOT", "Varid", "LPAREN", "Varid", "RPAREN", "DOT", "Varid"]
  typesOf "  def a = 1\n  def b = 2\n" === Right ["DEF", "Varid", "ASSIGN", "IntegerLiteral", "NEWLINE", "DEF", "Varid", "ASSIGN", "IntegerLiteral"]
  typesOf "class C {\n  def a = 1\n  // a comment line is blank\n  def b = 2\n}\n"
    === Right ["CLASS", "Id", "LBRACE", "DEF", "Varid", "ASSIGN", "IntegerLiteral", "NEWLINE", "DEF", "Varid", "ASSIGN", "IntegerLiteral", "RBRACE"]

-- | Real Scala 3 must parse whole, with every object, class, trait, definition, and given a file
-- declares found where the compiler finds it, or a Scala project's check would report parse
-- failures instead of findings. ref:REQ-scala-support ref:DEC-scala-grammar
prop_theScalaGrammarParsesEveryFileOfTheIronSampleIntoItsDefinitions :: Property
prop_theScalaGrammarParsesEveryFileOfTheIronSampleIntoItsDefinitions = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  trees <- forM sampleFiles $ \file -> do
    result <- evalIO (interpretFile interpreter (Name "compilationUnit") (sampleDir </> "source" </> file))
    either (\e -> annotate (file <> ": " <> T.unpack (renderInterpretError e)) >> failure) pure result
  let count rule tree = length (treeRuleNodes (Name rule) tree)
      counts tree = filter ((> 0) . snd) [(rule, count rule tree) | rule <- unitRules]
      unitRules = ["objectDefinition", "classDefinition", "caseClassDefinition", "traitDefinition", "defDefinition", "valDefinition", "givenDefinition", "extension_", "typeDefinition"]
      byFile = Map.fromList (zip sampleFiles (map counts trees))
      at file = Map.findWithDefault [] ("main/src/io/github/iltotore/iron/" <> file) byFile
  at "constraint/char.scala" === [("objectDefinition", 6), ("classDefinition", 5), ("defDefinition", 15), ("givenDefinition", 5), ("typeDefinition", 1)]
  at "constraint/any.scala" === [("objectDefinition", 7), ("classDefinition", 9), ("traitDefinition", 1), ("defDefinition", 15), ("givenDefinition", 19), ("typeDefinition", 3)]
  at "RefinedType.scala" === [("objectDefinition", 1), ("traitDefinition", 4), ("defDefinition", 15), ("valDefinition", 1), ("givenDefinition", 3), ("extension_", 1), ("typeDefinition", 9)]
  at "InvalidValue.scala" === [("caseClassDefinition", 1)]
  Map.lookup "main/test/src/io/github/iltotore/iron/testing/package.scala" byFile === Just [("defDefinition", 3), ("extension_", 1)]

profileFixture :: Text
profileFixture =
  T.unlines
    [ "package shapes"
    , ""
    , "import scala.math.Pi"
    , ""
    , "// A plain comment is not documentation."
    , "def helper(x: Int): Int = x + 1"
    , ""
    , "/** Areas are what shapes are for. ref:some-key */"
    , "// A note between the doc comment and its definition."
    , "@inline"
    , "final def area(shape: Shape): Double ="
    , "  shape match"
    , "    case Shape.Circle(r) => Pi * r * r"
    , "    case Shape.Square(w) => w * w"
    , ""
    , "/** A shape is a circle or a square. */"
    , "enum Shape:"
    , "  /** A circle by its radius. */"
    , "  case Circle(radius: Double)"
    , "  case Square(side: Double)"
    , ""
    , "/** A canvas draws shapes. */"
    , "class Canvas(width: Int):"
    , "  private var count = 0"
    , "  /** The canvas width. */"
    , "  val size: Int = width"
    , "  override def toString: String = s\"Canvas($width)\""
    , "  protected[shapes] def reset(): Unit = count = 0"
    , "  def draw(shape: Shape): Unit ="
    , "    count += 1"
    , ""
    , "/** Orders shapes by area. */"
    , "given Ordering[Shape] = Ordering.by(area)"
    , ""
    , "given shapeName: Conversion[Shape, String] = _.toString"
    , ""
    , "extension (s: Shape)"
    , "  /** Doubles the area. */"
    , "  def doubled: Double = area(s) * 2"
    , ""
    , "type Area = Double"
    , ""
    , "class AreaTest:"
    , "  /** Squares have the area of their side squared. ref:REQ-1 */"
    , "  @Test"
    , "  def squareArea(): Unit = assert(area(Shape.Square(2)) == 4)"
    , ""
    , "  @org.junit.Test def uncommented(): Unit = ()"
    ]

-- | An extraction through the sample's profile under a path.
extractAt :: FilePath -> Text -> PropertyT IO Extraction
extractAt path source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "scala" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The units of a model below the file, as kind, name, and requirement.
unitsOf :: Model Evidence -> [(Text, Text, CommentRequirement)]
unitsOf model = [(unitKindText (whatKind (whatOf u)), whatName (whatOf u), unitRequirement u) | u <- modelAllUnits model, unitKindText (whatKind (whatOf u)) /= "file"]
  where
    whatOf = answerValue . unitWhat

-- | The Why bound to each unit, by name.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(whatName (answerValue (unitWhat u)), whyText (answerValue (decisionWhy d))) | u <- modelAllUnits model, d <- decisionsFor (unitId u) model]

-- | Scaladoc documents the definition below it with its annotations and modifiers, a plain comment
-- between them does not part them, a member is public unless it says private or protected, an
-- override inherits the documentation of what it overrides, a JUnit @Test makes a method a test,
-- and a munit or ScalaTest suite is a test by its file, since its tests are calls; the profile must
-- bind, require, and recognise each that way. ref:REQ-scala-support ref:DEC-scala-grammar
-- ref:scaladoc
prop_theScalaProfileBindsScaladocAcrossAnnotationsExemptsPrivateAndOverridingMembersAndRecognisesTests :: Property
prop_theScalaProfileBindsScaladocAcrossAnnotationsExemptsPrivateAndOverridingMembersAndRecognisesTests = withTests 1 $ property $ do
  Extraction model findings <- extractAt "src/main/scala/shapes/Shapes.scala" profileFixture
  unitsOf model
    === [ ("def", "helper", Required)
        , ("def", "area", Required)
        , ("enum", "Shape", Required)
        , ("case", "Circle", Required)
        , ("case", "Square", Required)
        , ("class", "Canvas", Required)
        , ("var", "count", Optional)
        , ("val", "size", Required)
        , ("def", "toString", Optional)
        , ("def", "reset", Optional)
        , ("def", "draw", Required)
        , ("given", "Ordering[Shape]", Required)
        , ("given", "shapeName", Required)
        , ("extension", "Shape", Optional)
        , ("def", "doubled", Required)
        , ("type", "Area", Required)
        , ("class", "AreaTest", Required)
        , ("def", "squareArea", Required)
        , ("def", "uncommented", Required)
        ]
  whysOf model
    === [ ("area", "Areas are what shapes are for. ref:some-key")
        , ("Shape", "A shape is a circle or a square.")
        , ("Circle", "A circle by its radius.")
        , ("Canvas", "A canvas draws shapes.")
        , ("size", "The canvas width.")
        , ("Ordering[Shape]", "Orders shapes by area.")
        , ("doubled", "Doubles the area.")
        , ("squareArea", "Squares have the area of their side squared. ref:REQ-1")
        ]
  [() | OrphanDocComment _ _ <- findings] === []
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- modelAllUnits model, unitTest u] === [("squareArea", True), ("uncommented", True)]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []
  Extraction suite _ <-
    extractAt
      "src/test/scala/shapes/ShapesSuite.scala"
      ( T.unlines
          [ "package shapes"
          , ""
          , "/** Shapes have the areas their formulas give. ref:REQ-1 */"
          , "class ShapesSuite extends munit.FunSuite:"
          , "  test(\"a unit square has unit area\") {"
          , "    assertEquals(area(Shape.Square(1)), 1.0)"
          , "  }"
          ]
      )
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- modelAllUnits suite, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"] === [("ShapesSuite", True)]

-- | The canonically commented dialect of the Scala grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".scala"] (SplitGrammarFiles "grammars/scala/canonically_commented/Scala3Lexer.g4" "grammars/scala/canonically_commented/Scala3Parser.g4") (Name "compilationUnit") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | An extraction through the Scala dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "scala" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Scaladoc comments are tokens of the dialect, and the lexer hook must place them so optional
-- braces read as before: every file of the sample must parse with its comments, bind each of them,
-- and leave none attached to nothing, and the dialect must find the units, requirements, and doc
-- comments the profile finds. ref:REQ-scala-support ref:DEC-scala-dialect
prop_theScalaDialectParsesTheIronSampleWithItsDocCommentsAsTheProfileReadsIt :: Property
prop_theScalaDialectParsesTheIronSampleWithItsDocCommentsAsTheProfileReadsIt = withTests 1 $ property $ do
  forM_ sampleFiles $ \file -> do
    source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
    Extraction dialect dialectFindings <- extractDialect file source
    Extraction profiled _ <- extractAt file source
    annotate file
    [() | OrphanDocComment _ _ <- dialectFindings] === []
    length (modelDecisions dialect) === length (T.breakOnAll "/**" source)
    let missing model = [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
        unitDecisions model = [renderDecisionId (decisionId d) | d <- modelDecisions model]
    missing dialect === missing profiled
    unitDecisions dialect === unitDecisions profiled

-- | In the dialect the grammar says where a Scaladoc comment binds: above a definition and its
-- annotations and modifiers, and above an enum case, while one after an annotation or above a
-- statement or a local definition binds to nothing and is reported; what is private needs none, and
-- an enum's cases need one when the enum does. ref:REQ-scala-support ref:DEC-scala-dialect
prop_theScalaDialectBindsScaladocToDefinitionsAndReportsMisplacedComments :: Property
prop_theScalaDialectBindsScaladocToDefinitionsAndReportsMisplacedComments = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "Shapes.scala"
      ( T.unlines
          [ "package shapes"
          , ""
          , "/** A shape. ref:some-key */"
          , "enum Shape:"
          , "  /** A circle by its radius. */"
          , "  case Circle(radius: Double)"
          , "  case Square(side: Double)"
          , ""
          , "@deprecated(\"use area2\")"
          , "/** After the annotation, so an orphan. */"
          , "def area(shape: Shape): Double ="
          , "  /** A local definition, so an orphan. */"
          , "  val sq = 2.0"
          , "  sq"
          , ""
          , "/** Hidden needs none, but may have one. */"
          , "private def hidden = 0"
          , ""
          , "private def unused = 0"
          , ""
          , "/* A plain comment is not documentation. */"
          , "/** Shows a number. */"
          , "@inline def shown(x: Int) = x"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("scala/Shapes.scala/enum/Shape", "A shape. ref:some-key")
        , ("scala/Shapes.scala/enum/Shape/case/Circle", "A circle by its radius.")
        , ("scala/Shapes.scala/def/hidden", "Hidden needs none, but may have one.")
        , ("scala/Shapes.scala/def/shown", "Shows a number.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 2
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["scala/Shapes.scala/enum/Shape/case/Square", "scala/Shapes.scala/def/area"]
