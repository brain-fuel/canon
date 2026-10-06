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
  , renderSite
  ) where

import Canon.Antlr4.Interpret
import Canon.Antlr4.Parse (hPutParseTree)
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
import Canon.Folio (Block (..), Document (..))
import Canon.Registry (Reference (..), Registry (..))
import Canon.Highlight (classifierFor, highlightLines, plainLines)
import Canon.Profile (Embedding (..), Profile (..))
import Canon.Weave (Highlight, pagePath, renderIndex, renderPage)
import Canon.Tangle (Tangled (..))
import Canon.Version (canonVersion, renderVersion)
import Canon.Walk (Walked (..))
import qualified Data.ByteString as BS
import Data.List (isPrefixOf, sortOn)
import Data.Ord (Down (..))
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.Directory (createDirectoryIfMissing, doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (stderr, stdout)

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
  | CommandTangle Bool Bool [FilePath]
  | CommandSite FilePath
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
  ("tangle" : rest) | all known (filter isFlag rest) -> CommandTangle ("--check" `elem` rest) ("--manifest" `elem` rest) (filter (not . isFlag) rest)
  ["site", out] -> CommandSite out
  _ -> CommandUsage
  where
    isFlag = ("--" `isPrefixOf`)
    known f = f `elem` ["--check", "--manifest"]

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
    , "  canon tangle [--check] [--manifest] [<page>...]       write every source the project's Folio pages tangle to, or with --check report the stale ones; --manifest lists the blocks"
    , "  canon site <directory>                                render the project's Folio pages under docs/ to a static site in the directory"
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
    (path, total, files, fresh, dropped, failures) <- ingestProject project
    putStrLn (path ++ ": " ++ show (length fresh) ++ " pieces of canonical material recorded as pending, " ++ show (length dropped) ++ " pending rows of material that no longer exists dropped, " ++ show total ++ " entries in " ++ show files ++ " files")
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
  CommandTangle check manifest paths -> withProject $ \project -> do
    result <- tangleProject project paths
    case result of
      Left err -> report err >> pure (ExitFailure 1)
      Right (_, tangled, findings) -> do
        mapM_ (TIO.putStrLn . renderFinding) findings
        if manifest
          then do
            mapM_ (\t -> mapM_ (\(b, (from, to)) -> TIO.putStrLn (T.concat ["- {doc: ", T.pack (blockSource b), ", line: ", T.pack (show (blockLine b)), ", name: ", blockName b, ", part: ", if blockIsPart b then "true" else "false", ", file: ", T.pack (tangledPath t), ", from: ", T.pack (show from), ", to: ", T.pack (show to), "}"])) (zip (tangledBlocks t) (tangledRanges t))) tangled
            pure (if null findings then ExitSuccess else ExitFailure 1)
          else do
            stale <- mapM (writeTangled project check) tangled
            pure (if null findings && not (or stale) then ExitSuccess else ExitFailure 1)
  CommandSite out -> withProject $ \project -> do
    here <- getCurrentDirectory
    result <- renderSite project (T.pack (takeFileName here)) out
    case result of
      Left err -> report err >> pure (ExitFailure 1)
      Right pages -> putStrLn (show pages ++ " pages under " ++ out) >> pure ExitSuccess
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

-- | Renders a project's pages to a directory: one page per document under its quadrant and an
-- index, with citations resolved against the registry and the ledger. Returns how many pages
-- were written. ref:DEC-site-renderer
renderSite :: Project -> Text -> FilePath -> IO (Either Text Int)
renderSite project name out = do
  -- A project without the Folio has no pages, and an index that says so.
  result <- if null (folioProfiles project) then pure (Right ([], [], [])) else tangleProject project []
  case result of
    Left err -> pure (Left err)
    Right (docs, _, _) -> do
      highlight <- siteHighlighter project
      let resolve k = case Map.lookup k (registryEntries (projectRegistry project)) of
            Just r -> Just (referenceTitle r, referenceLocator r)
            Nothing -> (\e -> (entryQuestion e, T.pack (configDecisions (projectConfig project)) <> "#" <> referenceKeyText k)) <$> Map.lookup k (ledgerEntries (projectLedger project))
          pages = [(d, p) | d <- docs, Just p <- [pagePath (docPath d)]]
      mapM_ (\(d, p) -> createDirectoryIfMissing True (takeDirectory (out </> p)) >> TIO.writeFile (out </> p) (renderPage name resolve highlight d)) pages
      createDirectoryIfMissing True out
      TIO.writeFile (out </> "index.html") (renderIndex name pages)
      pure (Right (length pages))

-- | The highlighter of a project's fenced blocks: the fence word reaches a language through the
-- Folio profiles' embeddings, else a profile of that name, and the language's lexer classifies
-- the block; a word no profile owns is plain. ref:DEC-highlight-by-lexer
siteHighlighter :: Project -> IO Highlight
siteHighlighter project = do
  interpreters <- projectInterpreters project
  let languages = configLanguages (projectConfig project)
      embedded = Map.unions [Map.map embeddingLanguage (profileEmbeds p) | (_, p) <- folioProfiles project]
      languageOf word = case Map.lookup word embedded of
        Just lang -> lang
        Nothing -> word
      classifiers = Map.fromList [(lang, (classifierFor (profileHighlight p) i, i)) | (lang, p) <- Map.toList languages, Just (Right i) <- [Map.lookup lang interpreters]]
  pure $ \word body -> case Map.lookup (languageOf word) classifiers of
    Just (classifier, i) -> take (length body) (highlightLines classifier i (T.unlines body) ++ repeat [])
    Nothing -> plainLines (T.unlines body)

-- | Writes one tangled file, or under check only reports it, saying for each whether it was
-- unchanged, written, or stale.
writeTangled :: Project -> Bool -> Tangled -> IO Bool
writeTangled project check t = do
  let path = resolvePath project (tangledPath t)
  exists <- doesFileExist path
  current <- if exists then Just <$> TIO.readFile path else pure Nothing
  if current == Just (tangledText t)
    then putStrLn ("  unchanged  " ++ tangledPath t) >> pure False
    else
      if check
        then putStrLn ("  STALE      " ++ tangledPath t) >> pure True
        else do
          createDirectoryIfMissing True (takeDirectory path)
          TIO.writeFile path (tangledText t)
          putStrLn ("  written    " ++ tangledPath t)
          pure False

isPending :: Finding -> Bool
isPending f = case f of
  CommentPending {} -> True
  CommentStale {} -> True
  MaterialPending _ -> True
  MaterialStale _ -> True
  KindPending _ -> True
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
      Right tree -> hPutParseTree stdout tree >> pure ExitSuccess

withProject :: (Project -> IO ExitCode) -> IO ExitCode
withProject continue = do
  loaded <- loadProject "."
  case loaded of
    Left err -> report (renderProjectError err) >> pure (ExitFailure 1)
    Right project -> continue project

report :: Text -> IO ()
report = TIO.hPutStrLn stderr
