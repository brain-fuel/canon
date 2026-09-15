-- | A project is a directory with its configuration, registry, ledger, and vetting file, and the
-- check stops at nested projects because each answers for itself. ref:DEC-nested-root-check
-- ref:DEC-extraction-cache
module Canon.Project
  ( Project (..)
  , ProjectError (..)
  , loadProject
  , projectFiles
  , checkProject
  , extractFile
  , projectAssessments
  , ingestProject
  , vetProject
  , renderProjectError
  , resolvePath
  ) where

import Canon.Antlr4.Interpret
import Canon.Cache
import Canon.Config
import Canon.Version (canonVersion)
import Canon.Decisions
import Canon.Extract.Grammar
import Canon.Git.Shell (runGit, shellGitProvider)
import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import System.FilePath (takeDirectory)
import Canon.Ignore (defaultIgnorePatterns, parseIgnorePatterns)
import Canon.Model.Check (checkAll, requirementsCitedByTests)
import Canon.Model
import Canon.Model.Finding (Finding (..))
import qualified Data.Set as Set
import Canon.Model.Yaml (encodeSorted)
import Canon.Profile
import Canon.Registry
import Canon.Vetting
import qualified Data.Text.IO as TIO
import Canon.Walk
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (makeRelative, normalise, (</>))

-- | A project with its four canonical files loaded.
data Project = Project
  { projectDirectory :: FilePath
  , projectConfig :: Config
  , projectRegistry :: Registry
  , projectLedger :: Ledger
  , projectVetting :: Maybe Vetting
  }

-- | Any of the four files can be unreadable.
data ProjectError
  = ProjectConfigError ConfigError
  | ProjectRegistryError RegistryError
  | ProjectLedgerError LedgerError
  | ProjectVettingError VettingError
  deriving (Eq, Show)

-- | Renders a project error.
renderProjectError :: ProjectError -> Text
renderProjectError e = case e of
  ProjectConfigError err -> renderConfigError err
  ProjectRegistryError err -> renderRegistryError err
  ProjectLedgerError err -> renderLedgerError err
  ProjectVettingError err -> renderVettingError err

-- | Resolves a configured path against the project directory.
resolvePath :: Project -> FilePath -> FilePath
resolvePath project path = normalise (projectDirectory project </> path)

-- | Loads a project from a directory, defaulting each absent file when it has the default name.
loadProject :: FilePath -> IO (Either ProjectError Project)
loadProject directory = do
  let configPath = directory </> configFileName
  present <- doesFileExist configPath
  configResult <- if present then readConfigFile configPath else pure (Right defaultConfig)
  case configResult of
    Left err -> pure (Left (ProjectConfigError err))
    Right config -> do
      registry <- loadOptional (directory </> configRegistry config) (configRegistry config == defaultRegistryFileName) emptyRegistry readRegistryFile ProjectRegistryError
      ledger <- loadOptional (directory </> configDecisions config) (configDecisions config == defaultDecisionsFileName) emptyLedger readLedgerFile ProjectLedgerError
      vetting <- loadVetting (directory </> configVetting config) (configVetting config == defaultVettingFileName)
      pure (Project directory config <$> registry <*> ledger <*> vetting)

loadVetting :: FilePath -> Bool -> IO (Either ProjectError (Maybe Vetting))
loadVetting path isDefault = do
  present <- doesFileExist path
  if present
    then either (Left . ProjectVettingError) (Right . Just) <$> readVettingFile path
    else pure (if isDefault then Right Nothing else Left (ProjectVettingError (VettingUnreadable path "file not found")))

-- | The assessor of every verdict, read once per project from a blame of the vetting file.
-- ref:DEC-comment-vetting
projectAssessments :: Project -> IO (Map.Map VettingKey (Answer Assessment Evidence))
projectAssessments project = case projectVetting project of
  Nothing -> pure Map.empty
  Just vetting -> do
    let path = resolvePath project (configVetting (projectConfig project))
    source <- TIO.readFile path
    assess shellGitProvider path source vetting

loadOptional :: FilePath -> Bool -> a -> (FilePath -> IO (Either e a)) -> (e -> ProjectError) -> IO (Either ProjectError a)
loadOptional path isDefault empty reader wrap = do
  present <- doesFileExist path
  if not present && isDefault
    then pure (Right empty)
    else either (Left . wrap) Right <$> reader path

-- | The files a check visits, honouring ignore patterns and stopping at nested projects.
projectFiles :: Project -> Maybe FilePath -> IO Walked
projectFiles project target = do
  let config = projectConfig project
      patterns = defaultIgnorePatterns ++ parseIgnorePatterns (configIgnore config)
      extensions = grammarExtension : [T.unpack e | p <- Map.elems (configLanguages config), e <- profileExtensions p]
      root = resolvePath project (maybe (configRoot config) id target)
  isDirectory <- doesDirectoryExist root
  if isDirectory
    then walkProject patterns extensions configFileName root
    else pure (Walked [root] [])

-- | Checks a project, with project-wide findings decided after every file has been seen.
checkProject :: Project -> Maybe FilePath -> IO [Finding]
checkProject project target = do
  walked <- projectFiles project target
  assessments <- projectAssessments project
  extracted <- extractAll project walked
  let checked = map (checkExtraction project assessments) extracted
      citedSomewhere = Set.unions [c | (_, c, _, _) <- checked]
      seen = Set.unions [s | (_, _, s, _) <- checked]
      tested = Set.unions [t | (_, _, _, t) <- checked]
      own =
        [ f
        | (fs, _, _, _) <- checked
        , f <- fs
        , case f of
            DecisionUncited k -> not (Set.member k citedSomewhere)
            RequirementUntested k -> not (Set.member k tested)
            _ -> True
        ]
      live = Set.unions [Set.map CommentKey seen, Set.map LedgerKey (Map.keysSet (ledgerEntries (projectLedger project))), Set.map RegistryKey (Map.keysSet (registryEntries (projectRegistry project)))]
      signOff = case projectVetting project of
        Nothing -> []
        Just vetting -> materialFindings (configVersion (projectConfig project)) vetting assessments (projectLedger project) (projectRegistry project) ++ orphanVerdictFindings vetting live
  pure (nub own ++ signOff)

resolveProfile :: Project -> Profile -> Profile
resolveProfile project profile =
  profile
    { profileGrammar = case profileGrammar profile of
        CombinedGrammarFile path -> CombinedGrammarFile (resolvePath project path)
        SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolvePath project lexer) (resolvePath project parser)
    }

profileBytes :: Profile -> IO LBS.ByteString
profileBytes profile = do
  sources <- mapM readOrEmpty $ case profileGrammar profile of
    CombinedGrammarFile g -> [g]
    SplitGrammarFiles l r -> [l, r]
  pure (LBS.concat (LBS.fromStrict (encodeSorted profile) : sources))
  where
    readOrEmpty path = do
      present <- doesFileExist path
      if present then LBS.readFile path else pure LBS.empty

projectCacheParts :: Project -> IO [LBS.ByteString]
projectCacheParts project = do
  let root = resolvePath project (configRoot (projectConfig project))
  described <- either (const "") id <$> runGit root ["describe", "--tags", "--always", "--dirty"]
  tags <- either (const "") id <$> runGit root ["tag", "--list"]
  pure
    ( map
        (LBS.fromStrict . TE.encodeUtf8)
        [ T.pack canonVersion
        , maybe "" id (configVersion (projectConfig project))
        , described
        , tags
        ]
    )

extractAll :: Project -> Walked -> IO [(FilePath, Either Text Extraction)]
extractAll project walked = do
  let config = projectConfig project
  interpreters <- mapM (\(lang, profile) -> (,) lang <$> loadProfileInterpreter (resolveProfile project profile)) (Map.toList (configLanguages config))
  grammarBytes <- Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> profileBytes (resolveProfile project profile)) (Map.toList (configLanguages config))
  projectParts <- projectCacheParts project
  workers <- getNumCapabilities
  slots <- newQSem (max 1 workers)
  mapConcurrently (\path -> (,) path <$> bracket_ (waitQSem slots) (signalQSem slots) (extractCached project (Map.fromList interpreters) grammarBytes projectParts path)) (walkedFiles walked)

-- | Records every piece of canonical material without a verdict as pending, and names the files
-- it could not read, whose comments stay pending by their absence. ref:DEC-comment-vetting
-- ref:DEC-human-sign-off
ingestProject :: Project -> IO (FilePath, Int, [VettingKey], [Text])
ingestProject project = do
  walked <- projectFiles project Nothing
  extracted <- extractAll project walked
  let decisions = concat [modelDecisions (extractionModel e) | (_, Right e) <- extracted]
      failures = [T.concat [T.pack failed, ": ", message] | (failed, Left message) <- extracted]
      existing = maybe emptyVetting id (projectVetting project)
      (updated, fresh) = ingest existing (materials decisions (projectLedger project) (projectRegistry project))
      path = resolvePath project (configVetting (projectConfig project))
  writeVettingFile path updated
  pure (path, Map.size (vettingEntries updated), fresh, failures)

-- | The canonical material that needs a human verdict, each finding with the text to read.
vetProject :: Project -> IO [(Finding, Maybe Text)]
vetProject project = do
  walked <- projectFiles project Nothing
  assessments <- projectAssessments project
  extracted <- extractAll project walked
  let decisions = concat [modelDecisions (extractionModel e) | (_, Right e) <- extracted]
      texts = Map.fromList [(materialKey m, materialText m) | m <- materials decisions (projectLedger project) (projectRegistry project)]
      signOff = case projectVetting project of
        Nothing -> []
        Just vetting ->
          materialFindings (configVersion (projectConfig project)) vetting assessments (projectLedger project) (projectRegistry project)
            ++ orphanVerdictFindings vetting (Map.keysSet texts)
      findings = concat [fs | (fs, _, _, _) <- map (checkExtraction project assessments) extracted] ++ signOff
  pure [(f, keyOf f >>= (`Map.lookup` texts)) | f <- findings, attention f]
  where
    keyOf f = case f of
      CommentPending d _ -> Just (CommentKey d)
      CommentStale d _ -> Just (CommentKey d)
      CommentDeferredPastRevisit d _ _ _ -> Just (CommentKey d)
      VerdictWithoutRevisit d _ -> Just (CommentKey d)
      VerdictOrphan k -> Just k
      MaterialPending k -> Just k
      MaterialStale k -> Just k
      MaterialDeferredPastRevisit k _ _ -> Just k
      MaterialWithoutRevisit k -> Just k
      _ -> Nothing

idPathOf :: Project -> FilePath -> FilePath
idPathOf project path = makeRelative (normalise (projectDirectory project)) (normalise path)

-- | Extracts one file through the profile that owns it, for the model subcommand.
extractFile :: Project -> FilePath -> IO (Either Text Extraction)
extractFile project path = do
  let config = projectConfig project
  case profileForPath (configLanguages config) path of
    Nothing -> pure (Left (T.pack path <> ": no language profile matches this path"))
    Just (lang, profile) -> do
      loaded <- loadProfileInterpreter (resolveProfile project profile)
      case loaded of
        Left err -> pure (Left (renderInterpretError err))
        Right interpreter -> either (Left . renderGrammarExtractError) Right <$> extractWithProfile shellGitProvider config lang profile interpreter (idPathOf project path) path

extractCached :: Project -> Map.Map Text (Either InterpretError Interpreter) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> FilePath -> IO (Either Text Extraction)
extractCached project interpreters grammarBytes projectParts path = do
  let config = projectConfig project
      profileFor = profileForPath (configLanguages config) path
  content <- LBS.readFile path
  revision <- either (const "") id <$> runGit (takeDirectory path) ["rev-parse", "HEAD"]
  dirty <- either (const "") id <$> runGit (takeDirectory path) ["status", "--porcelain", "--", path]
  let key =
        cacheKey
          ( projectParts
              ++ [ content
                 , LBS.fromStrict (TE.encodeUtf8 revision)
                 , LBS.fromStrict (TE.encodeUtf8 dirty)
                 , maybe LBS.empty (\(lang, _) -> Map.findWithDefault LBS.empty lang grammarBytes) profileFor
                 , LBS.fromStrict (TE.encodeUtf8 (T.pack path))
                 ]
          )
  cached <- lookupCached (projectDirectory project) key
  case cached of
    Just hit -> pure (Right hit)
    Nothing -> do
      fresh <- case profileFor of
        Just (lang, profile) -> case Map.lookup lang interpreters of
          Just (Right interpreter) ->
            either (Left . renderGrammarExtractError) Right
              <$> extractWithProfile shellGitProvider config lang profile interpreter (idPathOf project path) path
          Just (Left err) -> pure (Left (renderInterpretError err))
          Nothing -> pure (Left "no interpreter for language")
        Nothing -> pure (Left "no language profile matches this path")
      either (const (pure ())) (storeCached (projectDirectory project) key) fresh
      pure fresh

checkExtraction :: Project -> Map.Map VettingKey (Answer Assessment Evidence) -> (FilePath, Either Text Extraction) -> ([Finding], Set.Set ReferenceKey, Set.Set DecisionId, Set.Set ReferenceKey)
checkExtraction project assessments (path, extraction) = case extraction of
  Left message -> ([ExtractionFailed path message], Set.empty, Set.empty, Set.empty)
  Right (Extraction model findings) ->
    ( findings
        ++ checkAll (configVersion config) (projectRegistry project) (projectLedger project) model
        ++ maybe [] (\v -> vettingFindings (configVersion config) v assessments model) (projectVetting project)
    , Set.fromList (concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions model))
    , Set.fromList (map decisionId (modelDecisions model))
    , requirementsCitedByTests (projectRegistry project) model
    )
  where
    config = projectConfig project
