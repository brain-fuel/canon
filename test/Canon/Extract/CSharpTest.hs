-- | C# is read through the grammars-v4 C# grammar, as changed for canon, and the profile the C#
-- sample ships, so these properties check both against what a C# author means by a member and its
-- XML documentation. ref:DEC-csharp-grammar ref:REQ-csharp-support
module Canon.Extract.CSharpTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (treeRuleNodes, treeTokens)
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
import Canon.Span (Position (..), Span (..))
import Data.List (sort)
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
    "csharp"
    [ testProperty "the C# grammar parses the GuardClauses sample into its members" prop_csharpGrammarParsesTheGuardClausesSampleIntoItsMembers
    , testProperty "the C# lexer reads interpolated, verbatim, and raw strings and one branch of each conditional" prop_csharpLexerReadsInterpolatedVerbatimAndRawStringsAndOneBranchOfEachConditional
    , testProperty "the C# profile binds XML docs above attributes, requires them on public members, and recognises tests" prop_csharpProfileBindsXmlDocsRequiresThemOnPublicMembersAndRecognisesTests
    , testProperty "the C# parser answers the predicates of its base class" prop_theCSharpParserAnswersThePredicatesOfItsBaseClass
    , testProperty "the holes of an interpolated raw string are parsed" prop_theHolesOfAnInterpolatedRawStringAreParsed
    , testProperty "an interface member needs a comment as the interface does unless it is private or internal" prop_anInterfaceMemberNeedsACommentAsTheInterfaceDoesUnlessItIsPrivateOrInternal
    , testProperty "every branch of an #if that some build compiles is read" prop_everyBranchOfAnIfThatSomeBuildCompilesIsRead
    , testProperty "a long collection initializer parses in memory linear in its length" prop_aLongCollectionInitializerParsesInMemoryLinearInItsLength
    , testProperty "the C# dialect parses the GuardClauses sample with its XML docs" prop_theCSharpDialectParsesTheGuardClausesSampleWithItsXmlDocs
    , testProperty "the C# dialect binds XML docs to members and reports misplaced ones" prop_theCSharpDialectBindsXmlDocsToMembersAndReportsMisplacedOnes
    , testProperty "a C# doc comment anywhere in a file parses and one that documents nothing is an orphan" prop_aCSharpDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan
    , testProperty "the C# grammar reads the operators and modifiers .NET's own sources use" prop_theCSharpGrammarReadsTheOperatorsAndModifiersDotNetsOwnSourcesUse
    , testProperty "a C# union is a type of its own, documented as a class is" prop_aCSharpUnionIsATypeOfItsOwnDocumentedAsAClassIs
    , testProperty "a C# /// doc comment ends at one token, inside a branch read or not" prop_aCSharpDocCommentEndsAtOneTokenInsideABranchReadOrNot
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
        , "csharp/Shapes.cs/namespace/Shapes/enum/Colour/member/Green"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/UncommentedTheory"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/NUnitCase"
        , "csharp/Shapes.cs/namespace/Shapes/class/ShapeTests/method/MsTestMethod"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []

-- | A C# fixture extracted through the sample's profile.
extractFixture :: Text -> PropertyT IO (Extraction)
extractFixture source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "csharp" profile interpreter "F.cs" "F.cs" source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | CSharpParserBase rejects what the compiler rejects: an arrow or a shift whose two tokens do not
-- touch, and a var declaration with more than one declarator; a parser that took them would read
-- code no build compiles. ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_theCSharpParserAnswersThePredicatesOfItsBaseClass :: Property
prop_theCSharpParserAnswersThePredicatesOfItsBaseClass = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let parses body = either (const False) (const True) (interpretText interpreter (Name "compilation_unit") "f.cs" ("class C { void M() { " <> body <> " } }"))
  map parses ["Func<int, int> f = x => x;", "int s = 8 >> 1; s >>= 2;", "int a = 1, b = 2;", "var k = 3;"] === [True, True, True, True]
  map parses ["Func<int, int> f = x = > x;", "int s = 8 > > 1;", "s > >= 2;", "var a = 1, b = 2;"] === [False, False, False, False]

-- | An interpolated raw string's holes are expressions, and a lambda or a call in one is code like any
-- other; a parser that took the whole string as one token read none of it. ref:REQ-csharp-support
-- ref:DEC-csharp-grammar
prop_theHolesOfAnInterpolatedRawStringAreParsed :: Property
prop_theHolesOfAnInterpolatedRawStringAreParsed = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "$\"\"\"a \"q\" {x:N2}\"\"\""
    === Right
      [ ("INTERPOLATED_RAW_STRING_START", "$\"\"\"")
      , ("RAW_STRING_CONTENT", "a ")
      , ("RAW_STRING_CONTENT", "\"")
      , ("RAW_STRING_CONTENT", "q")
      , ("RAW_STRING_CONTENT", "\"")
      , ("RAW_STRING_CONTENT", " ")
      , ("IDENTIFIER", "x")
      , ("COLON", ":")
      , ("FORMAT_STRING", "N2")
      , ("RAW_STRING_END", "\"\"\"")
      ]
  typesOf "$$\"\"\"{ \"n\": {{n + 1}} }\"\"\""
    === Right
      [ ("INTERPOLATED_RAW_STRING_START", "$$\"\"\"")
      , ("RAW_STRING_CONTENT", "{")
      , ("RAW_STRING_CONTENT", " ")
      , ("RAW_STRING_CONTENT", "\"")
      , ("RAW_STRING_CONTENT", "n")
      , ("RAW_STRING_CONTENT", "\"")
      , ("RAW_STRING_CONTENT", ": ")
      , ("IDENTIFIER", "n")
      , ("PLUS", "+")
      , ("INTEGER_LITERAL", "1")
      , ("RAW_STRING_CONTENT", " ")
      , ("RAW_STRING_CONTENT", "}")
      , ("RAW_STRING_END", "\"\"\"")
      ]
  case interpretText interpreter (Name "compilation_unit") "f.cs" "class C { string S => $\"\"\"{(a ? $\"{b}\" : Run(x => x))}\"\"\"; }" of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "interpolated_raw_string") tree) === 1
      length (treeRuleNodes (Name "lambda_expression") tree) === 1

-- | The members of an interface are public unless they say otherwise, and CS1591 asks for their
-- documentation when the interface is visible outside its assembly; private protected is not
-- visible there and protected internal is. ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_anInterfaceMemberNeedsACommentAsTheInterfaceDoesUnlessItIsPrivateOrInternal :: Property
prop_anInterfaceMemberNeedsACommentAsTheInterfaceDoesUnlessItIsPrivateOrInternal = withTests 1 $ property $ do
  Extraction model _ <-
    extractFixture
      ( T.unlines
          [ "public interface IShape"
          , "{"
          , "    double Area { get; }"
          , "    void Draw();"
          , "    private void Helper() { }"
          , "    internal void Inside() { }"
          , "    protected void ForImplementers() { }"
          , "}"
          , "internal interface IHidden"
          , "{"
          , "    void Hidden();"
          , "}"
          , "public class Base"
          , "{"
          , "    private protected void AssemblyOnly() { }"
          , "    protected private void AlsoAssemblyOnly() { }"
          , "    protected internal void Everywhere() { }"
          , "    internal protected void AlsoEverywhere() { }"
          , "    void Private() { }"
          , "}"
          ]
      )
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitRequirement u == Required]
    === [ "csharp/F.cs/interface/IShape"
        , "csharp/F.cs/interface/IShape/property/Area"
        , "csharp/F.cs/interface/IShape/method/Draw"
        , "csharp/F.cs/interface/IShape/method/ForImplementers"
        , "csharp/F.cs/class/Base"
        , "csharp/F.cs/class/Base/method/Everywhere"
        , "csharp/F.cs/class/Base/method/AlsoEverywhere"
        ]

-- | A build compiles one branch of each #if, and different builds compile different branches, so the
-- documentation of every branch some build compiles must be read and bound; a branch no build
-- compiles is not read, and its comment is no orphan. ref:REQ-csharp-support
-- ref:DEC-preprocessor-builds
prop_everyBranchOfAnIfThatSomeBuildCompilesIsRead :: Property
prop_everyBranchOfAnIfThatSomeBuildCompilesIsRead = withTests 1 $ property $ do
  Extraction model findings <-
    extractFixture
      ( T.unlines
          [ "public static class Spans"
          , "{"
          , "#if NET6_0_OR_GREATER"
          , "    /// <summary>Reads a span where the runtime has them.</summary>"
          , "    public static void Read(ReadOnlySpan<char> s) { }"
          , "#elif NETSTANDARD2_0"
          , "    /// <summary>Reads a string on .NET Standard.</summary>"
          , "    public static void ReadString(string s) { }"
          , "#else"
          , "    public static void Fallback() { }"
          , "#endif"
          , "#if DEBUG"
          , "    /// <summary>Checks in debug builds.</summary>"
          , "    public static void Check() { }"
          , "#endif"
          , "#if false"
          , "    /// <summary>Never compiled.</summary>"
          , "    public static void Never() { }"
          , "#endif"
          , "}"
          ]
      )
  let units = modelAllUnits model
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, whatName (answerValue (unitWhat u)) == n, d <- decisionsFor (unitId u) model]
  [whatName (answerValue (unitWhat u)) | u <- units, unitKindText (whatKind (answerValue (unitWhat u))) == "method"] === ["Read", "ReadString", "Fallback", "Check"]
  whyOf "Read" === ["<summary>Reads a span where the runtime has them.</summary>"]
  whyOf "ReadString" === ["<summary>Reads a string on .NET Standard.</summary>"]
  whyOf "Check" === ["<summary>Checks in debug builds.</summary>"]
  [() | OrphanDocComment _ _ <- findings] === []
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["csharp/F.cs/class/Spans", "csharp/F.cs/class/Spans/method/Fallback"]

-- | A generated file can hold a collection initializer of thousands of lines, and the parser built a
-- result for every pair of an item and a later end of the list, which took 10 GB on 13,000 lines; it
-- must parse such a list whole. ref:REQ-csharp-support ref:DEC-parser-memory
prop_aLongCollectionInitializerParsesInMemoryLinearInItsLength :: Property
prop_aLongCollectionInitializerParsesInMemoryLinearInItsLength = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let items = [T.concat ["    { \"key", T.pack (show i), "\", new int[] { ", T.pack (show i), ", 2 } },"] | i <- [1 .. 1500 :: Int]]
      source = T.unlines (["static class Data {", "  static readonly Dictionary<string, int[]> Table = new Dictionary<string, int[]> {"] ++ items ++ ["  };", "}"])
  case interpretText interpreter (Name "compilation_unit") "data.cs" source of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> length [t | t <- treeTokens tree, "\"key" `T.isPrefixOf` tokenText t] === 1500

-- | The canonically commented dialect of the C# grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".cs"] (SplitGrammarFiles "grammars/csharp/canonically_commented/CSharpLexer.g4" "grammars/csharp/canonically_commented/CSharpParser.g4") (Name "compilation_unit") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | An extraction through the C# dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "csharp" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | XML doc comments are tokens of the dialect, so real C# must still parse whole with them above
-- members, inside #if branches, and among the tests. ref:REQ-csharp-support ref:DEC-csharp-dialect
prop_theCSharpDialectParsesTheGuardClausesSampleWithItsXmlDocs :: Property
prop_theCSharpDialectParsesTheGuardClausesSampleWithItsXmlDocs = withTests 1 $ property $ do
  let files =
        [ "src/GuardClauses/GuardAgainstNullExtensions.cs"
        , "src/GuardClauses/GuardAgainstEmptyOrWhiteSpaceExtensions.cs"
        , "src/GuardClauses/GuardAgainstOutOfRangeExtensions.cs"
        , "src/GuardClauses/CompilerFixes/CallerArgumentExpressionAttribute.cs"
        , "test/GuardClauses.UnitTests/GuardAgainstNullOrEmpty.cs"
        ]
  counts <-
    mapM
      ( \file -> do
          source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
          Extraction model _ <- extractDialect file source
          pure (length (modelDecisions model))
      )
      files
  all (> 0) (take 4 counts) === True

-- | In the dialect the grammar says where an XML doc comment binds: above a type or member and its
-- attributes, while one after an attribute, before a statement, or after the last member binds to
-- nothing and is reported; a public or protected member requires one, and an interface member as
-- its interface does. ref:REQ-csharp-support ref:DEC-csharp-dialect
prop_theCSharpDialectBindsXmlDocsToMembersAndReportsMisplacedOnes :: Property
prop_theCSharpDialectBindsXmlDocsToMembersAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "Shapes.cs"
      ( T.unlines
          [ "using System;"
          , "namespace Shapes;"
          , ""
          , "/// <summary>A shape has an area. ref:some-key</summary>"
          , "[Serializable]"
          , "public interface IShape"
          , "{"
          , "    /// <summary>The area.</summary>"
          , "    double Area { get; }"
          , "    void Draw();"
          , "    private void Helper() { }"
          , "}"
          , ""
          , "public class Square : IShape"
          , "{"
          , "    [Obsolete]"
          , "    /// <summary>After an attribute, so an orphan.</summary>"
          , "    public double Area => 1;"
          , ""
          , "    /** <summary>Draws the square.</summary> */"
          , "    public void Draw()"
          , "    {"
          , "        /// <summary>Before a statement, so an orphan.</summary>"
          , "        var x = $\"\"\"{Area}\"\"\";"
          , "    }"
          , ""
          , "    //// <summary>Commented-out documentation.</summary>"
          , "    internal void Inside() { }"
          , ""
          , "    /// <summary>After the last member, so an orphan.</summary>"
          , "}"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- decisionUnits' d]
      decisionUnits' d = case decisionUnits d of u :| more -> u : more
  whys
    === [ ("csharp/Shapes.cs/namespace/Shapes/interface/IShape", "<summary>A shape has an area. ref:some-key</summary>")
        , ("csharp/Shapes.cs/namespace/Shapes/interface/IShape/property/Area", "<summary>The area.</summary>")
        , ("csharp/Shapes.cs/namespace/Shapes/class/Square/method/Draw", "<summary>Draws the square.</summary>")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "csharp/Shapes.cs/namespace/Shapes/interface/IShape/method/Draw"
        , "csharp/Shapes.cs/namespace/Shapes/class/Square"
        , "csharp/Shapes.cs/namespace/Shapes/class/Square/property/Area"
        ]

-- | The C# compiler warns of a doc comment on no valid element and compiles the file, so canon must
-- read a file with one inside an expression, among the arguments of a call, in a switch, after an
-- attribute, or at the end of a block, keep the Whys of its members, and report each such comment
-- as an orphan. ref:REQ-csharp-support ref:DEC-csharp-dialect ref:DEC-stray-comments
prop_aCSharpDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan :: Property
prop_aCSharpDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "Odd.cs"
      ( T.unlines
          [ "/// <summary>A class.</summary>"
          , "public class C"
          , "{"
          , "    [Obsolete]"
          , "    /// <summary>After an attribute.</summary>"
          , "    public int M(int a)"
          , "    {"
          , "        var x = a"
          , "            /// <summary>Inside an expression.</summary>"
          , "            + 1;"
          , "        var y = Math.Max(x"
          , "            /// <summary>After the last argument.</summary>"
          , "            );"
          , "        var z = y switch"
          , "        {"
          , "            1 => 2,"
          , "            /// <summary>Before an arm.</summary>"
          , "            _ => 3"
          , "        };"
          , "        switch (z)"
          , "        {"
          , "            case 1:"
          , "                /// <summary>In a switch section.</summary>"
          , "                return x"
          , "                    /// <summary>Before a member access.</summary>"
          , "                    .GetHashCode();"
          , "        }"
          , "        return z;"
          , "        /// <summary>At the end of a block.</summary>"
          , "    }"
          , "}"
          ]
      )
  [renderUnitId u | d <- modelDecisions model, u <- decisionUnitList d]
    === ["csharp/Odd.cs/class/C"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [5, 9, 12, 17, 23, 25, 29]
  where
    decisionUnitList d = case decisionUnits d of u :| more -> u : more

-- | The corpus of .NET's runtime, ASP.NET Core, Roslyn, Newtonsoft.Json, and Avalonia uses syntax
-- that the grammar rejected: the unsigned right shift and its assignment and operator (C# 11), a
-- constant pattern with a bitwise operator, the safe modifier of C# 15, partial after ref, a
-- modifier on an implicitly typed lambda parameter (C# 14) and on the parameter of a conversion
-- operator, a scoped ref local, a conditional of ref branches, and a pointer to a pointer in a
-- fixed statement. Each must parse in the grammar and in its dialect, and the shift must still
-- need its greater-than signs to touch. ref:REQ-csharp-support ref:DEC-csharp-grammar
prop_theCSharpGrammarReadsTheOperatorsAndModifiersDotNetsOwnSourcesUse :: Property
prop_theCSharpGrammarReadsTheOperatorsAndModifiersDotNetsOwnSourcesUse = withTests 1 $ property $ do
  plain <- interpreterOrFail
  loaded <- evalIO (loadInterpreter "grammars/csharp/canonically_commented/CSharpLexer.g4" "grammars/csharp/canonically_commented/CSharpParser.g4")
  dialect <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "public unsafe ref partial struct B"
          , "{"
          , "    public safe object? Value;"
          , "    public static B operator >>>(B b, int n) => b;"
          , "    public static implicit operator int(in B b) => 0;"
          , "    int F(int x, char c)"
          , "    {"
          , "        x >>>= 2;"
          , "        var y = x >>> 3;"
          , "        Run((_, out p) => true, (ref int q) => q);"
          , "        switch (c) { case 'n' ^ 't': return 1; case A | B: return 2; }"
          , "        var k = (e, x) switch { (E.A or E.B | E.C, _) => 1, (E.D, < 3) => 2, _ => 0 };"
          , "        scoped ref int m = ref (h ? ref a : ref b);"
          , "        fixed (H** p = &q) { }"
          , "        return y >> 1;"
          , "    }"
          , "}"
          ]
      parses interpreter text = either (Left . renderInterpretError) (const (Right ())) (interpretText interpreter (Name "compilation_unit") "B.cs" text)
  parses plain source === Right ()
  parses dialect source === Right ()
  case interpretText plain (Name "compilation_unit") "B.cs" source of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> length (treeRuleNodes (Name "right_shift_unsigned") tree) === 1
  (parses plain "class S { int F(int x) => x > > > 1; }" == Right ()) === False

-- | A C# 15 union is declared by its case types, as ASP.NET Core's tests declare public union
-- Pet(Cat, Dog); it is a type, so the grammar must read it, and its doc comment must bind to it as to
-- a class, while union stays a name elsewhere. ref:REQ-csharp-support ref:DEC-csharp-grammar
-- ref:DEC-csharp-dialect
prop_aCSharpUnionIsATypeOfItsOwnDocumentedAsAClassIs :: Property
prop_aCSharpUnionIsATypeOfItsOwnDocumentedAsAClassIs = withTests 1 $ property $ do
  Extraction model _ <-
    extractDialect
      "Pets.cs"
      ( T.unlines
          [ "namespace Pets;"
          , "/// <summary>A pet.</summary>"
          , "public union Pet(Cat, Dog);"
          , "public union Maybe<T>(T, None) where T : class"
          , "{"
          , "    public bool HasValue => true;"
          , "}"
          , "class C { void F() { var union = 1; union++; } }"
          ]
      )
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- unitList d]
    === [("csharp/Pets.cs/namespace/Pets/union/Pet", "<summary>A pet.</summary>")]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["csharp/Pets.cs/namespace/Pets/union/Maybe", "csharp/Pets.cs/namespace/Pets/union/Maybe/property/HasValue"]
  where
    unitList d = case decisionUnits d of u :| more -> u : more

-- | The dialect's /// comment once ended at a hidden line break, so its rule could end after any
-- word, and canon's parser kept a tree for each end: the long /// blocks of the runtime's AdvSimd.cs
-- doubled its parse. The CSharpLexerBase hook ends each one with DOC_END, at its line break, before a
-- //// line, or at the end of the file, hidden with the comment in a branch the build does not read.
-- ref:REQ-csharp-support ref:DEC-csharp-dialect
prop_aCSharpDocCommentEndsAtOneTokenInsideABranchReadOrNot :: Property
prop_aCSharpDocCommentEndsAtOneTokenInsideABranchReadOrNot = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/csharp/canonically_commented/CSharpLexer.g4" "grammars/csharp/canonically_commented/CSharpParser.g4")
  dialect <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let ends source = either (Left . renderLexError) (Right . map tokenChannel . filter ((== Name "DOC_END") . tokenType)) (interpreterTokenize dialect source)
  ends "/// <summary>A.</summary>\n/// More.\nclass A {}\n" === Right [defaultChannelName]
  ends "/// One.\n//// Plain.\nclass A {}\n" === Right [defaultChannelName]
  ends "class A {}\n/// Last" === Right [defaultChannelName]
  case ends "#if false\n/// Hidden.\nclass A {}\n#endif\n" of
    Right [channel] -> annotate (show channel) >> (channel /= defaultChannelName) === True
    other -> annotate (show other) >> failure
  let long = T.concat (replicate 2000 "/// <summary>Adds the vectors, see ref:simd and the Arm manual.</summary>\n") <> "public class A {}\n"
  case interpretText dialect (Name "compilation_unit") "A.cs" long of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right _ -> pure ()
