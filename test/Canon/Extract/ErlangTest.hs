-- | Erlang is read through the grammars-v4 Erlang grammar, changed for canon, and the profile the
-- recon sample ships, so these properties check both against what an Erlang author means by a
-- function and its documentation. ref:DEC-erlang-grammar ref:REQ-erlang-support
module Canon.Extract.ErlangTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretText, renderInterpretError)
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
    "erlang"
    [ testProperty "the Erlang grammar reads macros, directives, and the syntax of OTP 24 to 28" prop_erlangGrammarReadsMacrosDirectivesAndTheSyntaxOfOtp24To28
    , testProperty "the Erlang lexer reads subtraction, triple-quoted strings, sigils, and hidden docs" prop_erlangLexerReadsSubtractionTripleQuotedStringsSigilsAndHiddenDocs
    , testProperty "the Erlang profile binds edoc comments and doc attributes across specs and hides what -doc false hides" prop_erlangProfileBindsEdocCommentsAndDocAttributesAcrossSpecsAndHidesWhatDocFalseHides
    , testProperty "the Erlang dialect reads -doc strings and EDoc comments and requires them on exported units" prop_erlangDialectReadsDocStringsAndEdocCommentsAndRequiresThemOnExportedUnits
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/erlang-recon"

-- | The profile as the sample's canon.yaml declares it, with its grammar path made relative to the
-- repository root, so the test reads the profile an Erlang project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "erlang" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | Real Erlang files use the preprocessor, macros and conditional directives, and a macro a file
-- defines may stand for part of a form, escripts start with
-- a #! line, and code written for OTP 24 to 28 uses maybe expressions, map comprehensions, and zip
-- and strict generators, so the grammar must read each, or ten of recon's sixteen files and most of
-- OTP's own would be reported as parse failures instead of findings. ref:REQ-erlang-support
-- ref:DEC-erlang-grammar
prop_erlangGrammarReadsMacrosDirectivesAndTheSyntaxOfOtp24To28 :: Property
prop_erlangGrammarReadsMacrosDirectivesAndTheSyntaxOfOtp24To28 = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let source =
        T.unlines
          [ "#!/usr/bin/env escript"
          , "-module(fixture)."
          , "-include_lib(\"eunit/include/eunit.hrl\")."
          , "-define(TIMEOUT, 5000)."
          , "-define(LOG(Format, Args), io:format(Format ++ \"~n\", Args))."
          , "-define(FIELD(R), R#state.field)."
          , "-define(TRY, try)."
          , "-define(MATCH(X), X,)."
          , "-define(OPEN, begin)."
          , "-ifdef(TEST)."
          , "-export([checked/1])."
          , "-else."
          , "-export([unchecked/1])."
          , "-endif."
          , "-if(?OTP_RELEASE >= 27)."
          , "-feature(maybe_expr, enable)."
          , "-endif."
          , "-record(state, {field = 0 :: integer(), other})."
          , "-type id() :: {?MODULE, pos_integer()}."
          , "-callback init(term()) -> {ok, term()}."
          , ""
          , "checked(X) ->"
          , "    N = length(X)-1,"
          , "    ?LOG(\"~p\", [N]),"
          , "    Path = ?DIR \"file.txt\","
          , "    Pid = spawn_link(?MODULE, loop, [?config(pid, X)]),"
          , "    maybe"
          , "        {ok, A} ?= first(X),"
          , "        {ok, B} ?= second(A),"
          , "        {Path, Pid, B}"
          , "    else"
          , "        {error, _} = E -> E"
          , "    end."
          , ""
          , "partial() -> [?MATCH(a) b, ?OPEN ok end]."
          , ""
          , "pairs(M, L1, L2) ->"
          , "    Squares = #{K => V * V || K := V <- M},"
          , "    Zipped = [{A, B} || A <- L1 && B <- L2],"
          , "    Strict = [A || {A, _} <:- L1],"
          , "    {Squares, Zipped, Strict, 1_000_000, 16#FF_FF, $\\^A, $\\x{1F600}}."
          ]
  tree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure (interpretText interpreter (Name "forms") "fixture.erl" source)
  length (treeRuleNodes (Name "functionDefinition") tree) === 3
  length (treeRuleNodes (Name "defineAttribute") tree) === 3
  length (treeRuleNodes (Name "recordAttribute") tree) === 1
  length (treeRuleNodes (Name "typeAttribute") tree) === 1
  length (treeRuleNodes (Name "callbackAttribute") tree) === 1
  length (treeRuleNodes (Name "macroCall") tree) === 5
  length (treeRuleNodes (Name "maybeExpr") tree) === 1
  length (treeRuleNodes (Name "mapComprehension") tree) === 1

-- | Erlang reads X-1 as a subtraction, OTP 27 adds triple-quoted strings and sigils that may hold
-- quotes and span lines, and -doc false hides a function, so the lexer must keep each whole, or a
-- documented OTP 27 module would not parse and a hidden function would be reported as missing its
-- comment. ref:REQ-erlang-support ref:DEC-erlang-grammar
prop_erlangLexerReadsSubtractionTripleQuotedStringsSigilsAndHiddenDocs :: Property
prop_erlangLexerReadsSubtractionTripleQuotedStringsSigilsAndHiddenDocs = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t /= hiddenChannelName]
      named source = [(t, x) | (t, x) <- either (const []) id (typesOf source), not ("T__" `T.isPrefixOf` t)]
  fmap (map snd) (typesOf "X-1") === Right ["X", "-", "1"]
  named "X-1" === [("TokVar", "X"), ("TokInteger", "1")]
  typesOf "\"\"\"\nSays \"hi\".\n\"\"\"" === Right [("TokString", "\"\"\"\nSays \"hi\".\n\"\"\"")]
  typesOf "~\"\"\"\nA \"quoted\" word.\n\"\"\"" === Right [("TokSigil", "~\"\"\"\nA \"quoted\" word.\n\"\"\"")]
  typesOf "~b\"bin\" ~S[raw\\]" === Right [("TokSigil", "~b\"bin\""), ("TokSigil", "~S[raw\\]")]
  named "-doc false." === [("DocHidden", "-doc false")]
  named "-doc(false)." === [("DocHidden", "-doc(false)")]
  named "-moduledoc false." === [("ModuledocHidden", "-moduledoc false")]
  named "-spec f() -> ok." === [("SpecAttrName", "-spec"), ("TokAtom", "f"), ("TokAtom", "ok")]

fixture :: Text
fixture =
  T.unlines
    [ "-module(shapes)."
    , "-moduledoc \"\"\""
    , "Shapes exist to exercise the Erlang profile. ref:some-key"
    , "\"\"\"."
    , "-export([area/1, perimeter/1, hidden/0, internal/0, helper/0])."
    , ""
    , "-doc \"A shape is a circle or a square.\"."
    , "-type shape() :: {circle, float()} | {square, float()}."
    , ""
    , "-record(box, {width :: float(), height :: float()})."
    , ""
    , "%% @doc Areas are what shapes are for."
    , "-spec area(shape()) -> float()."
    , "area({circle, R}) -> 3.0 * R * R;"
    , "area({square, W}) -> W * W."
    , ""
    , "-doc \"\"\""
    , "Perimeters bound a shape."
    , "\"\"\"."
    , ""
    , "-doc #{since => <<\"1.0\">>}."
    , "-spec perimeter(shape()) -> float()."
    , "perimeter({square, W}) -> 4.0 * W."
    , ""
    , "-doc \"Overridden by the -doc false below.\"."
    , "-doc false."
    , "hidden() -> ok."
    , ""
    , "%% @private Kept for the tests."
    , "internal() -> ok."
    , ""
    , "helper() -> ok."
    , ""
    , "%% Squares have the area of their side squared. ref:REQ-1"
    , "square_area_test() -> 4.0 = area({square, 2.0})."
    , ""
    , "uncommented_test() -> ok."
    ]

-- | In Erlang an EDoc comment or an OTP 27 -doc attribute documents the function below its -spec,
-- -doc binds to the next function across blank lines and -doc metadata, -moduledoc documents the
-- module, -doc false and EDoc's @private hide a function, -doc false overrides an earlier -doc, a
-- function is known by its name and arity, and EUnit runs the functions named _test, so the profile
-- must bind, hide, name, and recognise each that way for the Why of an Erlang function to be its
-- documentation. ref:REQ-erlang-support ref:DEC-erlang-grammar
-- ref:DEC-hidden-label
prop_erlangProfileBindsEdocCommentsAndDocAttributesAcrossSpecsAndHidesWhatDocFalseHides :: Property
prop_erlangProfileBindsEdocCommentsAndDocAttributesAcrossSpecsAndHidesWhatDocFalseHides = withTests 1 $ property $ do
  profile <- sampleProfile
  interpreter <- interpreterOrFail
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "erlang" profile interpreter "shapes.erl" "shapes.erl" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u, unitRequirement u) | u <- units, kindOf u /= "file"]
    === [ ("type", "shape/0", Optional)
        , ("record", "box", Optional)
        , ("function", "area/1", Required)
        , ("function", "perimeter/1", Required)
        , ("function", "hidden/0", Hidden)
        , ("function", "internal/0", Hidden)
        , ("function", "helper/0", Required)
        , ("function", "square_area_test/0", Required)
        , ("function", "uncommented_test/0", Required)
        ]
  whyOf "shapes.erl" === ["Shapes exist to exercise the Erlang profile. ref:some-key"]
  whyOf "shape/0" === ["A shape is a circle or a square."]
  whyOf "area/1" === ["@doc Areas are what shapes are for."]
  whyOf "perimeter/1" === ["Perimeters bound a shape."]
  whyOf "hidden/0" === []
  whyOf "internal/0" === ["@private Kept for the tests."]
  length [() | OrphanDocComment _ _ <- findings] === 1
  map (map unitTest . byName) ["square_area_test/0", "uncommented_test/0", "helper/0"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["erlang/shapes.erl/function/helper/0", "erlang/shapes.erl/function/uncommented_test/0"]

-- | The Erlang dialect, under grammars/erlang/canonically_commented, as a project names it.
dialectProfile :: Profile
dialectProfile = Profile [".erl", ".hrl"] (SplitGrammarFiles "grammars/erlang/canonically_commented/ErlangLexer.g4" "grammars/erlang/canonically_commented/ErlangParser.g4") (Name "forms") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | A canonically commented grammar must say in grammar form what Erlang means by documentation: an
-- EDoc comment or an OTP 27 -doc string documents the next function, type, record, or callback
-- whatever attributes come between, the EDoc comment above -module and -moduledoc document the module,
-- -doc false and @private hide, and only what -export lists is public API, so an exported function
-- requires its comment and a private one may have one. ref:REQ-erlang-support ref:DEC-erlang-dialect
-- ref:DEC-hidden-label ref:DEC-export-rule
prop_erlangDialectReadsDocStringsAndEdocCommentsAndRequiresThemOnExportedUnits :: Property
prop_erlangDialectReadsDocStringsAndEdocCommentsAndRequiresThemOnExportedUnits = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "%%% @doc Shapes exist to exercise the Erlang dialect. ref:some-key"
          , "%%% @end"
          , "-module(shapes)."
          , "-moduledoc \"\"\""
          , "Shapes, documented again by OTP 27."
          , "\"\"\"."
          , "-export([area/1, perimeter/1, hidden/0, internal/0, uncommented_test/0])."
          , "-export_type([shape/0])."
          , ""
          , "-doc \"A shape is a circle or a square.\"."
          , "-type shape() :: {circle, float()} | {square, float()}."
          , ""
          , "-record(box, {width :: float(), height :: float()})."
          , ""
          , "-callback draw(shape()) -> ok."
          , ""
          , "%% @doc Areas are what shapes are for."
          , "-dialyzer({nowarn_function, area/1})."
          , "-spec area(shape()) -> float()."
          , "area({circle, R}) -> 3.0 * R * R;"
          , "area({square, W}) -> W * W."
          , ""
          , "-doc \"\"\""
          , "Perimeters bound a shape."
          , "\"\"\"."
          , ""
          , "-doc #{since => <<\"1.0\">>}."
          , "-spec perimeter(shape()) -> float()."
          , "perimeter({square, W}) -> 4.0 * W."
          , ""
          , "-doc \"Overridden by the -doc false below.\"."
          , "-doc false."
          , "hidden() -> ok."
          , ""
          , "%% @private Kept for the tests."
          , "internal() -> ok."
          , ""
          , "helper() -> ?MODULE."
          , ""
          , "uncommented_test() -> ok."
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "erlang" dialectProfile interpreter "shapes.erl" "shapes.erl" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u, unitRequirement u) | u <- units, kindOf u /= "file"]
    === [ ("type", "shape/0", Required)
        , ("record", "box", Optional)
        , ("callback", "draw/1", Required)
        , ("function", "area/1", Required)
        , ("function", "perimeter/1", Required)
        , ("function", "hidden/0", Hidden)
        , ("function", "internal/0", Hidden)
        , ("function", "helper/0", Optional)
        , ("function", "uncommented_test/0", Required)
        ]
  whyOf "shapes.erl" === ["@doc Shapes exist to exercise the Erlang dialect. ref:some-key\n@end\n\nShapes, documented again by OTP 27."]
  whyOf "shape/0" === ["A shape is a circle or a square."]
  whyOf "area/1" === ["@doc Areas are what shapes are for."]
  whyOf "perimeter/1" === ["Perimeters bound a shape."]
  whyOf "internal/0" === ["@private Kept for the tests."]
  length [() | OrphanDocComment _ _ <- findings] === 1
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["erlang/shapes.erl/callback/draw/1", "erlang/shapes.erl/function/uncommented_test/0"]
