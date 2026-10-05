-- | Elixir is read through canon's own structural Elixir grammar and the profile the Elixir sample
-- ships, so these properties check both against what an Elixir author means by a definition and its
-- documentation. ref:DEC-elixir-grammar ref:REQ-elixir-support
module Canon.Extract.ElixirTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (treeRuleNodes)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..), hiddenChannelName, isEofToken)
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
    "elixir"
    [ testProperty "the Elixir grammar parses the Jason sample into its definitions and tests" prop_elixirGrammarParsesTheJasonSampleIntoItsDefinitionsAndTests
    , testProperty "the Elixir lexer keeps interpolations, heredocs, and sigils whole" prop_elixirLexerKeepsInterpolationsHeredocsAndSigilsWhole
    , testProperty "the Elixir profile binds doc attributes, merges clauses, and recognises tests" prop_elixirProfileBindsDocAttributesMergesClausesAndRecognisesTests
    , testProperty "the Elixir profile names operator, unquoted, and test definitions as Elixir does" prop_elixirProfileNamesOperatorUnquotedAndTestDefinitionsAsElixirDoes
    , testProperty "the Elixir profile binds a doc across blank lines and hides what @doc false hides" prop_elixirProfileBindsADocAcrossBlankLinesAndHidesWhatDocFalseHides
    , testProperty "the Elixir dialect reads @doc and @moduledoc as canonical comments as Elixir binds them" prop_elixirDialectReadsDocAndModuledocAsCanonicalCommentsAsElixirBindsThem
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/elixir-jason"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/elixir/ElixirLexer.g4" "grammars/elixir/ElixirParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile an Elixir project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "elixir" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | A real library must parse whole, with every def, defp, type, and test found where the Elixir
-- compiler finds them, or an Elixir project's check would report parse failures instead of
-- findings. ref:REQ-elixir-support ref:DEC-elixir-grammar
prop_elixirGrammarParsesTheJasonSampleIntoItsDefinitionsAndTests :: Property
prop_elixirGrammarParsesTheJasonSampleIntoItsDefinitionsAndTests = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  library <- evalIO (interpretFile interpreter (Name "file") (sampleDir </> "source/lib/formatter.ex"))
  tree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure library
  length (treeRuleNodes (Name "moduleDefinition") tree) === 1
  length (treeRuleNodes (Name "publicFunction") tree) === 4
  length (treeRuleNodes (Name "privateFunction") tree) === 23
  length (treeRuleNodes (Name "typeDefinition") tree) === 1
  suite <- evalIO (interpretFile interpreter (Name "file") (sampleDir </> "source/test/formatter_test.exs"))
  testTree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure suite
  length (treeRuleNodes (Name "namedBlock") testTree) === 10

-- | Elixir nests code inside strings and quotes text inside sigils, so a closing brace inside an
-- interpolation, a quote inside a heredoc, or a parenthesis inside a sigil's interpolation must
-- not end the literal, or every statement after it would be misread. ref:REQ-elixir-support
-- ref:DEC-elixir-grammar
prop_elixirLexerKeepsInterpolationsHeredocsAndSigilsWhole :: Property
prop_elixirLexerKeepsInterpolationsHeredocsAndSigilsWhole = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t /= hiddenChannelName]
  typesOf "\"a #{%{b: \"}\"}} c\""
    === Right
      [ ("STRING_OPEN", "\"")
      , ("STRING_TEXT", "a ")
      , ("STRING_INTERPOLATION", "#{")
      , ("OPEN_MAP", "%{")
      , ("KEYWORD", "b:")
      , ("STRING_OPEN", "\"")
      , ("STRING_TEXT", "}")
      , ("STRING_CLOSE", "\"")
      , ("CLOSE_BRACE", "}")
      , ("CLOSE_BRACE", "}")
      , ("STRING_TEXT", " c")
      , ("STRING_CLOSE", "\"")
      ]
  typesOf "\"\"\"\nsay \"hi\" # not a comment\n\"\"\"" === Right [("HEREDOC_OPEN", "\"\"\""), ("HEREDOC_TEXT", "\nsay \"hi\" # not a comment\n"), ("HEREDOC_CLOSE", "\"\"\"")]
  typesOf "~S(<a href=\"#{x}\">)" === Right [("SIGIL", "~S(<a href=\"#{x}\">)")]
  typesOf "~s(<a href=\"#{f(%{a: x})}\n\">)"
    === Right
      [ ("SIGIL_PAREN_OPEN", "~s(")
      , ("SIGIL_TEXT", "<a href=\"")
      , ("SIGIL_INTERPOLATION", "#{")
      , ("IDENTIFIER", "f")
      , ("OPEN_PAREN", "(")
      , ("OPEN_MAP", "%{")
      , ("KEYWORD", "a:")
      , ("IDENTIFIER", "x")
      , ("CLOSE_BRACE", "}")
      , ("CLOSE_PAREN", ")")
      , ("CLOSE_BRACE", "}")
      , ("SIGIL_TEXT", "\n\">")
      , ("SIGIL_CLOSE", ")")
      ]
  typesOf "~r/#{\n  x\n}/u" === Right [("SIGIL_SLASH_OPEN", "~r/"), ("SIGIL_INTERPOLATION", "#{"), ("NL", "\n"), ("IDENTIFIER", "x"), ("NL", "\n"), ("CLOSE_BRACE", "}"), ("SIGIL_CLOSE", "/u")]
  typesOf "valid? x" === Right [("IDENTIFIER", "valid?"), ("IDENTIFIER", "x")]
  typesOf "@doc false\n@docs_url 1" === Right [("DOC_ATTRIBUTE", "@doc"), ("FALSE", "false"), ("NL", "\n"), ("ATTRIBUTE", "@docs_url"), ("INTEGER", "1")]
  typesOf "@moduledoc false" === Right [("MODULEDOC_ATTRIBUTE", "@moduledoc"), ("FALSE", "false")]

fixture :: Text
fixture =
  T.unlines
    [ "defmodule Shapes do"
    , "  @moduledoc \"\"\""
    , "  Shapes exist to exercise the Elixir profile. ref:some-key"
    , "  \"\"\""
    , ""
    , "  # A plain comment is not documentation."
    , "  def helper, do: :ok"
    , ""
    , "  @typedoc \"A shape is a circle or a square.\""
    , "  @type shape :: {:circle, float} | {:square, float}"
    , ""
    , "  @doc ~S\"\"\""
    , "  Areas are what shapes are for."
    , "  \"\"\""
    , "  # The spec below is the area's contract."
    , "  @spec area(shape) :: float"
    , "  def area({:circle, r}), do: 3.0 * r * r"
    , "  def area({:square, w}), do: w * w"
    , ""
    , "  @doc \"The area of a shape scaled by a factor.\""
    , "  def area(shape, factor), do: area(shape) * factor"
    , ""
    , "  defp twice(x), do: x * 2"
    , ""
    , "  @doc \"Orphaned by the @doc false that overrides it.\""
    , ""
    , "  @doc false"
    , "  def hidden, do: twice(1)"
    , "end"
    , ""
    , "defmodule ShapesTest do"
    , "  @moduledoc false"
    , "  use ExUnit.Case"
    , ""
    , "  describe \"area\" do"
    , "    @doc \"Squares have the area of their side squared. ref:REQ-1\""
    , "    @tag :fast"
    , "    test \"of a square\" do"
    , "      assert Shapes.area({:square, 2.0}) == 4.0"
    , "    end"
    , "  end"
    , ""
    , "  test \"uncommented\", do: assert(true)"
    , "end"
    ]

-- | In Elixir the documentation of a definition is the @doc attribute above it and its @spec,
-- @moduledoc documents the module around it, a # comment documents nothing, the clauses of a
-- function are one function, and test makes a test, so the profile must bind, merge, and
-- recognise each that way for the Why of an Elixir definition to be its documentation.
-- ref:REQ-elixir-support ref:DEC-elixir-grammar
prop_elixirProfileBindsDocAttributesMergesClausesAndRecognisesTests :: Property
prop_elixirProfileBindsDocAttributesMergesClausesAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "elixir" profile interpreter "shapes.ex" "shapes.ex" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("module", "Shapes")
        , ("function", "helper")
        , ("type", "shape")
        , ("function", "area")
        , ("function", "area")
        , ("function", "twice")
        , ("function", "hidden")
        , ("module", "ShapesTest")
        , ("describe", "area")
        , ("test", "of a square")
        , ("test", "uncommented")
        ]
  whyOf "Shapes" === ["Shapes exist to exercise the Elixir profile. ref:some-key"]
  whyOf "helper" === []
  whyOf "shape" === ["A shape is a circle or a square."]
  whyOf "area" === ["Areas are what shapes are for.", "The area of a shape scaled by a factor."]
  whyOf "hidden" === []
  whyOf "of a square" === ["Squares have the area of their side squared. ref:REQ-1"]
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["of a square", "uncommented", "twice"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "elixir/shapes.ex/module/Shapes/function/helper"
        , "elixir/shapes.ex/module/ShapesTest/test/uncommented"
        ]

-- | Extracts a fixture through the sample's profile, for the properties that read one.
extractFixture :: Text -> PropertyT IO Extraction
extractFixture source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "elixir" profile interpreter "fixture.ex" "fixture.ex" source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | An Elixir library defines operators with def a <~> b, generates functions with
-- def unquote(name)(args), and names tests with strings, in parentheses or not, so each must be a
-- unit named for what Elixir calls it, or its documentation would be reported as attached to
-- nothing and the unit as missing. ref:REQ-elixir-support ref:DEC-elixir-grammar
prop_elixirProfileNamesOperatorUnquotedAndTestDefinitionsAsElixirDoes :: Property
prop_elixirProfileNamesOperatorUnquotedAndTestDefinitionsAsElixirDoes = withTests 1 $ property $ do
  Extraction model findings <-
    extractFixture $
      T.unlines
        [ "defmodule Ops do"
        , "  @doc \"Combines two values.\""
        , "  def left <~> right, do: {left, right}"
        , ""
        , "  @doc \"Negates.\""
        , "  def -value, do: value"
        , ""
        , "  for name <- [:first, :second] do"
        , "    @doc \"Generated for each name.\""
        , "    def unquote(name)(arg), do: ~s(#{arg}: #{inspect(%{name: unquote(name)})})"
        , "  end"
        , ""
        , "  test(\"in parentheses\", %{conn: conn}) do"
        , "    assert conn"
        , "  end"
        , ""
        , "  test \"pending\""
        , "end"
        ]
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("module", "Ops")
        , ("function", "<~>")
        , ("function", "-")
        , ("function", "unquote(name)")
        , ("test", "in parentheses")
        , ("test", "pending")
        ]
  map whyOf ["<~>", "-", "unquote(name)"] === [["Combines two values."], ["Negates."], ["Generated for each name."]]
  length [() | OrphanDocComment _ _ <- findings] === 0

-- | Elixir binds every @doc to the next definition whatever blank lines lie between, a later
-- @doc false overrides an earlier @doc, and @doc false and @moduledoc false hide what they mark from
-- the documentation, as ExDoc does, so canon must bind across blank lines, report the overridden
-- @doc, and mark the hidden units hidden rather than missing their comment, while a test in a hidden
-- module still needs its requirement. ref:REQ-elixir-support ref:DEC-hidden-label
prop_elixirProfileBindsADocAcrossBlankLinesAndHidesWhatDocFalseHides :: Property
prop_elixirProfileBindsADocAcrossBlankLinesAndHidesWhatDocFalseHides = withTests 1 $ property $ do
  Extraction model findings <-
    extractFixture $
      T.unlines
        [ "defmodule Spaced do"
        , "  @moduledoc \"Spaced exists to test binding.\""
        , ""
        , "  @doc \"\"\""
        , "  Bound across the blank lines and the spec."
        , "  \"\"\""
        , ""
        , "  @spec spaced() :: :ok"
        , ""
        , "  def spaced, do: :ok"
        , ""
        , "  @doc \"Overridden.\""
        , "  @doc false"
        , "  def hidden, do: :ok"
        , ""
        , "  def generator do"
        , "    quote do"
        , "      @moduledoc false"
        , "    end"
        , "  end"
        , "end"
        , ""
        , "defmodule Internal do"
        , "  @moduledoc false"
        , "  def helper, do: :ok"
        , "  test \"still a test\", do: :ok"
        , "end"
        ]
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      requirementOf n = [unitRequirement u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  whyOf "spaced" === ["Bound across the blank lines and the spec."]
  whyOf "hidden" === []
  length [() | OrphanDocComment _ _ <- findings] === 1
  map requirementOf ["Spaced", "spaced", "hidden", "generator", "Internal", "helper", "still a test"]
    === [[Required], [Required], [Hidden], [Required], [Hidden], [Hidden], [Required]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["elixir/fixture.ex/module/Spaced/function/generator", "elixir/fixture.ex/module/Internal/test/still a test"]

-- | The Elixir dialect, under grammars/elixir/canonically_commented, as a project names it.
dialectProfile :: Profile
dialectProfile = Profile [".ex", ".exs"] (SplitGrammarFiles "grammars/elixir/canonically_commented/ElixirLexer.g4" "grammars/elixir/canonically_commented/ElixirParser.g4") (Name "file") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | A canonically commented grammar must say in grammar form what the Elixir profile says in
-- canon.yaml, so a project can check Elixir through the dialect alone: @doc and @typedoc document the
-- definition below their attributes across blank lines, a @typedoc only a type, @moduledoc documents
-- the module wherever it
-- sits in the body, the last @doc wins and @doc false hides, the clauses of a function are one unit,
-- and the Jason sample parses whole. ref:REQ-elixir-support ref:DEC-elixir-dialect
-- ref:DEC-hidden-label
prop_elixirDialectReadsDocAndModuledocAsCanonicalCommentsAsElixirBindsThem :: Property
prop_elixirDialectReadsDocAndModuledocAsCanonicalCommentsAsElixirBindsThem = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  library <- evalIO (interpretFile interpreter (Name "file") (sampleDir </> "source/lib/formatter.ex"))
  _ <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure library
  suite <- evalIO (interpretFile interpreter (Name "file") (sampleDir </> "source/test/formatter_test.exs"))
  _ <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure suite
  let source =
        T.unlines
          [ "defmodule Shapes do"
          , "  use Something"
          , "  @moduledoc \"\"\""
          , "  Shapes exist to exercise the Elixir dialect. ref:some-key"
          , "  \"\"\""
          , ""
          , "  @typedoc \"A typedoc documents a type and nothing else.\""
          , "  def helper, do: :ok"
          , ""
          , "  @typedoc \"A shape is a circle or a square.\""
          , "  @type shape :: {:circle, float} | {:square, float}"
          , ""
          , "  @doc ~S\"\"\""
          , "  Areas are what shapes are for, #{verbatim}."
          , "  \"\"\""
          , "  # The spec below is the area's contract."
          , ""
          , "  @spec area(shape) :: float"
          , "  def area({:circle, r}), do: 3.0 * r * r"
          , "  def area({:square, w}), do: w * w"
          , ""
          , "  @doc \"The area scaled by #{inspect(%{by: \"}\"})}.\""
          , "  def area(shape, factor), do: area(shape) * factor"
          , ""
          , "  @doc \"Overridden.\""
          , "  @doc false"
          , "  def hidden, do: :ok"
          , ""
          , "  @doc \"Combines.\""
          , "  def left <~> right, do: {left, right}"
          , "end"
          , ""
          , "defmodule ShapesTest do"
          , "  @moduledoc false"
          , "  describe \"area\" do"
          , "    @doc \"Squares have the area of their side squared. ref:REQ-1\""
          , "    @tag :fast"
          , "    test \"of a square\", do: :ok"
          , "  end"
          , ""
          , "  test(\"uncommented\", %{}) do"
          , "    :ok"
          , "  end"
          , "end"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "elixir" dialectProfile interpreter "shapes.ex" "shapes.ex" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u, unitRequirement u) | u <- units, kindOf u /= "file"]
    === [ ("module", "Shapes", Required)
        , ("function", "helper", Required)
        , ("type", "shape", Optional)
        , ("function", "area", Required)
        , ("function", "area", Required)
        , ("function", "hidden", Hidden)
        , ("function", "<~>", Required)
        , ("module", "ShapesTest", Hidden)
        , ("describe", "area", Hidden)
        , ("test", "of a square", Required)
        , ("test", "uncommented", Required)
        ]
  whyOf "Shapes" === ["Shapes exist to exercise the Elixir dialect. ref:some-key"]
  whyOf "shape" === ["A shape is a circle or a square."]
  whyOf "area" === ["Areas are what shapes are for, #{verbatim}.", "The area scaled by #{inspect(%{by: \"}\"})}."]
  whyOf "<~>" === ["Combines."]
  whyOf "of a square" === ["Squares have the area of their side squared. ref:REQ-1"]
  whyOf "helper" === []
  length [() | OrphanDocComment _ _ <- findings] === 2
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["elixir/shapes.ex/module/Shapes/function/helper", "elixir/shapes.ex/module/ShapesTest/test/uncommented"]
