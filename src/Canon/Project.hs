module Canon.Project
  ( Project (..)
  , ProjectError (..)
  , loadProject
  , projectFiles
  , checkProject
  , extractFile
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
import Control.Concurrent.Async (mapConcurrently)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import System.FilePath (takeDirectory)
import Canon.Ignore (defaultIgnorePatterns, parseIgnorePatterns)
import Canon.Model.Check (checkAll)
import Canon.Model
import Canon.Model.Finding (Finding (..))
import qualified Data.Set as Set
import Canon.Model.Yaml (encodeSorted)
import Canon.Profile
import Canon.Registry
import Canon.Walk
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (normalise, (</>))

data Project = Project
  { projectDirectory :: FilePath
  , projectConfig :: Config
  , projectRegistry :: Registry
  , projectLedger :: Ledger
  }

data ProjectError
  = ProjectConfigError ConfigError
  | ProjectRegistryError RegistryError
  | ProjectLedgerError LedgerError
  deriving (Eq, Show)

renderProjectError :: ProjectError -> Text
renderProjectError e = case e of
  ProjectConfigError err -> renderConfigError err
  ProjectRegistryError err -> renderRegistryError err
  ProjectLedgerError err -> renderLedgerError err

resolvePath :: Project -> FilePath -> FilePath
resolvePath project path = normalise (projectDirectory project </> path)

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
      pure (Project directory config <$> registry <*> ledger)

loadOptional :: FilePath -> Bool -> a -> (FilePath -> IO (Either e a)) -> (e -> ProjectError) -> IO (Either ProjectError a)
loadOptional path isDefault empty reader wrap = do
  present <- doesFileExist path
  if not present && isDefault
    then pure (Right empty)
    else either (Left . wrap) Right <$> reader path

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

checkProject :: Project -> Maybe FilePath -> IO [Finding]
checkProject project target = do
  walked <- projectFiles project target
  let config = projectConfig project
  interpreters <- mapM (\(lang, profile) -> (,) lang <$> loadProfileInterpreter (resolveProfile project profile)) (Map.toList (configLanguages config))
  grammarBytes <- Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> profileBytes (resolveProfile project profile)) (Map.toList (configLanguages config))
  projectParts <- projectCacheParts project
  checked <- mapConcurrently (checkFile project (Map.fromList interpreters) grammarBytes projectParts) (walkedFiles walked)
  nested <- concat <$> mapM checkNested (walkedProjects walked)
  let citedSomewhere = Set.unions (map snd checked)
      own = [f | f <- concatMap fst checked, case f of DecisionUncited k -> not (Set.member k citedSomewhere); _ -> True]
  pure (nub own ++ nested)
  where
    checkNested directory = do
      loaded <- loadProject directory
      case loaded of
        Left err -> pure [ProjectUnusable directory (renderProjectError err)]
        Right nestedProject -> checkProject nestedProject Nothing

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

extractFile :: Project -> FilePath -> IO (Either Text Extraction)
extractFile project path = do
  let config = projectConfig project
  case profileForPath (configLanguages config) path of
    Nothing -> pure (Left (T.pack path <> ": no language profile matches this path"))
    Just (lang, profile) -> do
      loaded <- loadProfileInterpreter (resolveProfile project profile)
      case loaded of
        Left err -> pure (Left (renderInterpretError err))
        Right interpreter -> either (Left . renderGrammarExtractError) Right <$> extractWithProfile shellGitProvider config lang profile interpreter path

checkFile :: Project -> Map.Map Text (Either InterpretError Interpreter) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> FilePath -> IO ([Finding], Set.Set ReferenceKey)
checkFile project interpreters grammarBytes projectParts path = do
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
  extraction <- case cached of
    Just hit -> pure (Right hit)
    Nothing -> do
      fresh <- case profileFor of
        Just (lang, profile) -> case Map.lookup lang interpreters of
          Just (Right interpreter) ->
            either (Left . renderGrammarExtractError) Right
              <$> extractWithProfile shellGitProvider config lang profile interpreter path
          Just (Left err) -> pure (Left (renderInterpretError err))
          Nothing -> pure (Left "no interpreter for language")
        Nothing -> pure (Left "no language profile matches this path")
      either (const (pure ())) (storeCached (projectDirectory project) key) fresh
      pure fresh
  case extraction of
    Left message -> pure ([ExtractionFailed path message], Set.empty)
    Right (Extraction model findings) ->
      pure
        ( findings ++ checkAll (configVersion config) (projectRegistry project) (projectLedger project) model
        , Set.fromList (concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions model))
        )
