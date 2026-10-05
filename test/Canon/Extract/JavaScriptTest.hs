-- | JavaScript is read through the grammars-v4 JavaScript grammar and the profile the chalk sample
-- ships, and through the grammar's canonically commented dialect, so these properties check both
-- against what a JavaScript author means by a declaration and its JSDoc comment.
-- ref:DEC-more-languages ref:DEC-javascript-dialect ref:REQ-javascript-support
module Canon.Extract.JavaScriptTest (tests) where

import Canon.Antlr4.Interpret (renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (emptyRegistry)
import Canon.Walk (Walked (..), walkProject)
import Data.List (stripPrefix)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
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
    "javascript"
    [ testProperty "the JavaScript profile parses every file of the chalk sample into its units" prop_theJavaScriptProfileParsesEveryFileOfTheChalkSampleIntoItsUnits
    , testProperty "the JavaScript profile binds JSDoc to the declaration below and treats test-directory units as tests" prop_theJavaScriptProfileBindsJsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests
    , testProperty "the JavaScript dialect parses the chalk sample with its doc comments" prop_theJavaScriptDialectParsesTheChalkSampleWithItsDocComments
    , testProperty "the JavaScript dialect binds JSDoc to declarations and reports misplaced ones" prop_theJavaScriptDialectBindsJsDocToDeclarationsAndReportsMisplacedOnes
    , testProperty "the first JSDoc comment of a file is the file's Why only when it says so" prop_theFirstJsDocCommentOfAFileIsTheFilesWhyOnlyWhenItSaysSo
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/javascript-chalk"

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a JavaScript project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "javascript" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the JavaScript grammar, with no units of a profile, so every
-- unit comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".js", ".mjs", ".cjs"] (SplitGrammarFiles "grammars/javascript/canonically_commented/JavaScriptLexer.g4" "grammars/javascript/canonically_commented/JavaScriptParser.g4") (Name "program") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | The JavaScript files of the sample, as canon check finds them, relative to its source root.
sampleFiles :: PropertyT IO [FilePath]
sampleFiles = do
  walked <- evalIO (walkProject [] [".js", ".mjs", ".cjs"] "canon.yaml" root)
  pure [fromMaybe path (stripPrefix (root ++ "/") path) | path <- walkedFiles walked]
  where
    root = sampleDir </> "source"

-- | An extraction of text through a profile.
extractText :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractText profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "javascript" profile interpreter path path source)
  either (\e -> annotate (path ++ ": " ++ T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Extracts every file of the sample through a profile.
extractSample :: Profile -> PropertyT IO [Extraction]
extractSample profile = do
  files <- sampleFiles
  mapM (\file -> evalIO (T.pack <$> readFile (sampleDir </> "source" </> file)) >>= extractText profile file) files

-- | The units of a model below its files.
unitsOf :: Model Evidence -> [CodeUnit Evidence]
unitsOf model = [u | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]

-- | A real package must parse whole, every function, class, and method found where the language
-- puts them, or a JavaScript project's check would report parse failures instead of findings.
-- ref:REQ-javascript-support ref:DEC-more-languages
prop_theJavaScriptProfileParsesEveryFileOfTheChalkSampleIntoItsUnits :: Property
prop_theJavaScriptProfileParsesEveryFileOfTheChalkSampleIntoItsUnits = withTests 1 $ property $ do
  profile <- sampleProfile
  extractions <- extractSample profile
  length extractions === 16
  sum [length (unitsOf model) | Extraction model _ <- extractions] === 14

-- | A JSDoc comment documents the declaration below it, and a test in JavaScript is a call to a test
-- runner rather than a declaration, so every unit under a test directory is a test and needs the
-- comment that cites its requirement. ref:REQ-javascript-support ref:DEC-more-languages
prop_theJavaScriptProfileBindsJsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests :: Property
prop_theJavaScriptProfileBindsJsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests = withTests 1 $ property $ do
  profile <- sampleProfile
  let source = T.unlines ["import chalk from 'chalk';", "", "/** Doubles a number. ref:REQ-1 */", "function double(n) { return n * 2; }", "", "class Shape {", "  /** The area. */", "  area() { return 0; }", "}"]
  Extraction library _ <- extractText profile "source/lib.js" source
  Extraction testFile _ <- extractText profile "test/lib.js" source
  let whys model = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys library
    === [ ("javascript/source/lib.js/function/double", "Doubles a number. ref:REQ-1")
        , ("javascript/source/lib.js/class/Shape/method/area", "The area.")
        ]
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- unitsOf library] === [("double", False), ("Shape", False), ("area", False)]
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- unitsOf testFile] === [("double", True), ("Shape", True), ("area", True)]

-- | JSDoc comments are tokens of the dialect, so a real package must still parse whole with them,
-- and its units, among them module-level bindings and the members of exported classes, must be
-- found. ref:REQ-javascript-support ref:DEC-javascript-dialect
prop_theJavaScriptDialectParsesTheChalkSampleWithItsDocComments :: Property
prop_theJavaScriptDialectParsesTheChalkSampleWithItsDocComments = withTests 1 $ property $ do
  extractions <- extractSample dialectProfile
  length extractions === 16
  sum [length (unitsOf model) | Extraction model _ <- extractions] === 58
  sum [length (modelDecisions model) | Extraction model _ <- extractions] === 0
  sum [length [() | OrphanDocComment _ _ <- findings] | Extraction _ findings <- extractions] === 0

-- | In the dialect the grammar says where a JSDoc comment binds: to the function, class, member,
-- module-level binding, or export default below it, as JSDoc reads it; one before any other
-- statement, inside an expression, or after the last member binds to nothing and is reported. What
-- a module exports requires one, the members of an exported class included, and a #private member
-- never does. ref:REQ-javascript-support ref:DEC-javascript-dialect
prop_theJavaScriptDialectBindsJsDocToDeclarationsAndReportsMisplacedOnes :: Property
prop_theJavaScriptDialectBindsJsDocToDeclarationsAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "lib.js"
      ( T.unlines
          [ "import fs from 'node:fs';"
          , ""
          , "/** Doubles a number. ref:some-key */"
          , "export function double(n) {"
          , "  /** Above a statement, so an orphan. */"
          , "  const x = n * 2;"
          , "  return /** @type {number} */ (x);"
          , "}"
          , ""
          , "function helper() {}"
          , ""
          , "/**"
          , " * A shape."
          , " * @see {@link double}"
          , " */"
          , "export class Shape {"
          , "  /** The area. */"
          , "  area() {}"
          , "  get size() { return 1; }"
          , "  set size(v) {}"
          , "  #secret = 1;"
          , "  static make() {}"
          , "  /** After the last member, so an orphan. */"
          , "}"
          , ""
          , "/** A limit. */"
          , "export const LIMIT = 10;"
          , "let local = 1;"
          , "export const arrow = () => 1;"
          , "/*** A plain comment. */"
          , "/** The default export. */"
          , "export default {LIMIT};"
          , "export {helper};"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("javascript/lib.js/function/double", "Doubles a number. ref:some-key")
        , ("javascript/lib.js/class/Shape", "A shape.\n@see {@link double}")
        , ("javascript/lib.js/class/Shape/method/area", "The area.")
        , ("javascript/lib.js/variable/LIMIT", "A limit.")
        , ("javascript/lib.js/export/default", "The default export.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [(renderUnitId (unitId u), unitRequirement u == Required) | u <- unitsOf model]
    === [ ("javascript/lib.js/function/double", True)
        , ("javascript/lib.js/function/helper", False)
        , ("javascript/lib.js/class/Shape", True)
        , ("javascript/lib.js/class/Shape/method/area", True)
        , ("javascript/lib.js/class/Shape/accessor/get-size", True)
        , ("javascript/lib.js/class/Shape/accessor/set-size", True)
        , ("javascript/lib.js/class/Shape/field/#secret", False)
        , ("javascript/lib.js/class/Shape/method/make", True)
        , ("javascript/lib.js/variable/LIMIT", True)
        , ("javascript/lib.js/variable/local", False)
        , ("javascript/lib.js/variable/arrow", True)
        , ("javascript/lib.js/export/default", True)
        ]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "javascript/lib.js/class/Shape/accessor/get-size"
        , "javascript/lib.js/class/Shape/accessor/set-size"
        , "javascript/lib.js/class/Shape/method/make"
        , "javascript/lib.js/variable/arrow"
        ]

-- | A file's first JSDoc comment documents the file when JSDoc says it does, with @file, @module, or
-- @license, or when it stands apart from the code by a blank line or above the imports; above a
-- declaration with neither it documents the declaration. ref:REQ-javascript-support
-- ref:DEC-javascript-dialect
prop_theFirstJsDocCommentOfAFileIsTheFilesWhyOnlyWhenItSaysSo :: Property
prop_theFirstJsDocCommentOfAFileIsTheFilesWhyOnlyWhenItSaysSo = withTests 1 $ property $ do
  let whysOf source = do
        Extraction model findings <- extractText dialectProfile "lib.js" (T.unlines source)
        length [() | OrphanDocComment _ _ <- findings] === 0
        pure [renderUnitId u | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  tagged <- whysOf ["/** @module lib */", "export function f() {}"]
  tagged === ["javascript/lib.js"]
  licensed <- whysOf ["// A plain comment first.", "/** Licensed. @license MIT license:MIT */", "export function f() {}"]
  licensed === ["javascript/lib.js"]
  apart <- whysOf ["/** The library. */", "", "export function f() {}"]
  apart === ["javascript/lib.js"]
  aboveImports <- whysOf ["/** The library. */", "import fs from 'node:fs';", "export function f() {}"]
  aboveImports === ["javascript/lib.js"]
  aboveDeclaration <- whysOf ["/** The function. */", "export function f() {}"]
  aboveDeclaration === ["javascript/lib.js/function/f"]
