-- | The command line is the only surface a user touches, so every subcommand is named and dispatched
-- here and nowhere else. ref:DEC-decision-ledger ref:DEC-comment-vetting
module Canon
  ( Command (..)
  , parseCommand
  , runCommand
  , runCanon
  , dispatch
  , usage
  , version
  , renderLedger
  ) where

import Canon.Antlr4.Interpret
import Canon.Antlr4.Parse (renderParseTree)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Decisions
import Canon.Extract.Grammar (Extraction (..))
import Canon.Config (Config (..))
import Canon.Git.Commit (CommitHash (..), Person (..))
import Canon.Model
import Canon.Vetting (applyAssessments, materialFindings)
import Canon.Model.Finding (Finding (..), Severity (..), findingSeverity, renderFinding)
import Canon.Model.Yaml (encodeModel)
import Canon.Project
import Canon.Version (canonVersion, renderVersion)
import Canon.Walk (Walked (..))
import qualified Data.ByteString as BS
import Data.List (sortOn)
import Data.Ord (Down (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

-- | One constructor per subcommand so that parsing arguments and running them are separate steps
-- that tests can exercise without a process.
data Command
  = CommandVersion
  | CommandModel FilePath
  | CommandCheck (Maybe FilePath)
  | CommandFiles (Maybe FilePath)
  | CommandParse FilePath FilePath Text FilePath
  | CommandParseCombined FilePath Text FilePath
  | CommandDecisions
  | CommandIngest
  | CommandVet
  | CommandUsage
  deriving (Eq, Show)

-- | The version string a user sees, derived from the one source of the version so it cannot drift.
-- ref:DEC-version-duplication
version :: String
version = "canon " ++ canonVersion

-- | Pure argument parsing, so unknown or malformed arguments are a value rather than an exit.
parseCommand :: [String] -> Command
parseCommand arguments = case arguments of
  ["version"] -> CommandVersion
  ["model", path] -> CommandModel path
  ["check"] -> CommandCheck Nothing
  ["check", path] -> CommandCheck (Just path)
  ["files"] -> CommandFiles Nothing
  ["files", path] -> CommandFiles (Just path)
  ["parse", lexer, parser, start, path] -> CommandParse lexer parser (T.pack start) path
  ["parse", grammar, start, path] -> CommandParseCombined grammar (T.pack start) path
  ["decisions"] -> CommandDecisions
  ["ingest"] -> CommandIngest
  ["vet"] -> CommandVet
  _ -> CommandUsage

-- | The pure part of running a command, kept for the tests that check usage text without side
-- effects.
dispatch :: [String] -> String
dispatch arguments = case parseCommand arguments of
  CommandVersion -> version
  _ -> usage

-- | Usage text lives beside the parser so that a subcommand cannot exist without a line describing
-- it.
usage :: String
usage =
  unlines
    [ "canon - canonical project documentation"
    , ""
    , "Usage:"
    , "  canon version"
    , "  canon model <file>                                    emit the canonical model of a file as YAML"
    , "  canon check [<file or directory>]                     report findings for the file, or every supported file under the directory or the current one, and fail if any is failing"
    , "  canon files [<directory>]                             list the supported files check would visit"
    , "  canon parse <lexer.g4> <parser.g4> <rule> <file>      parse a file with an interpreted grammar pair"
    , "  canon parse <grammar.g4> <rule> <file>                parse a file with an interpreted combined grammar"
    , "  canon decisions                                       list the decision ledger, open decisions first"
    , "  canon ingest                                          record every canonical comment of the project as pending in the vetting file"
    , "  canon vet                                             list the canonical comments that need a human verdict, with their text"
    ]

-- | The process entry point: arguments in, exit code out, with every effect inside runCommand.
runCanon :: IO ()
runCanon = getArgs >>= runCommand . parseCommand >>= exitWith

-- | Runs one command and returns its exit code, so that failing findings and errors fail the process
-- the way a build step expects.
runCommand :: Command -> IO ExitCode
runCommand command = case command of
  CommandVersion -> putStrLn version >> pure ExitSuccess
  CommandUsage -> putStr usage >> pure ExitSuccess
  CommandModel path -> withProject $ \project -> do
    extracted <- extractFile project path
    case extracted of
      Left err -> report err >> pure (ExitFailure 1)
      Right extraction -> do
        assessments <- projectAssessments project
        mapM_ (report . renderFinding) (extractionFindings extraction)
        BS.putStr (encodeModel (applyAssessments assessments (extractionModel extraction)))
        pure ExitSuccess
  CommandCheck target -> withProject $ \project -> do
    findings <- checkProject project target
    mapM_ (TIO.putStrLn . renderWithSeverity) findings
    let pending = length [() | f <- findings, isPending f]
    if pending > 0 then TIO.putStrLn (T.concat ["report invalid: ", T.pack (show pending), " pieces of canonical material pending sign-off"]) else pure ()
    pure (if any ((== Failing) . findingSeverity) findings then ExitFailure 1 else ExitSuccess)
  CommandIngest -> withProject $ \project -> do
    (path, total, fresh, failures) <- ingestProject project
    putStrLn (path ++ ": " ++ show (length fresh) ++ " pieces of canonical material recorded as pending, " ++ show total ++ " entries in total")
    mapM_ (report . ("not read, so its comments are not recorded: " <>)) failures
    pure (if null failures then ExitSuccess else ExitFailure 1)
  CommandVet -> withProject $ \project -> do
    items <- vetProject project
    mapM_ (TIO.putStr . renderAttention) items
    TIO.putStrLn (T.pack (show (length items)) <> " pieces of canonical material need a verdict")
    pure (if null items then ExitSuccess else ExitFailure 1)
  CommandFiles target -> withProject $ \project -> do
    walked <- projectFiles project target
    mapM_ putStrLn (walkedFiles walked)
    mapM_ (\d -> putStrLn (d ++ "  (nested project)")) (walkedProjects walked)
    pure ExitSuccess
  CommandParse lexer parser start path -> loadInterpreter lexer parser >>= runParse start path
  CommandParseCombined grammar start path -> loadCombinedInterpreter grammar >>= runParse start path
  CommandDecisions -> withProject $ \project -> do
    assessments <- projectAssessments project
    let config = projectConfig project
        states = case projectVetting project of
          Nothing -> Map.empty
          Just vetting -> Map.fromList (mapMaybe materialState (materialFindings (configVersion config) vetting assessments (projectLedger project) (projectRegistry project)))
        signed = Map.mapMaybe signOffText (Map.fromList [(k, a) | (LedgerKey k, a) <- Map.toList assessments])
    TIO.putStr (renderLedger (projectLedger project) (Map.union states signed))
    pure ExitSuccess

isPending :: Finding -> Bool
isPending f = case f of
  CommentPending {} -> True
  CommentStale {} -> True
  MaterialPending _ -> True
  MaterialStale _ -> True
  _ -> False

materialState :: Finding -> Maybe (ReferenceKey, Text)
materialState f = case f of
  MaterialPending (LedgerKey k) -> Just (k, "pending")
  MaterialStale (LedgerKey k) -> Just (k, "stale")
  MaterialBad (LedgerKey k) _ -> Just (k, "bad")
  _ -> Nothing

signOffText :: Answer Assessment Evidence -> Maybe Text
signOffText (Answer a _) = case (assessmentVerdict a, assessmentBy a, assessmentCommit a) of
  (Pending, _, _) -> Just "pending"
  (verdict, Just person, Just (CommitHash hash)) ->
    Just (T.concat [verdictText verdict, " by ", personName person, " in ", T.take 7 hash, if null (assessmentCoAuthors a) then "" else " with " <> T.intercalate ", " (map personName (assessmentCoAuthors a))])
  (verdict, _, _) -> Just (verdictText verdict <> ", not committed")

renderAttention :: (Finding, Maybe Text) -> Text
renderAttention (f, text) =
  T.concat
    ( [renderFinding f, "\n"]
        ++ maybe [] (\t -> ["    " <> T.intercalate "\n    " (T.lines t), "\n"]) text
    )

renderWithSeverity :: Finding -> Text
renderWithSeverity f = case findingSeverity f of
  Failing -> renderFinding f
  Informational -> "info: " <> renderFinding f

-- | Renders the decision ledger open-first because open decisions are the ones a reader must act on.
-- ref:DEC-decision-ledger
renderLedger :: Ledger -> Map.Map ReferenceKey Text -> Text
renderLedger ledger signOffs = T.concat (concatMap section [Open, Decided, Superseded])
  where
    entries status = [(k, e) | (k, e) <- Map.toList (ledgerEntries ledger), entryStatus e == status]
    ordered status = case status of
      Open -> sortOn (entryRevisit . snd) (entries status)
      _ -> sortOn (fmap Down . entryDecided . snd) (entries status)
    section status = case ordered status of
      [] -> []
      items -> (statusText status <> "\n") : map renderEntry items ++ ["\n"]
    renderEntry (ReferenceKey k, e) =
      T.concat
        [ "  ", k
        , maybe "" (\v -> "  revisit " <> renderVersion v) (entryRevisit e)
        , maybe "" (\v -> "  decided " <> renderVersion v) (entryDecided e)
        , maybe "" (\(ReferenceKey b) -> "  by " <> b) (entryBy e)
        , "  [", Map.findWithDefault "unsigned" (ReferenceKey k) signOffs, "]"
        , "\n    ", entryQuestion e, "\n"
        , maybe "" (\a -> "    " <> T.intercalate "\n    " (T.lines a) <> "\n") (entryAnswer e)
        , if null (entryUnits e) then "" else "    units: " <> T.intercalate ", " (map renderUnitId (entryUnits e)) <> "\n"
        ]

runParse :: Text -> FilePath -> Either InterpretError Interpreter -> IO ExitCode
runParse start path loaded = case loaded of
  Left err -> report (renderInterpretError err) >> pure (ExitFailure 1)
  Right interpreter -> do
    result <- interpretFile interpreter (Name start) path
    case result of
      Left err -> report (renderInterpretError err) >> pure (ExitFailure 1)
      Right tree -> TIO.putStrLn (renderParseTree tree) >> pure ExitSuccess

withProject :: (Project -> IO ExitCode) -> IO ExitCode
withProject continue = do
  loaded <- loadProject "."
  case loaded of
    Left err -> report (renderProjectError err) >> pure (ExitFailure 1)
    Right project -> continue project

report :: Text -> IO ()
report = TIO.hPutStrLn stderr
