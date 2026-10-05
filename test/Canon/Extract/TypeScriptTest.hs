-- | TypeScript is read through the grammars-v4 TypeScript grammar and the profile the ky sample
-- ships, and through the grammar's canonically commented dialect, so these properties check both
-- against what a TypeScript author means by a declaration and its TSDoc comment.
-- ref:DEC-more-languages ref:DEC-typescript-dialect ref:REQ-typescript-support
module Canon.Extract.TypeScriptTest (tests) where

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
    "typescript"
    [ testProperty "the TypeScript profile parses every file of the ky sample into its units" prop_theTypeScriptProfileParsesEveryFileOfTheKySampleIntoItsUnits
    , testProperty "the TypeScript profile binds TSDoc to the declaration below and treats test-directory units as tests" prop_theTypeScriptProfileBindsTsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests
    , testProperty "the TypeScript dialect parses the ky sample with its doc comments" prop_theTypeScriptDialectParsesTheKySampleWithItsDocComments
    , testProperty "the TypeScript dialect binds TSDoc to declarations and members and reports misplaced ones" prop_theTypeScriptDialectBindsTsDocToDeclarationsAndMembersAndReportsMisplacedOnes
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/typescript-ky"

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a TypeScript project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "typescript" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the TypeScript grammar, with no units of a profile, so every
-- unit comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".ts", ".mts", ".cts"] (SplitGrammarFiles "grammars/typescript/canonically_commented/TypeScriptLexer.g4" "grammars/typescript/canonically_commented/TypeScriptParser.g4") (Name "program") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | The TypeScript files of the sample, as canon check finds them, relative to its source root.
sampleFiles :: PropertyT IO [FilePath]
sampleFiles = do
  walked <- evalIO (walkProject [] [".ts", ".mts", ".cts"] "canon.yaml" root)
  pure [fromMaybe path (stripPrefix (root ++ "/") path) | path <- walkedFiles walked]
  where
    root = sampleDir </> "source"

-- | An extraction of text through a profile.
extractText :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractText profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "typescript" profile interpreter path path source)
  either (\e -> annotate (path ++ ": " ++ T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Extracts every file of the sample through a profile.
extractSample :: Profile -> PropertyT IO [Extraction]
extractSample profile = do
  files <- sampleFiles
  mapM (\file -> evalIO (T.pack <$> readFile (sampleDir </> "source" </> file)) >>= extractText profile file) files

-- | The units of a model below its files.
unitsOf :: Model Evidence -> [CodeUnit Evidence]
unitsOf model = [u | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]

-- | A real package must parse whole, every declaration and class member found where the language
-- puts them, or a TypeScript project's check would report parse failures instead of findings.
-- ref:REQ-typescript-support ref:DEC-more-languages
prop_theTypeScriptProfileParsesEveryFileOfTheKySampleIntoItsUnits :: Property
prop_theTypeScriptProfileParsesEveryFileOfTheKySampleIntoItsUnits = withTests 1 $ property $ do
  profile <- sampleProfile
  extractions <- extractSample profile
  length extractions === 87
  sum [length (unitsOf model) | Extraction model _ <- extractions] === 119

-- | A TSDoc comment documents the declaration below it, and a test in TypeScript is a call to a test
-- runner rather than a declaration, so every unit under a test directory is a test and needs the
-- comment that cites its requirement. ref:REQ-typescript-support ref:DEC-more-languages
prop_theTypeScriptProfileBindsTsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests :: Property
prop_theTypeScriptProfileBindsTsDocToTheDeclarationBelowAndTreatsTestDirectoryUnitsAsTests = withTests 1 $ property $ do
  profile <- sampleProfile
  let source = T.unlines ["import ky from 'ky';", "", "/** Options of a request. ref:REQ-1 */", "export interface Options { timeout?: number; }", "", "/** Doubles a number. */", "export function double(n: number): number { return n * 2; }"]
  Extraction library _ <- extractText profile "source/lib.ts" source
  Extraction testFile _ <- extractText profile "test/lib.ts" source
  let whys model = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys library
    === [ ("typescript/source/lib.ts/interface/Options", "Options of a request. ref:REQ-1")
        , ("typescript/source/lib.ts/function/double", "Doubles a number.")
        ]
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- unitsOf library] === [("Options", False), ("double", False)]
  [(whatName (answerValue (unitWhat u)), unitTest u) | u <- unitsOf testFile] === [("Options", True), ("double", True)]

-- | TSDoc comments are tokens of the dialect, so a real package must still parse whole with them, in
-- seconds, and its units, among them the members of exported interfaces and object types, must be
-- found with every TSDoc comment bound. ref:REQ-typescript-support ref:DEC-typescript-dialect
prop_theTypeScriptDialectParsesTheKySampleWithItsDocComments :: Property
prop_theTypeScriptDialectParsesTheKySampleWithItsDocComments = withTests 1 $ property $ do
  extractions <- extractSample dialectProfile
  length extractions === 87
  sum [length (unitsOf model) | Extraction model _ <- extractions] === 706
  sum [length (modelDecisions model) | Extraction model _ <- extractions] === 90
  sum [length [() | OrphanDocComment _ _ <- findings] | Extraction _ findings <- extractions] === 0

-- | In the dialect the grammar says where a TSDoc comment binds: to the declaration, class member,
-- interface or object type member, enum member, or export default below it, and, with
-- @packageDocumentation, to the file; one before any other statement, inside an expression, or
-- after the last member binds to nothing and is reported. What a module exports requires one, the
-- members of an exported class, interface, object type, or enum included, and a private, protected,
-- or #private member never does. ref:REQ-typescript-support ref:DEC-typescript-dialect
prop_theTypeScriptDialectBindsTsDocToDeclarationsAndMembersAndReportsMisplacedOnes :: Property
prop_theTypeScriptDialectBindsTsDocToDeclarationsAndMembersAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "lib.ts"
      ( T.unlines
          [ "/**"
          , " * The library exercises the dialect. ref:some-key"
          , " * @packageDocumentation"
          , " */"
          , "import type {Input} from './input.js';"
          , "import {type Options} from './options.js';"
          , ""
          , "/** Options of a request. */"
          , "export interface RequestOptions {"
          , "  /** The timeout. */"
          , "  timeout?: number;"
          , "  retries: number;"
          , "  /** Calls it. */"
          , "  <T>(input: Input): T;"
          , "  /** After the last member, so an orphan. */"
          , "}"
          , ""
          , "/** A shape. */"
          , "export type Shape = {"
          , "  /** The kind. */"
          , "  kind: string;"
          , "  area(): number;"
          , "};"
          , ""
          , "type Hidden = {inner: string};"
          , ""
          , "/** Colors. */"
          , "export enum Color {"
          , "  /** Red. */"
          , "  Red,"
          , "  Green,"
          , "}"
          , ""
          , "/** A box. */"
          , "export abstract class Box<T> {"
          , "  /** Made. */"
          , "  constructor(private readonly value: T) {}"
          , "  protected size = 0;"
          , "  private secret(): void {}"
          , "  #hidden = 1;"
          , "  get width(): number { return 1; }"
          , "  abstract area(): number;"
          , "}"
          , ""
          , "/** A namespace. */"
          , "export namespace Space {"
          , "  /** Inside. */"
          , "  export const inner = 1;"
          , "  const notExported = 2;"
          , "}"
          , ""
          , "export function f(a: unknown): void {"
          , "  /** Above a statement, so an orphan. */"
          , "  const x = /** A cast, so an orphan. */ (a as string);"
          , "}"
          , ""
          , "export default Box;"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("typescript/lib.ts", "The library exercises the dialect. ref:some-key\n@packageDocumentation")
        , ("typescript/lib.ts/interface/RequestOptions", "Options of a request.")
        , ("typescript/lib.ts/interface/RequestOptions/property/timeout", "The timeout.")
        , ("typescript/lib.ts/interface/RequestOptions/call/0", "Calls it.")
        , ("typescript/lib.ts/type/Shape", "A shape.")
        , ("typescript/lib.ts/type/Shape/property/kind", "The kind.")
        , ("typescript/lib.ts/enum/Color", "Colors.")
        , ("typescript/lib.ts/enum/Color/member/Red", "Red.")
        , ("typescript/lib.ts/class/Box", "A box.")
        , ("typescript/lib.ts/class/Box/constructor/constructor", "Made.")
        , ("typescript/lib.ts/namespace/Space", "A namespace.")
        , ("typescript/lib.ts/namespace/Space/variable/inner", "Inside.")
        ]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [renderUnitId (unitId u) | u <- unitsOf model, unitRequirement u == Optional]
    === [ "typescript/lib.ts/type/Hidden"
        , "typescript/lib.ts/type/Hidden/property/inner"
        , "typescript/lib.ts/class/Box/property/size"
        , "typescript/lib.ts/class/Box/method/secret"
        , "typescript/lib.ts/class/Box/property/#hidden"
        , "typescript/lib.ts/namespace/Space/variable/notExported"
        ]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "typescript/lib.ts/interface/RequestOptions/property/retries"
        , "typescript/lib.ts/type/Shape/method/area"
        , "typescript/lib.ts/enum/Color/member/Green"
        , "typescript/lib.ts/class/Box/accessor/get-width"
        , "typescript/lib.ts/class/Box/method/area"
        , "typescript/lib.ts/function/f"
        , "typescript/lib.ts/export/default"
        ]
