-- | Scala is read through the Scala grammar written for canon from the Scala 3 syntax summary and
-- the Scala 3 compiler's parser, whose lexer hook inserts layout tokens where the compiler's scanner
-- does, and the profile the Iron sample ships, so these properties check both against what the
-- compiler and a Scala author mean by a definition and its Scaladoc. ref:DEC-scala-grammar
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
    [ testProperty "the Scala lexer hook inserts layout tokens where the compiler does" prop_theScalaLexerHookInsertsLayoutTokensWhereTheCompilerDoes
    , testProperty "the Scala lexer reads strings, characters, comments, and XML whole" prop_theScalaLexerReadsStringsCharactersCommentsAndXmlWhole
    , testProperty "the Scala grammar parses every file of the Iron sample into its definitions" prop_theScalaGrammarParsesEveryFileOfTheIronSampleIntoItsDefinitions
    , testProperty "the Scala profile reads Scala 2 and Scala 3 constructs into their definitions" prop_theScalaProfileReadsScala2AndScala3ConstructsIntoTheirDefinitions
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
  loaded <- evalIO (loadInterpreter "grammars/scala/ScalaLexer.g4" "grammars/scala/ScalaParser.g4")
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

-- | The parser sees where a block ends only through the tokens the hook emits, so it must insert
-- INDENT, OUTDENT, and NEWLINE where the Scala 3 compiler's scanner does: after the tokens that may
-- open an indented region, at a line to the left, between statements level with each other, never
-- inside parentheses except for an indented lambda body, which closes before a comma or the closing
-- parenthesis, for case regions, colon-ended lines, with templates, end markers, extensions,
-- leading infix operators, and the closing tokens else, catch, and yield. ref:REQ-scala-support
-- ref:DEC-scala-indentation ref:scala3-indentation ref:scala3-compiler-scanners
prop_theScalaLexerHookInsertsLayoutTokensWhereTheCompilerDoes :: Property
prop_theScalaLexerHookInsertsLayoutTokensWhereTheCompilerDoes = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [nameText (tokenType t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  -- a colon-ended line opens a template body, = a def body, and a blank line is skipped
  typesOf "object A:\n  def f(x: Int): Int =\n    x + 1\n\n  val y = 2\ndef g = 3\n"
    === Right ["OBJECT", "ID", "COLON", "INDENT", "DEF", "ID", "LPAREN", "ID", "COLON", "ID", "RPAREN", "COLON", "ID", "EQUALS", "INDENT", "ID", "OP", "NUMBER", "OUTDENT", "NEWLINE", "VAL", "ID", "EQUALS", "NUMBER", "OUTDENT", "NEWLINE", "DEF", "ID", "EQUALS", "NUMBER"]
  -- a comma inside an enum body closes nothing
  typesOf "enum Color:\n  case Red, Green\n  case Blue\n"
    === Right ["ENUM", "ID", "COLON", "INDENT", "CASE", "ID", "COMMA", "ID", "NEWLINE", "CASE", "ID", "OUTDENT"]
  -- a file indented as a whole reads as one that is not
  typesOf "  def a = 1\n  def b = 2\n"
    === Right ["DEF", "ID", "EQUALS", "NUMBER", "NEWLINE", "DEF", "ID", "EQUALS", "NUMBER"]
  -- braces separate statements, and a comment line is blank
  typesOf "class C {\n  def a = 1\n  // a comment line is blank\n  def b = 2\n}\n"
    === Right ["CLASS", "ID", "LBRACE", "DEF", "ID", "EQUALS", "NUMBER", "NEWLINE", "DEF", "ID", "EQUALS", "NUMBER", "RBRACE"]
  -- case clauses level with their match form a region the first other line closes
  typesOf "x match\ncase 1 => a\ncase 2 => b\nprintln(x)\n"
    === Right ["ID", "MATCH", "INDENT", "CASE", "NUMBER", "FAT_ARROW", "ID", "NEWLINE", "CASE", "NUMBER", "FAT_ARROW", "ID", "OUTDENT", "NEWLINE", "ID", "LPAREN", "ID", "RPAREN"]
  -- an indented match region closes at a line of its width that is not a case
  typesOf "x match\n  case 1 => a\n  b\n"
    === Right ["ID", "MATCH", "INDENT", "CASE", "NUMBER", "FAT_ARROW", "ID", "OUTDENT", "NEWLINE", "ID"]
  -- line breaks inside parentheses separate nothing
  typesOf "g(\n  1,\n  2)\n"
    === Right ["ID", "LPAREN", "NUMBER", "COMMA", "NUMBER", "RPAREN"]
  -- a lambda's indented body inside parentheses closes before a comma
  typesOf "f(x =>\n    a\n  , y)\n"
    === Right ["ID", "LPAREN", "ID", "FAT_ARROW", "INDENT", "ID", "OUTDENT", "COMMA", "ID", "RPAREN"]
  -- else closes the then branch on the line it continues
  typesOf "val y = if c then\n    a else b\n"
    === Right ["VAL", "ID", "EQUALS", "IF", "ID", "THEN", "INDENT", "ID", "OUTDENT", "ELSE", "ID"]
  -- catch closes a try body to its left
  typesOf "try\n    a\n  catch b\n"
    === Right ["TRY", "INDENT", "ID", "OUTDENT", "CATCH", "ID"]
  -- yield closes the enumerators of a for
  typesOf "for\n  x <- xs\nyield x\n"
    === Right ["FOR", "INDENT", "ID", "LEFT_ARROW", "ID", "OUTDENT", "YIELD", "ID"]
  -- an end marker is a statement after the body it ends
  typesOf "class A:\n  def f = 1\nend A\n"
    === Right ["CLASS", "ID", "COLON", "INDENT", "DEF", "ID", "EQUALS", "NUMBER", "OUTDENT", "NEWLINE", "END", "ID"]
  -- a colon before an end marker is an empty body
  typesOf "class A extends B:\nend A\n"
    === Right ["CLASS", "ID", "EXTENDS", "ID", "COLON", "NEWLINE", "END", "ID"]
  -- with at the end of a line opens a given's body
  typesOf "given Foo with\n  def f = 1\n"
    === Right ["GIVEN", "ID", "WITH", "INDENT", "DEF", "ID", "EQUALS", "NUMBER", "OUTDENT"]
  -- a colon argument's lambda body is an indented block
  typesOf "xs.foreach: x =>\n  f(x)\n  g(x)\n"
    === Right ["ID", "DOT", "ID", "COLON", "ID", "FAT_ARROW", "INDENT", "ID", "LPAREN", "ID", "RPAREN", "NEWLINE", "ID", "LPAREN", "ID", "RPAREN", "OUTDENT"]
  -- a closing parenthesis closes the lambda body opened inside it
  typesOf "xs.map(x =>\n  x + 1\n)\n"
    === Right ["ID", "DOT", "ID", "LPAREN", "ID", "FAT_ARROW", "INDENT", "ID", "OP", "NUMBER", "OUTDENT", "RPAREN"]
  -- a lambda in braces takes the braces' width, so its body opens no region
  typesOf "xs.map { x =>\n  x + 1\n}\n"
    === Right ["ID", "DOT", "ID", "LBRACE", "ID", "FAT_ARROW", "ID", "OP", "NUMBER", "RBRACE"]
  -- an extension's methods are indented after its parameters
  typesOf "extension (s: String)\n  def a = 1\n  def b = 2\nend extension\n"
    === Right ["EXTENSION", "LPAREN", "ID", "COLON", "ID", "RPAREN", "INDENT", "DEF", "ID", "EQUALS", "NUMBER", "NEWLINE", "DEF", "ID", "EQUALS", "NUMBER", "OUTDENT", "NEWLINE", "END", "EXTENSION"]
  -- an old-style condition's closing parenthesis opens its branch
  typesOf "if (c)\n  a\nelse\n  b\n"
    === Right ["IF", "LPAREN", "ID", "RPAREN", "INDENT", "ID", "OUTDENT", "ELSE", "INDENT", "ID", "OUTDENT"]
  -- a line starting with a dot continues the one above
  typesOf "val w = xs\n  .map(f)\n  .sum\n"
    === Right ["VAL", "ID", "EQUALS", "ID", "DOT", "ID", "LPAREN", "ID", "RPAREN", "DOT", "ID"]
  -- a leading infix operator continues the line above
  typesOf "val x = a\n  + b\n"
    === Right ["VAL", "ID", "EQUALS", "ID", "OP", "ID"]
  -- a prefix operator touching its operand starts a statement
  typesOf "foo\n  !bar\n"
    === Right ["ID", "NEWLINE", "OP", "ID"]
  -- an indented line starting with a parenthesis continues the call
  typesOf "f(x)\n  (y)\n"
    === Right ["ID", "LPAREN", "ID", "RPAREN", "LPAREN", "ID", "RPAREN"]
  -- a brace on the next line is separated, for the template rule to take it
  typesOf "class C\n{\n  def a = 1\n}\n"
    === Right ["CLASS", "ID", "NEWLINE", "LBRACE", "DEF", "ID", "EQUALS", "NUMBER", "RBRACE"]
  -- an operator ends a statement
  typesOf "def f = ???\ndef g = 1\n"
    === Right ["DEF", "ID", "EQUALS", "OP", "NEWLINE", "DEF", "ID", "EQUALS", "NUMBER"]

-- | Interpolations, multi-line and dedented strings, characters, symbols, backquoted names, nested
-- comments, and XML literals must each lex whole, or a brace or quote inside one would be read as
-- code; an interpolated string is its text, holes, and the code of its ${ } blocks.
-- ref:REQ-scala-support ref:DEC-scala-grammar ref:scala3-syntax ref:scala3-compiler-scanners
prop_theScalaLexerReadsStringsCharactersCommentsAndXmlWhole :: Property
prop_theScalaLexerReadsStringsCharactersCommentsAndXmlWhole = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [nameText (tokenType t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "s\"a ${f(\"}\")} $x$y $$ $\"z\""
    === Right ["INTERPOLATION_START", "INTERPOLATION_TEXT", "LBRACE", "ID", "LPAREN", "STRING", "RPAREN", "RBRACE", "INTERPOLATION_TEXT", "INTERPOLATION_ID", "INTERPOLATION_ID", "INTERPOLATION_TEXT", "INTERPOLATION_ESCAPE", "INTERPOLATION_TEXT", "INTERPOLATION_ESCAPE", "INTERPOLATION_TEXT", "INTERPOLATION_END"]
  typesOf "s\"\"\"a ${x}\n \"b\"\"\"\" + 1"
    === Right ["INTERPOLATION_START", "INTERPOLATION_TEXT", "LBRACE", "ID", "RBRACE", "INTERPOLATION_TEXT", "INTERPOLATION_END", "OP", "NUMBER"]
  typesOf "raw\"a\\\\$$b\\\\\" raw\"\\$$x\""
    === Right ["INTERPOLATION_START", "INTERPOLATION_TEXT", "INTERPOLATION_ESCAPE", "INTERPOLATION_TEXT", "INTERPOLATION_END", "INTERPOLATION_START", "INTERPOLATION_TEXT", "INTERPOLATION_ESCAPE", "INTERPOLATION_TEXT", "INTERPOLATION_END"]
  typesOf "\"\"\"a \"q\" }\n\"\"\"" === Right ["MULTILINE_STRING"]
  typesOf "val d = '''\n  a } \"\n  '''\n" === Right ["VAL", "ID", "EQUALS", "DEDENTED_STRING"]
  typesOf "'\\n' '\"' '\\u0041' 'a 'sym" === Right ["CHARACTER", "CHARACTER", "CHARACTER", "SYMBOL", "SYMBOL"]
  typesOf "`a b` /* x /* y */ z */ unary_! a :: b" === Right ["BACKQUOTED_ID", "ID", "ID", "OP", "ID"]
  typesOf "val p = <p class=\"a\">Don't {x}</p>"
    === Right ["VAL", "ID", "EQUALS", "XML_OPEN", "XML_NAME", "XML_EQUALS", "XML_VALUE", "XML_TAG_END", "XML_TEXT", "LBRACE", "ID", "RBRACE", "XML_END_TAG"]
  typesOf "for (x <- xs) yield x: A <: B" === Right ["FOR", "LPAREN", "ID", "LEFT_ARROW", "ID", "RPAREN", "YIELD", "ID", "COLON", "ID", "SUBTYPE", "ID"]
  typesOf "a < b && c<d" === Right ["ID", "OP", "ID", "OP", "ID", "OP", "ID"]

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
      unitRules = ["objectDefinition", "classDefinition", "caseClassDefinition", "traitDefinition", "defDefinition", "valDefinition", "givenDefinition", "extension", "typeDefinition"]
      byFile = Map.fromList (zip sampleFiles (map counts trees))
      at file = Map.findWithDefault [] ("main/src/io/github/iltotore/iron/" <> file) byFile
  at "constraint/char.scala" === [("objectDefinition", 6), ("classDefinition", 5), ("defDefinition", 15), ("givenDefinition", 5), ("typeDefinition", 1)]
  at "constraint/any.scala" === [("objectDefinition", 7), ("classDefinition", 9), ("traitDefinition", 1), ("defDefinition", 15), ("givenDefinition", 19), ("typeDefinition", 3)]
  at "RefinedType.scala" === [("objectDefinition", 1), ("traitDefinition", 4), ("defDefinition", 15), ("valDefinition", 1), ("givenDefinition", 3), ("extension", 1), ("typeDefinition", 9)]
  at "InvalidValue.scala" === [("caseClassDefinition", 1)]
  Map.lookup "main/test/src/io/github/iltotore/iron/testing/package.scala" byFile === Just [("defDefinition", 3), ("extension", 1)]

-- | The Scala 2 forms the Scala 3 compiler still reads, procedure syntax, _ and => in imports, symbol
-- literals, implicit classes and conversions, existential types, XML literals, private[this], and a
-- template body in braces on the line below its class, and the Scala 3 forms, enums and their cases,
-- opaque types, extensions with end markers, exports, givens old and new with and without names,
-- colon-argument lambdas, and packagings, must each read into the definitions the compiler sees,
-- with no definition read as an expression and each given named by its name or its type.
-- ref:REQ-scala-support ref:DEC-scala-grammar ref:scala3-syntax ref:scala3-compiler-parser
prop_theScalaProfileReadsScala2AndScala3ConstructsIntoTheirDefinitions :: Property
prop_theScalaProfileReadsScala2AndScala3ConstructsIntoTheirDefinitions = withTests 1 $ property $ do
  let idsOf path model = [T.drop (T.length ("scala/" <> T.pack path <> "/")) (renderUnitId (unitId u)) | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]
  Extraction scala2 _ <- extractAt "src/main/scala/legacy/Legacy.scala" (T.unlines scala2Fixture)
  idsOf "src/main/scala/legacy/Legacy.scala" scala2
    === [ "object/Legacy"
        , "object/Legacy/val/ord"
        , "object/Legacy/class/RichInt"
        , "object/Legacy/class/RichInt/def/twice"
        , "object/Legacy/def/toRich"
        , "object/Legacy/def/run"
        , "object/Legacy/def/page"
        , "object/Legacy/type/Some2"
        , "object/Legacy/var/count"
        , "object/Legacy/def/old"
        , "class/Allman"
        , "class/Allman/def/this"
        , "trait/Ordered2"
        , "trait/Ordered2/def/compare"
        ]
  Extraction scala3 _ <- extractAt "src/main/scala/p/P.scala" (T.unlines scala3Fixture)
  idsOf "src/main/scala/p/P.scala" scala3
    === [ "enum/Color"
        , "enum/Color/case/Red"
        , "enum/Color/case/Green"
        , "enum/Color/def/hex"
        , "type/Meters"
        , "extension/Meters"
        , "extension/Meters/def/+"
        , "extension/Meters/def/value"
        , "object/Exports"
        , "trait/Shape"
        , "trait/Shape/def/area"
        , "def/hello"
        , "given/intOrd"
        , "given/intOrd/def/compare"
        , "given/Ordering[List[T]]"
        , "given/Ordering[List[T]]/def/compare"
        , "given/listOrd"
        , "given/Ordering[String]"
        , "given/Ordering[String]/def/compare"
        , "given/Ordering[Set[T]]"
        , "val/r"
        , "val/s"
        , "def/f"
        , "case_class/Point"
        , "case_class/Point/def/norm"
        ]

scala2Fixture :: [Text]
scala2Fixture =
  [ "package legacy"
  , ""
  , "import scala.collection.mutable._"
  , "import java.util.{List => JList, _}"
  , ""
  , "object Legacy extends App with Serializable {"
  , "  implicit val ord: Ordering[Int] = Ordering.Int"
  , "  implicit class RichInt(val x: Int) extends AnyVal { def twice = x * 2 }"
  , "  implicit def toRich(x: Int): RichInt = new RichInt(x)"
  , "  def run() { println('sym) }"
  , "  def page = <div class=\"a\">{ items.map(i => <li>{i}</li>) }</div>"
  , "  type Some2 = List[T] forSome { type T }"
  , "  private[this] var count = 0"
  , "  @deprecated(\"use other\", \"1.0\") protected def old(x: Int): Int = x"
  , "}"
  , ""
  , "class Allman(a: Int)"
  , "{"
  , "  def this() = this(0)"
  , "}"
  , ""
  , "trait Ordered2[A] { self: Comparable[A] =>"
  , "  def compare(that: A): Int"
  , "}"
  ]

scala3Fixture :: [Text]
scala3Fixture =
  [ "package p:"
  , "  enum Color(val rgb: Int) derives CanEqual:"
  , "    case Red extends Color(0xFF0000)"
  , "    case Green, Blue"
  , "    def hex: String = rgb.toHexString"
  , "  end Color"
  , ""
  , "  opaque type Meters = Double"
  , ""
  , "  extension (m: Meters)"
  , "    def +(o: Meters): Meters = m + o"
  , "    def value: Double = m"
  , "  end extension"
  , ""
  , "  object Exports:"
  , "    export scala.math.{max, min}"
  , ""
  , "  trait Shape:"
  , "    def area: Double"
  , ""
  , "  @main def hello(): Unit ="
  , "    if true then"
  , "      println(1) else println(2)"
  , ""
  , "  given intOrd: Ordering[Int] with"
  , "    def compare(a: Int, b: Int) = a - b"
  , ""
  , "  given [T](using Ordering[T]): Ordering[List[T]] with"
  , "    def compare(a: List[T], b: List[T]) = 0"
  , ""
  , "  given listOrd[T: Ordering]: Ordering[Vector[T]] = ???"
  , ""
  , "  given Ordering[String]:"
  , "    def compare(a: String, b: String) = 0"
  , ""
  , "  given [T: Ordering] => Ordering[Set[T]] = ???"
  , ""
  , "  val r = List(1).map: x =>"
  , "    x + 1"
  , "  val s = List(1).foldLeft(0): (a, b) =>"
  , "    a + b"
  , "  def f = List(1).map { x =>"
  , "    x + 1"
  , "  }"
  , "  case class Point(x: Int, y: Int):"
  , "    def norm = x * x + y * y"
  , "end p"
  ]

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
dialectProfile = Profile [".scala"] (SplitGrammarFiles "grammars/scala/canonically_commented/ScalaLexer.g4" "grammars/scala/canonically_commented/ScalaParser.g4") (Name "compilationUnit") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

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
-- statement or a local definition binds to nothing and is reported; what is private needs none, an
-- enum's cases need one when the enum does, and a comment nested in a Scaladoc comment is part of
-- it, as Scala comments nest. ref:REQ-scala-support ref:DEC-scala-dialect
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
  Extraction nested nestedFindings <- extractDialect "Nested.scala" (T.unlines ["/** Paths such as subdir/* and */*.csv, and /* a comment */, nest. */", "def f = 1"])
  length (modelDecisions nested) === 1
  [() | OrphanDocComment _ _ <- nestedFindings] === []
