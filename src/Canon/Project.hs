-- | A project is a directory with its configuration, registry, ledger, and vetting directory, and
-- the check stops at nested projects because each answers for itself. ref:DEC-nested-root-check
-- ref:DEC-extraction-cache ref:DEC-vetting-layout
module Canon.Project
  ( Project (..)
  , ProjectError (..)
  , loadProject
  , projectFiles
  , checkProject
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
import Canon.Version (canonVersion, renderVersion)
import Canon.Extract.Grammar
import Canon.Git.Shell (runGit, shellGitProvider)
import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_)
import Control.Monad (forM_)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import System.FilePath (takeDirectory)
import Canon.Ignore (defaultIgnorePatterns, parseIgnorePatterns)
import Canon.Model.Check (checkAll, requirementsCitedByTests)
import Canon.Model
import Canon.Model.Finding (Finding (..), findingKey, renderFinding)
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
import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.FilePath (makeRelative, normalise, takeExtension, takeFileName, (</>))

-- | A project with its three canonical files and its vetting directory loaded.
data Project = Project
  { projectDirectory :: FilePath
  , projectConfig :: Config
  , projectRegistry :: Registry
  , projectLedger :: Ledger
  , projectVetting :: Maybe Vetting
  , projectExemptions :: Exemptions
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
loadProject directory = do
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
      pure (Project directory config <$> registry <*> ledger <*> vetting <*> exemptions)

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
    assess shellGitProvider dir sources vetting

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

-- | The files a check visits, honouring ignore patterns and stopping at nested projects.
projectFiles :: Project -> Maybe FilePath -> IO Walked
projectFiles project target = do
  let config = projectConfig project
      patterns = defaultIgnorePatterns ++ parseIgnorePatterns (configIgnore config)
      supported entry = takeExtension entry == grammarExtension || any (`profileOwns` entry) (Map.elems (configLanguages config))
      root = resolvePath project (maybe (configRoot config) id target)
  isDirectory <- doesDirectoryExist root
  if isDirectory
    then walkProject patterns supported configFileName root
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
surveyProject project target = do
  walked <- projectFiles project target
  assessments <- projectAssessments project
  extracted <- linkSignatures (configLanguages (projectConfig project)) <$> extractAll project walked
  let checked = map (checkExtraction project assessments) extracted
      citedSomewhere = Set.unions [c | (_, c, _, _) <- checked]
      seen = Set.unions [v | (_, _, v, _) <- checked]
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
      , surveyFindings = [(f, exemptFinding project f) | f <- nub own ++ signOff]
      }

-- | What the check reports of a survey: every finding as exemptions leave it, each exemption past
-- its revisit, and a canon version other than the one canon.yaml names. ref:DEC-canon-lockstep
surveyReport :: Project -> Survey -> [Finding]
surveyReport project survey = map snd (surveyFindings survey) ++ exemptionFindings (configVersion config) (projectExemptions project) ++ lockstepFindings config
  where
    config = projectConfig project

-- | A project whose canon.yaml names a canon version other than this one was written with other
-- ids and digests, so reading it with this canon would show every row as changed or vanished.
-- ref:DEC-canon-lockstep
lockstepFindings :: Config -> [Finding]
lockstepFindings config = case configCanon config of
  Just declared | T.strip declared /= T.pack canonVersion -> [CanonVersionMismatch (T.strip declared) (T.pack canonVersion)]
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
    relative w = T.pack (makeRelative "." (normalise (wherePath w)))
    subjectOfKind k = case fileOf vetting k of
      Just shard -> T.pack (maybe shard id (stripSuffix ".yaml" (dropKind shard)))
      Nothing -> renderVettingKey k
    dropKind shard = drop 1 (dropWhile (/= '/') shard)
    stripSuffix suffix s = if suffix `isSuffixOf'` s then Just (take (length s - length suffix) s) else Nothing
    isSuffixOf' suffix s = reverse suffix == take (length suffix) (reverse s)
    -- A page is exempted by its path, like a comment; the other materials by their key.
    subjectOfMaterial k = case k of
      DocKey path -> T.pack (makeRelative "." (normalise path))
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

profileBytes :: Profile -> IO LBS.ByteString
profileBytes profile = do
  let named = case profileGrammar profile of
        CombinedGrammarFile g -> [g]
        SplitGrammarFiles l r -> [l, r]
  -- Imported lexer fragments live beside their owner. Hash that directory's grammar
  -- inputs too, so editing an imported grammar cannot reuse stale extraction.
  siblings <- fmap concat $ mapM grammarSiblings (nub (map takeDirectory named))
  sources <- mapM readOrEmpty (sort (nub (named ++ siblings)))
  pure (LBS.concat (LBS.fromStrict (encodeSorted profile) : sources))
  where
    grammarSiblings dir = do
      present <- doesDirectoryExist dir
      if present then map (dir </>) . filter (T.isSuffixOf ".g4" . T.pack) <$> listDirectory dir else pure []
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

-- | Extracts every walked file through the cache, so a review tool over the project sees the same
-- model the check does. ref:DEC-extraction-cache
extractAll :: Project -> Walked -> IO [(FilePath, Either Text Extraction)]
extractAll project walked = do
  let config = projectConfig project
  interpreters <- Map.toList <$> projectInterpreters project
  grammarBytes <- Map.fromList <$> mapM (\(lang, profile) -> (,) lang <$> profileBytes (resolveProfile project profile)) (Map.toList (configLanguages config))
  projectParts <- projectCacheParts project
  (folio, consumed) <- folioExtractions project (Map.fromList interpreters) grammarBytes projectParts
  let rest = [p | p <- walkedFiles walked, not (Set.member (idPathOf project p) consumed)]
  workers <- getNumCapabilities
  slots <- newQSem (max 1 workers)
  others <- mapConcurrently (\path -> (,) path <$> bracket_ (waitQSem slots) (signalQSem slots) (extractCached project (Map.fromList interpreters) grammarBytes projectParts path)) rest
  pure (folio ++ others)

-- | The extractions the Folio pages produce: one per page, its unit of kind doc with its findings,
-- and one per tangled file, parsed with the embedded language and relocated into the pages, so a
-- tangled file on disk is never extracted on its own. Returns the paths those extractions stand
-- for, pages and tangled files both. ref:DEC-units-by-tangled-path
folioExtractions :: Project -> Map.Map Text (Either InterpretError Interpreter) -> Map.Map Text LBS.ByteString -> [LBS.ByteString] -> IO ([(FilePath, Either Text Extraction)], Set.Set FilePath)
folioExtractions project interpreters grammarBytes projectParts = case folioProfiles project of
  [] -> pure ([], Set.empty)
  profiles -> do
    result <- tangleProject project []
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
          key = cacheKey (projectParts ++ [LBS.fromStrict (TE.encodeUtf8 (tangledText t)), contributing, folioGrammar, grammar, LBS.fromStrict (TE.encodeUtf8 (T.pack path))])
      onDisk <- doesFileExist (resolvePath project path)
      current <- if onDisk then Just <$> TIO.readFile (resolvePath project path) else pure Nothing
      let stale = [TangledStale path | current /= Just (tangledText t)]
      cached <- lookupCached (projectDirectory project) key
      fresh <- case cached of
        Just hit -> pure hit
        Nothing -> do
          made <- case (embedded, Map.lookup lang (configLanguages config), Map.lookup lang interpreters) of
            (Just _, Just profile, Just (Right interpreter)) ->
              either (Left . renderGrammarExtractError) (Right . relocate t) <$> extractWithProfileText shellGitProvider config lang profile interpreter path path (tangledText t)
            (_, _, Just (Left err)) -> pure (Left (renderInterpretError err))
            _ -> pure (Left ("no language profile embeds " <> language))
          storeCached (projectDirectory project) key made
          pure made
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
    Just hit -> pure hit
    Nothing -> do
      fresh <- case profileFor of
        Just (lang, profile) -> case Map.lookup lang interpreters of
          Just (Right interpreter) ->
            either (Left . renderGrammarExtractError) Right
              <$> extractWithProfile shellGitProvider config lang profile interpreter (idPathOf project path) path
          Just (Left err) -> pure (Left (renderInterpretError err))
          Nothing -> pure (Left "no interpreter for language")
        Nothing -> pure (Left "no language profile matches this path")
      storeCached (projectDirectory project) key fresh
      pure fresh

checkExtraction :: Project -> Map.Map VettingKey (Answer Assessment Evidence) -> (FilePath, Either Text Extraction) -> ([Finding], Set.Set ReferenceKey, Set.Set VettingKey, Set.Set ReferenceKey)
checkExtraction project assessments (path, extraction) = case extraction of
  Left message -> ([ExtractionFailed path message], Set.empty, Set.empty, Set.empty)
  Right (Extraction model findings) ->
    ( findings
        ++ checkAll (configVersion config) (projectRegistry project) (projectLedger project) model
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

-- | The languages of the project that embed another: the Folio pages. ref:DEC-folio-language
folioProfiles :: Project -> [(Text, Profile)]
folioProfiles project = [(lang, p) | (lang, p) <- Map.toList (configLanguages (projectConfig project)), lang == "folio" || not (Map.null (profileEmbeds p))]

-- | Scans every page of the project, or only the given ones, and assembles the files their
-- blocks tangle to, with the findings a block raises on its own: no declaration, a comment in
-- its body, or a language the page's profile does not embed. What a block defines is checked
-- where units are known. ref:DEC-tangle-in-canon
tangleProject :: Project -> [FilePath] -> IO (Either Text ([Document], [Tangled], [Finding]))
tangleProject project only = case folioProfiles project of
  [] -> pure (Left "no language in canon.yaml embeds another, so there is nothing to tangle")
  profiles -> do
    walked <- projectFiles project Nothing
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
    scanLanguage walked wanted (_, profile) = do
      loaded <- loadProfileInterpreter (resolveProfile project profile)
      case loaded of
        Left err -> pure (Left (renderInterpretError err))
        Right interpreter -> do
          let mine = [p | p <- walkedFiles walked, any (`T.isSuffixOf` T.pack (takeFileName p)) (profileExtensions profile), null wanted || idPathOf project p `elem` wanted]
          scanned <- mapM (scanOne interpreter profile) mine
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
