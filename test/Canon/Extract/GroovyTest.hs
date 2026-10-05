-- | Groovy is read through Apache Groovy's own ANTLR grammar, as changed for canon, and the profile the
-- Groovy sample ships, so these properties check both against what a Groovy author means by a
-- declaration and its Groovydoc. ref:DEC-groovy-grammar ref:REQ-groovy-support
module Canon.Extract.GroovyTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (ParseTree, treeRuleNodes)
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
import Data.List.NonEmpty (NonEmpty (..))
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
    "groovy"
    [ testProperty "the Groovy grammar parses the spock-genesis sample into its declarations" prop_theGroovyGrammarParsesTheSpockGenesisSampleIntoItsDeclarations
    , testProperty "the Groovy lexer tells slashy strings from division and reads GStrings" prop_theGroovyLexerTellsSlashyStringsFromDivisionAndReadsGStrings
    , testProperty "the Groovy parser answers the predicates of its base class" prop_theGroovyParserAnswersThePredicatesOfItsBaseClass
    , testProperty "the Groovy profile binds Groovydoc above annotations, requires it on public declarations, and recognises tests" prop_theGroovyProfileBindsGroovydocAboveAnnotationsRequiresItOnPublicDeclarationsAndRecognisesTests
    , testProperty "the Groovy dialect parses the spock-genesis sample with its Groovydoc" prop_theGroovyDialectParsesTheSpockGenesisSampleWithItsGroovydoc
    , testProperty "the Groovy dialect binds Groovydoc to declarations and reports misplaced ones" prop_theGroovyDialectBindsGroovydocToDeclarationsAndReportsMisplacedOnes
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/groovy-spock-genesis"

-- | The sample's Groovy files, below its source directory.
sampleFiles :: [FilePath]
sampleFiles =
  [ "src/main/groovy/spock/genesis/Gen.groovy"
  , "src/main/groovy/spock/genesis/generators/Generator.groovy"
  , "src/main/groovy/spock/genesis/generators/LimitedGenerator.groovy"
  , "src/main/groovy/spock/genesis/generators/Permutable.groovy"
  , "src/main/groovy/spock/genesis/generators/values/StringGenerator.groovy"
  , "src/main/groovy/spock/genesis/transform/Iterations.groovy"
  , "src/test/groovy/spock/genesis/generators/LimitedGeneratorSpec.groovy"
  , "src/test/groovy/spock/genesis/generators/values/StringGeneratorSpec.groovy"
  ]

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/groovy/GroovyLexer.g4" "grammars/groovy/GroovyParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Groovy project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "groovy" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The number of nodes of each declaration rule in a tree.
declarationCounts :: ParseTree -> [Int]
declarationCounts tree =
  [ length (treeRuleNodes (Name rule) tree)
  | rule <- ["normalClassDeclaration", "interfaceDeclaration", "annotationTypeDeclaration", "constructorDeclaration", "methodDeclaration", "fieldDeclaration"]
  ]

-- | Real Groovy must parse whole, with every class, constructor, method, and field a file declares
-- found where the compiler finds it, Spock feature methods named by strings and the methods of
-- anonymous classes included, or a Groovy project's check would report parse failures instead of
-- findings. ref:REQ-groovy-support ref:DEC-groovy-grammar
prop_theGroovyGrammarParsesTheSpockGenesisSampleIntoItsDeclarations :: Property
prop_theGroovyGrammarParsesTheSpockGenesisSampleIntoItsDeclarations = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  counts <-
    mapM
      ( \file -> do
          result <- evalIO (interpretFile interpreter (Name "compilationUnit") (sampleDir </> "source" </> file))
          either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) (pure . declarationCounts) result
      )
      sampleFiles
  counts
    === [ [1, 0, 0, 0, 33, 0]
        , [1, 0, 0, 0, 16, 1]
        , [1, 0, 0, 1, 4, 2]
        , [0, 1, 0, 0, 2, 0]
        , [1, 0, 0, 10, 4, 6]
        , [0, 0, 1, 0, 1, 0]
        , [1, 0, 0, 0, 4, 2]
        , [1, 0, 0, 0, 5, 0]
        ]

-- | Upstream's lexer decided with its base class whether a slash starts a slashy string, which
-- brackets make newlines insignificant, and whether !in is an operator, and looked ahead for the end
-- of a GString value; the hook and the grammar's replacements must lex each as Groovy does.
-- ref:REQ-groovy-support ref:DEC-groovy-grammar
prop_theGroovyLexerTellsSlashyStringsFromDivisionAndReadsGStrings :: Property
prop_theGroovyLexerTellsSlashyStringsFromDivisionAndReadsGStrings = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "a / b /* c */ / d"
    === Right [("Identifier", "a"), ("DIV", "/"), ("Identifier", "b"), ("DIV", "/"), ("Identifier", "d")]
  typesOf "f(/a\\/b$/, 1)"
    === Right [("Identifier", "f"), ("LPAREN", "("), ("StringLiteral", "/a\\/b$/"), ("COMMA", ","), ("IntegerLiteral", "1"), ("RPAREN", ")")]
  typesOf "\"x ${y} $p.q r\""
    === Right
      [ ("GStringBegin", "\"x $")
      , ("LBRACE", "{")
      , ("Identifier", "y")
      , ("RBRACE", "}")
      , ("GStringPart", " $")
      , ("Identifier", "p")
      , ("GStringPathPart", ".q")
      , ("GStringEnd", " r\"")
      ]
  typesOf "\"\"\"say \"hi\" \"\"twice\"\"\"" === Right [("StringLiteral", "\"\"\"say \"hi\" \"\"twice\"\"\"")]
  typesOf "~/\\d+$x/"
    === Right [("BITNOT", "~"), ("GStringBegin", "/\\d+$"), ("Identifier", "x"), ("GStringEnd", "/")]
  typesOf "(a\n, b)\n" === Right [("LPAREN", "("), ("Identifier", "a"), ("COMMA", ","), ("Identifier", "b"), ("RPAREN", ")"), ("NL", "\n")]
  typesOf "a !in b && !internal"
    === Right [("Identifier", "a"), ("NOT_IN", "!in"), ("Identifier", "b"), ("AND", "&&"), ("NOT", "!"), ("Identifier", "internal")]

-- | GroovyParser asks its base class whether a line at the top of a script declares a method or calls
-- one, whether a b declares b or calls a, and whether a command may take arguments after a call, and
-- canon asks whether a member without a return type is a constructor; reading any of them the other
-- way finds units that are not there. ref:REQ-groovy-support ref:DEC-groovy-grammar
prop_theGroovyParserAnswersThePredicatesOfItsBaseClass :: Property
prop_theGroovyParserAnswersThePredicatesOfItsBaseClass = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let parse source = case interpretText interpreter (Name "compilationUnit") "f.groovy" source of
        Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
        Right tree -> pure tree
      count rule tree = length (treeRuleNodes (Name rule) tree)
  script <- parse (T.unlines ["foo(1) { it }", "def bar(x) { println x }", "println bar(2)", "String s = 'a'", "assert s"])
  map (`count` script) ["methodDeclaration", "localVariableDeclaration", "commandExpression"] === [1, 1, 5]
  members <- parse (T.unlines ["class Point {", "  Point(int x) { }", "  static origin() { new Point(0) }", "  private Point() { }", "}"])
  map (`count` members) ["constructorDeclaration", "methodDeclaration"] === [2, 1]

fixture :: Text
fixture =
  T.unlines
    [ "// Licensed under the MIT license. license:MIT"
    , "package shapes"
    , ""
    , "import spock.lang.Specification"
    , ""
    , "/** A shape has an area. */"
    , "@groovy.transform.CompileStatic"
    , "abstract class Shape {"
    , "    /** The name of the shape. */"
    , "    String name"
    , ""
    , "    private double cached"
    , ""
    , "    Shape() { }"
    , ""
    , "    /**"
    , "     * Scales the shape."
    , "     */"
    , "    @Deprecated"
    , "    abstract Shape scale(double factor)"
    , ""
    , "    protected void reset() { }"
    , ""
    , "    /** Orphaned by the blank line below. */"
    , ""
    , "    private void helper() { }"
    , "}"
    , ""
    , "/** Colours are named. */"
    , "enum Colour {"
    , "    /** The colour red. */"
    , "    RED,"
    , "    GREEN"
    , "}"
    , ""
    , "/** Things that greet. */"
    , "trait Greets {"
    , "    String greet() { \"Hello, ${name}!\" }"
    , "}"
    , ""
    , "class ShapeSpec extends Specification {"
    , "    /** Squares have the area of their side squared. ref:REQ-1 */"
    , "    def 'a square has the area of its side squared'() {"
    , "        expect:"
    , "        2 * 2 == 4"
    , "    }"
    , ""
    , "    @org.junit.Test"
    , "    void uncommentedJUnitTest() { }"
    , ""
    , "    private helperMethod() { }"
    , "}"
    ]

-- | Groovydoc sits above a declaration's annotations, a declaration is public unless it is private,
-- so what is not private is the API the documentation is for, and a JUnit annotation or a Spock
-- feature method named by a string makes a method a test, so the profile must bind, require, and
-- recognise each that way for the Why of a Groovy declaration to be its Groovydoc.
-- ref:REQ-groovy-support ref:DEC-groovy-grammar
prop_theGroovyProfileBindsGroovydocAboveAnnotationsRequiresItOnPublicDeclarationsAndRecognisesTests :: Property
prop_theGroovyProfileBindsGroovydocAboveAnnotationsRequiresItOnPublicDeclarationsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let path = "src/test/groovy/ShapeSpec.groovy"
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "groovy" profile interpreter path path fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("class", "Shape")
        , ("field", "name")
        , ("field", "cached")
        , ("constructor", "Shape")
        , ("method", "scale")
        , ("method", "reset")
        , ("method", "helper")
        , ("enum", "Colour")
        , ("constant", "RED")
        , ("constant", "GREEN")
        , ("trait", "Greets")
        , ("method", "greet")
        , ("class", "ShapeSpec")
        , ("method", "'a square has the area of its side squared'")
        , ("method", "uncommentedJUnitTest")
        , ("method", "helperMethod")
        ]
  whyOf (T.pack path) === ["Licensed under the MIT license. license:MIT"]
  whyOf "Shape" === ["A shape has an area."]
  whyOf "name" === ["The name of the shape."]
  whyOf "scale" === ["Scales the shape."]
  whyOf "helper" === []
  whyOf "RED" === ["The colour red."]
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["'a square has the area of its side squared'", "uncommentedJUnitTest", "helperMethod", "greet"] === [[True], [True], [False], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "groovy/src/test/groovy/ShapeSpec.groovy/class/Shape/constructor/Shape"
        , "groovy/src/test/groovy/ShapeSpec.groovy/class/Shape/method/reset"
        , "groovy/src/test/groovy/ShapeSpec.groovy/enum/Colour/constant/GREEN"
        , "groovy/src/test/groovy/ShapeSpec.groovy/trait/Greets/method/greet"
        , "groovy/src/test/groovy/ShapeSpec.groovy/class/ShapeSpec"
        , "groovy/src/test/groovy/ShapeSpec.groovy/class/ShapeSpec/method/uncommentedJUnitTest"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []

-- | The canonically commented dialect of the Groovy grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".groovy"] (SplitGrammarFiles "grammars/groovy/canonically_commented/GroovyLexer.g4" "grammars/groovy/canonically_commented/GroovyParser.g4") (Name "compilationUnit") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | An extraction through the Groovy dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "groovy" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Groovydoc comments are tokens of the dialect, so real Groovy must still parse whole with them
-- above classes, methods, and annotated members, and each must bind to the declaration below it.
-- ref:REQ-groovy-support ref:DEC-groovy-dialect
prop_theGroovyDialectParsesTheSpockGenesisSampleWithItsGroovydoc :: Property
prop_theGroovyDialectParsesTheSpockGenesisSampleWithItsGroovydoc = withTests 1 $ property $ do
  counts <-
    mapM
      ( \file -> do
          source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
          Extraction model findings <- extractDialect file source
          pure (length (modelDecisions model), length [() | OrphanDocComment _ _ <- findings])
      )
      sampleFiles
  counts === [(34, 0), (5, 0), (0, 0), (0, 0), (1, 0), (2, 0), (0, 0), (0, 0)]

-- | In the dialect the grammar says where Groovydoc binds: above a declaration and its annotations,
-- while one after an annotation, before a statement, or after the last member binds to nothing and
-- is reported; a declaration that is not private requires one, an interface's methods included.
-- ref:REQ-groovy-support ref:DEC-groovy-dialect
prop_theGroovyDialectBindsGroovydocToDeclarationsAndReportsMisplacedOnes :: Property
prop_theGroovyDialectBindsGroovydocToDeclarationsAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "Shapes.groovy"
      ( T.unlines
          [ "package shapes"
          , ""
          , "/** A shape has an area. ref:some-key */"
          , "@groovy.transform.CompileStatic"
          , "interface Shape {"
          , "    /** The area. */"
          , "    double area()"
          , "    void draw()"
          , "}"
          , ""
          , "class Square implements Shape {"
          , "    @Override"
          , "    /** After an annotation, so an orphan. */"
          , "    double area() { 1 }"
          , ""
          , "    /** Draws the square. */"
          , "    void draw() {"
          , "        /** Before a statement, so an orphan. */"
          , "        def x = /a\\/b/"
          , "        println \"$x\""
          , "    }"
          , ""
          , "    private void inside() { }"
          , ""
          , "    /** After the last member, so an orphan. */"
          , "}"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- decisionUnits' d]
      decisionUnits' d = case decisionUnits d of u :| more -> u : more
  whys
    === [ ("groovy/Shapes.groovy/interface/Shape", "A shape has an area. ref:some-key")
        , ("groovy/Shapes.groovy/interface/Shape/method/area", "The area.")
        , ("groovy/Shapes.groovy/class/Square/method/draw", "Draws the square.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "groovy/Shapes.groovy/interface/Shape/method/draw"
        , "groovy/Shapes.groovy/class/Square"
        , "groovy/Shapes.groovy/class/Square/method/area"
        ]
