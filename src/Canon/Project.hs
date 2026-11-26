-- | A project is a directory with its configuration, registry, ledger, and vetting directory, and
-- the check stops at nested projects because each answers for itself. ref:DEC-nested-root-check
-- ref:DEC-extraction-cache ref:DEC-vetting-layout
module Canon.Project
  ( Project (..)
  , ProjectError (..)
  , loadProject
  , loadProjectWith
  , projectFiles
  , checkProject
  , findingFails
  , Survey (..)
  , surveyProject
  , surveyReport
  , exemptFinding
  , lockstepFindings
  , extractFile
  , extractAll
  , projectAssessments
  , projectMaterials
  , applyExemptions
  , ingestProject
  , vetProject
  , renderProjectError
  , resolvePath
  , folioProfiles
  , tangleProject
  , projectInterpreters
  ) where

import Canon.Antlr4.Interpret
import Canon.Cache
import Canon.Config
import Canon.Decisions
import Canon.Exemptions
import Canon.Version (canonVersion, patchCompatible, renderVersion)
import Canon.Extract.Grammar
import Canon.Git.Facts (Facts, bareProvider, factsProvider, factsStamp, repositoryFacts, stampExtraction)
import Canon.Git.Provider (GitProvider)
import Canon.Git.Shell (GitSide (..), gitIgnoredPaths, sideGitProvider)
import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Concurrent.MVar (modifyMVar, newMVar)
import Control.Exception (bracket_)
import Control.Monad (forM_)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import System.FilePath (takeDirectory)
import Canon.Ignore (defaultIgnorePatterns, parseIgnorePatterns)
import Canon.Model.Check (checkFile, checkProjectWide, requirementsCitedByTests)
import Canon.Model
import Canon.Model.Finding (Finding (..), Severity (..), findingKey, findingPending, findingSeverity, renderFinding)
import qualified Data.Set as Set
import Canon.Model.Yaml (encodeSorted)
import Canon.Extract.Folio (blockDefinitionFindings, duplicateIdFindings, frontMatterFindings, pageExtraction, relocate)
import Canon.Folio (Block (..), Document (..), scanDocument)
import Canon.Tangle (Tangled (..), assemble)
import Canon.Profile
import Canon.Signature (linkSignatures)
import Canon.Registry
import Canon.Vetting
import qualified Data.Text.IO as TIO
import Canon.Span (Located (..), Position (..), Span (..))
import Canon.CommentScan (scanCommentsWith)
import Canon.Walk
import Control.Exception (evaluate)
import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.FilePath (makeRelative, normalise, takeExtension, takeFileName, (</>))

-- | A project with its three canonical files and its vetting directory loaded, the git provider
-- that answers for the side of the repository it was read from, and, for a snapshot of the index
-- or a commit, the paths the working tree's git ignores, which the snapshot does not hold. The
-- cache is the working project's for every side: an entry's key holds all it depends on, the
-- side's own facts included, so the sides share every entry they agree on. ref:DEC-check-sides
-- ref:DEC-extraction-cache
data Project = Project
  { projectDirectory :: FilePath
  , projectConfig :: Config
  , projectRegistry :: Registry
  , projectLedger :: Ledger
  , projectVetting :: Maybe Vetting
  , projectExemptions :: Exemptions
  , projectGit :: GitProvider
  , projectSide :: GitSide
  , projectIgnored :: Maybe (Set.Set [Text])
  , projectCache :: FilePath
  }

-- | Any of the canonical files can be unreadable.
data ProjectError
  = ProjectConfigError ConfigError
  | ProjectRegistryError RegistryError
  | ProjectLedgerError LedgerError
  | ProjectVettingError VettingError
  | ProjectExemptionsError ExemptionsError
  deriving (Eq, Show)

-- | Renders a project error.
renderProjectError :: ProjectError -> Text
renderProjectError e = case e of
  ProjectConfigError err -> renderConfigError err
  ProjectRegistryError err -> renderRegistryError err
  ProjectLedgerError err -> renderLedgerError err
  ProjectVettingError err -> renderVettingError err
  ProjectExemptionsError err -> renderExemptionsError err

-- | Resolves a configured path against the project directory.
resolvePath :: Project -> FilePath -> FilePath
resolvePath project path = normalise (projectDirectory project </> path)

-- | Loads a project from a directory, defaulting each absent file when it has the default name.
loadProject :: FilePath -> IO (Either ProjectError Project)
loadProject = loadProjectWith WorkTreeSide Nothing

-- | Loads a project as one side of its repository holds it, with the paths to skip in place of
-- asking git what it ignores. ref:DEC-check-sides
loadProjectWith :: GitSide -> Maybe (Set.Set [Text]) -> FilePath -> IO (Either ProjectError Project)
loadProjectWith side ignored directory = do
  let configPath = directory </> configFileName
  present <- doesFileExist configPath
  configResult <- if present then readConfigFile configPath else pure (Right defaultConfig)
  case configResult of
    Left err -> pure (Left (ProjectConfigError err))
    Right config -> do
      registry <- loadOptional (directory </> configRegistry config) (configRegistry config == defaultRegistryFileName) emptyRegistry readRegistryFile ProjectRegistryError
      ledger <- loadOptional (directory </> configDecisions config) (configDecisions config == defaultDecisionsFileName) emptyLedger readLedgerFile ProjectLedgerError
      vetting <- loadVetting (directory </> configVetting config) (configVetting config == defaultVettingDirectory)
      exemptions <- loadOptional (directory </> configExemptions config) (configExemptions config == defaultExemptionsFileName) emptyExemptions readExemptionsFile ProjectExemptionsError
      pure ((\r l v e -> Project directory config r l v e (sideGitProvider side) side ignored directory) <$> registry <*> ledger <*> vetting <*> exemptions)

loadVetting :: FilePath -> Bool -> IO (Either ProjectError (Maybe Vetting))
loadVetting path isDefault = do
  isDirectory <- doesDirectoryExist path
  isFile <- doesFileExist path
  oldFile <- doesFileExist (path ++ ".yaml")
  if isFile || (isDefault && oldFile)
    then pure (Left (ProjectVettingError (VettingIsFile (if isFile then path else path ++ ".yaml"))))
    else
      if isDirectory
        then either (Left . ProjectVettingError) (Right . Just) <$> readVettingDirectory path
        else pure (if isDefault then Right Nothing else Left (ProjectVettingError (VettingUnreadable path "directory not found")))

-- | The assessor of every verdict, read once per project from a blame of each vetting file.
-- ref:DEC-comment-vetting ref:DEC-vetting-layout
projectAssessments :: Project -> IO (Map.Map VettingKey (Answer Assessment Evidence))
projectAssessments project = case projectVetting project of
  Nothing -> pure Map.empty
  Just vetting -> do
    let dir = resolvePath project (configVetting (projectConfig project))
    sources <- Map.traverseWithKey (\p _ -> TIO.readFile (dir </> p)) (vettingFiles vetting)
    assess (projectGit project) dir sources vetting

-- | The file each material's verdict belongs in, named after the project's ledger and registry.
projectMaterials :: Project -> [Decision Evidence] -> [Material]
projectMaterials project decisions =
  materials (configDecisions config) (configRegistry config) decisions (projectLedger project) (projectRegistry project)
  where
    config = projectConfig project

loadOptional :: FilePath -> Bool -> a -> (FilePath -> IO (Either e a)) -> (e -> ProjectError) -> IO (Either ProjectError a)
loadOptional path isDefault empty reader wrap = do
  present <- doesFileExist path
  if not present && isDefault
    then pure (Right empty)
    else either (Left . wrap) Right <$> reader path

-- | The files a check visits, honouring git's ignores and canon's own patterns, and stopping at
-- nested projects. ref:DEC-honour-gitignore
projectFiles :: Project -> Maybe FilePath -> IO Walked
projectFiles project target = do
  let config = projectConfig project
      patterns = defaultIgnorePatterns ++ parseIgnorePatterns (configIgnore config)
      supported entry = takeExtension entry == grammarExtension || any (`profileOwns` entry) (Map.elems (configLanguages config))
      root = resolvePath project (maybe (configRoot config) id target)
  isDirectory <- doesDirectoryExist root
  if isDirectory
    then do
      gitIgnored <- maybe (gitIgnoredPaths root) pure (projectIgnored project)
      walkProjectExcluding gitIgnored patterns supported configFileName root
    else pure (Walked [root] [])

-- | Checks a project, with project-wide findings decided after every file has been seen.
checkProject :: Project -> Maybe FilePath -> IO [Finding]
checkProject project target = surveyReport project <$> surveyProject project target

-- | One reading of a project: the files walked, each extraction with signatures linked, the
-- assessors from blame, the materials, and every finding before and after exemptions. check,
-- vet, and ingest are each a view of it, and a tool built on canon reads the same value, so a
-- row it shows as pending is one the check counts. ref:DEC-canon-lockstep
data Survey = Survey
  { surveyWalked :: Walked
  , surveyExtracted :: [(FilePath, Either Text Extraction)]
  , surveyAssessments :: Map.Map VettingKey (Answer Assessment Evidence)
  , surveyMaterials :: [Material]
  , surveyFindings :: [(Finding, Finding)]
  }

-- | Reads a project once, in full or under a target. ref:DEC-canon-lockstep
surveyProject :: Project -> Maybe FilePath -> IO Survey
surveyProject unread target = do
  (project, facts) <- withFacts unread
  walked <- projectFiles project target
  assessments <- projectAssessments project
  extracted <- linkSignatures (configLanguages (projectConfig project)) <$> extractAllWith facts project walked
  -- Each file is checked on its own, so the files are checked at once, each result forced where
  -- it is made rather than where it is read.
  checked <- mapConcurrently (forced . checkExtraction project assessments) extracted
  let config = projectConfig project
      citedSomewhere = Set.unions [c | (_, c, _, _) <- checked]
      seen = Set.unions [v | (_, _, v, _) <- checked]
      tested = Set.unions [t | (_, _, _, t) <- checked]
      known = Set.fromList [unitId u | (_, Right e) <- extracted, u <- modelAllUnits (extractionModel e)]
      -- Each file's own findings, then the project's, which are answered once from what every
      -- file cites, tests, and defines. ref:DEC-decision-ledger
      own = distinct (concat [fs | (fs, _, _, _) <- checked]) ++ checkProjectWide (configVersion config) (projectRegistry project) (projectLedger project) citedSomewhere tested known
      live = Set.unions [seen, Set.map LedgerKey (Map.keysSet (ledgerEntries (projectLedger project))), Set.map RegistryKey (Map.keysSet (registryEntries (projectRegistry project)))]
      signOff = case projectVetting project of
        Nothing -> []
        Just vetting -> materialFindings (configVersion (projectConfig project)) vetting assessments (projectLedger project) (projectRegistry project) ++ kindFindings (configKinds (projectConfig project)) vetting assessments ++ orphanVerdictFindings vetting live
      decisions = concat [modelDecisions (extractionModel e) | (_, Right e) <- extracted]
  pure
    Survey
      { surveyWalked = walked
      , surveyExtracted = extracted
      , surveyAssessments = assessments
      , surveyMaterials = projectMaterials project decisions
      , surveyFindings = [(f, exemptFinding project f) | f <- own ++ signOff]
      }

-- | A file's check with its findings and key sets evaluated.
forced :: ([Finding], Set.Set ReferenceKey, Set.Set VettingKey, Set.Set ReferenceKey) -> IO ([Finding], Set.Set ReferenceKey, Set.Set VettingKey, Set.Set ReferenceKey)
forced result@(findings, cited, seen, tested) = do
  _ <- evaluate (Set.size (Set.fromList findings))
  _ <- evaluate (Set.size cited + Set.size seen + Set.size tested)
  pure result

-- | The findings in their first order with repeats dropped, in one pass over a set, where `nub`
-- compared every finding with every earlier one.
distinct :: [Finding] -> [Finding]
distinct = go Set.empty
  where
    go _ [] = []
    go seen (f : rest)
      | Set.member f seen = go seen rest
      | otherwise = f : go (Set.insert f seen) rest

-- | What the check reports of a survey: every finding as exemptions leave it, each exemption past
-- its revisit, and a canon version other than the one canon.yaml names. ref:DEC-canon-lockstep
surveyReport :: Project -> Survey -> [Finding]
surveyReport project survey = map snd (surveyFindings survey) ++ exemptionFindings (configVersion config) (projectExemptions project) ++ lockstepFindings config
  where
    config = projectConfig project

-- | A project whose canon.yaml names a canon version of another minor than this one was written with
-- other ids and digests, so reading it with this canon would show every row as changed or vanished;
-- any patch of this minor, or the line written as major.minor.x, reads alike.
-- ref:DEC-canon-lockstep ref:DEC-canon-patch-compatibility
lockstepFindings :: Config -> [Finding]
lockstepFindings config = case configCanon config of
  Just declared | not (patchCompatible declared (T.pack canonVersion)) -> [CanonVersionMismatch (T.strip declared) (T.pack canonVersion)]
  _ -> []

-- | A finding that a debt is unpaid becomes an exempt finding while an exemption covers its
-- subject for its kind, so the debt is counted and not yet due. ref:DEC-exemptions
applyExemptions :: Project -> [Finding] -> [Finding]
applyExemptions project = map (exemptFinding project)

-- | One finding as the project's exemptions leave it. ref:DEC-exemptions
exemptFinding :: Project -> Finding -> Finding
exemptFinding project = exempt
  where
    exemptions = projectExemptions project
    vetting = maybe emptyVetting id (projectVetting project)
    relative w = T.pack (makeRelative (normalise (projectDirectory project)) (normalise (wherePath w)))
    subjectOfKind k = case fileOf vetting k of
      Just shard -> T.pack (maybe shard id (stripSuffix ".yaml" (dropKind shard)))
      Nothing -> renderVettingKey k
    dropKind shard = drop 1 (dropWhile (/= '/') shard)
    stripSuffix suffix s = if suffix `isSuffixOf'` s then Just (take (length s - length suffix) s) else Nothing
    isSuffixOf' suffix s = reverse suffix == take (length suffix) (reverse s)
    -- A page is exempted by its path, like a comment; the other materials by their key.
    subjectOfMaterial k = case k of
      DocKey path -> T.pack (makeRelative (normalise (projectDirectory project)) (normalise path))
      _ -> renderVettingKey k
    kindOfKey k = case k of
      CommentKey _ -> "comment"
      LedgerKey _ -> "ledger"
      RegistryKey _ -> "registry"
      KindKey kind _ -> kind
      DocKey _ -> "doc"
    covered what subject kind = case exemptionFor exemptions subject kind of
      Just (pat, e) -> Just (Exempt what pat (renderVersion (exemptionRevisit e)) (exemptionReason e))
      Nothing -> Nothing
    exempt f = maybe f id $ case f of
      CommentPending d w -> covered ("comment " <> renderDecisionId d) (relative w) "comment"
      CommentStale d w -> covered ("comment " <> renderDecisionId d) (relative w) "comment"
      MissingCanonicalComment u w -> covered ("missing comment on " <> renderUnitId u) (relative w) "comment"
      TestWithoutRequirement u w -> covered ("test " <> renderUnitId u) (relative w) "comment"
      MaterialPending k -> covered (renderVettingKey k) (subjectOfMaterial k) (kindOfKey k)
      MaterialStale k -> covered (renderVettingKey k) (subjectOfMaterial k) (kindOfKey k)
      KindPending k -> covered (renderVettingKey k) (subjectOfKind k) (kindOfKey k)
      _ -> Nothing

resolveProfile :: Project -> Profile -> Profile
resolveProfile project profile =
  profile
    { profileGrammar = case profileGrammar profile of
        CombinedGrammarFile path -> CombinedGrammarFile (resolvePath project path)
        SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolvePath project lexer) (resolvePath project parser)
    }

-- | What a profile contributes to a cache key: the profile as canon.yaml writes it, and the
-- grammar sources it resolves to. The resolved paths are left out, since a snapshot resolves a
-- project's own grammar under its own root and its entries are shared. ref:DEC-extraction-cache
profileBytes :: Project -> Profile -> IO LBS.ByteString
profileBytes project written = do
  let profile = resolveProfile project written
      named = case profileGrammar profile of
        CombinedGrammarFile g -> [g]
        SplitGrammarFiles l r -> [l, r]
  -- Imported lexer fragments live beside their owner. Hash that directory's grammar
  -- inputs too, so editing an imported grammar cannot reuse stale extraction.
  siblings <- fmap concat $ mapM grammarSiblings (nub (map takeDirectory named))
  sources <- mapM readOrEmpty (sort (nub (named ++ siblings)))
  pure (LBS.concat (LBS.fromStrict (encodeSorted written) : sources))
  where
    grammarSiblings dir = do
      present <- doesDirectoryExist dir
      if present then map (dir </>) . filter (T.isSuffixOf ".g4" . T.pack) <$> listDirectory dir else pure []
    readOrEmpty path = do
      present <- doesFileExist path
      if present then LBS.readFile path else pure LBS.empty

-- | What every cache key of a project holds: the canon that read it. Nothing project- or
-- repository-wide is in it: the version canon.yaml names, the described version, and the
-- releases are stamped on after the cache, so a release, a commit, or a tag elsewhere leaves an
-- entry valid, and every side of the repository shares it. ref:DEC-extraction-cache
-- ref:DEC-repository-facts
projectCacheParts :: [LBS.ByteString]
projectCacheParts = [LBS.fromStrict (TE.encodeUtf8 (T.pack canonVersion))]

-- | The project with its side's repository facts read once, and a provider that answers from them
-- and keeps blames and messages in the cache. Outside a repository, or with no git, there are no
-- facts and the provider is the side's own, which reports git as unavailable per file as before.
-- ref:DEC-repository-facts
withFacts :: Project -> IO (Project, Maybe Facts)
withFacts project = do
  read' <- repositoryFacts (projectDirectory project) (projectSide project)
  pure $ case read' of
    Right facts -> (project {projectGit = factsProvider (projectCache project) facts (projectGit project)}, Just facts)
    Left _ -> (project, Nothing)

-- | A file's extraction under a key, and its model as the side stands now: extracted without the
-- repository-wide answers, cached, and stamped with them and with the project's version, which a
-- release changes in canon.yaml without changing the file. ref:DEC-extraction-cache
throughCache :: Project -> Maybe Facts -> CacheKey -> (GitProvider -> IO (Either Text Extraction)) -> IO (Either Text Extraction)
throughCache project facts key extract = do
  cached <- lookupCached (projectDirectory project) (projectCache project) key
  fresh <- case cached of
    Just hit -> pure hit
    Nothing -> do
      made <- extract (bareProvider (projectGit project))
      storeCached (projectDirectory project) (projectCache project) key made
      pure made
  let version = configVersion (projectConfig project)
      versioned (Extraction model findings) = Extraction model {modelVersion = version} findings
  pure (maybe id (fmap . stampExtraction) facts (versioned <$> fresh))

-- | Extracts every walked file through the cache, so a review tool over the project sees the same
-- model the check does. ref:DEC-extraction-cache
extractAll :: Project -> Walked -> IO [(FilePath, Either Text Extraction)]
extractAll unread walked = do
  (project, facts) <- withFacts unread
  extractAllWith facts project walked

extractAllWith :: Maybe Facts -> Project -> Walked -> IO [(FilePath, Either Text Extraction)]
extractAllWith facts project walked = do
  let config = projectConfig project
  interpreters <- lazyInterpreters project
  grammarBytes <- Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> profileBytes project profile) (Map.toList (configLanguages config))
  let projectParts = projectCacheParts
  (folio, consumed) <- folioExtractions facts project walked interpreters grammarBytes projectParts
  let rest = [p | p <- walkedFiles walked, not (Set.member (idPathOf project p) consumed)]
  workers <- getNumCapabilities
  slots <- newQSem (max 1 workers)
  others <- mapConcurrently (\path -> (,) path <$> bracket_ (waitQSem slots) (signalQSem slots) (extractCached facts project interpreters grammarBytes projectParts path)) rest
  pure (folio ++ others)

-- | The extractions the Folio pages produce: one per page, its unit of kind doc with its findings,
-- and one per tangled file, parsed with the embedded language and relocated into the pages, so a
-- tangled file on disk is never extracted on its own. Returns the paths those extractions stand
-- for, pages and tangled files both. ref:DEC-units-by-tangled-path
folioExtractions :: Maybe Facts -> Project -> Walked -> Map.Map Text (IO (Either InterpretError Interpreter)) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> IO ([(FilePath, Either Text Extraction)], Set.Set FilePath)
folioExtractions facts project walked interpreters grammarBytes projectParts = case folioProfiles project of
  [] -> pure ([], Set.empty)
  profiles -> do
    result <- tangleWith project (Just walked) (\lang profile -> Map.findWithDefault (loadProfileInterpreter (resolveProfile project profile)) lang interpreters) []
    case result of
      Left err -> pure ([("folio", Left err)], Set.empty)
      Right (docs, tangled, findings) -> do
        let config = projectConfig project
            embeds = Map.unions [profileEmbeds p | (_, p) <- profiles]
            folioGrammar = LBS.concat [Map.findWithDefault LBS.empty lang grammarBytes | (lang, _) <- profiles]
        sources <- Map.fromList <$> mapM (\d -> (,) (docPath d) <$> LBS.readFile (resolvePath project (docPath d))) docs
        extracted <- mapM (extractTangled config embeds folioGrammar sources) tangled
        -- A block is checked for what it defines only when its tangled file was read; a file the
        -- grammar refuses is reported once, not once per block.
        let units = concat [modelAllUnits (extractionModel e) | (_, Right e, _) <- extracted]
            readBlocks = concat [tangledBlocks t | (_, Right _, t) <- extracted]
            definitions = blockDefinitionFindings readBlocks units
            duplicates = duplicateIdFindings docs
            pageOf d =
              let own = frontMatterFindings d ++ videoFindings d ++ [f | f <- findings ++ definitions, findingPath f == Just (docPath d)] ++ [f | f <- duplicates, docPath d == firstPathOf f]
                  Extraction m fs = pageExtraction config d
               in (docPath d, Right (Extraction m (fs ++ own)))
            failed = [(p, Left message) | ExtractionFailed p message <- findings]
            files = [(p, either Left Right e) | (p, e, _) <- extracted]
            consumed = Set.fromList (map docPath docs ++ map tangledPath tangled ++ map fst failed)
        pure (map pageOf docs ++ failed ++ files, consumed)
  where
    findingPath f = case f of
      BlockUndeclared p _ -> Just p
      BlockDoesNotDefine p _ _ -> Just p
      BlockCarriesComment p _ -> Just p
      BlockLanguageUnknown p _ _ -> Just p
      _ -> Nothing
    firstPathOf f = case f of
      DocIdDuplicate _ a _ -> a
      _ -> ""
    videoFindings d = case Map.lookup "video" (docFront d) of
      Just k | isReferenceKey k, Just r <- Map.lookup (ReferenceKey k) (registryEntries (projectRegistry project)), referenceKind r /= Video -> [VideoKeyNotVideo (docPath d) (ReferenceKey k)]
      _ -> []
    -- A tangled file is parsed as the language it embeds, cached by the pages that produce it,
    -- and reported stale when the file on disk differs from the assembly.
    extractTangled config embeds folioGrammar sources t = do
      let path = tangledPath t
          language = case tangledBlocks t of
            (b : _) -> blockLanguage b
            [] -> ""
          contributing = LBS.concat [Map.findWithDefault LBS.empty (blockSource b) sources | b <- tangledBlocks t]
          embedded = Map.lookup language embeds
          lang = maybe "" embeddingLanguage embedded
          grammar = Map.findWithDefault LBS.empty lang grammarBytes
      onDisk <- doesFileExist (resolvePath project path)
      current <- if onDisk then Just <$> TIO.readFile (resolvePath project path) else pure Nothing
      history <- if onDisk then maybe (pure LBS.empty) (`factsStamp` resolvePath project path) facts else pure LBS.empty
      let key = cacheKey (projectParts ++ [LBS.fromStrict (TE.encodeUtf8 (tangledText t)), contributing, folioGrammar, grammar, LBS.fromStrict (TE.encodeUtf8 (T.pack path)), history])
          stale = [TangledStale path | current /= Just (tangledText t)]
      fresh <- throughCache project facts key $ \provider -> do
        loaded <- maybe (pure Nothing) (fmap Just) (Map.lookup lang interpreters)
        case (embedded, Map.lookup lang (configLanguages config), loaded) of
          (Just _, Just profile, Just (Right interpreter)) ->
            either (Left . renderGrammarExtractError) (Right . relocate t) <$> extractWithProfileText provider config lang profile interpreter path path (tangledText t)
          (_, _, Just (Left err)) -> pure (Left (renderInterpretError err))
          _ -> pure (Left ("no language profile embeds " <> language))
      pure (path, fmap (\(Extraction m fs) -> Extraction m (fs ++ stale)) fresh, t)

-- | Records every piece of canonical material without a verdict as pending, each in the file of
-- its kind and subject, and drops the pending rows whose material no longer exists, removing a
-- file left with none. The files it could not read keep their rows, and name themselves, since
-- their comments are unknown rather than gone. ref:DEC-comment-vetting ref:DEC-human-sign-off
-- ref:DEC-vetting-layout
ingestProject :: Project -> IO (FilePath, Int, Int, [VettingKey], [VettingKey], [Text])
ingestProject project = do
  survey <- surveyProject project Nothing
  let extracted = surveyExtracted survey
      unread = [failed | (failed, Left _) <- extracted]
      failures = [T.concat [T.pack failed, ": ", message] | (failed, Left message) <- extracted]
      existing = maybe emptyVetting id (projectVetting project)
      items = surveyMaterials survey
      (added, fresh) = ingest existing items
      unreadFiles = Set.fromList (concat [[commentFile f, docFile f] | f <- unread])
      (updated, dropped) = pruneVanished (`Set.notMember` unreadFiles) (Set.fromList (map materialKey items)) added
      dir = resolvePath project (configVetting (projectConfig project))
  writeVettingDirectory dir updated
  forM_ (Map.keys (vettingFiles existing)) $ \p ->
    if Map.member p (vettingFiles updated) then pure () else removeFile (dir </> p)
  pure (dir, Map.size (vettingEntries updated), Map.size (vettingFiles updated), fresh, dropped, failures)

-- | The canonical material that needs a human verdict, each finding with the text to read.
vetProject :: Project -> IO [(Finding, Maybe Text)]
vetProject project = do
  survey <- surveyProject project Nothing
  let texts = Map.fromList [(materialKey m, materialText m) | m <- surveyMaterials survey]
  pure [(f, findingKey f >>= (`Map.lookup` texts)) | (_, f) <- surveyFindings survey, attention f]

idPathOf :: Project -> FilePath -> FilePath
idPathOf project path = makeRelative (normalise (projectDirectory project)) (normalise path)

-- | Extracts one file through the profile that owns it, for the model subcommand.
extractFile :: Project -> FilePath -> IO (Either Text Extraction)
extractFile project path = do
  let config = projectConfig project
  case profileForPath (configLanguages config) path of
    Nothing -> pure (Left (T.pack path <> ": no language profile matches this path"))
    Just (lang, profile) | lang == "folio" || not (Map.null (profileEmbeds profile)) -> do
      result <- tangleProject project [path]
      pure $ case result of
        Left err -> Left err
        Right (docs, _, findings) -> case docs of
          (d : _) -> Right (let Extraction m fs = pageExtraction config d in Extraction m (fs ++ frontMatterFindings d ++ findings))
          [] -> Left (T.pack path <> ": " <> T.intercalate "; " (map renderFinding findings))
    Just (lang, profile) -> do
      loaded <- loadProfileInterpreter (resolveProfile project profile)
      case loaded of
        Left err -> pure (Left (renderInterpretError err))
        Right interpreter -> either (Left . renderGrammarExtractError) Right <$> extractWithProfile (projectGit project) config lang profile interpreter (idPathOf project path) path

-- | One file through the cache. Its key is what reaches its model: the file's bytes and path, its
-- grammar, and the history its blame reads, which is whether the side's commit holds the file and
-- the commit that last changed it there; no git process runs for it on a hit. ref:DEC-extraction-cache
-- ref:DEC-repository-facts
extractCached :: Maybe Facts -> Project -> Map.Map Text (IO (Either InterpretError Interpreter)) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> FilePath -> IO (Either Text Extraction)
extractCached facts project interpreters grammarBytes projectParts path = do
  let config = projectConfig project
      profileFor = profileForPath (configLanguages config) path
  content <- LBS.readFile path
  history <- maybe (pure LBS.empty) (`factsStamp` path) facts
  let key =
        cacheKey
          ( projectParts
              ++ [ content
                 , history
                 , maybe LBS.empty (\(lang, _) -> Map.findWithDefault LBS.empty lang grammarBytes) profileFor
                 , LBS.fromStrict (TE.encodeUtf8 (T.pack (sharedPath (projectDirectory project) path)))
                 ]
          )
  throughCache project facts key $ \provider -> case profileFor of
    Just (lang, profile) -> sequence (Map.lookup lang interpreters) >>= \loaded -> case loaded of
      Just (Right interpreter) ->
        either (Left . renderGrammarExtractError) Right
          <$> extractWithProfile provider config lang profile interpreter (idPathOf project path) path
      Just (Left err) -> pure (Left (renderInterpretError err))
      Nothing -> pure (Left "no interpreter for language")
    Nothing -> pure (Left "no language profile matches this path")

checkExtraction :: Project -> Map.Map VettingKey (Answer Assessment Evidence) -> (FilePath, Either Text Extraction) -> ([Finding], Set.Set ReferenceKey, Set.Set VettingKey, Set.Set ReferenceKey)
checkExtraction project assessments (path, extraction) = case extraction of
  Left message -> ([ExtractionFailed path message], Set.empty, Set.empty, Set.empty)
  Right (Extraction model findings) ->
    ( findings
        ++ checkFile (projectRegistry project) (projectLedger project) model
        ++ maybe [] (\v -> vettingFindings (configVersion config) v assessments model) (projectVetting project)
    , Set.fromList (concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions model))
    , Set.fromList (map decisionKey (modelDecisions model))
    , requirementsCitedByTests (projectRegistry project) model
    )
  where
    config = projectConfig project

-- | One interpreter per language of the project, keyed by the language's name, for extraction
-- and for highlighting alike. ref:DEC-highlight-by-lexer
projectInterpreters :: Project -> IO (Map.Map Text (Either InterpretError Interpreter))
projectInterpreters project = Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> loadProfileInterpreter (resolveProfile project profile)) (Map.toList (configLanguages (projectConfig project)))

-- | One interpreter per language, each built the first time a file of the language misses the
-- cache, so a check whose every file is cached builds none. Each is a write-once cell: the first
-- caller builds it and every other waits for and shares that one, the only state the extraction
-- threads share. ref:DEC-extraction-cache
lazyInterpreters :: Project -> IO (Map.Map Text (IO (Either InterpretError Interpreter)))
lazyInterpreters project = Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> once (loadProfileInterpreter (resolveProfile project profile))) (Map.toList (configLanguages (projectConfig project)))

-- | An action run at most once, its result kept for every later call.
once :: IO a -> IO (IO a)
once action = do
  cell <- newMVar Nothing
  pure $ modifyMVar cell $ \held -> case held of
    Just value -> pure (held, value)
    Nothing -> do
      value <- action
      pure (Just value, value)

-- | The languages of the project that embed another: the Folio pages. ref:DEC-folio-language
folioProfiles :: Project -> [(Text, Profile)]
folioProfiles project = [(lang, p) | (lang, p) <- Map.toList (configLanguages (projectConfig project)), lang == "folio" || not (Map.null (profileEmbeds p))]

-- | Scans every page of the project, or only the given ones, and assembles the files their
-- blocks tangle to, with the findings a block raises on its own: no declaration, a comment in
-- its body, or a language the page's profile does not embed. What a block defines is checked
-- where units are known. ref:DEC-tangle-in-canon
tangleProject :: Project -> [FilePath] -> IO (Either Text ([Document], [Tangled], [Finding]))
tangleProject project = tangleWith project Nothing (\_ profile -> loadProfileInterpreter (resolveProfile project profile))

-- | Tangles with the walk and the interpreters a check already has, so a check walks the project
-- and builds each grammar once; the pages are scanned at once.
tangleWith :: Project -> Maybe Walked -> (Text -> Profile -> IO (Either InterpretError Interpreter)) -> [FilePath] -> IO (Either Text ([Document], [Tangled], [Finding]))
tangleWith project known interpreterFor only = case folioProfiles project of
  [] -> pure (Left "no language in canon.yaml embeds another, so there is nothing to tangle")
  profiles -> do
    walked <- maybe (projectFiles project Nothing) pure known
    let wanted = map (idPathOf project) only
    results <- mapM (scanLanguage walked wanted) profiles
    case sequence results of
      Left err -> pure (Left err)
      Right perLanguage ->
        let docs = concatMap fst perLanguage
            findings = concatMap snd perLanguage
            embeds = Map.unions [profileEmbeds p | (_, p) <- profiles]
            blocks = concatMap docBlocks docs
            byLanguage = Map.fromListWith (flip (++)) [(blockLanguage b, [b]) | b <- blocks]
            unknown = [BlockLanguageUnknown (blockSource b) (blockLine b) (blockLanguage b) | b <- blocks, not (Map.member (blockLanguage b) embeds)]
            tangled = concat [assemble e bs | (lang, bs) <- Map.toList byLanguage, Just e <- [Map.lookup lang embeds]]
            own = concat [blockFindings e b | b <- blocks, Just e <- [Map.lookup (blockLanguage b) embeds]]
         in pure (Right (docs, tangled, findings ++ unknown ++ own))
  where
    scanLanguage walked wanted (lang, profile) = do
      loaded <- interpreterFor lang profile
      case loaded of
        Left err -> pure (Left (renderInterpretError err))
        Right interpreter -> do
          let mine = [p | p <- walkedFiles walked, any (`T.isSuffixOf` T.pack (takeFileName p)) (profileExtensions profile), null wanted || idPathOf project p `elem` wanted]
          scanned <- mapConcurrently (scanOne interpreter profile) mine
          pure (Right ([d | Right d <- scanned], [f | Left f <- scanned]))
    scanOne interpreter profile path = do
      source <- readSourceFile path
      pure $ case interpretText interpreter (profileStart profile) path source of
        Left err -> Left (ExtractionFailed path (renderInterpretError err))
        Right tree -> Right (scanDocument (idPathOf project path) tree)
    blockFindings embedding b =
      [BlockUndeclared (blockSource b) (blockLine b) | not (blockDeclared b)]
        ++ [BlockCarriesComment (blockSource b) (blockLine b + line) | line <- commentLines embedding (blockBody b)]
    -- A comment is found by the embedded language's syntax; a pragma is not one, and dashes
    -- inside an operator are not one either.
    commentLines embedding body =
      [ positionLine (spanStart (locatedSpan c))
      | c <- scanCommentsWith (embeddingComments embedding) (T.unlines body)
      , let Position line column = spanStart (locatedSpan c)
      , let text = if line >= 1 && line <= length body then body !! (line - 1) else ""
      , let after = T.drop (column - 1) text
      , not ("{-#" `T.isPrefixOf` after)
      , not (T.take 2 after == "--" && column > 1 && T.index text (column - 2) `elem` ("!#$%&*+./<=>?@\\^|~-" :: String))
      ]

-- | Whether a finding fails the check under the project's taxes: material owed a verdict fails
-- only while the sign-off tax is paid; every other failing finding fails regardless.
-- ref:DEC-tax-opt-out
findingFails :: Config -> Finding -> Bool
findingFails config f
  | findingPending f = taxSignOff (configTaxes config) == TaxPaid
  | otherwise = findingSeverity f == Failing
