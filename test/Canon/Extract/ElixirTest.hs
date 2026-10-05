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
  typesOf "~s(<a href=\"#{path(x)}\">)" === Right [("SIGIL", "~s(<a href=\"#{path(x)}\">)")]
  typesOf "valid? x" === Right [("IDENTIFIER", "valid?"), ("IDENTIFIER", "x")]
  typesOf "@doc false\n@docs_url 1" === Right [("DOC_ATTRIBUTE", "@doc"), ("FALSE", "false"), ("NL", "\n"), ("ATTRIBUTE", "@docs_url"), ("INTEGER", "1")]

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
    , "  @doc \"Orphaned by the blank line below.\""
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
        , "elixir/shapes.ex/module/Shapes/function/hidden"
        , "elixir/shapes.ex/module/ShapesTest"
        , "elixir/shapes.ex/module/ShapesTest/test/uncommented"
        ]
