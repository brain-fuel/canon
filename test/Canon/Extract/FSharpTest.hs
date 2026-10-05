-- | F# is read through canon's own F# grammar, whose lexer hook turns the offside rule into layout
-- tokens, and the profile the F# sample ships, so these properties check both against what an F#
-- author means by a declaration and its documentation. ref:DEC-fsharp-grammar ref:REQ-fsharp-support
module Canon.Extract.FSharpTest (tests) where

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
import Canon.Signature (linkSignatures)
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
    "fsharp"
    [ testProperty "the F# grammar parses the Giraffe.ViewEngine sample into its declarations" prop_fsharpGrammarParsesTheViewEngineSampleIntoItsDeclarations
    , testProperty "the F# lexer turns the offside rule into layout tokens outside brackets" prop_fsharpLexerTurnsTheOffsideRuleIntoLayoutTokensOutsideBrackets
    , testProperty "the F# profile binds doc comments, exempts private declarations, and recognises tests" prop_fsharpProfileBindsDocCommentsExemptsPrivateDeclarationsAndRecognisesTests
    , testProperty "F# type parameters span lines and may be quoted" prop_fsharpTypeParametersSpanLinesAndMayBeQuoted
    , testProperty "the members after a union case with an anonymous record are the union's" prop_theMembersAfterAUnionCaseWithAnAnonymousRecordAreTheUnions
    , testProperty "a doc comment on a local let binds to it" prop_aDocCommentOnALocalLetBindsToIt
    , testProperty "a signature file carries the comments of its implementation" prop_aSignatureFileCarriesTheCommentsOfItsImplementation
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/fsharp-giraffe-viewengine"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/fsharp/FSharpLexer.g4" "grammars/fsharp/FSharpParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile an F# project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "fsharp" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | Real F# must parse whole, with every module, binding, and type a file declares found where the
-- compiler finds it, or an F# project's check would report parse failures instead of findings.
-- ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_fsharpGrammarParsesTheViewEngineSampleIntoItsDeclarations :: Property
prop_fsharpGrammarParsesTheViewEngineSampleIntoItsDeclarations = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let parse file = do
        result <- evalIO (interpretFile interpreter (Name "file") (sampleDir </> "source" </> file))
        either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure result
  engine <- parse "src/Giraffe.ViewEngine/Engine.fs"
  length (treeRuleNodes (Name "nestedModule") engine) === 8
  length (treeRuleNodes (Name "functionDefinition") engine) === 30
  length (treeRuleNodes (Name "valueDefinition") engine) === 369
  length (treeRuleNodes (Name "unionType") engine) === 2
  length (treeRuleNodes (Name "abbreviationType") engine) === 1
  pool <- parse "src/Giraffe.ViewEngine/StringBuilderPool.fs"
  length (treeRuleNodes (Name "classType") pool) === 1
  length (treeRuleNodes (Name "memberDefinition") pool) === 3
  unitTests <- parse "tests/Giraffe.ViewEngine.Tests/Tests.fs"
  length (treeRuleNodes (Name "functionDefinition") unitTests) === 7

-- | The parser finds where a declaration ends only through the layout tokens the hook emits, so the
-- hook must emit them as the offside rule reads the lines, suppress them inside brackets, keep
-- characters, type parameters, nested comments, and the (*) operator apart, and read one branch
-- of each #if. ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_fsharpLexerTurnsTheOffsideRuleIntoLayoutTokensOutsideBrackets :: Property
prop_fsharpLexerTurnsTheOffsideRuleIntoLayoutTokensOutsideBrackets = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [nameText (tokenType t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "let f x =\n    x\nlet y = [\n  1\n]\n"
    === Right ["LET", "IDENTIFIER", "IDENTIFIER", "EQUALS", "INDENT", "IDENTIFIER", "DEDENT", "NEWLINE", "LET", "IDENTIFIER", "EQUALS", "LBRACK", "BRNL", "NUMBER", "BRNL", "RBRACK"]
  typesOf "module M =\n    let a = 1\n        + 2\n    let b = 3\n"
    === Right ["MODULE", "IDENTIFIER", "EQUALS", "INDENT", "LET", "IDENTIFIER", "EQUALS", "NUMBER", "INDENT", "SYMBOLIC_OPERATOR", "NUMBER", "DEDENT", "NEWLINE", "LET", "IDENTIFIER", "EQUALS", "NUMBER", "DEDENT"]
  typesOf "f 'a' ('b -> (*) (* (* nested *) *) '''"
    === Right ["IDENTIFIER", "CHAR", "LPAREN", "TYPE_PARAMETER", "SYMBOLIC_OPERATOR", "MULTIPLY_NAME", "CHAR"]
  typesOf "#if DEBUG\nlet a = 1\n#else\nlet b = 2\n#endif\n" === Right ["LET", "IDENTIFIER", "EQUALS", "NUMBER"]

fixture :: Text
fixture =
  T.unlines
    [ "/// The drawing module draws shapes. ref:some-key"
    , "module Shapes.Drawing"
    , ""
    , "open System"
    , ""
    , "// A plain comment is not documentation."
    , "let helper x = x + 1"
    , ""
    , "/// Areas are what shapes are for."
    , "// A note between the doc comment and its function."
    , "[<CompiledName(\"Area\")>]"
    , "let area (shape: Shape) ="
    , "    match shape with"
    , "    | Circle r -> 3.0 * r * r"
    , "    | Square w -> w * w"
    , ""
    , "/// Private helpers need no comment, but may have one."
    , "let private scale k x = k * x"
    , ""
    , "let private unused = 0"
    , ""
    , "/// A shape is a circle or a square."
    , "type Shape ="
    , "    /// A circle by its radius."
    , "    | Circle of float"
    , "    | Square of float"
    , ""
    , "/// Points are records."
    , "type Point ="
    , "    { /// The horizontal coordinate."
    , "      X: float"
    , "      Y: float }"
    , ""
    , "/// A canvas draws shapes."
    , "type Canvas(width: int) ="
    , "    let mutable count = 0"
    , "    /// The canvas width."
    , "    member _.Width = width"
    , "    member this.Draw(shape: Shape) ="
    , "        count <- count + 1"
    , ""
    , "/// Drawing is an interface."
    , "type IDraw ="
    , "    abstract Draw : Shape -> unit"
    , ""
    , "type Alias = int list"
    , ""
    , "module Nested ="
    , "    /// Nested values may have a comment."
    , "    let limit = 10"
    , ""
    , "/// Orphaned by the blank line below."
    , ""
    , "let rec even n = if n = 0 then true else odd (n - 1)"
    , "and odd n = if n = 0 then false else even (n - 1)"
    , ""
    , "#if NEVER && !NEVER"
    , "/// A doc comment in a branch canon does not read."
    , "let never () = ()"
    , "#endif"
    , ""
    , "/// Squares have the area of their side squared. ref:REQ-1"
    , "[<Fact>]"
    , "let ``square area is side squared`` () ="
    , "    Assert.Equal(4.0, area (Square 2.0))"
    , ""
    , "[<Property>]"
    , "let ``uncommented property`` (x: int) = x = x"
    , ""
    , "[<Tests>]"
    , "let tests ="
    , "    testList \"shapes\" ["
    , "        testCase \"circle\" <| fun () -> ()"
    , "    ]"
    ]

-- | In F# a doc comment sits above a declaration's attributes and a plain comment between them does
-- not part them, a private or internal declaration is not what a module exports, and an xUnit,
-- NUnit, FsCheck, or Expecto attribute makes a binding a test, so the profile must bind, require,
-- and recognise each that way for the Why of an F# declaration to be its documentation.
-- ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_fsharpProfileBindsDocCommentsExemptsPrivateDeclarationsAndRecognisesTests :: Property
prop_fsharpProfileBindsDocCommentsExemptsPrivateDeclarationsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "fsharp" profile interpreter "Shapes.fs" "Shapes.fs" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("module", "Shapes.Drawing")
        , ("function", "helper")
        , ("function", "area")
        , ("function", "scale")
        , ("value", "unused")
        , ("union", "Shape")
        , ("case", "Circle")
        , ("case", "Square")
        , ("record", "Point")
        , ("field", "X")
        , ("field", "Y")
        , ("class", "Canvas")
        , ("value", "count")
        , ("member", "Width")
        , ("member", "Draw")
        , ("interface", "IDraw")
        , ("member", "Draw")
        , ("abbreviation", "Alias")
        , ("module", "Nested")
        , ("value", "limit")
        , ("function", "even")
        , ("function", "odd")
        , ("function", "``square area is side squared``")
        , ("function", "``uncommented property``")
        , ("value", "tests")
        ]
  whyOf "Shapes.fs" === []
  whyOf "Shapes.Drawing" === ["The drawing module draws shapes. ref:some-key"]
  whyOf "helper" === []
  whyOf "area" === ["Areas are what shapes are for."]
  whyOf "scale" === ["Private helpers need no comment, but may have one."]
  whyOf "Circle" === ["A circle by its radius."]
  whyOf "X" === ["The horizontal coordinate."]
  whyOf "Width" === ["The canvas width."]
  whyOf "limit" === ["Nested values may have a comment."]
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["``square area is side squared``", "``uncommented property``", "tests", "helper"] === [[True], [True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "fsharp/Shapes.fs/module/Shapes.Drawing/function/helper"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/class/Canvas/member/Draw"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/interface/IDraw/member/Draw"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/function/even"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/function/odd"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/function/``uncommented property``"
        , "fsharp/Shapes.fs/module/Shapes.Drawing/value/tests"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []

-- | An F# fixture extracted through the sample's profile under a path.
extractAt :: FilePath -> Text -> PropertyT IO Extraction
extractAt path source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "fsharp" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The units of a model with their requirement, below the file, as kind, name, and requirement.
unitsOf :: Model Evidence -> [(Text, Text, CommentRequirement)]
unitsOf model = [(unitKindText (whatKind (whatOf u)), whatName (whatOf u), unitRequirement u) | u <- modelAllUnits model, unitKindText (whatKind (whatOf u)) /= "file"]
  where
    whatOf = answerValue . unitWhat

-- | The Why bound to each unit, by name.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(whatName (answerValue (unitWhat u)), whyText (answerValue (decisionWhy d))) | u <- modelAllUnits model, d <- decisionsFor (unitId u) model]

-- | A statically resolved type parameter list may span lines, as F# lets angle brackets do, and a
-- type parameter may be quoted in double backticks; a parser that refused either lost the
-- declaration and reported its documentation as attached to nothing, while a less-than sign that is
-- a comparison must still be read as one. ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_fsharpTypeParametersSpanLinesAndMayBeQuoted :: Property
prop_fsharpTypeParametersSpanLinesAndMayBeQuoted = withTests 1 $ property $ do
  Extraction model findings <-
    extractAt
      "Srtp.fs"
      ( T.unlines
          [ "module Srtp"
          , ""
          , "/// Adds anything with a static zero."
          , "let inline addZero< ^a"
          , "                    when ^a : (static member Zero : ^a)"
          , "                    and ^a : (static member (+) : ^a * ^a -> ^a)> (x: ^a) ="
          , "    x + (^a : (static member Zero : ^a) ())"
          , ""
          , "/// Boxes a value."
          , "type Box<'``T``> = { Value: '``T`` }"
          , ""
          , "/// Compares without spaces."
          , "let less a b = a<b"
          , ""
          , "/// Comes after."
          , "let after = 1"
          ]
      )
  [(k, n) | (k, n, _) <- unitsOf model] === [("module", "Srtp"), ("function", "addZero"), ("record", "Box"), ("field", "Value"), ("function", "less"), ("value", "after")]
  map fst (whysOf model) === ["addZero", "Box", "less", "after"]
  [() | OrphanDocComment _ _ <- findings] === []

-- | A union's members may follow a single case whose fields are a multi-line anonymous record, and
-- they are the union's members, documented as members, not part of the case's type.
-- ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_theMembersAfterAUnionCaseWithAnAnonymousRecordAreTheUnions :: Property
prop_theMembersAfterAUnionCaseWithAnAnonymousRecordAreTheUnions = withTests 1 $ property $ do
  Extraction model findings <-
    extractAt
      "Union.fs"
      ( T.unlines
          [ "module Union"
          , ""
          , "/// A wrapper."
          , "type Wrapper = Wrapper of {| A: int"
          , "                             B: int |}"
          , "               with"
          , "                   /// The A of the wrapper."
          , "                   member x.A = 1"
          ]
      )
  [(k, n) | (k, n, _) <- unitsOf model] === [("module", "Union"), ("union", "Wrapper"), ("case", "Wrapper"), ("member", "A")]
  lookup "A" (whysOf model) === Just "The A of the wrapper."
  [() | OrphanDocComment _ _ <- findings] === []

-- | A let inside a function is private to it but may carry a Why, and a doc comment on one is its
-- documentation rather than a comment attached to nothing; such a binding needs no comment.
-- ref:REQ-fsharp-support ref:DEC-fsharp-grammar
prop_aDocCommentOnALocalLetBindsToIt :: Property
prop_aDocCommentOnALocalLetBindsToIt = withTests 1 $ property $ do
  Extraction model findings <-
    extractAt
      "Local.fs"
      ( T.unlines
          [ "module Local"
          , ""
          , "/// Adds the helpers' results."
          , "let outer x ="
          , "    /// Steps once."
          , "    let rec step y = if y > 0 then next (y - 1) else 0"
          , "    and next y = step y"
          , "    /// Two, always."
          , "    let two = 2"
          , "    step x + two"
          ]
      )
  unitsOf model
    === [ ("module", "Local", Optional)
        , ("function", "outer", Required)
        , ("function", "step", Optional)
        , ("function", "next", Optional)
        , ("value", "two", Optional)
        ]
  whysOf model === [("outer", "Adds the helpers' results."), ("step", "Steps once."), ("two", "Two, always.")]
  [() | OrphanDocComment _ _ <- findings] === []

-- | With a signature file, F# takes the documentation of what the signature declares from it and
-- hides what it leaves out, so the comment is required on the signature's val and type, the
-- implementation's binding is documented by it, and a binding the signature omits is private.
-- ref:REQ-fsharp-support ref:DEC-fsharp-signatures
prop_aSignatureFileCarriesTheCommentsOfItsImplementation :: Property
prop_aSignatureFileCarriesTheCommentsOfItsImplementation = withTests 1 $ property $ do
  profile <- sampleProfile
  signature <-
    extractAt
      "Lib.fsi"
      ( T.unlines
          [ "module Lib"
          , ""
          , "/// Doubles a number."
          , "val double : int -> int"
          , ""
          , "val triple : int -> int"
          , ""
          , "/// A counter."
          , "type Counter ="
          , "    /// The count."
          , "    member Count : int"
          ]
      )
  implementation <-
    extractAt
      "Lib.fs"
      ( T.unlines
          [ "module Lib"
          , ""
          , "let double x = x * 2"
          , "let triple x = x * 3"
          , "let hidden x = x"
          , ""
          , "type Counter() ="
          , "    member _.Count = 0"
          ]
      )
  let linked = linkSignatures (Map.singleton "fsharp" profile) [("Lib.fsi", Right signature), ("Lib.fs", Right implementation) :: (FilePath, Either Text Extraction)]
  case linked of
    [("Lib.fsi", Right sig'), ("Lib.fs", Right impl')] -> do
      [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger (extractionModel sig')] === ["fsharp/Lib.fsi/module/Lib/val/triple"]
      [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger (extractionModel impl')] === []
      [(k, n, r) | (k, n, r) <- unitsOf (extractionModel sig'), r == Required] === [("val", "double", Required), ("val", "triple", Required), ("class", "Counter", Required), ("member", "Count", Required)]
    _ -> failure
