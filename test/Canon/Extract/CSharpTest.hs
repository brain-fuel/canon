-- | C# is read through the grammars-v4 C# grammar, as changed for canon, and the profile the C#
-- sample ships, so these properties check both against what a C# author means by a member and its
-- XML documentation. ref:DEC-csharp-grammar ref:REQ-csharp-support
module Canon.Extract.CSharpTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, renderInterpretError)
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
    "csharp"
    [ testProperty "the C# grammar parses the GuardClauses sample into its members" prop_csharpGrammarParsesTheGuardClausesSampleIntoItsMembers
    , testProperty "the C# lexer reads interpolated, verbatim, and raw strings and one branch of each conditional" prop_csharpLexerReadsInterpolatedVerbatimAndRawStringsAndOneBranchOfEachConditional
    , testProperty "the C# profile binds XML docs above attributes, requires them on public members, and recognises tests" prop_csharpProfileBindsXmlDocsRequiresThemOnPublicMembersAndRecognisesTests
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/csharp-guardclauses"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/csharp/CSharpLexer.g4" "grammars/csharp/CSharpParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a C# project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "csharp" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | Real C# must parse whole, with every member a file declares found where the compiler finds it,
-- or a C# project's check would report parse failures instead of findings.
-- ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_csharpGrammarParsesTheGuardClausesSampleIntoItsMembers :: Property
prop_csharpGrammarParsesTheGuardClausesSampleIntoItsMembers = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let parse file = do
        result <- evalIO (interpretFile interpreter (Name "compilation_unit") (sampleDir </> "source" </> file))
        either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure result
  extensions <- parse "src/GuardClauses/GuardAgainstNullExtensions.cs"
  length (treeRuleNodes (Name "file_scoped_namespace_declaration") extensions) === 1
  length (treeRuleNodes (Name "class_definition") extensions) === 1
  length (treeRuleNodes (Name "method_declaration") extensions) === 8
  unitTests <- parse "test/GuardClauses.UnitTests/GuardAgainstNullOrEmpty.cs"
  length (treeRuleNodes (Name "method_declaration") unitTests) === 21
  exception <- parse "src/GuardClauses/Exceptions/NotFoundException.cs"
  length (treeRuleNodes (Name "constructor_declaration") exception) === 2

-- | The upstream lexer read interpolated strings and the preprocessor through a base class canon
-- has no port of; the hook and the grammar's replacements must keep each string one token or one
-- run of parts, and read one branch of each #if. ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_csharpLexerReadsInterpolatedVerbatimAndRawStringsAndOneBranchOfEachConditional :: Property
prop_csharpLexerReadsInterpolatedVerbatimAndRawStringsAndOneBranchOfEachConditional = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "$\"a{b:N2}c\""
    === Right
      [ ("INTERPOLATED_REGULAR_STRING_START", "$\"")
      , ("REGULAR_STRING_INSIDE", "a")
      , ("IDENTIFIER", "b")
      , ("COLON", ":")
      , ("FORMAT_STRING", "N2")
      , ("REGULAR_STRING_INSIDE", "c")
      , ("DOUBLE_QUOTE_INSIDE", "\"")
      ]
  typesOf "$@\"x\"\"\\{f(a ? 1 : 2)}\""
    === Right
      [ ("INTERPOLATED_VERBATIUM_STRING_START", "$@\"")
      , ("VERBATIUM_INSIDE_STRING", "x")
      , ("VERBATIUM_DOUBLE_QUOTE_INSIDE", "\"\"")
      , ("VERBATIUM_INSIDE_STRING", "\\")
      , ("IDENTIFIER", "f")
      , ("OPEN_PARENS", "(")
      , ("IDENTIFIER", "a")
      , ("INTERR", "?")
      , ("INTEGER_LITERAL", "1")
      , ("COLON", ":")
      , ("INTEGER_LITERAL", "2")
      , ("CLOSE_PARENS", ")")
      , ("DOUBLE_QUOTE_INSIDE", "\"")
      ]
  typesOf "\"\"\"a \"quoted\" b\"\"\"" === Right [("RAW_STRING", "\"\"\"a \"quoted\" b\"\"\"")]
  typesOf "\"\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\"" === Right [("REGULAR_STRING", "\"\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\\x00a0\"")]
  let conditional = T.unlines ["#if NET6_0 && !NET6_0", "int a;", "#elif DEBUG", "int b;", "#else", "int c;", "#endif", "#if false", "int d;", "#endif"]
  typesOf conditional === Right [("INT", "int"), ("IDENTIFIER", "b"), ("SEMICOLON", ";")]
  case interpretText interpreter (Name "compilation_unit") "f.cs" "class C { string S => x switch { > 1 and < 5 => $\"{x}\", { Length: 0 } => \"\", _ => s with { A = 1 } }; }" of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> length (treeRuleNodes (Name "switch_expression_arm") tree) === 3

fixture :: Text
fixture =
  T.unlines
    [ "// Licensed under the MIT license. license:MIT"
    , "namespace Shapes;"
    , ""
    , "using System;"
    , ""
    , "/// <summary>A shape has an area.</summary>"
    , "[Serializable]"
    , "public abstract class Shape"
    , "{"
    , "    /// <summary>The area of the shape.</summary>"
    , "    public abstract double Area { get; }"
    , ""
    , "    public Shape() { }"
    , ""
    , "    private double cached;"
    , ""
    , "    /// <summary>Scales the shape.</summary>"
    , "#pragma warning disable CS0618"
    , "    public abstract Shape Scale(double factor);"
    , ""
    , "    //// <summary>Commented-out documentation.</summary>"
    , "    protected void Reset() { }"
    , ""
    , "    /// <summary>Orphaned by the blank line below.</summary>"
    , ""
    , "    internal void Helper() { }"
    , "}"
    , ""
    , "/// <summary>A point is a pair of coordinates.</summary>"
    , "// A plain note between a doc comment and its record."
    , "public record Point(double X, double Y);"
    , ""
    , "/// <summary>Colours are named.</summary>"
    , "public enum Colour"
    , "{"
    , "    /// <summary>The colour red.</summary>"
    , "    Red,"
    , "    Green,"
    , "}"
    , ""
    , "#if NEVER && !NEVER"
    , "/// <summary>A doc comment in a branch canon does not read.</summary>"
    , "public class Never { }"
    , "#endif"
    , ""
    , "public class ShapeTests"
    , "{"
    , "    /// <summary>Squares have the area of their side squared. ref:REQ-1</summary>"
    , "    [Fact]"
    , "    public void SquareAreaIsSideSquared() { }"
    , ""
    , "    [Theory, InlineData(1)]"
    , "    public void UncommentedTheory(int n) { }"
    , ""
    , "    [NUnit.Framework.TestCase(2)]"
    , "    private void NUnitCase(int n) { }"
    , ""
    , "    [TestMethod]"
    , "    public void MsTestMethod() { }"
    , "}"
    ]

-- | In C# an XML doc comment sits above a member's attributes, a #pragma or a plain comment between
-- them does not part them, //// is no documentation, a member visible outside its assembly is the
-- API the documentation is for, and an xUnit, NUnit, or MSTest attribute makes a method a test, so
-- the profile must bind, require, and recognise each that way for the Why of a C# member to be its
-- documentation. ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_csharpProfileBindsXmlDocsRequiresThemOnPublicMembersAndRecognisesTests :: Property
prop_csharpProfileBindsXmlDocsRequiresThemOnPublicMembersAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "csharp" profile interpreter "Shapes.cs" "Shapes.cs" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("namespace", "Shapes")
        , ("class", "Shape")
        , ("property", "Area")
        , ("constructor", "Shape")
        , ("field", "cached")
        , ("method", "Scale")
        , ("method", "Reset")
        , ("method", "Helper")
        , ("record", "Point")
        , ("enum", "Colour")
        , ("member", "Red")
        , ("member", "Green")
        , ("class", "ShapeTests")
        , ("method", "SquareAreaIsSideSquared")
        , ("method", "UncommentedTheory")
        , ("method", "NUnitCase")
        , ("method", "MsTestMethod")
        ]
  whyOf "Shapes.cs" === ["Licensed under the MIT license. license:MIT"]
  whyOf "Shape" === ["<summary>A shape has an area.</summary>"]
  whyOf "Area" === ["<summary>The area of the shape.</summary>"]
  whyOf "Scale" === ["<summary>Scales the shape.</summary>"]
  whyOf "Reset" === []
  whyOf "Helper" === []
  whyOf "Point" === ["<summary>A point is a pair of coordinates.</summary>"]
  whyOf "Red" === ["<summary>The colour red.</summary>"]
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["SquareAreaIsSideSquared", "UncommentedTheory", "NUnitCase", "MsTestMethod", "Helper"] === [[True], [True], [True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "csharp/Shapes.cs/namespace/Shapes/class/Shape/constructor/Shape"
        , "csharp/Shapes.cs/namespace/Shapes/class/Shape/method/Reset"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/UncommentedTheory"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/NUnitCase"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/MsTestMethod"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []
