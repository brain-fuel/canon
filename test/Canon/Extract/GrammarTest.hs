-- | Extraction through each dialect must yield the units, decisions, requirements, and orphans the
-- grammar declares. ref:DEC-grammar-carries-extraction-rules ref:DEC-export-rule
module Canon.Extract.GrammarTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (defaultConfig)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Commit
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Canon.Span (Position (..), Span (..))
import Data.Foldable (for_, toList)
import Data.List (sort)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "extract"
    [ testProperty "the parser meta-grammar yields its rules as units in order" parserUnits
    , testProperty "every rule of the parser meta-grammar carries a decision" parserDecisions
    , testProperty "a static git provider fills Who and When with git evidence" gitEvidence
    , testProperty "an unresolved reference key is reported" unresolvedKey
    , testProperty "the lexer meta-grammar yields modes with nested rules and optional fragments" lexerUnits
    , testProperty "the license header binds to the grammar unit" fileLevelLicense
    , testProperty "the dialect grammar's extraction rules are labeled alternatives" dialectPlans
    , testProperty "an action's comments, its strings across lines, and escapes each have one reading, so the meta-grammar and its dialect read them in time" prop_anActionsCommentsStringsAcrossLinesAndEscapesHaveOneReadingSoTheMetaGrammarReadsThemInTime
    , testProperty "an ANTLR rule without a canonical comment parses and is reported, and a comment that binds to nothing is an orphan" prop_anAntlrRuleWithoutACanonicalCommentParsesAndIsReportedAndACommentThatBindsToNothingIsAnOrphan
    , testProperty "two ANTLR comments in a row where none binds are both orphans" prop_twoAntlrCommentsInARowWhereNoneBindsAreBothOrphans
    , testProperty "the java dialect marks public members required and misplaced comments orphan" javaDialect
    , testProperty "a Javadoc comment inside an expression or between arguments is an orphan and the file still parses" aJavadocCommentInsideAnExpressionOrBetweenArgumentsIsAnOrphanAndTheFileStillParses
    , testProperty "the haskell dialect requires comments on exported units" haskellDialect
    , testProperty "bindings attach to the signature with their name and become its How" haskellBindingsBindByName
    , testProperty "a Haskell doc comment anywhere in a file parses and one that documents nothing is an orphan" prop_aHaskellDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan
    , testProperty "a Haskell layout block ends at a comma, then, else, or guard equals sign it cannot hold" prop_aHaskellLayoutBlockEndsAtACommaThenElseOrGuardEqualsSignItCannotHold
    , testProperty "a Haskell file reads the first branch of each #if and hides the branches not read" prop_aHaskellFileReadsTheFirstBranchOfEachIfAndHidesTheBranchesNotRead
    , testProperty "a Haskell pragma anywhere is hidden like a comment" prop_aHaskellPragmaAnywhereIsHiddenLikeAComment
    , testProperty "a Haskell operator is one token by maximal munch" prop_aHaskellOperatorIsOneTokenByMaximalMunch
    , testProperty "Haskell imports and exports name pattern synonyms, type operators, and packages" prop_haskellImportsAndExportsNamePatternSynonymsTypeOperatorsAndPackages
    , testProperty "Haskell literals take underscores, binary digits, magic hashes, and many escapes" prop_haskellLiteralsTakeUnderscoresBinaryDigitsMagicHashesAndManyEscapes
    , testProperty "a Haskell quasi-quotation is one token only where QuasiQuotes is enabled" prop_aHaskellQuasiQuotationIsOneTokenOnlyWhereQuasiQuotesIsEnabled
    , testProperty "the Haskell layout closes blocks where GHC's parse-error rule does" prop_theHaskellLayoutClosesBlocksWhereGhcsParseErrorRuleDoes
    , testProperty "Haskell declarations and expressions GHC accepts parse" prop_haskellDeclarationsAndExpressionsGhcAcceptsParse
    , testProperty "a Haddock comment in an export list or on a record field is an orphan read in place" prop_aHaddockCommentInAnExportListOrOnARecordFieldIsAnOrphanReadInPlace
    , testProperty "a Haskell syntax error after doc comments is reported where it is" prop_aHaskellSyntaxErrorAfterDocCommentsIsReportedWhereItIs
    , testProperty "the make dialect requires a comment on every plain rule" makeDialect
    , testProperty "a Makefile reference keeps its colons, commas, spaces, and hashes inside one name" prop_aMakefileReferenceKeepsItsColonsCommasSpacesAndHashesInsideOneName
    , testProperty "a Makefile directive word is a name after the first word of a line" prop_aMakefileDirectiveWordIsANameAfterTheFirstWordOfALine
    , testProperty "a Makefile rule keeps its recipe across conditionals and continued lines" prop_aMakefileRuleKeepsItsRecipeAcrossConditionalsAndContinuedLines
    , testProperty "a canonical comment a Makefile cannot bind is an orphan and the file still parses" prop_aCanonicalCommentAMakefileCannotBindIsAnOrphanAndTheFileStillParses
    , testProperty "export entries parse and decide requirement" exportEntries
    ]

dialectDir :: FilePath
dialectDir = "grammars/antlr4/canonically_commented"

parserPath :: FilePath
parserPath = "grammars/antlr4/ANTLRv4Parser.g4"

lexerPath :: FilePath
lexerPath = "grammars/antlr4/ANTLRv4Lexer.g4"

antlrProfile :: Profile
antlrProfile = Profile [".g4"] (SplitGrammarFiles (dialectDir ++ "/ANTLRv4Lexer.g4") (dialectDir ++ "/ANTLRv4Parser.g4")) (Name "grammarSpec") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

sampleCommits :: [Commit]
sampleCommits =
  [ Commit (CommitHash (T.replicate 40 "a")) alice (posixSecondsToUTCTime 1000) alice (posixSecondsToUTCTime 1000) "first"
  , Commit (CommitHash (T.replicate 40 "b")) bob (posixSecondsToUTCTime 2000) alice (posixSecondsToUTCTime 2000) "second"
  ]
  where
    alice = Person "Alice" "alice@example"
    bob = Person "Bob" "bob@example"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadProfileInterpreter antlrProfile)
  case loaded of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right interpreter -> pure interpreter

extractOrFail :: [Commit] -> FilePath -> PropertyT IO Extraction
extractOrFail commits path = do
  interpreter <- interpreterOrFail
  result <- evalIO (extractWithProfile (staticGitProvider commits) defaultConfig "antlr4" antlrProfile interpreter path path)
  case result of
    Left err -> annotate (T.unpack (renderGrammarExtractError err)) >> failure
    Right extraction -> pure extraction

extractTextOrFail :: FilePath -> Text -> PropertyT IO Extraction
extractTextOrFail path source = do
  interpreter <- interpreterOrFail
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "antlr4" antlrProfile interpreter path path source)
  case result of
    Left err -> annotate (T.unpack (renderGrammarExtractError err)) >> failure
    Right extraction -> pure extraction

grammarUnit :: Model ev -> PropertyT IO (CodeUnit ev)
grammarUnit model = case modelUnits model of
  [file] | [grammar] <- unitChildren file -> do
    unitKindText (whatKind (answerValue (unitWhat grammar))) === "grammarDefinition"
    pure grammar
  _ -> failure

kindOf :: CodeUnit ev -> Text
kindOf = unitKindText . whatKind . answerValue . unitWhat

parserUnits :: Property
parserUnits = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] parserPath
  findings === []
  modelLanguage model === "antlr4"
  grammar <- grammarUnit model
  renderUnitId (unitId grammar) === "antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser"
  length (unitChildren grammar) === 67
  take 2 (map (renderUnitId . unitId) (unitChildren grammar)) === ["antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/grammarSpec", "antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/grammarDecl"]
  assert (all ((== Required) . unitRequirement) (unitChildren grammar))
  assert (all ((== "parserRule") . kindOf) (unitChildren grammar))
  case unitChildren grammar of
    (first : _) -> case answerValue (unitHow first) of
      HowText body -> assert (T.isPrefixOf "grammarDecl prequelConstruct*" body)
      _ -> failure
    [] -> failure

parserDecisions :: Property
parserDecisions = withTests 1 $ property $ do
  Extraction model _ <- extractOrFail [] parserPath
  length (modelDecisions model) === 68
  case [d | d <- modelDecisions model, renderDecisionId (decisionId d) == "decision/antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/ruleAction"] of
    [d] -> do
      assert (T.isPrefixOf "Match stuff like @init {int i;}" (whyText (answerValue (decisionWhy d))))
      assert (isAsserted (answerEvidence (decisionWhy d)))
    other -> annotate (show (length other)) >> failure
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

gitEvidence :: Property
gitEvidence = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail sampleCommits parserPath
  findings === []
  let units = modelAllUnits model
  assert (all (isJust . unitWho) units)
  assert (all (isJust . unitWhen) units)
  assert (all isDerivedFromGit (concatMap (toList . answerEvidenceOf) units))
  case unitWhen (head' units) of
    Just (Answer w _) -> do
      changeCommit (whenFirst w) === CommitHash (T.replicate 40 "a")
      changeCommit (whenLast w) === CommitHash (T.replicate 40 "b")
    Nothing -> failure
  where
    answerEvidenceOf u = maybe [] (pure . answerEvidence) (unitWho u) ++ maybe [] (pure . answerEvidence) (unitWhen u)
    head' us = case us of
      (u : _) -> u
      [] -> error "no units"

unresolvedKey :: Property
unresolvedKey = withTests 1 $ property $ do
  let source = "grammar Tiny;\n\n/** exists because of ref:missing, see license:MIT. */\nstart\n    : 'a'\n    ;\n"
  Extraction model findings <- extractTextOrFail "tiny.g4" source
  findings === []
  [k | UnresolvedReference _ _ k <- checkModel emptyRegistry emptyLedger model] === [ReferenceKey "missing", ReferenceKey "MIT"]
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []
  map (whyText . answerValue . decisionWhy) (modelDecisions model) === ["exists because of ref:missing, see license:MIT."]

lexerUnits :: Property
lexerUnits = withTests 1 $ property $ do
  Extraction model findings <- extractOrFail [] lexerPath
  findings === []
  grammar <- grammarUnit model
  length (unitChildren grammar) === 52
  length (modelAllUnits model) === 72
  map kindOf (drop 50 (unitChildren grammar)) === ["lexerMode", "lexerMode"]
  map (length . unitChildren) (drop 50 (unitChildren grammar)) === [7, 11]
  length [() | u <- modelAllUnits model, kindOf u == "fragmentRule"] === 9
  assert (all (\u -> (unitRequirement u == Optional) == (kindOf u `elem` ["file", "grammarDefinition", "lexerMode", "fragmentRule"])) (modelAllUnits model))
  length (modelDecisions model) === 60
  [u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

fileLevelLicense :: Property
fileLevelLicense = withTests 1 $ property $ do
  Extraction model _ <- extractOrFail [] parserPath
  grammar <- grammarUnit model
  case [d | d <- modelDecisions model, decisionUnits d == NonEmpty.fromList [unitId grammar]] of
    [d] -> do
      whyLicenses (answerValue (decisionWhy d)) === [ReferenceKey "BSD-3-Clause"]
      assert (T.isInfixOf "BSD license" (whyText (answerValue (decisionWhy d))))
    other -> annotate (show (length other)) >> failure

dialectPlans :: Property
dialectPlans = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let plans = alternativePlans (interpreterParser interpreter)
  Map.lookup (Name "grammarSpec") plans === Just [Just (AlternativePlan "grammarDefinition" False)]
  Map.lookup (Name "parserRuleSpec") plans === Just [Just (AlternativePlan "parserRule" False)]
  Map.lookup (Name "lexerRuleSpec") plans === Just [Just (AlternativePlan "fragmentRule" False), Just (AlternativePlan "lexerRule" False)]
  Map.lookup (Name "modeSpec") plans === Just [Just (AlternativePlan "lexerMode" False)]
  Map.lookup (Name "ruleSpec") plans === Just [Nothing, Nothing]

-- | grammars-v4 holds grammars whose actions carry many comments, Python comments with apostrophes,
-- and strings full of escapes; canon's lexer backtracks, so each must have one reading or a grammar
-- of a thousand lines takes minutes, and an apostrophe pairs with the next across lines as the ANTLR
-- tool pairs it. ref:REQ-antlr4-support ref:DEC-grammar-carries-extraction-rules
prop_anActionsCommentsStringsAcrossLinesAndEscapesHaveOneReadingSoTheMetaGrammarReadsThemInTime :: Property
prop_anActionsCommentsStringsAcrossLinesAndEscapesHaveOneReadingSoTheMetaGrammarReadsThemInTime = withTests 1 $ property $ do
  let commented i = ["    // Line " <> T.pack (show i) <> " of a note, it's {@code true}.", "    /* and a block, the parser's " <> T.pack (show i) <> " */"]
      source =
        T.unlines
          ( ["grammar Busy;", "@members {"]
              ++ concatMap commented [1 .. 30 :: Int]
              ++ ["    # we're in Python here", "    # and it's paired", "    x = a / b / (c) /'d';", "}", "start : 'x' {print(\"\"\"a doc\nstring\"\"\")} ;"]
              ++ ["ESCAPED : '" <> T.replicate 40 "\\n" <> "' ;"]
          )
  plain <- evalIO (loadInterpreter "grammars/antlr4/ANTLRv4Lexer.g4" "grammars/antlr4/ANTLRv4Parser.g4")
  dialect <- evalIO (loadProfileInterpreter antlrProfile)
  for_ [plain, dialect] $ \loaded -> do
    interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
    case interpretText interpreter (Name "grammarSpec") "Busy.g4" source of
      Left e -> annotate (T.unpack (renderInterpretError e)) >> failure
      Right _ -> pure ()

-- | Every grammar of grammars-v4 must parse through the dialect, most of them without canonical
-- comments, so a rule without one parses and the check reports it as missing, as every other
-- dialect does through a required label; of several comments in a row the last binds, one inside a
-- rule's alternatives documents nothing, and /**/ is an empty plain comment.
-- ref:REQ-antlr4-support ref:DEC-grammar-carries-extraction-rules ref:DEC-stray-comments
prop_anAntlrRuleWithoutACanonicalCommentParsesAndIsReportedAndACommentThatBindsToNothingIsAnOrphan :: Property
prop_anAntlrRuleWithoutACanonicalCommentParsesAndIsReportedAndACommentThatBindsToNothingIsAnOrphan = withTests 1 $ property $ do
  let source =
        T.unlines
          [ "/** The fixture grammar. */"
          , "grammar T;"
          , "/** An old note. */"
          , "/** Starts. */"
          , "start : /** stray */ A | other ;"
          , "other : A ;"
          , "/**/"
          , "A : 'a' ;"
          , "fragment F : 'f' ;"
          ]
  Extraction model findings <- extractTextOrFail "T.g4" source
  map (whyText . answerValue . decisionWhy) (modelDecisions model) === ["The fixture grammar.", "Starts."]
  length [() | OrphanDocComment _ _ <- findings] === 2
  sort [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["antlr4/T.g4/grammarDefinition/T/lexerRule/A", "antlr4/T.g4/grammarDefinition/T/parserRule/other"]

-- | A grammar may carry notes above an action, where the dialect binds no comment, and grammars-v4
-- writes them; each is an orphan and the grammar still parses, however many stand in a row.
-- ref:REQ-antlr4-support ref:DEC-stray-comments
prop_twoAntlrCommentsInARowWhereNoneBindsAreBothOrphans :: Property
prop_twoAntlrCommentsInARowWhereNoneBindsAreBothOrphans = withTests 1 $ property $ do
  let source = T.unlines ["/** The fixture grammar. */", "grammar T;", "/** One. */", "/** Two. */", "@members { int x; }", "/** Starts. */", "start : A ;", "/** A. */", "A : 'a' ;"]
  Extraction _ findings <- extractTextOrFail "T.g4" source
  length [() | OrphanDocComment _ _ <- findings] === 2

javaProfile :: Profile
javaProfile = Profile [".java"] (SplitGrammarFiles "grammars/java/canonically_commented/JavaLexer.g4" "grammars/java/canonically_commented/JavaParser.g4") (Name "compilationUnit") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

javaDialect :: Property
javaDialect = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter javaProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "package p;"
          , "/** Doc for A. ref:some-key */"
          , "public class A {"
          , "  /** Field. */"
          , "  public int f;"
          , "  private int g;"
          , "  /** Extra. */"
          , "  /** Method. */"
          , "  public void m() { int local = 1; }"
          , "  @Deprecated /** Misplaced. */ public void n() {}"
          , "  /** Init. */"
          , "  static { }"
          , "  /** Checks t. ref:REQ-1 */"
          , "  @Test void t() {}"
          , "  @Test(timeout = 5) public void u() {}"
          , "  @Deprecated void v() {}"
          , "}"
          , "interface I { /** Constant. */ int C = 1; void k(); }"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "java" javaProfile interpreter "A.java" "A.java" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      byName n = [u | u <- units, whatName (answerValue (unitWhat u)) == n]
      requirementOf n = map unitRequirement (byName n)
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
  map kindOf (filter ((/= "file") . kindOf) units) === ["package", "class", "field", "field", "method", "method", "method", "method", "method", "interface", "constant", "method"]
  map (\n -> map unitTest (byName n)) ["t", "u", "v", "m"] === [[True], [True], [False], [False]]
  requirementOf "t" === [Required]
  requirementOf "u" === [Required]
  requirementOf "v" === [Optional]
  whyOf "t" === ["Checks t. ref:REQ-1"]
  requirementOf "A" === [Required]
  requirementOf "f" === [Required]
  requirementOf "g" === [Optional]
  requirementOf "n" === [Required]
  requirementOf "C" === [Required]
  requirementOf "k" === [Required]
  requirementOf "I" === [Optional]
  whyOf "A" === ["Doc for A. ref:some-key"]
  whyOf "m" === ["Method."]
  whyOf "n" === []
  whyOf "C" === ["Constant."]
  map (whyReferences . answerValue . decisionWhy) [d | u <- byName "A", d <- decisionsFor (unitId u) model] === [[ReferenceKey "some-key"]]
  length [() | OrphanDocComment _ _ <- findings] === 3
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["java/A.java/package/p/class/A/method/n", "java/A.java/package/p/class/A/method/u", "java/A.java/package/p/interface/I/method/k"]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests emptyRegistry model] === ["java/A.java/package/p/class/A/method/t"]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "t" "here"))) model] === []

-- | Javadoc may stand anywhere a comment may, and one inside an expression or between arguments
-- documents nothing, so it must not stop a Java project's check: the file parses, each member keeps
-- its own Javadoc, and each misplaced comment is reported as an orphan.
-- ref:DEC-grammar-carries-extraction-rules ref:DEC-stray-comments
aJavadocCommentInsideAnExpressionOrBetweenArgumentsIsAnOrphanAndTheFileStillParses :: Property
aJavadocCommentInsideAnExpressionOrBetweenArgumentsIsAnOrphanAndTheFileStillParses = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter javaProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "package p;"
          , "class A {"
          , "  /** Sums. */"
          , "  int sum(int a, int b) {"
          , "    int c = foo(a, /** between arguments */ b) + /** between operands */ 3;"
          , "    int[] l = { 1, /** in an initializer */ 2 };"
          , "    Runnable r = () -> /** in a lambda */ run();"
          , "    return (int) /** after a cast */ c;"
          , "  }"
          , "  /** Still documented. */"
          , "  int f = 1 * /** in a field */ 2;"
          , "}"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "java" javaProfile interpreter "A.java" "A.java" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- toList (decisionUnits d)]
    === [("java/A.java/package/p/class/A/method/sum", "Sums."), ("java/A.java/package/p/class/A/field/f", "Still documented.")]
  length [() | OrphanDocComment _ _ <- findings] === 6

isAsserted :: Evidence -> Bool
isAsserted ev = case ev of
  Asserted _ -> True
  _ -> False

haskellProfile :: Profile
haskellProfile = Profile [".hs"] (SplitGrammarFiles "grammars/haskell/canonically_commented/HaskellLexer.g4" "grammars/haskell/canonically_commented/HaskellParser.g4") (Name "module") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

haskellDialect :: Property
haskellDialect = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "-- | This module exists to exercise the dialect. ref:some-key"
          , "module Fixture"
          , "  ( Shape (..)"
          , "  , area"
          , "  , Named (name)"
          , "  , (+.+)"
          , "  ) where"
          , ""
          , "-- | A shape is either a circle or a box"
          , "-- and nothing else."
          , "data Shape = Circle Double | Box Double Double"
          , ""
          , "{-| Names exist so that shapes can be reported. -}"
          , "class Named a where"
          , "  -- | The reported name."
          , "  name :: a -> Text"
          , "  describe :: a -> Text"
          , ""
          , "instance Named Shape where"
          , "  name _ = \"shape\""
          , ""
          , "area :: Shape -> Double"
          , "area s = go s"
          , "  where"
          , "    -- | not a unit"
          , "    go _ = 1"
          , ""
          , "(+.+) :: Double -> Double -> Double"
          , "a +.+ b = a + b"
          , ""
          , "helper :: Int"
          , "helper = 2"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Fixture.hs" "Fixture.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      byName n = [u | u <- units, whatName (answerValue (unitWhat u)) == n]
      requirementOf n = map unitRequirement (byName n)
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
  map kindOf (filter ((/= "file") . kindOf) units) === ["module", "data", "class", "method", "method", "instance", "function", "function", "function"]
  map requirementOf ["Shape", "Named", "name", "describe", "area", "(+.+)", "helper", "Fixture"] === [[Required], [Required], [Required], [Optional], [Required], [Required], [Optional], [Optional]]
  requirementOf "Named-Shape" === [Optional]
  whyOf "Fixture" === ["This module exists to exercise the dialect. ref:some-key"]
  whyOf "Shape" === ["A shape is either a circle or a box\nand nothing else."]
  whyOf "Named" === ["Names exist so that shapes can be reported."]
  whyOf "name" === ["The reported name."]
  let howOf n = [t | u <- byName n, HowText t <- [answerValue (unitHow u)]]
      signatureOf n = [whatSignature (answerValue (unitWhat u)) | u <- byName n]
      endLineOf n = [positionLine (spanEnd (whereSpan (answerValue (unitWhere u)))) | u <- byName n]
  howOf "area" === ["area s = go s\n  where\n    -- | not a unit\n    go _ = 1"]
  signatureOf "area" === [Just "Shape -> Double"]
  endLineOf "area" === [26]
  howOf "(+.+)" === ["a +.+ b = a + b"]
  howOf "helper" === ["helper = 2"]
  howOf "name" === ["name :: a -> Text"]
  signatureOf "Shape" === [Nothing]
  length [() | OrphanDocComment _ _ <- findings] === 1
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["haskell/Fixture.hs/module/Fixture/function/area", "haskell/Fixture.hs/module/Fixture/function/(+.+)"]

haskellBindingsBindByName :: Property
haskellBindingsBindByName = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "module Fixture (f, g) where"
          , ""
          , "-- | Counts down."
          , "f :: Int -> Int"
          , "{-# INLINE f #-}"
          , "f 0 = 1"
          , "f n = n"
          , ""
          , "helper = 2"
          , ""
          , "g :: Int"
          , "g = 3"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Fixture.hs" "Fixture.hs" source)
  Extraction model _ <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      byName n = [u | u <- units, whatName (answerValue (unitWhat u)) == n]
      howOf n = [t | u <- byName n, HowText t <- [answerValue (unitHow u)]]
      spanOf n = [whereSpan (answerValue (unitWhere u)) | u <- byName n]
  howOf "f" === ["f 0 = 1\nf n = n"]
  spanOf "f" === [Span (Position 3 1) (Position 7 8)]
  byName "helper" === []
  howOf "g" === ["g = 3"]

exportEntries :: Property
exportEntries = withTests 1 $ property $ do
  parseExportEntry "Shape (..)" === ExportAll "Shape"
  parseExportEntry "Named (name, describe)" === ExportSome "Named" ["name", "describe"]
  parseExportEntry "(+.+)" === ExportName "(+.+)"
  parseExportEntry "module Data.Text" === ExportModule "Data.Text"
  parseExportEntry "area" === ExportName "area"
  let entries = Just [ExportAll "Shape", ExportSome "Named" ["name"], ExportName "area"]
  exportRequires entries Nothing "Shape" === True
  exportRequires entries (Just "Shape") "Circle" === True
  exportRequires entries (Just "Named") "name" === True
  exportRequires entries (Just "Named") "describe" === False
  exportRequires entries Nothing "helper" === False
  exportRequires Nothing Nothing "helper" === True
  exportRequires Nothing Nothing "Named Shape" === False

makeProfile :: Profile
makeProfile = Profile ["Makefile"] (SplitGrammarFiles "grammars/make/canonically_commented/MakefileLexer.g4" "grammars/make/canonically_commented/MakefileParser.g4") (Name "makefile") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

makeDialect :: Property
makeDialect = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter makeProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "# | The port the page listens on."
          , "PORT ?= 8080"
          , "BIN = $$(stack path --local-install-root)/bin/x"
          , ".DEFAULT_GOAL := help"
          , ".PHONY: help build"
          , ""
          , "# | What you can ask for, so the list"
          , "# cannot drift. ref:some-key"
          , "help: ## what you can ask for"
          , "\t@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST)"
          , ""
          , "build: deps | order ## compile"
          , "\tstack build \\"
          , "\t  --no-terminal"
          , ""
          , "%.o: %.c"
          , "\t$(CC) -c $< -o $@"
          , ""
          , "ifeq ($(OS),Windows_NT)"
          , "SHELL := cmd"
          , "else"
          , "SHELL := bash"
          , "endif"
          , "export PORT"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "make" makeProfile interpreter "Makefile" "Makefile" source)
  Extraction model _ <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      byName n = [u | u <- units, whatName (answerValue (unitWhat u)) == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
  map kindOf (filter ((/= "file") . kindOf) units) === ["variable", "variable", "variable", "specialRule", "rule", "rule", "patternRule", "variable", "variable"]
  map unitRequirement (byName "help" ++ byName "build" ++ byName ".PHONY" ++ byName "%.o" ++ byName "PORT") === [Required, Required, Optional, Optional, Optional]
  whyOf "help" === ["What you can ask for, so the list\ncannot drift. ref:some-key"]
  whyOf "PORT" === ["The port the page listens on."]
  [t | u <- byName "build", HowText t <- [answerValue (unitHow u)]] === ["stack build \\\n\t  --no-terminal"]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["make/Makefile/rule/build"]

-- | A real Makefile names its targets and variables through references that hold colons, commas,
-- equals signs, spaces, and hashes, and expands whole lines of $(eval ...) and $(foreach ...); make
-- reads the Linux and git Makefiles this way, so canon must too. ref:REQ-make-support
-- ref:DEC-make-dialect
prop_aMakefileReferenceKeepsItsColonsCommasSpacesAndHashesInsideOneName :: Property
prop_aMakefileReferenceKeepsItsColonsCommasSpacesAndHashesInsideOneName = withTests 1 $ property $ do
  parsesAsMakefile $
    T.unlines
      [ "obj-$(CONFIG_X) += a.o"
      , "CFLAGS+=-O2"
      , "x!=echo hi"
      , "y ?:= $(x)"
      , "$(call target,a:b,c d) $(subst :,=,${z}): $(patsubst %.c,%.o,$(wildcard *.c)) # a comment"
      , "\t$(CC) -o $@ $^"
      , "$(eval $(call tpl,one, two # not a comment \\"
      , "  , three))"
      , "$(foreach v,$(VARS),$(eval $(v)_FLAGS := -D$(v)))"
      , "joined := a$\\"
      , "    b"
      , "all: d$\\"
      , "     e; @:"
      , "lib.a(member.o): member.o"
      , "\\#literal: ; @echo \\#"
      ]

-- | Make recognises a directive only at the start of a line and reads export = 1 as an assignment
-- to a variable named export, so GNU make's own tests and the Makefiles that use define, include,
-- or else as target names parse, as do every modifier and directive make has. ref:REQ-make-support
-- ref:DEC-make-dialect
prop_aMakefileDirectiveWordIsANameAfterTheFirstWordOfALine :: Property
prop_aMakefileDirectiveWordIsANameAfterTheFirstWordOfALine = withTests 1 $ property $ do
  parsesAsMakefile $
    T.unlines
      [ "all: define include else endif"
      , "define = define"
      , "export = 123"
      , "export export = 456"
      , "export: ; @echo $@"
      , "override CFLAGS += -g"
      , "private export F = global"
      , "a: private export FOO := a"
      , "export A B C"
      , "unexport D"
      , "override undefine E"
      , "vpath %.c src"
      , "-include $(DEPS)"
      , "override define TEMPLATE :="
      , "define inner"
      , "endef"
      , "  endef # the outer block ends here"
      , "ifeq ($(A),1)"
      , "  X = 1"
      , "else ifneq ($(B),)"
      , "  X = 2"
      , "else"
      , "\tY = 3"
      , "endif # chained"
      , "t1 t2 &: s ; touch t1 t2"
      , "&:;"
      , "$(OBJS): %.o: %.c | dirs"
      ]

-- | Make keeps reading a rule's recipe across a conditional between its lines and joins a recipe line
-- ending in a backslash to the next whatever it starts with, so the rule's How must hold every line,
-- and a line after .RECIPEPREFIX sets another prefix must parse. ref:REQ-make-support
-- ref:DEC-make-dialect
prop_aMakefileRuleKeepsItsRecipeAcrossConditionalsAndContinuedLines :: Property
prop_aMakefileRuleKeepsItsRecipeAcrossConditionalsAndContinuedLines = withTests 1 $ property $ do
  model <- makeModelOf $
    T.unlines
      [ "# | Builds the program."
      , "build: main.o"
      , "\tcc -o build \\"
      , "  main.o"
      , "ifdef DEBUG"
      , "\t@echo debug"
      , "else"
      , "\t@echo release"
      , "endif"
      , ""
      , ".RECIPEPREFIX := >"
      , "run:"
      , "> @echo MAKELEVEL = $(MAKELEVEL)"
      ]
  let units = modelAllUnits model
  [t | u <- units, whatName (answerValue (unitWhat u)) == "build", HowText t <- [answerValue (unitHow u)]]
    === ["cc -o build \\\n  main.o\nifdef DEBUG\n\t@echo debug\nelse\n\t@echo release\nendif"]

-- | A canonical comment in a place no unit follows, between recipe lines or above an endif, binds to
-- nothing; make ignores it, so canon must still read the file and report the comment as an orphan.
-- ref:REQ-make-support ref:DEC-make-dialect ref:DEC-stray-comments
prop_aCanonicalCommentAMakefileCannotBindIsAnOrphanAndTheFileStillParses :: Property
prop_aCanonicalCommentAMakefileCannotBindIsAnOrphanAndTheFileStillParses = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter makeProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "# | Builds it."
          , "build:"
          , "\tcc -c a.c"
          , "# | Between recipe lines."
          , "\tcc -o a a.o"
          , "ifdef X"
          , "Y = 1"
          , "# | Above an endif."
          , "endif"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "make" makeProfile interpreter "Makefile" "Makefile" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [whyText (answerValue (decisionWhy d)) | d <- modelDecisions model] === ["Builds it."]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [4, 8]

-- | Parses a Makefile with the make dialect, which is also canon's only Makefile grammar.
parsesAsMakefile :: Text -> PropertyT IO ()
parsesAsMakefile source = do
  loaded <- evalIO (loadInterpreter "grammars/make/canonically_commented/MakefileLexer.g4" "grammars/make/canonically_commented/MakefileParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  case interpretText interpreter (Name "makefile") "Makefile" source of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right _ -> pure ()

-- | The model the make dialect extracts from a Makefile.
makeModelOf :: Text -> PropertyT IO (Model Evidence)
makeModelOf source = do
  loaded <- evalIO (loadProfileInterpreter makeProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "make" makeProfile interpreter "Makefile" "Makefile" source)
  Extraction model _ <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  pure model

-- | GHC skips a Haddock comment that documents nothing, and Haddock warns of it, so canon must read
-- a module with one inside an expression, between the arguments of a call, before a case
-- alternative, at the end of a do block, after a pragma, or at the end of the file, keep the Whys of
-- its declarations, and report each such comment as an orphan. ref:REQ-haskell-support
-- ref:DEC-haskell-dialect ref:DEC-stray-comments
prop_aHaskellDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan :: Property
prop_aHaskellDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "module Odd (f) where"
          , ""
          , "-- | A function."
          , "f :: Int -> IO Int"
          , "f x = do"
          , "  let y ="
          , "        -- | Inside an expression."
          , "        x + 1"
          , "  z <- g y"
          , "    -- | Between the arguments."
          , "    2"
          , "  case z of"
          , "    -- | Before an alternative."
          , "    1 -> pure 2"
          , "    _ -> pure [ z"
          , "              -- | In a list."
          , "              , 3 ] >> pure z"
          , "  -- | At the end of a do block."
          , ""
          , "{-# INLINE g #-}"
          , "-- | After a pragma, so the function's."
          , "g :: Int -> Int -> IO Int"
          , "g a b = pure (a + b)"
          , "-- | At the end of the file."
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Odd.hs" "Odd.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [renderUnitId u | d <- modelDecisions model, u <- toList (decisionUnits d)] === ["haskell/Odd.hs/module/Odd/function/f", "haskell/Odd.hs/module/Odd/function/g"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [7, 10, 13, 16, 18, 24]

-- | GHC closes an implicit layout block at a token the block cannot hold, by the parse-error rule of
-- the layout algorithm, so code that writes a case in a tuple, a let in a comprehension, a case
-- between then and else, or a let in a guard on one line compiles; canon must read it through the
-- plain grammar and the dialect, while a comma of a guard, of a comprehension's qualifiers, or of an
-- operator such as /= leaves the block open. ref:REQ-haskell-support ref:DEC-haskell-grammar-fixes
-- ref:DEC-layout-parse-error-rule
prop_aHaskellLayoutBlockEndsAtACommaThenElseOrGuardEqualsSignItCannotHold :: Property
prop_aHaskellLayoutBlockEndsAtACommaThenElseOrGuardEqualsSignItCannotHold = withTests 1 $ property $ do
  let source =
        T.unlines
          [ "module Layout where"
          , "pair x = (case x of Just y -> y, 2)"
          , "list x = [case x of Just y -> y, 2]"
          , "comprehension xs = [y | x <- xs, let y = x + 1, odd y]"
          , "two xs = [z | x <- xs, let y = x + 1; z = y, odd y]"
          , "spread xs = [y | x <- xs, let y = x"
          , "                              z = y, odd z]"
          , "choose x = if x then case x of True -> 1 else 2"
          , "guarded x | Just y <- x, let z = y = z"
          , "          | otherwise = 0"
          , "fold xs = foldr (\\u acc -> case u of"
          , "              Just v | v /= 0, v == 1 -> acc"
          , "              _ -> acc) 0 xs"
          , "record r = r {a = case r of R -> 1, b = 2}"
          ]
  for' [("grammars/haskell/HaskellLexer.g4", "grammars/haskell/HaskellParser.g4"), ("grammars/haskell/canonically_commented/HaskellLexer.g4", "grammars/haskell/canonically_commented/HaskellParser.g4")] $ \(lexer, parser) -> do
    loaded <- evalIO (loadInterpreter lexer parser)
    interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
    case interpretText interpreter (Name "module") "Layout.hs" source of
      Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
      Right _ -> pure ()
  where
    for' xs f = mapM_ f xs

-- | Parses a module through the plain Haskell grammar and through the dialect, failing with the
-- parse error of either.
parsesThroughBothHaskellGrammars :: Text -> PropertyT IO ()
parsesThroughBothHaskellGrammars source =
  mapM_ parseWith [("grammars/haskell/HaskellLexer.g4", "grammars/haskell/HaskellParser.g4"), ("grammars/haskell/canonically_commented/HaskellLexer.g4", "grammars/haskell/canonically_commented/HaskellParser.g4")]
  where
    parseWith (lexer, parser) = do
      loaded <- evalIO (loadInterpreter lexer parser)
      interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
      case interpretText interpreter (Name "module") "Corpus.hs" source of
        Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
        Right _ -> pure ()

-- | GHC runs the C preprocessor before its lexer in a module with CPP, and ghc's base, lens, and
-- aeson branch on compiler and package versions throughout; canon must read such a module, so it
-- reads the first branch of each #if whose condition can hold, hides the others, an #if 0 among
-- them, and hides every directive line and a script's #! line. ref:REQ-haskell-support
-- ref:DEC-haskell-grammar-fixes ref:DEC-preprocessor-builds
prop_aHaskellFileReadsTheFirstBranchOfEachIfAndHidesTheBranchesNotRead :: Property
prop_aHaskellFileReadsTheFirstBranchOfEachIfAndHidesTheBranchesNotRead = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "#!/usr/bin/env stack"
      , "{-# LANGUAGE CPP #-}"
      , "module Cpp (f) where"
      , "#include \"lens-common.h\""
      , "#if MIN_VERSION_base(4,8,0)"
      , "import Data.List (foldl')"
      , "#else"
      , "import Data.List (foldl') where"
      , "#endif"
      , "# define ENABLED 1"
      , "#ifdef mingw32_HOST_OS"
      , "f :: Int"
      , "#elif defined(linux_HOST_OS)"
      , "f :: Int ->"
      , "#else"
      , "f :: )"
      , "#endif"
      , "f = 1"
      , "#if 0"
      , "this is not Haskell"
      , "#endif"
      ]

-- | GHC ignores a pragma it does not know and reads none as syntax canon needs, while real modules put
-- OPTIONS_HADDOCK, a lowercase Language, INLINE, and SOURCE pragmas in places the upstream grammar
-- did not take them. ref:REQ-haskell-support ref:DEC-haskell-grammar-fixes
prop_aHaskellPragmaAnywhereIsHiddenLikeAComment :: Property
prop_aHaskellPragmaAnywhereIsHiddenLikeAComment = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# OPTIONS_HADDOCK not-home #-}"
      , "{-# Language CPP #-}"
      , "module Pragmas"
      , "  ( f"
      , "  , {-# DEPRECATED \"use f\" #-} g"
      , "  ) where"
      , "import {-# SOURCE #-} Pragmas.Types"
      , "f :: Int"
      , "f = h where"
      , "  {-# NOINLINE h #-}"
      , "  h = 1"
      , "{-# NOINLINE g #-}"
      , "g = f"
      ]

-- | The Haskell report lexes an operator by maximal munch, so ==>, >=>, .:, $$, and the qualified
-- Map.! and C.. are one operator each, and dashes followed by a symbol are an operator rather than a
-- comment; the upstream grammar read operators as runs of one-character tokens that a reserved
-- operator such as =>, .., or $$ broke apart. ref:REQ-haskell-support ref:DEC-haskell-grammar-fixes
prop_aHaskellOperatorIsOneTokenByMaximalMunch :: Property
prop_aHaskellOperatorIsOneTokenByMaximalMunch = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Operators ((==>), (>=>), (..:), ($$), (#.), (-->)) where"
      , "import qualified Data.Map as Map"
      , "a ==> b = b"
      , "f >=> g = g"
      , "x ..: y = x Map.! y"
      , "x $$ y = x C.. y"
      , "f #. g = f"
      , "a --> b = a"
      , "h = (Map.!) Map.empty"
      ]

-- | Real modules export pattern synonyms, type operators with their namespace or in parentheses with
-- members, and members that mix the two dots with names, and import with qualified after the module
-- name, a package name, or safe; GHC accepts all of them. ref:REQ-haskell-support
-- ref:DEC-haskell-grammar-fixes
prop_haskellImportsAndExportsNamePatternSynonymsTypeOperatorsAndPackages :: Property
prop_haskellImportsAndExportsNamePatternSynonymsTypeOperatorsAndPackages = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Exports"
      , "  ( pattern Infinity"
      , "  , type (&&)"
      , "  , (:~:)(Refl)"
      , "  , Shape(.., Square)"
      , "  , interruptible"
      , "  , module Data.List"
      , "  ) where"
      , "import Data.List qualified as List"
      , "import \"extra\" Data.List.Extra (lower)"
      , "import safe Data.Maybe (pattern Nothing, type (~))"
      , "import Text.Printf ((#.))"
      , "interruptible = 1"
      ]

-- | NumericUnderscores, binary literals, and MagicHash literals are in ghc's base, and a string of
-- numeric escapes such as canon's own Unicode tables must lex in time linear in its length; e-1 in
-- show (e-1) is a name, a minus, and a number, not an exponent. ref:REQ-haskell-support
-- ref:DEC-haskell-grammar-fixes
prop_haskellLiteralsTakeUnderscoresBinaryDigitsMagicHashesAndManyEscapes :: Property
prop_haskellLiteralsTakeUnderscoresBinaryDigitsMagicHashesAndManyEscapes = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Literals where"
      , "million = 1_000_000 + 0x_ff + 0b1010 + 1.5e-3"
      , "unboxed = (\"bytes\"# , 'c'#, 1#, 2##, 1.0##)"
      , "showE e = show (e-1)"
      , "table = \"" <> T.concat (replicate 40 "\\x1885\\x1886\\2118") <> "\\SOH\\&9\""
      ]

-- | With QuasiQuotes a bracket, a quoter, and a bar open a quasi-quotation whose body the quoter
-- reads, so its text need not be Haskell; without the extension, [x|x<-xs] is a list comprehension,
-- and [e| opens Template Haskell's own expression quotation. ref:REQ-haskell-support
-- ref:DEC-haskell-grammar-fixes
prop_aHaskellQuasiQuotationIsOneTokenOnlyWhereQuasiQuotesIsEnabled :: Property
prop_aHaskellQuasiQuotationIsOneTokenOnlyWhereQuasiQuotesIsEnabled = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# LANGUAGE QuasiQuotes #-}"
      , "module Quotes where"
      , "dir = [reldir|hooks|]"
      , "json = [aesonQQ| {\"string\": \"\\/\", \"n\": 2e-3} |]"
      , "table = [P.persistLowerCase|"
      , "  User"
      , "    name Text default=\"x\""
      , "|]"
      , "expr = [e|KM.toList|]"
      ]
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Comprehension where"
      , "odds xs = [x|x<-xs, odd x]"
      , "evens xs = [x|x<-xs, even x]"
      , "expr = [e|toList|]"
      ]

-- | GHC closes an implicit block at a token it cannot hold and opens an empty one where a body is
-- empty, and real modules rely on both: an empty module or case, a record's closing brace level with
-- the statements of a do, a second guard of a case alternative after a do, a where after nested do
-- blocks, a let inside a guard before the guard's next comma, unboxed tuples and declaration
-- quotations as brackets, and rec as a name where RecursiveDo is off. ref:REQ-haskell-support
-- ref:DEC-haskell-grammar-fixes ref:DEC-layout-parse-error-rule
prop_theHaskellLayoutClosesBlocksWhereGhcsParseErrorRuleDoes :: Property
prop_theHaskellLayoutClosesBlocksWhereGhcsParseErrorRuleDoes = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars "module Lib where\n"
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# LANGUAGE EmptyCase, UnboxedTuples, TemplateHaskell #-}"
      , "module Layout where"
      , "absurd x = case x of"
      , ""
      , "size = do"
      , "  return Size {"
      , "    width = 1"
      , "  , height = 2"
      , "  }"
      , ""
      , "image x = case x of"
      , "  Just y | y > 0 -> do"
      , "    report y"
      , "    return y"
      , "    | otherwise -> do"
      , "      return 0"
      , "  Nothing -> return 0"
      , ""
      , "control = do"
      , "  x <- get"
      , "  m <|> do"
      , "    y <- lexMacro"
      , "    return y"
      , "      where"
      , "        l = 1"
      , ""
      , "normal p = case p of"
      , "  (l:rs)"
      , "    | isLower l"
      , "    , let (seps, path) = span isSep rs"
      , "    , length seps > 1 -> path"
      , "  _ -> p"
      , ""
      , "newArray (I# n#) ="
      , "  ST (\\s# -> case newArray# n# s# of"
      , "    (# s1, arr #) -> (# s1, M arr #))"
      , ""
      , "declareLenses [d|"
      , "  data Quark = Quark { gaffer :: Int }"
      , "              | Other"
      , "  |]"
      , ""
      , "lookupField rec obj key = rec"
      ]

-- | GHC accepts constructors on a data instance, a type application between arguments, a record
-- wildcard after named fields, a type annotation in a pattern guard, and nested block comments, and
-- ghc's base and aeson use each. ref:REQ-haskell-support ref:DEC-haskell-grammar-fixes
prop_haskellDeclarationsAndExpressionsGhcAcceptsParse :: Property
prop_haskellDeclarationsAndExpressionsGhcAcceptsParse = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Declarations where"
      , "data family Nullary a"
      , "data instance Nullary Int = C1 | C2 deriving (Eq, Show)"
      , "newtype instance Cast Nat l r = CastNat { runCastNat :: l }"
      , "example = ExG @Int 1 Nothing"
      , "flags i@Internal.GCFlags{..} = GCFlags { giveStats = 1, .. }"
      , "handle dev"
      , "  | Just h <- cast dev :: Maybe Handle = h"
      , "{- an outer comment {- with an inner one -}"
      , "   and {-# INLINE inside #-} -}"
      , "done = ()"
      ]

-- | Haddock documents a section of the export list and a record field with a comment in place, and
-- pandoc and ghc's base do both throughout; canon reads such a comment where it stands as an orphan,
-- since neither is a unit, so a module with many of them parses once rather than once per comment.
-- ref:REQ-haskell-support ref:DEC-haskell-dialect ref:DEC-stray-comments
prop_aHaddockCommentInAnExportListOrOnARecordFieldIsAnOrphanReadInPlace :: Property
prop_aHaddockCommentInAnExportListOrOnARecordFieldIsAnOrphanReadInPlace = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "module Sections"
          , "  ( -- | The state."
          , "    State (..)"
          , "  , -- | A section."
          , "    f"
          , "  ) where"
          , ""
          , "-- | The reader's state."
          , "data State = State"
          , "  { -- | A field."
          , "    styles :: Int"
          , "    -- | Another field."
          , "  , depth :: Int"
          , "  }"
          , ""
          , "-- | A function."
          , "f :: Int"
          , "f = 1"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Sections.hs" "Sections.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [renderUnitId u | d <- modelDecisions model, u <- toList (decisionUnits d)] === ["haskell/Sections.hs/module/Sections/data/State", "haskell/Sections.hs/module/Sections/function/f"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [2, 4, 10, 12]

-- | A syntax error must fail fast and point at itself, and the dialect looks for a stray comment near
-- it, reading each comment within reach of the failure from at most the tokens up to the failure, so
-- documented declarations before the error neither move the report nor cost a parse of the rest of
-- the file each. ref:REQ-haskell-support ref:DEC-stray-comments
prop_aHaskellSyntaxErrorAfterDocCommentsIsReportedWhereItIs :: Property
prop_aHaskellSyntaxErrorAfterDocCommentsIsReportedWhereItIs = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/haskell/canonically_commented/HaskellLexer.g4" "grammars/haskell/canonically_commented/HaskellParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          ( ["module Broken where", "-- | The first.", "a :: Int", "a = 1", "-- | The second.", "b :: Int", "b = 2", "broken = (( ]"]
              ++ concat [["-- | Function " <> T.pack (show i) <> ".", "f" <> T.pack (show i) <> " = " <> T.pack (show i)] | i <- [1 .. 200 :: Int]]
          )
  case interpretText interpreter (Name "module") "Broken.hs" source of
    Left err -> assert ("Broken.hs:8:13" `T.isInfixOf` renderInterpretError err)
    Right _ -> failure

