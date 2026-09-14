module Canon.Project
  ( Project (..)
  , ProjectError (..)
  , loadProject
  , projectFiles
  , checkProject
  , renderProjectError
  , resolvePath
  ) where

import Canon.Antlr4.Interpret
import Canon.Cache
import Canon.Antlr4.Lex (LexError (..))
import Canon.Antlr4.Parse (ParseError (..), ParseFailure (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (tokenPosition)
import Canon.Config
import Canon.Version (canonVersion)
import Canon.Decisions
import Canon.Extract.Antlr4 (Extraction (..), extractGrammarModel, renderExtractError)
import Canon.Extract.Grammar
import Canon.Git.Shell (runGit, shellGitProvider)
import Control.Concurrent.Async (mapConcurrently)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import System.FilePath (takeDirectory)
import Canon.Ignore (defaultIgnorePatterns, parseIgnorePatterns)
import Canon.Model.Check (checkAll)
import Canon.Model.Finding (Finding (..))
import Canon.Model.Yaml (encodeSorted)
import Canon.Profile
import Canon.Registry
import Canon.Span (Position (..))
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
  canonical <- loadCanonical project
  interpreters <- mapM (\(lang, profile) -> (,) lang <$> loadProfileInterpreter (resolveProfile project profile)) (Map.toList (configLanguages config))
  grammarBytes <- Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> profileBytes (resolveProfile project profile)) (Map.toList (configLanguages config))
  projectParts <- projectCacheParts project
  own <- concat <$> mapConcurrently (checkFile project canonical (Map.fromList interpreters) grammarBytes projectParts) (walkedFiles walked)
  nested <- concat <$> mapM checkNested (walkedProjects walked)
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

checkFile :: Project -> Maybe (Text, Either InterpretError Interpreter) -> Map.Map Text (Either InterpretError Interpreter) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> FilePath -> IO [Finding]
checkFile project canonical interpreters grammarBytes projectParts path = do
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
        Nothing -> either (Left . renderExtractError) Right <$> extractGrammarModel shellGitProvider config path
      either (const (pure ())) (storeCached (projectDirectory project) key) fresh
      pure fresh
  case extraction of
    Left message -> pure [ExtractionFailed path message]
    Right (Extraction model findings) -> do
      dialect <- if profileForPath (configLanguages config) path == Nothing then canonicalFindings canonical path else pure []
      pure (findings ++ checkAll (configVersion config) (projectRegistry project) (projectLedger project) model ++ dialect)

loadCanonical :: Project -> IO (Maybe (Text, Either InterpretError Interpreter))
loadCanonical project = case Map.lookup "antlr4" (configCanonical (projectConfig project)) of
  Nothing -> pure Nothing
  Just (CanonicalGrammar lexer parser start) ->
    Just . (,) start <$> loadInterpreter (resolvePath project lexer) (resolvePath project parser)

canonicalFindings :: Maybe (Text, Either InterpretError Interpreter) -> FilePath -> IO [Finding]
canonicalFindings canonical path = case canonical of
  Nothing -> pure []
  Just (_, Left err) -> pure [CanonicalGrammarUnusable path (renderInterpretError err)]
  Just (start, Right interpreter) -> do
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
