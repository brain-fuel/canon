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
import Canon.Config (Config (..), defaultDecisionsFileName, loadConfig, renderConfigError)
import Canon.Decisions
import Canon.Extract.Antlr4 (Extraction (..), extractGrammarModel, renderExtractError)
import Canon.Git.Shell (shellGitProvider)
import Canon.Model.Finding (Finding, Severity (..), findingSeverity, renderFinding)
import Canon.Model.Id (ReferenceKey (..), renderUnitId)
import Canon.Model.Yaml (encodeModel)
import Canon.Project
import Canon.Version (canonVersion, renderVersion)
import Canon.Walk (Walked (..))
import qualified Data.ByteString as BS
import Data.List (sortOn)
import Data.Ord (Down (..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

data Command
  = CommandVersion
  | CommandModel FilePath
  | CommandCheck (Maybe FilePath)
  | CommandFiles (Maybe FilePath)
  | CommandParse FilePath FilePath Text FilePath
  | CommandParseCombined FilePath Text FilePath
  | CommandDecisions
  | CommandUsage
  deriving (Eq, Show)

version :: String
version = "canon " ++ canonVersion

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
  _ -> CommandUsage

dispatch :: [String] -> String
dispatch arguments = case parseCommand arguments of
  CommandVersion -> version
  _ -> usage

usage :: String
usage =
  unlines
    [ "canon - canonical project documentation"
    , ""
    , "Usage:"
    , "  canon version"
    , "  canon model <grammar.g4>                              emit the canonical model as YAML"
    , "  canon check [<file or directory>]                     report findings for the file, or every supported file under the directory or the current one, and fail if any is failing"
    , "  canon files [<directory>]                             list the supported files check would visit"
    , "  canon parse <lexer.g4> <parser.g4> <rule> <file>      parse a file with an interpreted grammar pair"
    , "  canon parse <grammar.g4> <rule> <file>                parse a file with an interpreted combined grammar"
    , "  canon decisions                                       list the decision ledger, open decisions first"
    ]

runCanon :: IO ()
runCanon = getArgs >>= runCommand . parseCommand >>= exitWith

runCommand :: Command -> IO ExitCode
runCommand command = case command of
  CommandVersion -> putStrLn version >> pure ExitSuccess
  CommandUsage -> putStr usage >> pure ExitSuccess
  CommandModel path -> withExtraction path $ \_ extraction -> do
    mapM_ (report . renderFinding) (extractionFindings extraction)
    BS.putStr (encodeModel (extractionModel extraction))
    pure ExitSuccess
  CommandCheck target -> withProject $ \project -> do
    findings <- checkProject project target
    mapM_ (TIO.putStrLn . renderWithSeverity) findings
    pure (if any ((== Failing) . findingSeverity) findings then ExitFailure 1 else ExitSuccess)
  CommandFiles target -> withProject $ \project -> do
    walked <- projectFiles project target
    mapM_ putStrLn (walkedFiles walked)
    mapM_ (\d -> putStrLn (d ++ "  (nested project)")) (walkedProjects walked)
    pure ExitSuccess
  CommandParse lexer parser start path -> loadInterpreter lexer parser >>= runParse start path
  CommandParseCombined grammar start path -> loadCombinedInterpreter grammar >>= runParse start path
  CommandDecisions -> withConfig $ \config -> do
    loaded <- loadLedger config
    case loaded of
      Left err -> report err >> pure (ExitFailure 1)
      Right ledger -> TIO.putStr (renderLedger ledger) >> pure ExitSuccess

renderWithSeverity :: Finding -> Text
renderWithSeverity f = case findingSeverity f of
  Failing -> renderFinding f
  Informational -> "info: " <> renderFinding f

renderLedger :: Ledger -> Text
renderLedger ledger = T.concat (concatMap section [Open, Decided, Superseded])
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

withConfig :: (Config -> IO ExitCode) -> IO ExitCode
withConfig continue = do
  configResult <- loadConfig
  case configResult of
    Left err -> report (renderConfigError err) >> pure (ExitFailure 1)
    Right config -> continue config

withProject :: (Project -> IO ExitCode) -> IO ExitCode
withProject continue = do
  loaded <- loadProject "."
  case loaded of
    Left err -> report (renderProjectError err) >> pure (ExitFailure 1)
    Right project -> continue project

withExtraction :: FilePath -> (Config -> Extraction -> IO ExitCode) -> IO ExitCode
withExtraction path continue = withConfig $ \config -> do
  extracted <- extractGrammarModel shellGitProvider config path
  case extracted of
    Left err -> report (renderExtractError err) >> pure (ExitFailure 1)
    Right extraction -> continue config extraction

loadLedger :: Config -> IO (Either Text Ledger)
loadLedger config = do
  let path = configDecisions config
  present <- doesFileExist path
  if not present && path == defaultDecisionsFileName
    then pure (Right emptyLedger)
    else either (Left . renderLedgerError) Right <$> readLedgerFile path

report :: Text -> IO ()
report = TIO.hPutStrLn stderr
