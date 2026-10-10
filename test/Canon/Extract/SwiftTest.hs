-- | Swift is read through the Swift grammar written for canon from the grammar summary of The Swift
-- Programming Language and the Swift compiler's parser, whose lexer hook emits a NEWLINE where a
-- line break ends a statement and reads #if compilation conditions, and the profile the Swift
-- Argument Parser sample ships, so these properties check both against what the compiler and a
-- Swift author mean by a declaration and its doc comment. ref:DEC-swift-grammar ref:DEC-swift-dialect
-- ref:REQ-swift-support
module Canon.Extract.SwiftTest (tests) where

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
import Canon.Preprocessor (Condition (..), Directive (..), DirectiveSyntax (..), buildsIn, inactiveLinesIn, swiftDirectiveOf)
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Canon.Testing (isTestUnit)
import Control.Monad (forM, forM_)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
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
    "swift"
    [ testProperty "the Swift lexer hook ends statements where the compiler does" prop_theSwiftLexerHookEndsStatementsWhereTheCompilerDoes
    , testProperty "the Swift lexer reads strings, regex literals, and comments whole" prop_theSwiftLexerReadsStringsRegexLiteralsAndCommentsWhole
    , testProperty "the Swift lexer hook reads the branches of #if a build compiles" prop_theSwiftLexerHookReadsTheBranchesOfIfABuildCompiles
    , testProperty "the Swift grammar parses every file of the Argument Parser sample into its declarations" prop_theSwiftGrammarParsesEveryFileOfTheArgumentParserSampleIntoItsDeclarations
    , testProperty "the Swift profile reads Swift 6 constructs into their declarations" prop_theSwiftProfileReadsSwift6ConstructsIntoTheirDeclarations
    , testProperty "the Swift profile requires public API, hides private, and recognises tests" prop_theSwiftProfileRequiresPublicApiHidesPrivateAndRecognisesTests
    , testProperty "the Swift dialect parses the Argument Parser sample with its doc comments as the profile reads it" prop_theSwiftDialectParsesTheArgumentParserSampleWithItsDocCommentsAsTheProfileReadsIt
    , testProperty "the Swift dialect binds doc comments to declarations and reports misplaced comments" prop_theSwiftDialectBindsDocCommentsToDeclarationsAndReportsMisplacedComments
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/swift-argument-parser"

-- | The sample's files below source/, which the grammar must each parse whole.
sampleFiles :: [FilePath]
sampleFiles =
  [ "Sources/ArgumentParser/Parsable Properties/ArgumentHelp.swift"
  , "Sources/ArgumentParser/Parsable Properties/ArgumentVisibility.swift"
  , "Sources/ArgumentParser/Parsable Properties/Flag.swift"
  , "Sources/ArgumentParser/Parsable Properties/NameSpecification.swift"
  , "Sources/ArgumentParser/Parsable Types/EnumerableFlag.swift"
  , "Sources/ArgumentParser/Parsable Types/ExpressibleByArgument.swift"
  , "Sources/ArgumentParser/Parsable Types/ParsableArguments.swift"
  , "Sources/ArgumentParser/Parsable Types/ParsableCommand.swift"
  , "Sources/ArgumentParser/Utilities/Platform.swift"
  , "Sources/ArgumentParser/Utilities/StringExtensions.swift"
  , "Tests/ArgumentParserUnitTests/NameSpecificationTests.swift"
  , "Tests/ArgumentParserUnitTests/SequenceExtensionTests.swift"
  ]

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/swift/SwiftLexer.g4" "grammars/swift/SwiftParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The default-channel token types of a source, as the parser sees them.
typesWith :: Interpreter -> Text -> Either Text [Text]
typesWith interpreter source = case interpreterTokenize interpreter source of
  Left err -> Left (renderLexError err)
  Right toks -> Right [nameText (tokenType t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Swift project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "swift" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The parser sees where a statement ends only through the NEWLINE tokens the hook emits, so it
-- must emit one where the Swift compiler ends a statement at a line break: between two lines in
-- braces or at the top level when the first can end a statement and the second can start one, and
-- not inside parentheses or brackets, before a binary operator, a dot, a closing bracket, an opening
-- brace, else, catch, or where, after a binary operator, an opening bracket, a comma, or a keyword
-- that something must follow, or between a generic clause and its parameters; a keyword after a dot
-- or a declaration's introducer is a name. ref:REQ-swift-support ref:DEC-swift-grammar
-- ref:swift-statements
prop_theSwiftLexerHookEndsStatementsWhereTheCompilerDoes :: Property
prop_theSwiftLexerHookEndsStatementsWhereTheCompilerDoes = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf = typesWith interpreter
  -- two declarations on two lines, and a blank line between them, are one break
  typesOf "let a = 1\n\nvar b = 2\n" === Right ["LET", "ID", "OP", "NUMBER", "NEWLINE", "VAR", "ID", "OP", "NUMBER"]
  -- line breaks inside parentheses and brackets separate nothing; inside braces they do
  typesOf "f(a,\n  b)\nlet c = [\n  1,\n]\n" === Right ["ID", "LPAREN", "ID", "COMMA", "ID", "RPAREN", "NEWLINE", "LET", "ID", "OP", "LBRACK", "NUMBER", "COMMA", "RBRACK"]
  typesOf "struct S {\n  var a: Int\n  var b: Int\n}\n" === Right ["STRUCT", "ID", "LBRACE", "VAR", "ID", "COLON", "ID", "NEWLINE", "VAR", "ID", "COLON", "ID", "RBRACE"]
  -- a binary operator with whitespace on both sides continues the line above; a prefix one starts a
  -- statement
  typesOf "let x = a\n  + b\n!c\n" === Right ["LET", "ID", "OP", "ID", "OP", "ID", "NEWLINE", "OP", "ID"]
  -- a postfix operator ends a statement, and an operator ending a line after whitespace does not
  typesOf "let y = z!\nlet w = a &&\n  b\n" === Right ["LET", "ID", "OP", "ID", "OP", "NEWLINE", "LET", "ID", "OP", "ID", "OP", "ID"]
  -- a member chain continues on lines starting with a dot
  typesOf "let v = xs\n  .map { $0 }\n  .count\n" === Right ["LET", "ID", "OP", "ID", "DOT", "ID", "LBRACE", "ID", "RBRACE", "DOT", "ID"]
  -- a body's brace on the next line, else, catch, and where continue the line above
  typesOf "func f()\n{\n}\nif a {\n} else {\n}\n" === Right ["FUNC", "ID", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "NEWLINE", "ID", "ID", "LBRACE", "RBRACE", "ID", "LBRACE", "RBRACE"]
  typesOf "func g<T>(x: T)\n  where T: P\n{}\n" === Right ["FUNC", "ID", "LT", "ID", "GT", "LPAREN", "ID", "COLON", "ID", "RPAREN", "ID", "ID", "COLON", "ID", "LBRACE", "RBRACE"]
  -- a generic parameter clause over several lines, and parameters on the line after it
  typesOf "func h<\n  T\n>\n(x: T) -> Array<\n  T\n>\nlet z = 0\n"
    === Right ["FUNC", "ID", "LT", "ID", "GT", "LPAREN", "ID", "COLON", "ID", "RPAREN", "OP", "ID", "LT", "ID", "GT", "NEWLINE", "LET", "ID", "OP", "NUMBER"]
  -- an attribute's arguments run into the type on the next line
  typesOf "typealias G = @convention(thin)\n  (Int) -> Int\n" === Right ["TYPEALIAS", "ID", "OP", "AT", "ID", "LPAREN", "ID", "RPAREN", "LPAREN", "ID", "RPAREN", "OP", "ID"]
  -- a keyword is a name after a dot and after a declaration's introducer, and ends a statement there
  typesOf "let d = Foo.default\nenum K {\n  case await\n  case init\n}\n"
    === Right ["LET", "ID", "OP", "ID", "DOT", "ID", "NEWLINE", "ENUM", "ID", "LBRACE", "CASE", "ID", "NEWLINE", "CASE", "INIT", "RBRACE"]
  -- a parenthesis starting a line starts a statement, as the compiler takes no call across a line
  typesOf "f()\n(a, b) = (1, 2)\n" === Right ["ID", "LPAREN", "RPAREN", "NEWLINE", "LPAREN", "ID", "COMMA", "ID", "RPAREN", "OP", "LPAREN", "NUMBER", "COMMA", "NUMBER", "RPAREN"]

-- | Strings with interpolations, multi-line and raw strings, regex literals, nested comments, and
-- backquoted names must each lex whole, or a quote, a bracket, or a comment marker inside one would
-- be read as code. ref:REQ-swift-support ref:DEC-swift-grammar ref:swift-lexical-structure
-- ref:swift-regex-literals
prop_theSwiftLexerReadsStringsRegexLiteralsAndCommentsWhole :: Property
prop_theSwiftLexerReadsStringsRegexLiteralsAndCommentsWhole = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf = typesWith interpreter
  typesOf "\"a \\(f(\")\", g(x))) } \\\" b\"" === Right ["STRING"]
  typesOf "\"\"\"\n  a \"q\" } \\(x + \"\"\"\n  inner\n  \"\"\")\n  \"\"\"" === Right ["MULTILINE_STRING"]
  typesOf "#\"a \"b\" \\(c)\"# ##\"x\"#y\"##" === Right ["RAW_STRING", "RAW_STRING"]
  typesOf "#\"\"\"\n  \"# inside\n  \"\"\"#" === Right ["RAW_STRING"]
  typesOf "let r = /a+(b)/\nlet q = x / y / z" === Right ["LET", "ID", "OP", "REGEX", "NEWLINE", "LET", "ID", "OP", "ID", "OP", "ID", "OP", "ID"]
  typesOf "f(#/[a-z]+ (/)/#)" === Right ["ID", "LPAREN", "EXTENDED_REGEX", "RPAREN"]
  typesOf "/* a /* nested */ comment */ `class` _ $0 x" === Right ["BACKQUOTED_ID", "UNDERSCORE", "ID", "ID"]
  typesOf "a..<b ... c?.d ?? e" === Right ["ID", "OP", "ID", "OP", "ID", "OP", "DOT", "ID", "OP", "ID"]
  typesOf "0x1p-2 1_000.5e3 0b1010 0o17" === Right ["NUMBER", "NUMBER", "NUMBER", "NUMBER"]

-- | Swift compiles one branch of each #if, chosen by its compilation conditions, so canon must read
-- the first branch some build compiles by default, every branch some build compiles across the
-- builds it reads, and hide the others from the parser; a condition such as os(Linux) is decided as
-- a whole. ref:REQ-swift-support ref:DEC-swift-grammar ref:DEC-preprocessor-builds
-- ref:swift-compiler-control
prop_theSwiftLexerHookReadsTheBranchesOfIfABuildCompiles :: Property
prop_theSwiftLexerHookReadsTheBranchesOfIfABuildCompiles = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  swiftDirectiveOf "#if os(Linux) || canImport( Glibc ) // linux"
    === Just (DirectiveIf (CondOr (CondSymbol "os(Linux)") (CondSymbol "canImport(Glibc)")))
  swiftDirectiveOf "  #elseif !DEBUG && swift(>=5.9)" === Just (DirectiveElif (CondAnd (CondNot (CondSymbol "DEBUG")) (CondSymbol "swift(>=5.9)")))
  swiftDirectiveOf "#else" === Just DirectiveElse
  swiftDirectiveOf "#endif // os(Linux)" === Just DirectiveEndif
  swiftDirectiveOf "#warning(\"x\")" === Nothing
  let source = "#if os(Linux)\nimport Glibc\n#elseif false\nimport Nothing\n#else\nimport Darwin\n#endif\nfoo()\n  #if DEBUG\n  .debug()\n  #endif\n"
  typesWith interpreter source === Right ["IMPORT", "ID", "NEWLINE", "ID", "LPAREN", "RPAREN", "DOT", "ID", "LPAREN", "RPAREN"]
  let builds = buildsIn SwiftDirectives source
  length builds === 2
  Set.unions [Set.difference (Set.fromList [1 .. 12]) (inactiveLinesIn SwiftDirectives b source) | b <- builds] === Set.fromList ([1 .. 3] ++ [6 .. 12])
  imported <- forM builds $ \b -> case interpreterTokenizeWith interpreter b source of
    Left err -> annotate (T.unpack (renderLexError err)) >> failure
    Right toks ->
      let code = [t | t <- toks, tokenChannel t == defaultChannelName]
       in pure [tokenText next | (t, next) <- zip code (drop 1 code), tokenType t == Name "IMPORT"]
  Set.fromList (concat imported) === Set.fromList ["Glibc", "Darwin"]

-- | Real Swift must parse whole, with every type, member, and extension a file declares found where
-- the compiler finds it, or a Swift project's check would report parse failures instead of findings.
-- ref:REQ-swift-support ref:DEC-swift-grammar
prop_theSwiftGrammarParsesEveryFileOfTheArgumentParserSampleIntoItsDeclarations :: Property
prop_theSwiftGrammarParsesEveryFileOfTheArgumentParserSampleIntoItsDeclarations = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  trees <- forM sampleFiles $ \file -> do
    result <- evalIO (interpretFile interpreter (Name "topLevel") (sampleDir </> "source" </> file))
    either (\e -> annotate (file <> ": " <> T.unpack (renderInterpretError e)) >> failure) pure result
  let count rule tree = length (treeRuleNodes (Name rule) tree)
      counts tree = filter ((> 0) . snd) [(rule, count rule tree) | rule <- unitRules]
      unitRules = ["structDeclaration", "enumDeclaration", "enumCaseDeclaration", "protocolDeclaration", "extensionDeclaration", "functionDeclaration", "initializerDeclaration", "variableDeclaration", "constantDeclaration", "typealiasDeclaration", "expressionStatement"]
      byFile = Map.fromList (zip sampleFiles (map counts trees))
      at file = Map.findWithDefault [] file byFile
  at "Sources/ArgumentParser/Parsable Properties/ArgumentVisibility.swift"
    === [("structDeclaration", 1), ("enumDeclaration", 1), ("enumCaseDeclaration", 3), ("extensionDeclaration", 4), ("functionDeclaration", 3), ("variableDeclaration", 2), ("constantDeclaration", 3)]
  at "Sources/ArgumentParser/Parsable Types/ParsableCommand.swift"
    === [("protocolDeclaration", 1), ("extensionDeclaration", 3), ("functionDeclaration", 12), ("variableDeclaration", 7)]
  at "Tests/ArgumentParserUnitTests/SequenceExtensionTests.swift" === [("structDeclaration", 1), ("functionDeclaration", 2)]

-- | The constructs Swift 6 adds and the ones Swift code is full of must each read into the
-- declarations the compiler sees: actors, typed throws, async signatures, result builders, macros,
-- property wrappers, value generics, ~Copyable, attribute generics, operators and precedence groups,
-- protocols and their requirements, enums and their cases, extensions named by the type they
-- extend, initializers and subscripts, and declarations inside #if, with no declaration read as an
-- expression. ref:REQ-swift-support ref:DEC-swift-grammar ref:swift-grammar-summary
prop_theSwiftProfileReadsSwift6ConstructsIntoTheirDeclarations :: Property
prop_theSwiftProfileReadsSwift6ConstructsIntoTheirDeclarations = withTests 1 $ property $ do
  let idsOf path model = [T.drop (T.length ("swift/" <> T.pack path <> "/")) (renderUnitId (unitId u)) | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]
  Extraction model _ <- extractAt "Sources/Shapes/Modern.swift" (T.unlines modernFixture)
  idsOf "Sources/Shapes/Modern.swift" model
    === [ "actor/Counter"
        , "actor/Counter/var/value"
        , "actor/Counter/func/increment"
        , "actor/Counter/var/id"
        , "struct/ListBuilder"
        , "struct/ListBuilder/func/buildBlock"
        , "macro/Members"
        , "struct/Box"
        , "struct/Box/var/wrapped"
        , "struct/Box/subscript/subscript"
        , "struct/Box/init/init"
        , "struct/Box/deinit/deinit"
        , "operator/<>"
        , "precedencegroup/Combining"
        , "protocol/Shape"
        , "protocol/Shape/associatedtype/Measure"
        , "protocol/Shape/var/area"
        , "protocol/Shape/func/<>"
        , "enum/Tree"
        , "enum/Tree/case/leaf"
        , "enum/Tree/case/node"
        , "extension/Swift.Array"
        , "extension/Swift.Array/typealias/Measure"
        , "extension/Swift.Array/var/area"
        , "func/platform"
        , "let/package"
        ]

modernFixture :: [Text]
modernFixture =
  [ "import Foundation"
  , "@preconcurrency import Dispatch"
  , ""
  , "public actor Counter {"
  , "  private var value = 0"
  , "  public func increment() async throws(CounterError) -> Int {"
  , "    value += 1"
  , "    return value"
  , "  }"
  , "  nonisolated public var id: String { \"counter\" }"
  , "}"
  , ""
  , "@resultBuilder"
  , "public struct ListBuilder {"
  , "  public static func buildBlock(_ parts: String...) -> [String] { parts }"
  , "}"
  , ""
  , "@attached(member, names: arbitrary)"
  , "public macro Members() = #externalMacro(module: \"M\", type: \"Members\")"
  , ""
  , "public struct Box<let count: Int, Element: ~Copyable>: ~Copyable {"
  , "  @Wrapped<Int>(default: 1) var wrapped: Int"
  , "  public subscript(index: Int) -> Element? { nil }"
  , "  public init?(\n    from decoder: any Decoder\n  ) throws {"
  , "    nil"
  , "  }"
  , "  deinit {}"
  , "}"
  , ""
  , "infix operator <>: AdditionPrecedence"
  , "precedencegroup Combining {"
  , "  associativity: left"
  , "}"
  , ""
  , "public protocol Shape: Sendable {"
  , "  associatedtype Measure"
  , "  var area: Measure { get }"
  , "  static func <> (lhs: Self, rhs: Self) -> Self"
  , "}"
  , ""
  , "public indirect enum Tree<T> {"
  , "  case leaf(T), empty"
  , "  case node(Tree, Tree)"
  , "}"
  , ""
  , "extension Swift.Array: Shape where Element: Shape {"
  , "  public typealias Measure = Int"
  , "  public var area: Int { 0 }"
  , "}"
  , ""
  , "#if os(Linux)"
  , "public func platform() -> String { \"linux\" }"
  , "#else"
  , "public func platform() -> String { \"other\" }"
  , "#endif"
  , ""
  , "let (x, y) = (1, 2)"
  , "let _ = x"
  , "print(x + y)"
  , "let package = Package(name: \"shapes\")"
  , "package.targets.append(target)"
  ]

profileFixture :: Text
profileFixture =
  T.unlines
    [ "import Foundation"
    , ""
    , "// A plain comment is not documentation."
    , "func helper(_ x: Int) -> Int { x + 1 }"
    , ""
    , "/// Areas are what shapes are for. ref:some-key"
    , "// A note between the doc comment and its declaration."
    , "@inlinable"
    , "public func area(of shape: Shape) -> Double {"
    , "  switch shape {"
    , "  case .circle(let r): return .pi * r * r"
    , "  case .square(let w): return w * w"
    , "  }"
    , "}"
    , ""
    , "/// A shape is a circle or a square."
    , "public enum Shape {"
    , "  /// A circle by its radius."
    , "  case circle(radius: Double)"
    , "  case square(side: Double)"
    , "  func scaled() -> Shape { self }"
    , "}"
    , ""
    , "/// A canvas draws shapes."
    , "open class Canvas {"
    , "  /// The count, documented though private."
    , "  private var count = 0"
    , "  /// The canvas width."
    , "  public let size: Int"
    , "  public private(set) var drawn = 0"
    , "  public override var description: String { \"Canvas\" }"
    , "  fileprivate func reset() { count = 0 }"
    , "  @_spi(Testing) public func debugDump() {}"
    , "  /** Makes a canvas. */"
    , "  public init(size: Int) { self.size = size }"
    , "  deinit {}"
    , "  public subscript(index: Int) -> Shape? { nil }"
    , "  open func draw(_ shape: Shape) { count += 1 }"
    , "}"
    , ""
    , "/// Things that can be drawn."
    , "public protocol Drawable {"
    , "  func draw(on canvas: Canvas)"
    , "}"
    , ""
    , "public extension Shape {"
    , "  var doubled: Double { area(of: self) * 2 }"
    , "  internal var plain: Int { 0 }"
    , "}"
    , ""
    , "extension Canvas: Drawable {"
    , "  public func draw(on canvas: Canvas) {}"
    , "}"
    , ""
    , "private struct Cache {"
    , "  public var entries: [Int] = []"
    , "}"
    , ""
    , "public typealias Area = Double"
    ]

-- | An extraction through the sample's profile under a path.
extractAt :: FilePath -> Text -> PropertyT IO Extraction
extractAt path source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "swift" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The units of a model below the file, as kind, name, and requirement.
unitsOf :: Model Evidence -> [(Text, Text, CommentRequirement)]
unitsOf model = [(unitKindText (whatKind (whatOf u)), whatName (whatOf u), unitRequirement u) | u <- modelAllUnits model, unitKindText (whatKind (whatOf u)) /= "file"]
  where
    whatOf = answerValue . unitWhat

-- | The Why bound to each unit, by name.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(whatName (answerValue (unitWhat u)), whyText (answerValue (decisionWhy d))) | u <- modelAllUnits model, d <- decisionsFor (unitId u) model]

-- | A doc comment documents the declaration below it with its attributes and modifiers, and a plain
-- comment between them does not part them. What is public or open is API and needs a comment, what
-- is internal or package may have one, an override inherits its documentation, and what is private,
-- fileprivate, or @_spi is left out of the documentation as DocC leaves it out, with the members of
-- a hidden type; an enum's cases, a protocol's requirements, and the members of a public extension
-- take the access of the declaration around them. An XCTest test is a test* method in a test
-- target, and a Swift Testing test or suite is marked @Test or @Suite. ref:REQ-swift-support
-- ref:DEC-swift-grammar ref:swift-access-control ref:docc
prop_theSwiftProfileRequiresPublicApiHidesPrivateAndRecognisesTests :: Property
prop_theSwiftProfileRequiresPublicApiHidesPrivateAndRecognisesTests = withTests 1 $ property $ do
  Extraction model findings <- extractAt "Sources/Shapes/Shapes.swift" profileFixture
  unitsOf model
    === [ ("func", "helper", Optional)
        , ("func", "area", Required)
        , ("enum", "Shape", Required)
        , ("case", "circle", Required)
        , ("case", "square", Required)
        , ("func", "scaled", Optional)
        , ("class", "Canvas", Required)
        , ("var", "count", Hidden)
        , ("let", "size", Required)
        , ("var", "drawn", Required)
        , ("var", "description", Optional)
        , ("func", "reset", Hidden)
        , ("func", "debugDump", Hidden)
        , ("init", "init", Required)
        , ("deinit", "deinit", Optional)
        , ("subscript", "subscript", Required)
        , ("func", "draw", Required)
        , ("protocol", "Drawable", Required)
        , ("func", "draw", Required)
        , ("extension", "Shape", Required)
        , ("var", "doubled", Required)
        , ("var", "plain", Optional)
        , ("extension", "Canvas", Optional)
        , ("func", "draw", Required)
        , ("struct", "Cache", Hidden)
        , ("var", "entries", Hidden)
        , ("typealias", "Area", Required)
        ]
  whysOf model
    === [ ("area", "Areas are what shapes are for. ref:some-key")
        , ("Shape", "A shape is a circle or a square.")
        , ("circle", "A circle by its radius.")
        , ("Canvas", "A canvas draws shapes.")
        , ("size", "The canvas width.")
        , ("init", "Makes a canvas.")
        , ("Drawable", "Things that can be drawn.")
        ]
  -- the doc comment on the private count binds to nothing, as DEC-hidden-label has it
  length [() | OrphanDocComment _ _ <- findings] === 1
  Extraction xctest _ <-
    extractAt
      "Tests/ShapesTests/ShapeTests.swift"
      ( T.unlines
          [ "import XCTest"
          , "final class ShapeTests: XCTestCase {"
          , "  /// Squares have the area of their side squared. ref:REQ-1"
          , "  func testSquareArea() { XCTAssertEqual(area(of: .square(side: 2)), 4) }"
          , "  func helper() {}"
          , "}"
          ]
      )
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- modelAllUnits xctest, unitTest u] === [("testSquareArea", True)]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) xctest] === []
  Extraction testing _ <-
    extractAt
      "Sources/Checks/Checks.swift"
      ( T.unlines
          [ "import Testing"
          , "@Suite(.serialized) struct ShapeSuite {"
          , "  @Test(\"a unit square has unit area\") func unitSquare() {"
          , "    #expect(area(of: .square(side: 1)) == 1)"
          , "  }"
          , "  func testNotXCTest() {}"
          , "}"
          ]
      )
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- modelAllUnits testing, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]
    === [("ShapeSuite", True), ("unitSquare", True), ("testNotXCTest", False)]
  isTestUnit "swift" "extension" "Shapes" "Sources/A.swift" ["@Testing.Suite"] === True
  isTestUnit "swift" "func" "testA" "Sources/Shapes/A.swift" [] === False
  isTestUnit "swift" "func" "testA" "Sources/Shapes/ShapesTests.swift" [] === True

-- | The canonically commented dialect of the Swift grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".swift"] (SplitGrammarFiles "grammars/swift/canonically_commented/SwiftLexer.g4" "grammars/swift/canonically_commented/SwiftParser.g4") (Name "topLevel") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | An extraction through the Swift dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "swift" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Doc comments are tokens of the dialect, and the lexer hook must place them so statements end as
-- before: every file of the sample must parse with its comments, and the dialect must find the units
-- and requirements the profile finds and bind the doc comments the profile binds, and also those on
-- hidden declarations, which the profile reports as orphans under DEC-hidden-label.
-- ref:REQ-swift-support ref:DEC-swift-dialect ref:DEC-hidden-label
prop_theSwiftDialectParsesTheArgumentParserSampleWithItsDocCommentsAsTheProfileReadsIt :: Property
prop_theSwiftDialectParsesTheArgumentParserSampleWithItsDocCommentsAsTheProfileReadsIt = withTests 1 $ property $ do
  forM_ sampleFiles $ \file -> do
    source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
    Extraction dialect dialectFindings <- extractDialect file source
    Extraction profiled profiledFindings <- extractAt file source
    annotate file
    -- the profile also binds the file's licence header to the file, a plain comment the dialect hides
    let missing model = [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
        unitDecisions model = [renderDecisionId (decisionId d) | d <- modelDecisions model, renderDecisionId (decisionId d) /= "decision/swift/" <> T.intercalate "/" (pathIdSegments file)]
        hidden model = [renderDecisionId (decisionIdFor (unitId u)) | u <- modelAllUnits model, unitRequirement u == Hidden]
        orphans fs = length [() | OrphanDocComment _ _ <- fs]
    missing dialect === missing profiled
    [d | d <- unitDecisions dialect, d `notElem` hidden dialect] === [d | d <- unitDecisions profiled, d `notElem` hidden profiled]
    orphans dialectFindings + length [d | d <- unitDecisions dialect, d `elem` hidden dialect] === orphans profiledFindings

-- | In the dialect the grammar says where a doc comment binds: above a declaration and its attributes
-- and modifiers, while one after an attribute, above an import or a statement, inside a body's
-- statements, or at the end of a body binds to nothing and is reported; a comment nested in a /**
-- comment is part of it, as Swift comments nest, and //// is a plain comment.
-- ref:REQ-swift-support ref:DEC-swift-dialect
prop_theSwiftDialectBindsDocCommentsToDeclarationsAndReportsMisplacedComments :: Property
prop_theSwiftDialectBindsDocCommentsToDeclarationsAndReportsMisplacedComments = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "Shapes.swift"
      ( T.unlines
          [ "/// Above an import, so an orphan."
          , "import Foundation"
          , ""
          , "/// A shape. ref:some-key"
          , "public enum Shape {"
          , "  /// A circle by its radius."
          , "  case circle(radius: Double)"
          , "  case square(side: Double)"
          , "  /// At the end of the body, so an orphan."
          , "}"
          , ""
          , "@available(*, deprecated)"
          , "/// After the attribute, so an orphan."
          , "public func area(_ shape: Shape) -> Double {"
          , "  /// A local declaration, so an orphan."
          , "  let sq = 2.0"
          , "  return sq"
          , "}"
          , ""
          , "/// Hidden needs none, but may have one."
          , "private func hidden() {}"
          , ""
          , "//// A plain comment is not documentation."
          , "/** Shows a number, /* nested */ whole. */"
          , "@inlinable public func shown(_ x: Int) -> Int { x }"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("swift/Shapes.swift/enum/Shape", "A shape. ref:some-key")
        , ("swift/Shapes.swift/enum/Shape/case/circle", "A circle by its radius.")
        , ("swift/Shapes.swift/func/hidden", "Hidden needs none, but may have one.")
        , ("swift/Shapes.swift/func/shown", "Shows a number, /* nested */ whole.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 4
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["swift/Shapes.swift/enum/Shape/case/square", "swift/Shapes.swift/func/area"]
