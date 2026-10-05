-- | Prolog is read through the vendored grammars-v4 Prolog grammar and the profile the marelle sample
-- ships, and through canon's canonically commented dialect of it, so these properties check both
-- against what a Prolog author means by a predicate and its PlDoc comment.
-- ref:DEC-prolog-grammar-fixes ref:DEC-prolog-dialect ref:REQ-prolog-support
module Canon.Extract.PrologTest (tests) where

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
import qualified Data.List.NonEmpty as NonEmpty
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
    "prolog"
    [ testProperty "the Prolog profile parses every file of the marelle sample into its clauses" prop_thePrologProfileParsesEveryFileOfTheMarelleSampleIntoItsClauses
    , testProperty "the Prolog dialect parses the marelle sample into its predicates" prop_thePrologDialectParsesTheMarelleSampleIntoItsPredicates
    , testProperty "the Prolog dialect binds PlDoc comments to predicates and reports misplaced ones" prop_thePrologDialectBindsPlDocCommentsToPredicatesAndReportsMisplacedOnes
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/prolog-marelle"

-- | The Prolog files of the marelle sample, every one of which must parse.
sampleFiles :: [FilePath]
sampleFiles =
  [ "00-util.pl"
  , "01-python.pl"
  , "02-fs.pl"
  , "03-homebrew.pl"
  , "04-apt.pl"
  , "05-git.pl"
  , "06-meta.pl"
  , "07-managed.pl"
  , "08-pacman.pl"
  , "09-freebsd.pl"
  , "marelle.pl"
  , "sudo.pl"
  , "test_marelle.pl"
  ]

-- | The profile as the sample's canon.yaml declares it, with its grammar path made relative to the
-- repository root, so the test reads the profile a Prolog project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "prolog" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the Prolog grammar, with no units of a profile and no
-- comment syntax, so every unit and every Why comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".pl"] (SplitGrammarFiles "grammars/prolog/canonically_commented/PrologLexer.g4" "grammars/prolog/canonically_commented/PrologParser.g4") (Name "p_text") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | An extraction of one text through a profile.
extractThrough :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractThrough profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "prolog" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Every file of the sample extracted through a profile, each with its own path as its id path.
extractSample :: Profile -> PropertyT IO [Extraction]
extractSample profile =
  mapM
    ( \file -> do
        source <- evalIO (T.pack <$> readFile (sampleDir </> "source" </> file))
        extractThrough profile file source
    )
    sampleFiles

-- | The units of an extraction below its file.
unitsBelowFile :: Extraction -> [CodeUnit Evidence]
unitsBelowFile e = [u | u <- modelAllUnits (extractionModel e), whatKind (answerValue (unitWhat u)) /= UnitKind "file"]

-- | A real Prolog project must parse whole, marelle's check mark in a quoted atom included, or its
-- check would report parse failures instead of findings; the plain profile makes a unit of every
-- clause and directive. ref:REQ-prolog-support ref:DEC-prolog-grammar-fixes
prop_thePrologProfileParsesEveryFileOfTheMarelleSampleIntoItsClauses :: Property
prop_thePrologProfileParsesEveryFileOfTheMarelleSampleIntoItsClauses = withTests 1 $ property $ do
  profile <- sampleProfile
  extractions <- extractSample profile
  let units = concatMap unitsBelowFile extractions
      kinds k = length [() | u <- units, whatKind (answerValue (unitWhat u)) == UnitKind k]
  length extractions === 13
  length units === 233
  kinds "clause" === 177
  kinds "directive" === 56
  length [() | u <- units, unitTest u] === 6

-- | PlDoc comments are tokens of the dialect, so real Prolog must still parse whole with them, and
-- the clauses of a predicate must be one unit named name/arity; marelle writes no PlDoc, so nothing
-- binds and nothing is an orphan, and a file without a module directive exports every predicate.
-- ref:REQ-prolog-support ref:DEC-prolog-dialect
prop_thePrologDialectParsesTheMarelleSampleIntoItsPredicates :: Property
prop_thePrologDialectParsesTheMarelleSampleIntoItsPredicates = withTests 1 $ property $ do
  extractions <- extractSample dialectProfile
  let units = concatMap unitsBelowFile extractions
      kinds k = length [() | u <- units, whatKind (answerValue (unitWhat u)) == UnitKind k]
  length extractions === 13
  length units === 197
  kinds "predicate" === 191
  kinds "test" === 6
  length [() | u <- units, unitRequirement u == Required] === 197
  length (concatMap (modelDecisions . extractionModel) extractions) === 0
  length [() | e <- extractions, OrphanDocComment _ _ <- extractionFindings e] === 0
  [renderUnitId (unitId u) | e <- take 1 (drop 10 extractions), u <- unitsBelowFile e, whatName (answerValue (unitWhat u)) == "main/2"] === ["prolog/marelle.pl/predicate/main/2"]

-- | In the dialect the grammar says where a PlDoc comment binds: a %! or %% comment with the %
-- lines below it, or a /** comment, documents the clauses directly below it, and a /** <module>
-- comment documents the file. A comment where no predicate follows, as above a directive, is an
-- orphan; a plain % comment and a %% inside a clause body are no documentation. The export list
-- decides which predicates require a comment, and a plunit test always does.
-- ref:REQ-prolog-support ref:DEC-prolog-dialect ref:DEC-export-rule
prop_thePrologDialectBindsPlDocCommentsToPredicatesAndReportsMisplacedOnes :: Property
prop_thePrologDialectBindsPlDocCommentsToPredicatesAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractThrough
      dialectProfile
      "lists.pl"
      ( T.unlines
          [ ":- module(lists, [append/3, last/2, empty/0, module_path/1])."
          , ""
          , "/** <module> List utilities"
          , ""
          , "The module exercises the dialect. ref:some-key"
          , "*/"
          , ""
          , "%!  append(?A, ?B, ?AB) is nondet."
          , "%"
          , "%   AB is A followed by B. ref:append-key"
          , "append([], L, L)."
          , "append([H|T], L, [H|R]) :-"
          , "    append(T, L, R)."
          , ""
          , "%%  last(?List, ?Last) is semidet."
          , "%   Last is the last element."
          , ":- dynamic last/2."
          , "last([X], X)."
          , "last([_|T], X) :- last(T, X)."
          , ""
          , "empty."
          , ""
          , "% A plain comment documents nothing."
          , "helper(X, Y) :- X = Y, %% inside a body is plain"
          , "    true."
          , ""
          , "%%%%%%%%%%%%%%%%%%%%"
          , "%! orphaned(X) is det."
          , ""
          , ":- use_module(library(lists))."
          , ""
          , "greeting --> [hello]."
          , ""
          , "%! The empty list appended to itself is empty. ref:REQ-append"
          , "test(append_empty) :- append([], [], [])."
          , "test(last_one, [true]) :- last([a], a)."
          , ""
          , "module_path(lists)."
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("prolog/lists.pl", "<module> List utilities\n\nThe module exercises the dialect. ref:some-key")
        , ("prolog/lists.pl/predicate/append/3", "append(?A, ?B, ?AB) is nondet.\n\nAB is A followed by B. ref:append-key")
        , ("prolog/lists.pl/predicate/last/2", "last(?List, ?Last) is semidet.\nLast is the last element.")
        , ("prolog/lists.pl/test/append_empty", "The empty list appended to itself is empty. ref:REQ-append")
        ]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model] === [[ReferenceKey "some-key"], [ReferenceKey "append-key"], [], [ReferenceKey "REQ-append"]]
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitTest u] === ["prolog/lists.pl/test/append_empty", "prolog/lists.pl/test/last_one"]
  length [() | OrphanDocComment _ _ <- findings] === 1
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["prolog/lists.pl/predicate/empty/0", "prolog/lists.pl/test/last_one", "prolog/lists.pl/predicate/module_path/1"]
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitRequirement u == Optional, whatKind (answerValue (unitWhat u)) /= UnitKind "file"]
    === ["prolog/lists.pl/predicate/helper/2", "prolog/lists.pl/nonterminal/greeting/0"]
