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
    , testProperty "the Python dialect knows the top level by nesting, not by column" prop_thePythonDialectKnowsTheTopLevelByNestingNotByColumn
    , testProperty "the Python dialect reads adjacent strings as one docstring" prop_thePythonDialectReadsAdjacentStringsAsOneDocstring
    , testProperty "the Python grammars parse the syntax of Python 3.8 through 3.15" prop_thePythonGrammarsParseTheSyntaxOfPython38Through315
    , testProperty "a module docstring full of backslashes lexes at once" prop_aModuleDocstringFullOfBackslashesLexesAtOnce
    , testProperty "the Python grammars parse a table of many items and a long f-string run in linear time" prop_thePythonGrammarsParseATableOfManyItemsAndALongFStringRunInLinearTime
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
dialectProfile = Profile [".py"] (SplitGrammarFiles "grammars/python/canonically_commented/Python3Lexer.g4" "grammars/python/canonically_commented/Python3Parser.g4") (Name "file_input") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

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

-- | A module exports what it defines outside every def and class, inside a module-level if, try, or
-- with block as much as at its first column, so such a definition requires a docstring, while a
-- definition in a function or class body is no export of the module. ref:REQ-python-support
-- ref:DEC-python-dialect ref:pep-257
prop_thePythonDialectKnowsTheTopLevelByNestingNotByColumn :: Property
prop_thePythonDialectKnowsTheTopLevelByNestingNotByColumn = withTests 1 $ property $ do
  Extraction model _ <-
    extractWith
      dialectProfile
      "compat.py"
      ( T.unlines
          [ "import sys"
          , ""
          , "if sys.version_info >= (3, 8):"
          , "    def fast():"
          , "        pass"
          , "else:"
          , "    def fast():"
          , "        \"\"\"The slow fallback.\"\"\""
          , ""
          , "try:"
          , "    class Loader:"
          , "        pass"
          , "except ImportError:"
          , "    pass"
          , ""
          , "def outer():"
          , "    \"\"\"Defines a helper.\"\"\""
          , "    if True:"
          , "        def inner():"
          , "            pass"
          , "    return inner"
          , ""
          , "def one(): pass"
          , "def two():"
          , "    pass"
          , ""
          , "class _Private:"
          , "    def method(self):"
          , "        pass"
          , "    with open(__file__) as f:"
          , "        class Inside:"
          , "            pass"
          ]
      )
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "python/compat.py/function/fast"
        , "python/compat.py/class/Loader"
        , "python/compat.py/function/one"
        , "python/compat.py/function/two"
        ]

-- | Python joins adjacent string literals into one string, so a docstring written as several strings
-- side by side is one docstring, read whole with its citations. ref:REQ-python-support
-- ref:DEC-python-dialect ref:pep-257
prop_thePythonDialectReadsAdjacentStringsAsOneDocstring :: Property
prop_thePythonDialectReadsAdjacentStringsAsOneDocstring = withTests 1 $ property $ do
  Extraction model findings <-
    extractWith
      dialectProfile
      "joined.py"
      ( T.unlines
          [ "def joined():"
          , "    \"Joined from two strings, \" 'cited. ref:some-key'"
          , "    return 1"
          , ""
          , "def mixed():"
          , "    \"A bytes string \" b\"is no docstring.\""
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d)), whyReferences (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys === [("python/joined.py/function/joined", "Joined from two strings, cited. ref:some-key", [ReferenceKey "some-key"])]
  length [() | OrphanDocComment _ _ <- findings] === 0

-- | Current projects are written in the Python their interpreter runs, so both grammars must read
-- what Python 3.8 through 3.15 added: named expressions, positional-only lambda parameters, any
-- expression as a decorator, parenthesized context managers, starred items in a return, a for, and a
-- subscript, match on a tuple with case as a soft keyword, except*, except without parentheses, type
-- parameters and type aliases, lazy imports, digits grouped by underscores, f-strings whose fields
-- hold strings in the same quotes, and t-strings, which are no docstring. ref:REQ-python-support
-- ref:DEC-python-grammar ref:DEC-python-dialect
prop_thePythonGrammarsParseTheSyntaxOfPython38Through315 :: Property
prop_thePythonGrammarsParseTheSyntaxOfPython38Through315 = withTests 1 $ property $ do
  profile <- sampleProfile
  Extraction plain _ <- extractWith profile "modern.py" modern
  [(unitKindText (whatKind (answerValue (unitWhat u))), whatName (answerValue (unitWhat u))) | u <- unitsBelowFile plain]
    === [("function", "first"), ("class", "Box"), ("function", "items"), ("function", "matcher")]
  Extraction model findings <- extractWith dialectProfile "modern.py" modern
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("python/modern.py", "Modern syntax, Python 3.8 to 3.15.")
        , ("python/modern.py/function/first", "Type parameters, positional-only, and a starred annotation.")
        , ("python/modern.py/class/Box", "A generic class.")
        , ("python/modern.py/class/Box/function/items", "Parenthesized context managers, except*, and except without parentheses.")
        , ("python/modern.py/function/matcher", "A match on a tuple, with a guard.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 0
  where
    modern =
      T.unlines
          [ "\"\"\"Modern syntax, Python 3.8 to 3.15.\"\"\""
          , "lazy import json"
          , "lazy from os import path"
          , "import re as _re"
          , ""
          , "type Pair[T] = tuple[T, T]"
          , "type = \"a soft keyword is still a name\""
          , "case = match = lazy = 0"
          , ""
          , "total = 1_000_000 + 0x_ff + 1_0.5e1_0 + 3_0j"
          , ""
          , "@registry[0].register"
          , "def first[T: int = int, *Ts, **P](x, /, *args: *Ts, **kw) -> T:"
          , "    \"\"\"Type parameters, positional-only, and a starred annotation.\"\"\""
          , "    if (n := len(args)) > 1:"
          , "        return *args, n"
          , "    return f\"{kw[\"key\"]!r:>{n}} {'\\N{EM DASH}'} {f'{x}'}\""
          , ""
          , "class Box[T](Base):"
          , "    \"\"\"A generic class.\"\"\""
          , ""
          , "    def items(self):"
          , "        \"\"\"Parenthesized context managers, except*, and except without parentheses.\"\"\""
          , "        with (open(a) as f,"
          , "              open(b) as g,):"
          , "            try:"
          , "                pass"
          , "            except* ValueError as group:"
          , "                pass"
          , "        try:"
          , "            pass"
          , "        except KeyError, IndexError:"
          , "            pass"
          , "        for x in *self.a, *self.b:"
          , "            yield self.c[*x]"
          , ""
          , "def matcher(command):"
          , "    \"\"\"A match on a tuple, with a guard.\"\"\""
          , "    match command.verb, command.obj:"
          , "        case (\"go\", direction) if (d := direction):"
          , "            return d"
          , "        case _:"
          , "            return t\"unknown {command}\""
          ]

-- | A backslash in a string escapes one character. The upstream lexer also let it escape a NEWLINE
-- token, which at the start of a file matched the spaces after a backslash a second way, so a module
-- docstring drawing a diagram in backslashes took seconds to lex and longer with each backslash; it
-- must lex at once, as the corpus requires of every file. ref:REQ-python-support
-- ref:DEC-python-grammar
prop_aModuleDocstringFullOfBackslashesLexesAtOnce :: Property
prop_aModuleDocstringFullOfBackslashesLexesAtOnce = withTests 1 $ property $ do
  profile <- sampleProfile
  Extraction model _ <- extractWith profile "diagram.py" (T.unlines (["r\"\"\"A diagram."] ++ replicate 60 "   / \\   / \\   / \\" ++ ["\"\"\"", "", "def f():", "    pass"]))
  [whatName (answerValue (unitWhat u)) | u <- unitsBelowFile model] === ["f"]

-- | A rule that ended inside a run of items built a tree for each item it could end after, so a list
-- of n items took time in n squared and a table of a few thousand numbers took seconds; the items
-- of a display, a call, and a subscript are read in the rule that holds their brackets. An f-string
-- field read in two ways, as one long string or as short ones, went on through every later string of
-- the file in each reading when one did not close; three quotes now always open a long string, so a
-- field has one reading. ref:REQ-python-support ref:DEC-python-grammar
prop_thePythonGrammarsParseATableOfManyItemsAndALongFStringRunInLinearTime :: Property
prop_thePythonGrammarsParseATableOfManyItemsAndALongFStringRunInLinearTime = withTests 1 $ property $ do
  profile <- sampleProfile
  Extraction plain _ <- extractWith profile "tables.py" source
  [whatName (answerValue (unitWhat u)) | u <- unitsBelowFile plain] === ["lookup"]
  Extraction model _ <- extractWith dialectProfile "tables.py" source
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["python/tables.py/function/lookup"]
  where
    source =
      T.unlines
        ( ["TABLE = [", "    f(1, 2), {'a': 1}, x[1:2], (3, 4),"]
            ++ replicate 3000 "    0x00, 0x41, 0x0300, 0x00c0, 0x00, 0x41, 0x0301, 0x00c1,"
            ++ ["]", "", "def lookup(key):", "    return f'{\"\"\"a\" # inside\"\"\"=}'"]
            ++ replicate 40 "TEXT = '''a''' + \"\"\"b\"\"\""
        )
