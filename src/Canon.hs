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
import Canon.Antlr4.Lex (LexError (..))
import Canon.Antlr4.Parse (ParseError (..), ParseFailure (..), renderParseTree)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (tokenPosition)
import Canon.Config (CanonicalGrammar (..), Config (..), defaultDecisionsFileName, defaultRegistryFileName, loadConfig, renderConfigError)
import Canon.Decisions
import Canon.Extract.Antlr4 (Extraction (..), extractGrammarModel, renderExtractError)
import Canon.Git.Shell (shellGitProvider)
import Canon.Model.Check (checkAll)
import Canon.Model.Finding (Finding (..), Severity (..), findingSeverity, renderFinding)
import Canon.Model.Id (ReferenceKey (..), renderUnitId)
import Canon.Model.Yaml (encodeModel)
import Canon.Registry (Registry, emptyRegistry, readRegistryFile, renderRegistryError)
import Canon.Span (Position (..))
import qualified Data.ByteString as BS
import Data.List (sortOn)
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
  | CommandCheck FilePath
  | CommandParse FilePath FilePath Text FilePath
  | CommandParseCombined FilePath Text FilePath
  | CommandDecisions
  | CommandUsage
  deriving (Eq, Show)

version :: String
version = "canon 0.1.0.0"

parseCommand :: [String] -> Command
parseCommand arguments = case arguments of
  ["version"] -> CommandVersion
  ["model", path] -> CommandModel path
  ["check", path] -> CommandCheck path
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
    , "  canon check <grammar.g4>                              report findings and fail if any is failing"
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
  CommandCheck path -> withExtraction path $ \config extraction -> do
    sources <- loadSources config
    case sources of
      Left err -> report err >> pure (ExitFailure 1)
      Right (registry, ledger) -> do
        canonical <- canonicalFindings config path
        let findings =
              extractionFindings extraction
                ++ checkAll (configVersion config) registry ledger (extractionModel extraction)
                ++ canonical
        mapM_ (TIO.putStrLn . renderWithSeverity) findings
        pure (if any ((== Failing) . findingSeverity) findings then ExitFailure 1 else ExitSuccess)
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
      _ -> sortOn (fmap negateVersion . entryDecided . snd) (entries status)
    negateVersion (Version parts) = Version (map negate parts)
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

canonicalFindings :: Config -> FilePath -> IO [Finding]
canonicalFindings config path = case Map.lookup "antlr4" (configCanonical config) of
  Nothing -> pure []
  Just (CanonicalGrammar lexer parser start) -> do
    loaded <- loadInterpreter lexer parser
    case loaded of
      Left err -> pure [CanonicalGrammarUnusable path (renderInterpretError err)]
      Right interpreter -> do
        result <- interpretFile interpreter (Name start) path
        pure $ case result of
          Right _ -> []
          Left (InterpretParseError _ (ParseNoParse (ParseFailure _ (Just tok)))) ->
            [NotCanonical path (tokenPosition tok) "the canonical dialect does not accept this token"]
          Left (InterpretParseError _ (ParseNoParse (ParseFailure _ Nothing))) ->
            [NotCanonical path (Position 1 1) "the canonical dialect does not accept this file"]
          Left (InterpretLexError _ (LexNoMatch pos _)) ->
            [NotCanonical path pos "the canonical dialect cannot tokenize this input"]
          Left err -> [CanonicalGrammarUnusable path (renderInterpretError err)]

withConfig :: (Config -> IO ExitCode) -> IO ExitCode
withConfig continue = do
  configResult <- loadConfig
  case configResult of
    Left err -> report (renderConfigError err) >> pure (ExitFailure 1)
    Right config -> continue config

withExtraction :: FilePath -> (Config -> Extraction -> IO ExitCode) -> IO ExitCode
withExtraction path continue = withConfig $ \config -> do
  extracted <- extractGrammarModel shellGitProvider config path
  case extracted of
    Left err -> report (renderExtractError err) >> pure (ExitFailure 1)
    Right extraction -> continue config extraction

loadSources :: Config -> IO (Either Text (Registry, Ledger))
loadSources config = do
  registry <- loadRegistry config
  ledger <- loadLedger config
  pure ((,) <$> registry <*> ledger)

loadRegistry :: Config -> IO (Either Text Registry)
loadRegistry config = do
  let path = configRegistry config
  present <- doesFileExist path
  if not present && path == defaultRegistryFileName
    then pure (Right emptyRegistry)
    else either (Left . renderRegistryError) Right <$> readRegistryFile path

loadLedger :: Config -> IO (Either Text Ledger)
loadLedger config = do
  let path = configDecisions config
  present <- doesFileExist path
  if not present && path == defaultDecisionsFileName
    then pure (Right emptyLedger)
    else either (Left . renderLedgerError) Right <$> readLedgerFile path

report :: Text -> IO ()
report = TIO.hPutStrLn stderr
