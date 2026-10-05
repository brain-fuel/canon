-- | JavaScript is read through the grammars-v4 JavaScript grammar and the profile the chalk sample
-- ships, and through the grammar's canonically commented dialect, so these properties check both
-- against what a JavaScript author means by a declaration and its JSDoc comment.
-- ref:DEC-more-languages ref:DEC-javascript-dialect ref:REQ-javascript-support
module Canon.Extract.JavaScriptTest (tests) where

import Canon.Antlr4.Interpret (interpretText, loadInterpreter, renderInterpretError)
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
import Canon.Span (Position (..), Span (..))
import Canon.Walk (Walked (..), walkProject)
import Data.List (isSuffixOf, sort, stripPrefix)
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
    , testProperty "a JSDoc comment anywhere never fails the parse and is an orphan unless it is a type annotation" prop_aJsDocCommentAnywhereNeverFailsTheParseAndIsAnOrphanUnlessItIsATypeAnnotation
    , testProperty "the properties of an exported object literal are units that inherit its requirement" prop_thePropertiesOfAnExportedObjectLiteralAreUnitsThatInheritItsRequirement
    , testProperty "the first JSDoc comment below a hashbang line can be the file's Why" prop_theFirstJsDocCommentBelowAHashbangLineCanBeTheFilesWhy
    , testProperty "a line break between two tokens ends a statement where JavaScript inserts a semicolon" prop_aLineBreakBetweenTwoTokensEndsAStatementWhereJavaScriptInsertsASemicolon
    , testProperty "the grammar reads the syntax node, three.js, and express write" prop_theGrammarReadsTheSyntaxNodeThreeJsAndExpressWrite
    , testProperty "the grammar reads JSX where an expression may start and less-than elsewhere" prop_theGrammarReadsJsxWhereAnExpressionMayStartAndLessThanElsewhere
    , testProperty "the dialect documents a component written with JSX" prop_theDialectDocumentsAComponentWrittenWithJsx
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
dialectProfile = Profile [".js", ".mjs", ".cjs"] (SplitGrammarFiles "grammars/javascript/canonically_commented/JavaScriptLexer.g4" "grammars/javascript/canonically_commented/JavaScriptParser.g4") (Name "program") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | The JavaScript files of the sample, as canon check finds them, relative to its source root.
sampleFiles :: PropertyT IO [FilePath]
sampleFiles = do
  walked <- evalIO (walkProject [] (\e -> any (`isSuffixOf` e) [".js", ".mjs", ".cjs"]) "canon.yaml" root)
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
-- statement or after the last member binds to nothing and is reported, and a @type cast is no
-- documentation and is neither. What
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
  -- The @type cast is a type annotation, not documentation, so only the other two are orphans.
  length [() | OrphanDocComment _ _ <- findings] === 2
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
        , ("javascript/lib.js/export/default/property/LIMIT", True)
        ]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "javascript/lib.js/class/Shape/accessor/get-size"
        , "javascript/lib.js/class/Shape/accessor/set-size"
        , "javascript/lib.js/class/Shape/method/make"
        , "javascript/lib.js/variable/arrow"
        , "javascript/lib.js/export/default/property/LIMIT"
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

-- | A JSDoc comment may stand between any two tokens, so one the grammar does not take, as after an
-- argument, before a property, or before a semicolon, must not fail the parse: it documents nothing and is reported as
-- an orphan, as one above a local binding is. A comment that starts with @type or @satisfies is a
-- type annotation that TypeScript reads as a type, not documentation, so it is neither a Why nor an
-- orphan. ref:REQ-javascript-support ref:DEC-javascript-dialect ref:DEC-stray-comments
prop_aJsDocCommentAnywhereNeverFailsTheParseAndIsAnOrphanUnlessItIsATypeAnnotation :: Property
prop_aJsDocCommentAnywhereNeverFailsTheParseAndIsAnOrphanUnlessItIsATypeAnnotation = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "lib.js"
      ( T.unlines
          [ "/** Applies f. */"
          , "export function apply(a, b) {"
          , "  /** Above a local, so an orphan. */"
          , "  const x = /** @type {number} */ (a);"
          , "  /** @type {string} */"
          , "  const y = b;"
          , "  g(a /** After an argument, so an orphan. */, b);"
          , "  h(/** Before an argument, so an orphan. */ a);"
          , "  k({inner: {/** Before a property, so an orphan. */ value: a}});"
          , "  const o = {k: /** @satisfies {Shape} */ ({})};"
          , "  return x /** Before a semicolon, so an orphan. */;"
          , "}"
          ]
      )
  sort [line | OrphanDocComment _ sp <- findings, let line = positionLine (spanStart sp)] === [3, 7, 8, 9, 11]
  [renderUnitId u | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)] === ["javascript/lib.js/function/apply"]

-- | What a module exports is its API, and a module often exports an object literal of settings or
-- functions, so the properties, methods, and accessors of an object literal that an exported binding
-- or export default holds directly are units, nested object literals included, and require a comment
-- as the export does; those of an object literal that is not exported, or that is part of a larger
-- expression, are no units. ref:REQ-javascript-support ref:DEC-javascript-dialect
prop_thePropertiesOfAnExportedObjectLiteralAreUnitsThatInheritItsRequirement :: Property
prop_thePropertiesOfAnExportedObjectLiteralAreUnitsThatInheritItsRequirement = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "lib.js"
      ( T.unlines
          [ "/** The defaults. */"
          , "export const defaults = {"
          , "  /** The retry count. */"
          , "  retries: 2,"
          , "  nested: {"
          , "    /** Deep. */"
          , "    depth: 1,"
          , "  },"
          , "  run() {},"
          , "  get size() { return 1; },"
          , "  ...base,"
          , "};"
          , "const local = {a: 1};"
          , "export const picked = {a: 1}.a;"
          , "export default {"
          , "  /** The name. */"
          , "  name: 'x',"
          , "};"
          ]
      )
  length [() | OrphanDocComment _ _ <- findings] === 0
  [(renderUnitId (unitId u), unitRequirement u == Required) | u <- unitsOf model]
    === [ ("javascript/lib.js/variable/defaults", True)
        , ("javascript/lib.js/variable/defaults/property/retries", True)
        , ("javascript/lib.js/variable/defaults/property/nested", True)
        , ("javascript/lib.js/variable/defaults/property/nested/property/depth", True)
        , ("javascript/lib.js/variable/defaults/method/run", True)
        , ("javascript/lib.js/variable/defaults/accessor/get-size", True)
        , ("javascript/lib.js/variable/local", False)
        , ("javascript/lib.js/variable/picked", True)
        , ("javascript/lib.js/export/default", True)
        , ("javascript/lib.js/export/default/property/name", True)
        ]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "javascript/lib.js/variable/defaults/property/nested"
        , "javascript/lib.js/variable/defaults/method/run"
        , "javascript/lib.js/variable/defaults/accessor/get-size"
        , "javascript/lib.js/variable/picked"
        , "javascript/lib.js/export/default"
        ]

-- | A script starts with a hashbang line, which is no code a comment documents, so the first JSDoc
-- comment below it is still the first of the file and may be the file's Why.
-- ref:REQ-javascript-support ref:DEC-javascript-dialect
prop_theFirstJsDocCommentBelowAHashbangLineCanBeTheFilesWhy :: Property
prop_theFirstJsDocCommentBelowAHashbangLineCanBeTheFilesWhy = withTests 1 $ property $ do
  Extraction model findings <- extractText dialectProfile "cli.js" (T.unlines ["#!/usr/bin/env node", "/** @module cli */", "export function main() {}"])
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)] === ["javascript/cli.js"]

-- | JavaScriptParserBase finds a line terminator among the hidden tokens between two tokens, which
-- canon's predicate hook does not see; the hook tells it from the lines of the code tokens on either
-- side, so a statement without a semicolon ends at a line break and not inside a line, and return
-- followed by a line break returns nothing, in the plain grammar and in the dialect.
-- ref:REQ-javascript-support ref:DEC-javascript-dialect ref:DEC-parser-predicates
prop_aLineBreakBetweenTwoTokensEndsAStatementWhereJavaScriptInsertsASemicolon :: Property
prop_aLineBreakBetweenTwoTokensEndsAStatementWhereJavaScriptInsertsASemicolon = withTests 1 $ property $ do
  let grammars = [("grammars/javascript/JavaScriptLexer.g4", "grammars/javascript/JavaScriptParser.g4"), ("grammars/javascript/canonically_commented/JavaScriptLexer.g4", "grammars/javascript/canonically_commented/JavaScriptParser.g4")]
  results <- mapM (\(lexer, parser) -> do
    loaded <- evalIO (loadInterpreter lexer parser)
    interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
    let parses source = either (const False) (const True) (interpretText interpreter (Name "program") "f.js" source)
    pure (map parses ["let a = 1\nlet b = 2\n", "let a = 1 let b = 2\n", "function f() { return\n1 }\n", "a\n++b\n", "a ++ b\n"])) grammars
  results === replicate 2 [True, False, True, True, False]

-- | The corpus of node's lib/, three.js, express, lodash, and React found syntax newer than the
-- grammars-v4 grammar, which node accepts: logical assignment, a trailing comma after the last
-- parameter, a number with a dot and no fraction digits, a private brand check, and using and
-- await using declarations. The plain grammar and the dialect read each, and a near miss without
-- the new syntax still fails. ref:REQ-javascript-support ref:DEC-more-languages ref:DEC-javascript-dialect
prop_theGrammarReadsTheSyntaxNodeThreeJsAndExpressWrite :: Property
prop_theGrammarReadsTheSyntaxNodeThreeJsAndExpressWrite = withTests 1 $ property $ do
  let grammars = [("grammars/javascript/JavaScriptLexer.g4", "grammars/javascript/JavaScriptParser.g4"), ("grammars/javascript/canonically_commented/JavaScriptLexer.g4", "grammars/javascript/canonically_commented/JavaScriptParser.g4")]
      sources =
        [ "a ||= b;\nc &&= d;\n"
        , "function f(\n  a,\n  b,\n) {}\nclass C { m(a, /* rest */) {} }\n"
        , "const t = 0.;\nf(1., 2.);\n"
        , "class C { #brand; static is(o) { return #brand in o; } }\n"
        , "async function f() {\n  using a = g();\n  await using b = h();\n  using(c);\n}\n"
        , "a ||| b;\n"
        ]
  results <- mapM (\(lexer, parser) -> do
    loaded <- evalIO (loadInterpreter lexer parser)
    interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
    pure [either (const False) (const True) (interpretText interpreter (Name "program") "f.js" source) | source <- sources]) grammars
  results === replicate 2 [True, True, True, True, True, False]

-- | JSX is no ECMAScript, but React, Next.js, and Material UI write it in .js and .jsx files that
-- Babel compiles, so the grammar reads it: elements, fragments, namespaced and member tag names,
-- string, expression, and element attribute values, spread attributes and children, empty and
-- comment-only containers, text with entities, and JSX inside a template. A < where an expression
-- may start opens a tag and anywhere else it is less-than, as after an operand or a member named
-- default; the plain grammar and the dialect read each, and an unclosed tag fails.
-- ref:REQ-javascript-support ref:DEC-javascript-jsx
prop_theGrammarReadsJsxWhereAnExpressionMayStartAndLessThanElsewhere :: Property
prop_theGrammarReadsJsxWhereAnExpressionMayStartAndLessThanElsewhere = withTests 1 $ property $ do
  let grammars = [("grammars/javascript/JavaScriptLexer.g4", "grammars/javascript/JavaScriptParser.g4"), ("grammars/javascript/canonically_commented/JavaScriptLexer.g4", "grammars/javascript/canonically_commented/JavaScriptParser.g4")]
      sources =
        [ "const a = <div className=\"app\" data-id={1} aria-label='x' {...rest}>Hello &amp; {name}!</div>;\n"
        , "const b = <><a.b.C x:y=\"z\" /><svg:rect /></>;\n"
        , "const c = <ul>{items.map(i => <Item key={i.id} {...i} />)}{/* a comment */}{}</ul>;\n"
        , "const d = cond ? <A render={() => <B>{x}</B>} /> : <C label=<b>bold</b> />;\n"
        , "const e = `t ${<span>{x}</span>}`;\nif (x.default < 3 && a < b) f(a > c);\n"
        , "function App() {\n  return (\n    <p>\n      multi line\n      text\n    </p>\n  );\n}\n"
        , "const f = <div><span></div>;\n"
        ]
  results <- mapM (\(lexer, parser) -> do
    loaded <- evalIO (loadInterpreter lexer parser)
    interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
    pure [either (const False) (const True) (interpretText interpreter (Name "program") "f.jsx" source) | source <- sources]) grammars
  results === replicate 2 [True, True, True, True, True, True, False]

-- | A React component is a function that returns JSX, so its JSDoc comment binds to it as to any
-- function, and a doc comment inside an expression container documents nothing and is an orphan.
-- ref:REQ-javascript-support ref:DEC-javascript-jsx ref:DEC-javascript-dialect
prop_theDialectDocumentsAComponentWrittenWithJsx :: Property
prop_theDialectDocumentsAComponentWrittenWithJsx = withTests 1 $ property $ do
  Extraction model findings <-
    extractText
      dialectProfile
      "App.jsx"
      ( T.unlines
          [ "import React from 'react';"
          , ""
          , "/** The application. */"
          , "export function App({items}) {"
          , "  return ("
          , "    <ul>"
          , "      {/** Inside a container, so an orphan. */ items.map(i => <li key={i}>{i}</li>)}"
          , "    </ul>"
          , "  );"
          , "}"
          ]
      )
  [renderUnitId u | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)] === ["javascript/App.jsx/function/App"]
  length [() | OrphanDocComment _ _ <- findings] === 1
