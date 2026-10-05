-- | Python is read through the vendored grammars-v4 Python grammar, the profile the itsdangerous
-- sample ships, and the canonically commented dialect, so these properties check all three against
-- what a Python author means by a definition and its docstring. ref:DEC-more-languages
-- ref:DEC-python-dialect ref:REQ-python-support
module Canon.Extract.PythonTest (tests) where

import Canon.Antlr4.Interpret (renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Data.List (sort)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (listDirectory)
import System.FilePath (normalise, takeExtension, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "python"
    [ testProperty "the Python grammar and profile parse every file of the itsdangerous sample into its definitions" prop_thePythonGrammarAndProfileParseEveryFileOfTheItsdangerousSampleIntoItsDefinitions
    , testProperty "the Python profile binds docstrings to definitions and recognises tests" prop_thePythonProfileBindsDocstringsToDefinitionsAndRecognisesTests
    , testProperty "the Python dialect parses every file of the itsdangerous sample with its docstrings" prop_thePythonDialectParsesEveryFileOfTheItsdangerousSampleWithItsDocstrings
    , testProperty "the Python dialect binds docstrings that open a body and requires them on public names" prop_thePythonDialectBindsDocstringsThatOpenABodyAndRequiresThemOnPublicNames
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/python-itsdangerous"

-- | The directories of the sample that hold Python sources, relative to its source root.
sampleSourceDirs :: [FilePath]
sampleSourceDirs = ["src/itsdangerous", "tests/test_itsdangerous"]

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Python project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "python" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the Python grammar, with no units of a profile, so every
-- unit comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".py"] (SplitGrammarFiles "grammars/python/canonically_commented/Python3Lexer.g4" "grammars/python/canonically_commented/Python3Parser.g4") (Name "file_input") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | An extraction of one source text through a profile.
extractWith :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractWith profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "python" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Every Python file of the sample, each extracted through a profile under its path from the
-- source root, in name order.
extractSample :: Profile -> PropertyT IO [(FilePath, Extraction)]
extractSample profile = do
  paths <- evalIO (concat <$> mapM (\dir -> map (dir </>) . sort . filter ((== ".py") . takeExtension) <$> listDirectory (sampleDir </> "source" </> dir)) sampleSourceDirs)
  mapM (\path -> evalIO (T.pack <$> readFile (sampleDir </> "source" </> path)) >>= fmap ((,) path) . extractWith profile path) paths

-- | The units of a model below its file unit.
unitsBelowFile :: Model Evidence -> [CodeUnit Evidence]
unitsBelowFile model = [u | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]

-- | A real package must parse whole, with every function and class it defines found where Python
-- finds them, or a Python project's check would report parse failures instead of findings.
-- ref:REQ-python-support ref:DEC-more-languages
prop_thePythonGrammarAndProfileParseEveryFileOfTheItsdangerousSampleIntoItsDefinitions :: Property
prop_thePythonGrammarAndProfileParseEveryFileOfTheItsdangerousSampleIntoItsDefinitions = withTests 1 $ property $ do
  profile <- sampleProfile
  extractions <- extractSample profile
  let units = concatMap (unitsBelowFile . extractionModel . snd) extractions
      kinds = [unitKindText (whatKind (answerValue (unitWhat u))) | u <- units]
  (length extractions, length units, length (filter (== "function") kinds), length (filter (== "class") kinds), length (filter unitTest units), length (concatMap (modelDecisions . extractionModel . snd) extractions)) === (14, 144, 115, 29, 43, 50)

-- | In Python a docstring is the string that opens a body, a # comment documents nothing, and pytest
-- runs functions named test_ and classes named Test, so the profile must bind and recognise each that
-- way for the Why of a Python definition to be its docstring. ref:REQ-python-support
-- ref:DEC-more-languages
prop_thePythonProfileBindsDocstringsToDefinitionsAndRecognisesTests :: Property
prop_thePythonProfileBindsDocstringsToDefinitionsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  Extraction model _ <-
    extractWith
      profile
      "test_shapes.py"
      ( T.unlines
          [ "\"\"\"Shapes exercise the Python profile.\"\"\""
          , ""
          , "class Shape:"
          , "    \"\"\"A shape has an area.\"\"\""
          , ""
          , "    def area(self):"
          , "        \"\"\"The area of the shape.\"\"\""
          , "        return 0"
          , ""
          , "class TestShape:"
          , "    def test_area_is_zero(self):"
          , "        \"\"\"A bare shape has no area. ref:REQ-1\"\"\""
          , "        assert Shape().area() == 0"
          , ""
          , "def helper():"
          , "    pass"
          ]
      )
  let units = unitsBelowFile model
      nameOf u = whatName (answerValue (unitWhat u))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- modelAllUnits model, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(unitKindText (whatKind (answerValue (unitWhat u))), nameOf u, unitTest u) | u <- units]
    === [("class", "Shape", False), ("function", "area", False), ("class", "TestShape", True), ("function", "test_area_is_zero", True), ("function", "helper", False)]
  whyOf "test_shapes.py" === ["Shapes exercise the Python profile."]
  whyOf "Shape" === ["A shape has an area."]
  whyOf "area" === ["The area of the shape."]
  whyOf "test_area_is_zero" === ["A bare shape has no area. ref:REQ-1"]
  whyOf "helper" === []
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "areas" "here"))) model] === []

-- | Docstrings are strings the dialect places, so real Python must still parse whole with every
-- module, class, and function body read for one, and find the definitions the profile finds.
-- ref:REQ-python-support ref:DEC-python-dialect
prop_thePythonDialectParsesEveryFileOfTheItsdangerousSampleWithItsDocstrings :: Property
prop_thePythonDialectParsesEveryFileOfTheItsdangerousSampleWithItsDocstrings = withTests 1 $ property $ do
  extractions <- extractSample dialectProfile
  let models = map (extractionModel . snd) extractions
      units = concatMap unitsBelowFile models
      kinds = [unitKindText (whatKind (answerValue (unitWhat u))) | u <- units]
  (length extractions, length units, length (filter (== "function") kinds), length (filter (== "class") kinds), length (concatMap modelDecisions models)) === (14, 144, 115, 29, 48)
  length [() | (_, Extraction _ findings) <- extractions, OrphanDocComment _ _ <- findings] === 0
  length (filter unitTest units) === 43

-- | In the dialect the grammar says where a docstring binds: the string that opens a module, class,
-- or function body, while a string elsewhere, a # comment, and an f-string are no documentation. A
-- public top-level name requires one, and so does a public method of a public class, __init__
-- included, while a private or dunder name, an @overload stub, and a nested function need none.
-- ref:REQ-python-support ref:DEC-python-dialect
prop_thePythonDialectBindsDocstringsThatOpenABodyAndRequiresThemOnPublicNames :: Property
prop_thePythonDialectBindsDocstringsThatOpenABodyAndRequiresThemOnPublicNames = withTests 1 $ property $ do
  Extraction model findings <-
    extractWith
      dialectProfile
      "shapes.py"
      ( T.unlines
          [ "#!/usr/bin/env python"
          , "# A comment is no documentation."
          , "\"\"\"The module exercises the dialect. ref:some-key\"\"\""
          , ""
          , "import functools"
          , ""
          , "def public():"
          , "    \"\"\"A public function documents itself.\"\"\""
          , "    x = 1"
          , "    \"\"\"A string after a statement is no documentation.\"\"\""
          , "    return x"
          , ""
          , "def undocumented():"
          , "    pass"
          , ""
          , "def _private():"
          , "    pass"
          , ""
          , "@functools.lru_cache"
          , "async def cached():"
          , "    '''Async and decorated.'''"
          , ""
          , "class Shape:"
          , "    \"\"\"A shape has an area.\"\"\""
          , ""
          , "    def __init__(self):"
          , "        pass"
          , ""
          , "    def area(self):"
          , "        r\"\"\"The area of the shape.\"\"\""
          , "        if True:"
          , "            \"\"\"A string in an if body is no documentation.\"\"\""
          , "        return 0"
          , ""
          , "    def __repr__(self):"
          , "        return 'Shape'"
          , ""
          , "    def _helper(self):"
          , "        def nested():"
          , "            pass"
          , "        return nested"
          , ""
          , "    @typing.overload"
          , "    def scale(self, k: int) -> 'Shape': ..."
          , ""
          , "class _Hidden:"
          , "    def visible(self):"
          , "        pass"
          , ""
          , "def one_liner(): \"\"\"A docstring on the def line.\"\"\""
          , ""
          , "def formatted():"
          , "    f\"\"\"An f-string is no docstring.\"\"\""
          , ""
          , "class TestShape:"
          , "    def test_area_is_zero(self):"
          , "        \"\"\"A bare shape has no area. ref:REQ-1\"\"\""
          , ""
          , "    def test_uncommented(self):"
          , "        pass"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("python/shapes.py", "The module exercises the dialect. ref:some-key")
        , ("python/shapes.py/function/public", "A public function documents itself.")
        , ("python/shapes.py/function/cached", "Async and decorated.")
        , ("python/shapes.py/class/Shape", "A shape has an area.")
        , ("python/shapes.py/class/Shape/function/area", "The area of the shape.")
        , ("python/shapes.py/function/one_liner", "A docstring on the def line.")
        , ("python/shapes.py/class/TestShape/function/test_area_is_zero", "A bare shape has no area. ref:REQ-1")
        ]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model, NonEmpty.head (decisionUnits d) == UnitId ("python" NonEmpty.:| ["shapes.py"])] === [[ReferenceKey "some-key"]]
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "python/shapes.py/function/undocumented"
        , "python/shapes.py/class/Shape/function/__init__"
        , "python/shapes.py/function/formatted"
        , "python/shapes.py/class/TestShape"
        , "python/shapes.py/class/TestShape/function/test_uncommented"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "areas" "here"))) model] === []
