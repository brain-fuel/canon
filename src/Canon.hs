module Canon
  ( Command (..)
  , parseCommand
  , runCommand
  , runCanon
  , dispatch
  , usage
  , version
  ) where

import Canon.Config (Config (..), defaultRegistryFileName, loadConfig, renderConfigError)
import Canon.Extract.Antlr4 (Extraction (..), extractGrammarModel, renderExtractError)
import Canon.Git.Shell (shellGitProvider)
import Canon.Model.Check (checkModel)
import Canon.Model.Finding (renderFinding)
import Canon.Model.Yaml (encodeModel)
import Canon.Registry (Registry, emptyRegistry, readRegistryFile, renderRegistryError)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

data Command
  = CommandVersion
  | CommandModel FilePath
  | CommandCheck FilePath
  | CommandUsage
  deriving (Eq, Show)

version :: String
version = "canon 0.1.0.0"

parseCommand :: [String] -> Command
parseCommand arguments = case arguments of
  ["version"] -> CommandVersion
  ["model", path] -> CommandModel path
  ["check", path] -> CommandCheck path
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
    , "  canon model <grammar.g4>   emit the canonical model as YAML"
    , "  canon check <grammar.g4>   report findings and fail if there are any"
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
  CommandCheck path -> withExtraction path $ \config extraction -> do
    registry <- loadRegistry config
    case registry of
      Left err -> report err >> pure (ExitFailure 1)
      Right r -> do
        let findings = extractionFindings extraction ++ checkModel r (extractionModel extraction)
        mapM_ (TIO.putStrLn . renderFinding) findings
        pure (if null findings then ExitSuccess else ExitFailure 1)

withExtraction :: FilePath -> (Config -> Extraction -> IO ExitCode) -> IO ExitCode
withExtraction path continue = do
  configResult <- loadConfig
  case configResult of
    Left err -> report (renderConfigError err) >> pure (ExitFailure 1)
    Right config -> do
      extracted <- extractGrammarModel shellGitProvider config path
      case extracted of
        Left err -> report (renderExtractError err) >> pure (ExitFailure 1)
        Right extraction -> continue config extraction

loadRegistry :: Config -> IO (Either Text Registry)
loadRegistry config = do
  let path = configRegistry config
  present <- doesFileExist path
  if not present && path == defaultRegistryFileName
    then pure (Right emptyRegistry)
    else either (Left . renderRegistryError) Right <$> readRegistryFile path

report :: Text -> IO ()
report = TIO.hPutStrLn stderr
