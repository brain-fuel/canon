-- | Clojure is read through the vendored grammars-v4 Clojure grammar with the profile the hiccup
-- sample ships, and through its canonically commented dialect, so these properties check both
-- against what a Clojure author means by a definition and its docstring. ref:DEC-clojure-dialect
-- ref:DEC-clojure-grammar-fixes ref:REQ-clojure-support
module Canon.Extract.ClojureTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), loadCombinedInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..), defaultChannelName, isEofToken)
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (emptyRegistry)
import Control.Monad (filterM, forM)
import Data.List (isSuffixOf, sort)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (makeRelative, normalise, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "clojure"
    [ testProperty "the Clojure lexer reads keywords and strings as the Clojure reader does" prop_theClojureLexerReadsKeywordsAndStringsAsTheClojureReaderDoes
    , testProperty "the Clojure grammar and profile parse every file of the hiccup sample" prop_theClojureGrammarAndProfileParseEveryFileOfTheHiccupSample
    , testProperty "the Clojure profile binds comments above definitions and recognises tests" prop_theClojureProfileBindsCommentsAboveDefinitionsAndRecognisesTests
    , testProperty "the Clojure dialect parses every file of the hiccup sample with its docstrings" prop_theClojureDialectParsesEveryFileOfTheHiccupSampleWithItsDocstrings
    , testProperty "the Clojure dialect binds docstrings to definitions, requires them on public API, and reports misplaced ones" prop_theClojureDialectBindsDocstringsToDefinitionsRequiresThemOnPublicApiAndReportsMisplacedOnes
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/clojure-hiccup"

-- | Every Clojure file of the sample's sources, relative to them, in a stable order.
sampleFiles :: IO [FilePath]
sampleFiles = sort . map (makeRelative root) <$> go root
  where
    root = sampleDir </> "source"
    go dir = do
      entries <- map (dir </>) <$> listDirectory dir
      dirs <- filterM doesDirectoryExist entries
      nested <- concat <$> mapM go dirs
      pure ([e | e <- entries, e `notElem` dirs, any (`isSuffixOf` e) [".clj", ".cljc", ".cljs"]] ++ nested)

-- | The profile as the sample's canon.yaml declares it, with its grammar path made relative to the
-- repository root, so the test reads the profile a Clojure project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "clojure" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the Clojure grammar, with no units of a profile, so every
-- unit comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".clj"] (CombinedGrammarFile "grammars/clojure/canonically_commented/Clojure.g4") (Name "file_") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | Extracts every file of the sample through a profile, failing on the first that does not parse.
extractSample :: Profile -> PropertyT IO [(FilePath, Extraction)]
extractSample profile = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  files <- evalIO sampleFiles
  forM files $ \file -> do
    source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
    result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "clojure" profile interpreter file file source)
    either (\e -> annotate file >> annotate (T.unpack (renderGrammarExtractError e)) >> failure) (\x -> pure (file, x)) result

-- | Extracts one source text through a profile.
extractText :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractText profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "clojure" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The units of a model below its file, as kind and name.
unitsOf :: Model Evidence -> [(Text, Text)]
unitsOf model = [(unitKindText (whatKind w), whatName w) | w <- map (answerValue . unitWhat) (drop 1 (modelAllUnits model))]

-- | Each decision of a model as the unit it binds to and its Why.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]

-- | The Clojure reader reads a keyword as one token of whatever constituent characters follow the
-- colon, so :1.8 and :div#id are keywords, and a backslash in a string always escapes the next
-- character, so "\\" ends at its second quote; upstream's grammar split the first and ran the
-- second on to the next string. ref:REQ-clojure-support ref:DEC-clojure-grammar-fixes
prop_theClojureLexerReadsKeywordsAndStringsAsTheClojureReaderDoes :: Property
prop_theClojureLexerReadsKeywordsAndStringsAsTheClojureReaderDoes = withTests 1 $ property $ do
  loaded <- evalIO (loadCombinedInterpreter "grammars/clojure/Clojure.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t == defaultChannelName]
  typesOf "{:1.8 [:div#foo.bar] ::local :ns/key}"
    === Right [("T__4", "{"), ("KEYWORD", ":1.8"), ("T__2", "["), ("KEYWORD", ":div#foo.bar"), ("T__3", "]"), ("MACRO_KEYWORD", "::local"), ("KEYWORD", ":ns/key"), ("T__5", "}")]
  typesOf "(str \"a\\\\\" \"b\\\"c\")" === Right [("T__0", "("), ("SYMBOL", "str"), ("STRING", "\"a\\\\\""), ("STRING", "\"b\\\"c\""), ("T__1", ")")]

-- | A Clojure project's check reports findings only if every file parses, with each definition form
-- the profile names, so the grammar and the profile a Clojure project copies must read all of
-- hiccup, its project.clj and tests included. ref:REQ-clojure-support ref:DEC-clojure-grammar-fixes
prop_theClojureGrammarAndProfileParseEveryFileOfTheHiccupSample :: Property
prop_theClojureGrammarAndProfileParseEveryFileOfTheHiccupSample = withTests 1 $ property $ do
  profile <- sampleProfile
  extracted <- extractSample profile
  length extracted === 21
  length [() | (_, Extraction model _) <- extracted, _ <- unitsOf model] === 180

-- | Without a dialect, a Clojure comment is bound by the line-adjacency rule, and a deftest is a test
-- whatever it is named, so the profile must bind a ; comment to the definition below it and
-- recognise every deftest of the sample. ref:REQ-clojure-support ref:DEC-clojure-dialect
prop_theClojureProfileBindsCommentsAboveDefinitionsAndRecognisesTests :: Property
prop_theClojureProfileBindsCommentsAboveDefinitionsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  extracted <- extractSample profile
  length [() | (_, Extraction model _) <- extracted, u <- modelAllUnits model, unitTest u] === 67
  Extraction fixture _ <-
    extractText
      profile
      "checks.clj"
      ( T.unlines
          [ "(ns checks)"
          , ""
          , ";; Squares are what checks are for."
          , "(defn square [x] (* x x))"
          , ""
          , "(deftest square-of-two-is-four (is (= 4 (square 2))))"
          ]
      )
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- drop 1 (modelAllUnits fixture)]
    === [("checks", False), ("square", False), ("square-of-two-is-four", True)]
  whysOf fixture === [("clojure/checks.clj/definition/square", "Squares are what checks are for.")]

-- | Docstrings are strings the dialect reads by where they stand, so real Clojure must still parse
-- whole, with each definition and its docstring found and no string mistaken for a misplaced
-- docstring. ref:REQ-clojure-support ref:DEC-clojure-dialect
prop_theClojureDialectParsesEveryFileOfTheHiccupSampleWithItsDocstrings :: Property
prop_theClojureDialectParsesEveryFileOfTheHiccupSampleWithItsDocstrings = withTests 1 $ property $ do
  extracted <- extractSample dialectProfile
  length extracted === 21
  let models = [model | (_, Extraction model _) <- extracted]
      kinds = [k | model <- models, (k, _) <- unitsOf model]
      count k = length (filter (== k) kinds)
  map count ["function", "macro", "multimethod", "protocol", "method", "record", "type", "var", "deftest"] === [57, 11, 2, 4, 4, 0, 1, 9, 64]
  sum (map (length . modelDecisions) models) === 60
  length [() | (_, Extraction _ findings) <- extracted, OrphanDocComment _ _ <- findings] === 0
  length [() | model <- models, u <- modelAllUnits model, unitTest u] === 64
  length [() | model <- models, MissingCanonicalComment _ _ <- checkModel emptyRegistry emptyLedger model] === 73

-- | In the dialect the grammar says where a docstring binds and what needs one: after the name of a
-- function, a macro, a multimethod, a protocol and each of its methods, and a def with a value, or
-- in :doc metadata, and the ns docstring is the file's; a string after a function's parameters with
-- more body after it is a misplaced docstring and is reported. A public function, macro,
-- multimethod, or protocol needs a docstring, a test needs a Why, and defn-, ^:private, and ^:no-doc
-- definitions do not. ref:REQ-clojure-support ref:DEC-clojure-dialect
prop_theClojureDialectBindsDocstringsToDefinitionsRequiresThemOnPublicApiAndReportsMisplacedOnes :: Property
prop_theClojureDialectBindsDocstringsToDefinitionsRequiresThemOnPublicApiAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "shapes.clj"
      ( T.unlines
          [ "(ns shapes"
          , "  \"Shapes and their areas. ref:some-key"
          , "  Each shape is a map with a \\\"kind\\\".\""
          , "  (:require [clojure.string :as str]))"
          , ""
          , ";; A plain comment is not documentation."
          , "(defn area"
          , "  \"The area of a shape. ref:REQ-area\""
          , "  [shape]"
          , "  (* (:w shape) (:h shape)))"
          , ""
          , "(defn perimeter [shape]"
          , "  \"After the parameters, so a misplaced docstring.\""
          , "  (* 2 (+ (:w shape) (:h shape))))"
          , ""
          , "(defn describe [shape] \"A string that is the body's value.\")"
          , ""
          , "(defn- helper [x] x)"
          , ""
          , "(defn ^:private hidden [x] x)"
          , ""
          , "(def ^{:doc \"The unit square.\" :added \"1.0\"} unit {:w 1 :h 1})"
          , ""
          , "(def origin \"The origin, a string value.\")"
          , ""
          , "(def scale \"How much to scale by.\" 2)"
          , ""
          , "(defmacro with-shape \"Binds a shape.\" [s & body] `(let [~'shape ~s] ~@body))"
          , ""
          , "(defmulti draw \"Draws a shape by its kind.\" :kind)"
          , ""
          , "(defmethod draw :square [s] s)"
          , ""
          , "(defprotocol Scalable"
          , "  \"Things that scale.\""
          , "  (scale-by [s k] \"Scales by k.\")"
          , "  (reset [s]))"
          , ""
          , "(defrecord Square [w h])"
          , ""
          , "(deftest ^{:doc \"Squares have area w*h. ref:REQ-area\"} square-area"
          , "  (is (= 4 (area {:w 2 :h 2}))))"
          , ""
          , "(deftest uncommented-test (is true))"
          ]
      )
  whysOf model
    === [ ("clojure/shapes.clj", "Shapes and their areas. ref:some-key\nEach shape is a map with a \"kind\".")
        , ("clojure/shapes.clj/function/area", "The area of a shape. ref:REQ-area")
        , ("clojure/shapes.clj/var/unit", "The unit square.")
        , ("clojure/shapes.clj/var/scale", "How much to scale by.")
        , ("clojure/shapes.clj/macro/with-shape", "Binds a shape.")
        , ("clojure/shapes.clj/multimethod/draw", "Draws a shape by its kind.")
        , ("clojure/shapes.clj/protocol/Scalable", "Things that scale.")
        , ("clojure/shapes.clj/protocol/Scalable/method/scale-by", "Scales by k.")
        , ("clojure/shapes.clj/deftest/square-area", "Squares have area w*h. ref:REQ-area")
        ]
  [(renderUnitId (NonEmpty.head (decisionUnits d)), whyReferences (answerValue (decisionWhy d))) | d <- take 2 (modelDecisions model)]
    === [("clojure/shapes.clj", [ReferenceKey "some-key"]), ("clojure/shapes.clj/function/area", [ReferenceKey "REQ-area"])]
  length [() | OrphanDocComment _ _ <- findings] === 1
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "clojure/shapes.clj/function/perimeter"
        , "clojure/shapes.clj/function/describe"
        , "clojure/shapes.clj/protocol/Scalable/method/reset"
        , "clojure/shapes.clj/deftest/uncommented-test"
        ]
