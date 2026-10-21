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
    , testProperty "the Java grammar and dialect read the Java 21 to 25 syntax widely used projects write" prop_theJavaGrammarAndDialectReadTheJava21To25SyntaxWidelyUsedProjectsWrite
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
    , testProperty "a case alternative's body with no guard ends at a comprehension's bar" prop_aCaseAlternativesBodyWithNoGuardEndsAtAComprehensionsBar
    , testProperty "a let in a guard ends at the guard's next comma" prop_aLetInAGuardEndsAtTheGuardsNextComma
    , testProperty "a do block that is a case's scrutinee ends at the of" prop_aDoBlockThatIsACasesScrutineeEndsAtTheOf
    , testProperty "a do block ends at the guard that follows it" prop_aDoBlockEndsAtTheGuardThatFollowsIt
    , testProperty "a let with explicit braces leaves its in nothing to close" prop_aLetWithExplicitBracesLeavesItsInNothingToClose
    , testProperty "a bar or comma a block can hold leaves the block open" prop_aBarOrCommaABlockCanHoldLeavesTheBlockOpen
    , testProperty "explicit braces suspend the layout around them, as ghc's compiler writes them" prop_explicitBracesSuspendTheLayoutAroundThemAsGhcsCompilerWritesThem
    , testProperty "a let in a guard ends at the guard's own equals sign or arrow on a later line" prop_aLetInAGuardEndsAtTheGuardsOwnEqualsSignOrArrowOnALaterLine
    , testProperty "an operator, a deriving clause, or a pragma that starts a line is read as GHC reads it" prop_anOperatorDerivingClauseOrPragmaThatStartsALineIsReadAsGhcReadsIt
    , testProperty "Haskell declarations and expressions GHC accepts parse" prop_haskellDeclarationsAndExpressionsGhcAcceptsParse
    , testProperty "a Haddock comment in an export list is an orphan read in place" prop_aHaddockCommentInAnExportListIsAnOrphanReadInPlace
    , testProperty "a Haskell syntax error after doc comments is reported where it is" prop_aHaskellSyntaxErrorAfterDocCommentsIsReportedWhereItIs
    , testProperty "a Haddock comment before a constructor documents it, wherever Haddock reads it" prop_aHaddockCommentBeforeAConstructorDocumentsItWhereverHaddockReadsIt
    , testProperty "constructor Haddock parses through the plain grammar and binds through a profile's constructor rule" prop_constructorHaddockParsesThroughThePlainGrammarAndBindsThroughAProfilesConstructorRule
    , testProperty "a Haddock comment before a record field documents it, wherever Haddock reads it" prop_aHaddockCommentBeforeARecordFieldDocumentsItWhereverHaddockReadsIt
    , testProperty "record field Haddock parses through the plain grammar" prop_recordFieldHaddockParsesThroughThePlainGrammar
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

-- | Widely used Java projects, the JDK, Guava, and Elasticsearch among them, write record patterns
-- whose components are declared with var or are the unnamed pattern, type annotations on the type
-- and dimensions an array creation makes, module imports, compact source files that declare methods
-- and fields at the top level, and a module's Javadoc below its imports. The plain grammar and the
-- dialect must read each, and the dialect bind the Javadoc of a top-level method and of a module
-- declared after imports. ref:REQ-java-support ref:DEC-java-grammar
prop_theJavaGrammarAndDialectReadTheJava21To25SyntaxWidelyUsedProjectsWrite :: Property
prop_theJavaGrammarAndDialectReadTheJava21To25SyntaxWidelyUsedProjectsWrite = withTests 1 $ property $ do
  let load lexer parser = do
        loaded <- evalIO (loadInterpreter lexer parser)
        either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
      parses interpreter source = either (Left . T.unpack . renderInterpretError) (const (Right ())) (interpretText interpreter (Name "compilationUnit") "A.java" source)
      sources =
        [ "class A { boolean f(Object o) { return o instanceof P(var x, _) && x != null; } }"
        , "class A { int f(Object o) { return switch (o) { case P.N(final var c, P.M(var d)) when c > 0 -> 1; default -> 0; }; } }"
        , "class A { void f() { Object[] a = new @Nullable Object[3]; int[] b = new @A int @B [2]; Object c = new p.@B C<D>(); } }"
        , "import module java.base;\nclass A {}"
        , "import module java.base;\nvoid main() { IO.println(greeting); }\nString greeting = \"hi\";"
        , "import a.B;\n/** The server. */\nmodule org.example.server { requires java.logging; }"
        ]
  plain <- load "grammars/java/JavaLexer.g4" "grammars/java/JavaParser.g4"
  dialect <- load "grammars/java/canonically_commented/JavaLexer.g4" "grammars/java/canonically_commented/JavaParser.g4"
  map (parses plain) sources === map (const (Right ())) sources
  map (parses dialect) sources === map (const (Right ())) sources
  loaded <- evalIO (loadProfileInterpreter javaProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let whys path source = do
        result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "java" javaProfile interpreter path path source)
        Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
        pure ([(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- toList (decisionUnits d)], length [() | OrphanDocComment _ _ <- findings])
  compact <- whys "Main.java" "import module java.base;\n\n/** Greets. */\nvoid main() { IO.println(\"hi\"); }\n"
  compact === ([("java/Main.java/method/main", "Greets.")], 0)
  modular <- whys "module-info.java" "/** Stray. */\nimport a.B;\n\n/** The server. */\nmodule org.example.server { requires java.logging; }\n"
  modular === ([("java/module-info.java/module/org.example.server", "The server.")], 1)

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

-- | GHC closes a case alternative's block at a bar that follows the alternative's body when the
-- alternative has no guard, so a case written inside a list comprehension compiles; LawSpec had to
-- parenthesise such cases in Core, Core.Types, Indexed, Model, Refinement, DomainModel and its typed
-- emitters until canon read them. ref:REQ-haskell-support ref:DEC-layout-parse-error-rule
-- ref:DEC-layout-bars-commas-and-of
prop_aCaseAlternativesBodyWithNoGuardEndsAtAComprehensionsBar :: Property
prop_aCaseAlternativesBodyWithNoGuardEndsAtAComprehensionsBar = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Comprehension where"
      , "substituteIn table t = case t of"
      , "  TypeVariable v -> fromMaybe t (lookup v table)"
      , "  Constructor n as -> Constructor n [case a of TypeArgument x -> TypeArgument (substituteIn table x); o -> o | a <- as]"
      , "  other -> other"
      , "typeNames (RefinementApp _ args) = concat [case a of TypeArgument t -> typeNames t; ValueArgument e -> exprVars e | a <- args]"
      , "substituteIndices substitution ty = case ty of"
      , "  Constructor n args -> Constructor n"
      , "    [case a of ValueArgument e -> ValueArgument (replaceExprVars substitution e)"
      , "               TypeArgument t -> TypeArgument (substituteIndices substitution t) | a <- args]"
      , "  other -> other"
      , "outputs infos = [\\case Application \"Either\" [_, n] -> n; r -> r | (_, r) <- infos]"
      , "guarded x | isJust x = case x of Just y -> y | otherwise = 0"
      ]

-- | GHC closes a let opened in a guard at the comma that follows its bindings, where the guard's
-- next condition begins; LawSpec's Testing had to bind by a pattern guard instead.
-- ref:REQ-haskell-support ref:DEC-layout-parse-error-rule ref:DEC-layout-bars-commas-and-of
prop_aLetInAGuardEndsAtTheGuardsNextComma :: Property
prop_aLetInAGuardEndsAtTheGuardsNextComma = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Guards where"
      , "finiteScalars bits limit name"
      , "  | Just (lo,hi) <- integerBounds bits name, hi-lo+1 <= fromIntegral limit ="
      , "      Just [ScalarValue (SInteger name x) | x <- [lo..hi]]"
      , "  | name `elem` [\"Bool\", \"Unit\"],"
      , "      let values = map ScalarValue (scalarBoundaries bits name), length values <= limit = Just values"
      , "  | otherwise = Nothing"
      , "pick x = case x of"
      , "  Just y | let z = y + 1, z > 0 -> z"
      , "  _ -> 0"
      ]

-- | GHC closes the blocks opened since a case at its of, so a do block may be the case's
-- scrutinee; LawSpec's Core.Eval had to name the do block in a let instead.
-- ref:REQ-haskell-support ref:DEC-layout-parse-error-rule ref:DEC-layout-bars-commas-and-of
prop_aDoBlockThatIsACasesScrutineeEndsAtTheOf :: Property
prop_aDoBlockThatIsACasesScrutineeEndsAtTheOf = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Scrutinee where"
      , "every index (item:rest) = do"
      , "  accepted <- case do"
      , "    checked <- validate item"
      , "    run checked >>= valueBoolean of"
      , "      Left message -> Left (show index ++ message)"
      , "      Right result -> Right result"
      , "  if accepted then every (index + 1) rest else Right False"
      , "inline m = case do { x <- m; pure x } of Just y -> y; Nothing -> 0"
      ]

-- | GHC closes a do block at a bar that continues its last statement, since no statement holds a
-- bar, so a binding's second guard may follow a do block in its first; LawSpec's RustEmit had to
-- reorder its guards. A multi-way if's bars stay in the block. ref:REQ-haskell-support
-- ref:DEC-layout-parse-error-rule ref:DEC-layout-bars-commas-and-of
prop_aDoBlockEndsAtTheGuardThatFollowsIt :: Property
prop_aDoBlockEndsAtTheGuardThatFollowsIt = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# LANGUAGE MultiWayIf #-}"
      , "module Bars where"
      , "callbacks entries = forM entries $ \\(index, contract) -> do"
      , "    let reference ty = do"
      , "          ref <- typeReference ty"
      , "          pure ref"
      , "        key ty | variable ty = do"
      , "          ref <- typeReference ty"
      , "          pure (text \"&\" <> ref)"
      , "               | otherwise = pure (text (typeName ty))"
      , "    key index"
      , "choose x = do"
      , "  y <- if | x > 0 -> pure 1"
      , "          | otherwise -> pure 2"
      , "  pure y"
      ]

-- | A let with explicit braces is closed by its own brace, so the in after it closes no block
-- around it; LawSpec's runtime had to write such lets with layout.
-- ref:REQ-haskell-support ref:DEC-layout-parse-error-rule ref:DEC-layout-bars-commas-and-of
prop_aLetWithExplicitBracesLeavesItsInNothingToClose :: Property
prop_aLetWithExplicitBracesLeavesItsInNothingToClose = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Braces where"
      , "helper n args bits = case (n,args) of"
      , "  (\"round\",[a,b]) ->"
      , "    let { x = either error id (exactValue a)"
      , "        ; scale = either error numerator (exactValue (convert \"Int32\" b bits))"
      , "        ; factor = if scale >= 0 then 10^scale % 1 else 1 % 10^(-scale)"
      , "        }"
      , "    in either error id (decimal (fromInteger (round (x*factor)) / factor))"
      , "  _ -> error \"unknown helper or wrong arity\""
      , "sample t = do"
      , "  let { n = case t of Just m -> m; Nothing -> 0 }"
      , "  pure n"
      ]

-- | The bars and commas a block can hold leave it open: a guarded alternative's next guard, a
-- multi-way if's guards and their commas, a binding's guard commas, and a let's signature naming
-- several bindings. ref:REQ-haskell-support ref:DEC-layout-parse-error-rule
-- ref:DEC-layout-bars-commas-and-of
prop_aBarOrCommaABlockCanHoldLeavesTheBlockOpen :: Property
prop_aBarOrCommaABlockCanHoldLeavesTheBlockOpen = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# LANGUAGE MultiWayIf #-}"
      , "module Open where"
      , "sign x = case x of n | n > 0 -> 1 | n < 0, odd n -> -1 | otherwise -> 0"
      , "signs x = [case x of n | n > 0 -> 1 | otherwise -> 0, 2]"
      , "grade x = do"
      , "  if | x > 90, even x -> pure 'A' | otherwise -> pure 'B'"
      , "pair = let a, b :: Int"
      , "           a = 1"
      , "           b = 2 in (a, b)"
      , "small = let f x | x > 0, x < 10 = True"
      , "                | otherwise = False in f 3"
      , "class Convert a b | a -> b where"
      , "  convert :: a -> b"
      , "data Shape = Circle | Square"
      ]

-- | Inside an explicit brace, a layout keyword's or a record's, the Haskell report suspends the
-- layout of the blocks around it, and ghc's compiler relies on it: statement and declaration lists
-- that begin with semicolons, a case's explicit alternatives whose last opens a do block at the
-- enclosing statements' indentation, a closing brace that starts a line below the blocks it is
-- inside, and a record whose fields stand level with the let that binds it.
-- ref:REQ-haskell-support ref:DEC-layout-bars-commas-and-of
prop_explicitBracesSuspendTheLayoutAroundThemAsGhcsCompilerWritesThem :: Property
prop_explicitBracesSuspendTheLayoutAroundThemAsGhcsCompilerWritesThem = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Braces where"
      , "derive x ="
      , "    do  {"
      , "        -- the deriving stuff"
      , "        ; traceTc \"rnd\" x"
      , "        ; let  { ; !rules = update x"
      , "               ; other = 2 }"
      , "        ; rec { a <- g b"
      , "              ; b <- h a }"
      , "        ; return a }"
      , "ticks pos = do"
      , "  tickish <- getEnv"
      , "  case tickish of { ProfNotes | inline -> return pos; _ -> do"
      , ""
      , "  selTicks <- recSelTick pos"
      , "  return selTicks }"
      , "check r = do { case r of Stale reason -> return reason ; _ -> do {"
      , "       ; when oneShot $ do {"
      , "          ; update 1"
      , "       }"
      , "       ; recomp <- check r"
      , "       ; return recomp } }"
      , "summary = do"
      , "    let ms = ModSummary {"
      , "        ms_mod = m,"
      , "        ms_parsed = Just (Parsed {"
      , "                hpm_module = 1"
      , "            }),"
      , "        ms_file = \"\""
      , "        }"
      , "    return ms"
      ]

-- | A let in a guard ends at the guard's own equals sign, or a case alternative's arrow, even on a
-- later line or after a record pattern spread over lines, while a let's signature and a pattern
-- binding with a signature and guards keep their arrows and bars. ref:REQ-haskell-support
-- ref:DEC-layout-bars-commas-and-of
prop_aLetInAGuardEndsAtTheGuardsOwnEqualsSignOrArrowOnALaterLine :: Property
prop_aLetInAGuardEndsAtTheGuardsOwnEqualsSignOrArrowOnALaterLine = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module GuardLets where"
      , "isSrc (TyCon { tyConDetails = details })"
      , "  | AlgTyCon { algTcRhs = rhs } <- details"
      , "  , let isSrcParent = isNoParent parent"
      , "              = case rhs of"
      , "                   DataTyCon {}  -> isSrcParent"
      , "                   _             -> False"
      , "  | otherwise = False"
      , "update range mb"
      , "  | Just prev <- mb"
      , "  , let Edits"
      , "          { insertEdit = prevInsert"
      , "          , deleteEdit = prevDelete } = prev"
      , "  , let start = prevInsert"
      , "  = start"
      , "  | otherwise = range"
      , "annotate w = case w of"
      , "  Wrapper value | let serialized = toSerialized value ->"
      , "      serialized"
      , "  _ -> \\x -> x"
      , "frame = do"
      , "     let apply :: [Fit] -> ([Fit] -> M [Fit]) -> M [Fit]"
      , "         apply fits f = f fits"
      , "         header :: Int"
      , "           | tupleFrame = 3"
      , "           | otherwise = 1"
      , "     return header"
      ]

-- | No statement starts with an infix operator, so one that starts a line level with a do block
-- applies to the block; a deriving clause ends a GADT's constructors; a pragma that starts a line, as
-- an SCC before a statement, is the line's first lexeme; a record field's pattern may be a view
-- pattern; and \cases opens alternatives of several patterns. ghc's compiler and ghcide write each.
-- ref:REQ-haskell-support ref:DEC-layout-bars-commas-and-of
prop_anOperatorDerivingClauseOrPragmaThatStartsALineIsReadAsGhcReadsIt :: Property
prop_anOperatorDerivingClauseOrPragmaThatStartsALineIsReadAsGhcReadsIt = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "{-# LANGUAGE LambdaCase, GADTs, ViewPatterns, TypeFamilies #-}"
      , "module Lines where"
      , "data Message where"
      , "  Unknown :: Int -> Message"
      , "  {- | Too many."
      , "  -}"
      , "  TooMany :: Message"
      , "  deriving Generic"
      , "instance Family Int where"
      , "  data Key Int where"
      , "    IntKey :: Key Int"
      , "    deriving Show"
      , "  size = 1"
      , "lookupBoth env name = do"
      , "  lookupNameEnv (home env) name"
      , "  <|> lookupNameEnv (external env) name"
      , "output config = do"
      , "  let platform = config"
      , "  {-# SCC \"seqString\" #-} evaluate platform"
      , "  return ()"
      , "kind (FamDecl { fam ="
      , "  FamilyDecl { name     = unLoc -> n"
      , "             , tyVars   = vs } }) = n"
      , "mkRange = \\cases"
      , "  (Just x) (Just y) | x > y -> Nothing"
      , "  x y -> Just (x, y)"
      , "run = do"
      , "  setup"
      , "  do"
      , "    serve"
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

-- | Haddock documents a section of the export list with a comment in place, and pandoc and ghc's
-- base do so throughout; canon reads such a comment where it stands as an orphan, since a section is
-- no unit, so a module with many of them parses once rather than once per comment. A record field's
-- comment, read in place as an orphan before canon 0.2.3, documents its field.
-- ref:REQ-haskell-support ref:DEC-haskell-dialect ref:DEC-stray-comments ref:DEC-haskell-field-haddock
prop_aHaddockCommentInAnExportListIsAnOrphanReadInPlace :: Property
prop_aHaddockCommentInAnExportListIsAnOrphanReadInPlace = withTests 1 $ property $ do
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
  [renderUnitId u | d <- modelDecisions model, u <- toList (decisionUnits d)]
    === [ "haskell/Sections.hs/module/Sections/data/State"
        , "haskell/Sections.hs/module/Sections/data/State/field/styles"
        , "haskell/Sections.hs/module/Sections/data/State/field/depth"
        , "haskell/Sections.hs/module/Sections/function/f"
        ]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [2, 4]

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


-- | Haddock documents a constructor with a comment above it, standing above the bar or equals sign,
-- as LawSpec's DotNet code writes -- | doc above | C, or after it, as ormolu writes | -- | doc above
-- C, and above a GADT constructor; canon 0.2.1 reported each as an orphan that could not be exempted.
-- The dialect binds the comment to the constructor, a unit of kind constructor named by its
-- constructor, prefix, infix, backticked, record, existential, or strict; an undocumented
-- constructor is no unit, so no other unit's id, Why, or requirement changes, and a constructor
-- needs no comment, documented ones always holding theirs. A record field's comment documents its
-- field. ref:DEC-haskell-constructor-haddock ref:DEC-haskell-field-haddock ref:REQ-haskell-support
prop_aHaddockCommentBeforeAConstructorDocumentsItWhereverHaddockReadsIt :: Property
prop_aHaddockCommentBeforeAConstructorDocumentsItWhereverHaddockReadsIt = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "{-# LANGUAGE GADTs, ExistentialQuantification #-}"
          , "module Ctors (Expr (..), Op (..), G (..), N (..)) where"
          , ""
          , "-- | An expression."
          , "data Expr"
          , "  = Var String"
          , "  | Call String [Expr]"
          , "  -- | A constructor applied to a tuple of arguments, as both"
          , "  -- languages write it."
          , "  | Ctor String [Expr]"
          , "  | Let String Expr Expr"
          , "  -- | Unit-valued effects, then a value."
          , "  | Do [Expr] Expr"
          , "  deriving (Eq, Show)"
          , ""
          , "-- | Operators, as ormolu lays them out."
          , "data Op"
          , "  -- | Before the equals sign."
          , "  = Plus Int Int"
          , "  | -- | After the bar."
          , "    Int :+ Int"
          , "  | -- | Backticked."
          , "    Int `Minus` Int"
          , "  | -- | A record."
          , "    Rec"
          , "      { -- | A field."
          , "        field :: Int"
          , "      }"
          , "  | -- | Existential."
          , "    forall a. Show a => Some a"
          , "  | -- | Strict."
          , "    Strict !Int {-# UNPACK #-} !Int"
          , "  | Plain"
          , ""
          , "-- | A GADT."
          , "data G a where"
          , "  -- | An int."
          , "  GInt :: Int -> G Int"
          , "  GBool :: Bool -> G Bool"
          , ""
          , "-- | A newtype."
          , "newtype N = -- | The wrapper."
          , "  N Int"
          ]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Ctors.hs" "Ctors.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- toList (decisionUnits d), "/constructor/" `T.isInfixOf` renderUnitId u]
    === [ ("haskell/Ctors.hs/module/Ctors/data/Expr/constructor/Ctor", "A constructor applied to a tuple of arguments, as both\nlanguages write it.")
        , ("haskell/Ctors.hs/module/Ctors/data/Expr/constructor/Do", "Unit-valued effects, then a value.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Plus", "Before the equals sign.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/:+", "After the bar.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Minus", "Backticked.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Rec", "A record.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Rec/field/field", "A field.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Some", "Existential.")
        , ("haskell/Ctors.hs/module/Ctors/data/Op/constructor/Strict", "Strict.")
        , ("haskell/Ctors.hs/module/Ctors/data/G/constructor/GInt", "An int.")
        , ("haskell/Ctors.hs/module/Ctors/newtype/N/constructor/N", "The wrapper.")
        ]
  let units = modelAllUnits model
  [whatName (answerValue (unitWhat u)) | u <- units, kindOf u /= "file", kindOf u /= "constructor", kindOf u /= "field"] === ["Ctors", "Expr", "Op", "G", "N"]
  [whatName (answerValue (unitWhat u)) | u <- units, kindOf u == "field"] === ["field"]
  [howText | u <- units, whatName (answerValue (unitWhat u)) == "Ctor", HowText howText <- [answerValue (unitHow u)]] === ["Ctor String [Expr]"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === []
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

-- | The plain grammar skips comments, so it reads every placement of a constructor's Haddock, and a
-- profile that makes the grammar's constr rule a unit binds the comment above a constructor to it,
-- as Haddock does; one above a GADT constructor binds where the profile makes gadt_constr a unit,
-- and is an orphan here. ref:DEC-haskell-constructor-haddock ref:REQ-haskell-support
prop_constructorHaddockParsesThroughThePlainGrammarAndBindsThroughAProfilesConstructorRule :: Property
prop_constructorHaddockParsesThroughThePlainGrammarAndBindsThroughAProfilesConstructorRule = withTests 1 $ property $ do
  let source =
        T.unlines
          [ "module Plain where"
          , ""
          , "-- | An expression."
          , "data Expr"
          , "  = Var String"
          , "  -- | Unit-valued effects, then a value."
          , "  | Do [Expr] Expr"
          , "  | -- | After the bar."
          , "    Lit Int"
          , ""
          , "-- | A GADT."
          , "data G a where"
          , "  -- | An int."
          , "  GInt :: Int -> G Int"
          ]
      syntax = defaultCommentSyntax {commentLine = Just "--", commentBlockOpen = Just "{-", commentBlockClose = Just "-}", commentOuterDoc = ["-- |"]}
      profile =
        Profile
          [".hs"]
          (SplitGrammarFiles "grammars/haskell/HaskellLexer.g4" "grammars/haskell/HaskellParser.g4")
          (Name "module")
          [ UnitRule (Name "ty_decl") "data" (NameFromToken (Name "CONID") 0) True Nothing False
          , UnitRule (Name "constr") "constructor" (NameFromToken (Name "CONID") 0) False Nothing False
          ]
          syntax
          Map.empty
          Map.empty
          Map.empty
          []
  parsesThroughBothHaskellGrammars source
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" profile interpreter "Plain.hs" "Plain.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- toList (decisionUnits d), "/constructor/" `T.isInfixOf` renderUnitId u]
    === [("haskell/Plain.hs/data/Expr/constructor/Do", "Unit-valued effects, then a value."), ("haskell/Plain.hs/data/Expr/constructor/Lit", "After the bar.")]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [13]

-- | Haddock documents a record field with a comment before it, standing after the opening brace, above
-- the field's comma, or after that comma as ormolu and fourmolu write it, one line or several, and
-- with -- ^ after it, which canon reads as a plain comment; canon 0.2.2 reported each comment before
-- a field as an orphan that could not be exempted, so Ironframe's Manifest/Types.hs failed canon
-- check. The dialect binds the comment to the field, a unit of kind field named by its first name;
-- an undocumented field is no unit, so no other unit's id, Why, or requirement changes, and a field
-- needs no comment. Of two comments the last binds, and one after the last field is an orphan read in
-- place. ref:DEC-haskell-field-haddock ref:REQ-haskell-support
prop_aHaddockCommentBeforeARecordFieldDocumentsItWhereverHaddockReadsIt :: Property
prop_aHaddockCommentBeforeARecordFieldDocumentsItWhereverHaddockReadsIt = withTests 1 $ property $ do
  loaded <- evalIO (loadProfileInterpreter haskellProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "module Fields (Twin (..), Pair (..), Plain (..)) where"
          , ""
          , "-- | A twin, as Ironframe's manifest declares it."
          , "data Twin = Twin"
          , "  { -- | After the brace."
          , "    twinName :: Text"
          , "  , twinPorts :: [Integer]"
          , "  , -- | The conformance report named by @conformance.report@, read when the"
          , "    -- manifest was loaded; never serialised."
          , "    twinReport :: Maybe Report"
          , "  -- | Above the comma."
          , "  , twinSeed :: Maybe Integer"
          , "  , twinEnv :: Map Text Text -- ^ After the field, a plain comment."
          , "  , -- | Several names."
          , "    twinLow, twinHigh :: !Int"
          , "  , {-| A block comment"
          , "      over two lines. -}"
          , "    twinBlock :: Int"
          , "  -- | Not this one."
          , "  , -- | This one."
          , "    twinLast :: Int"
          , "  -- | After the last field."
          , "  }"
          , ""
          , "-- | Fields documented with -- ^ alone."
          , "data Pair = Pair"
          , "  { first :: Int"
          , "  -- ^ The first."
          , "  , second :: Int"
          , "  -- ^ The second."
          , "  }"
          , ""
          , "-- | No field documented."
          , "data Plain = Plain {plainA :: Int, plainB, plainC :: Bool}"
          , ""
          , "-- | A newtype's field."
          , "newtype N = N"
          , "  { -- | The wrapped value."
          , "    unN :: Int"
          , "  }"
          ]
  parsesThroughBothHaskellGrammars source
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "haskell" haskellProfile interpreter "Fields.hs" "Fields.hs" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- toList (decisionUnits d), "/field/" `T.isInfixOf` renderUnitId u]
    === [ ("haskell/Fields.hs/module/Fields/data/Twin/field/twinName", "After the brace.")
        , ("haskell/Fields.hs/module/Fields/data/Twin/field/twinReport", "The conformance report named by @conformance.report@, read when the\nmanifest was loaded; never serialised.")
        , ("haskell/Fields.hs/module/Fields/data/Twin/field/twinSeed", "Above the comma.")
        , ("haskell/Fields.hs/module/Fields/data/Twin/field/twinLow", "Several names.")
        , ("haskell/Fields.hs/module/Fields/data/Twin/field/twinBlock", "A block comment\nover two lines.")
        , ("haskell/Fields.hs/module/Fields/data/Twin/field/twinLast", "This one.")
        , ("haskell/Fields.hs/module/Fields/newtype/N/field/unN", "The wrapped value.")
        ]
  let units = modelAllUnits model
  [whatName (answerValue (unitWhat u)) | u <- units, kindOf u /= "file", kindOf u /= "field"] === ["Fields", "Twin", "Pair", "Plain", "N"]
  [howText | u <- units, whatName (answerValue (unitWhat u)) == "twinLow", HowText howText <- [answerValue (unitHow u)]] === ["twinLow, twinHigh :: !Int"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [19, 22]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

-- | The plain grammar skips comments, so it reads every placement of a record field's Haddock, and so
-- does the Haskell corpus's plain reading of every file that documents a field.
-- ref:DEC-haskell-field-haddock ref:REQ-haskell-support
prop_recordFieldHaddockParsesThroughThePlainGrammar :: Property
prop_recordFieldHaddockParsesThroughThePlainGrammar = withTests 1 $ property $ do
  parsesThroughBothHaskellGrammars $
    T.unlines
      [ "module Plain where"
      , ""
      , "data R = R"
      , "  { -- | After the brace."
      , "    a :: Int"
      , "  , -- | After the comma,"
      , "    -- over two lines."
      , "    b :: Int"
      , "  -- | Above the comma."
      , "  , c :: Int"
      , "  , d :: Int -- ^ After the field."
      , "  -- ^ Below it."
      , "  }"
      ]
