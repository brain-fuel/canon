-- | Canonical material that nobody has judged is not known to fulfil its purpose, so every
-- canonical comment, ledger entry, and registry entry carries a verdict, and the signer is whoever
-- wrote the verdict line, read from git blame, together with the co-authors of that commit. The
-- verdicts live in a directory with a file per kind and subject, so a record sits beside the path
-- it judges and any review tool reads and rewrites the same files canon checks.
-- ref:DEC-comment-vetting ref:DEC-human-sign-off ref:DEC-vetting-layout
module Canon.Vetting
  ( VettingEntry (..)
  , Vetting (..)
  , VettingError (..)
  , Material (..)
  , emptyVetting
  , vettingEntries
  , fileOf
  , mapEntries
  , readVettingDirectory
  , readVettingFile
  , writeVettingDirectory
  , renderVetting
  , renderVettingError
  , digestOf
  , commentDigest
  , ledgerDigest
  , registryDigest
  , commentFile
  , docFile
  , decisionKey
  , ledgerFile
  , registryFile
  , materials
  , ingest
  , pruneVanished
  , verdictLines
  , assess
  , applyAssessments
  , vettingFindings
  , materialFindings
  , kindFindings
  , orphanVerdictFindings
  , attention
  ) where

import Canon.Config (Disposition (..))
import Canon.Decisions (DecisionEntry (entryQuestion), Ledger (..))
import Canon.Git.Commit (BlameLine (..), CommitHash (..))
import Canon.Git.Parse (trailerPersons)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Model.Yaml (encodeSorted)
import Canon.Registry (Reference (..), Registry (..))
import Canon.Span (Position (..), Span (..))
import Canon.Version (Version, parseVersion, renderVersion)
import Control.Monad (forM, forM_)
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.:?), (.=))
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isAlphaNum, isHexDigit, isSpace)
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import qualified Data.Yaml as Yaml
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import System.FilePath (makeRelative, normalise, takeDirectory, takeExtension, takeFileName, (<.>), (</>))

-- | A verdict with the digest of the material it applies to, an optional revisit version, a
-- note, and for a row another tool raises the run it was decided against, which canon carries
-- and does not read. ref:DEC-vetting-kinds ref:DEC-vetting-run-field
data VettingEntry = VettingEntry
  { entryVerdict :: Verdict
  , entryDigest :: Text
  , entryRevisit :: Maybe Version
  , entryNote :: Maybe Text
  , entryRun :: Maybe Text
  }
  deriving (Eq, Show)

-- | The entries of each file in the vetting directory, keyed by the file's path within it, so a
-- verdict is written back to the file it was read from and blamed there. ref:DEC-vetting-layout
newtype Vetting = Vetting {vettingFiles :: Map FilePath (Map VettingKey VettingEntry)}
  deriving (Eq, Show)

-- | An unreadable vetting file is an error, and so is the single file of the old layout, which
-- must be regenerated rather than read. ref:DEC-vetting-layout
data VettingError
  = VettingUnreadable FilePath Text
  | VettingIsFile FilePath
  deriving (Eq, Show)

-- | One piece of canonical material as the vetting sees it: its key, the file its verdict belongs
-- in, the digest of what it says, and the text a reviewer reads. ref:DEC-human-sign-off
data Material = Material
  { materialKey :: VettingKey
  , materialFile :: FilePath
  , materialDigest :: Text
  , materialText :: Text
  }
  deriving (Eq, Show)

-- | No verdicts.
emptyVetting :: Vetting
emptyVetting = Vetting Map.empty

-- | Every entry regardless of file, which is what the checks look at.
vettingEntries :: Vetting -> Map VettingKey VettingEntry
vettingEntries = Map.unions . Map.elems . vettingFiles

-- | The file an entry lives in.
fileOf :: Vetting -> VettingKey -> Maybe FilePath
fileOf (Vetting files) k = case [p | (p, es) <- Map.toList files, Map.member k es] of
  (p : _) -> Just p
  [] -> Nothing

-- | Applies a change to every entry, keeping each in its file.
mapEntries :: (VettingEntry -> VettingEntry) -> Vetting -> Vetting
mapEntries f (Vetting files) = Vetting (Map.map (Map.map f) files)

-- | Renders a vetting error.
renderVettingError :: VettingError -> Text
renderVettingError e = case e of
  VettingUnreadable path message -> T.concat [T.pack path, ": ", message]
  VettingIsFile path -> T.concat [T.pack path, ": the vetting ledger is a directory with a file per kind and subject; delete this file and run canon ingest"]

-- | Reads every YAML file under the vetting directory, each keyed by its path within it.
readVettingDirectory :: FilePath -> IO (Either VettingError Vetting)
readVettingDirectory dir = do
  paths <- yamlFilesUnder dir ""
  results <- forM paths $ \p -> fmap ((,) p) <$> readVettingFile (dir </> p)
  pure (Vetting . Map.fromList <$> sequence results)

yamlFilesUnder :: FilePath -> FilePath -> IO [FilePath]
yamlFilesUnder dir rel = do
  names <- sort <$> listDirectory (dir </> rel)
  concat
    <$> forM
      names
      ( \name -> do
          let here = if null rel then name else rel </> name
          isDirectory <- doesDirectoryExist (dir </> here)
          if isDirectory
            then yamlFilesUnder dir here
            else pure [here | takeExtension name == ".yaml"]
      )

-- | Reads one vetting file.
readVettingFile :: FilePath -> IO (Either VettingError (Map VettingKey VettingEntry))
readVettingFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . VettingUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

-- | Writes every file of the vetting directory in the fixed form the line scanner reads, creating
-- the directories a file needs.
writeVettingDirectory :: FilePath -> Vetting -> IO ()
writeVettingDirectory dir (Vetting files) = forM_ (Map.toList files) $ \(p, entries) -> do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  TIO.writeFile (dir </> p) (renderVetting entries)

-- | Renders entries one key per line so git blame attributes each verdict line to its author.
renderVetting :: Map VettingKey VettingEntry -> Text
renderVetting entries
  | Map.null entries = "{}\n"
  | otherwise = T.concat (map render (Map.toList entries))
  where
    render (k, e) =
      T.concat
        ( [keyText (renderVettingKey k), ":\n", "  digest: ", digestText (entryDigest e), "\n"]
            ++ maybe [] (\n -> ["  note: ", quoted n, "\n"]) (entryNote e)
            ++ maybe [] (\r -> ["  revisit: ", renderVersion r, "\n"]) (entryRevisit e)
            ++ maybe [] (\r -> ["  run: ", quoted r, "\n"]) (entryRun e)
            ++ ["  verdict: ", verdictText (entryVerdict e), "\n"]
        )
    keyText k = if T.all plain k then k else quoted k
    -- A digest of hex digits alone can read as a YAML number, so it is quoted; canon's own carry
    -- the algorithm as a prefix and cannot.
    digestText d = if T.all isHexDigit d then quoted d else d
    plain c = isAlphaNum c || c `elem` ("/._-#+~@" :: String)
    quoted t = TE.decodeUtf8 (LBS.toStrict (encode t))

-- | A short digest of text, so a verdict applies to exactly the material that was read.
digestOf :: Text -> Text
digestOf t = "sha256:" <> T.take 16 (TE.decodeUtf8 (Base16.encode (hash (TE.encodeUtf8 t))))

-- | The digest of a comment is the digest of its Why.
commentDigest :: Why -> Text
commentDigest = digestOf . whyText

-- | The digest of a ledger entry covers everything it says, in a fixed key order, so any edit
-- makes its verdict stale.
ledgerDigest :: DecisionEntry -> Text
ledgerDigest = digestOf . TE.decodeUtf8 . encodeSorted

-- | The digest of a registry entry covers its kind, title, and locator.
registryDigest :: Reference -> Text
registryDigest = digestOf . TE.decodeUtf8 . encodeSorted

-- | A comment's verdicts mirror the source tree under comment/, so a record sits beside the path
-- it judges and a rename of the source moves its record. ref:DEC-vetting-layout
commentFile :: FilePath -> FilePath
commentFile source = "comment" </> makeRelative "/" (normalise source) <.> "yaml"

-- | A page's verdicts sit under doc/ at the page's path, as a comment's sit under comment/.
-- ref:DEC-doc-kind
docFile :: FilePath -> FilePath
docFile path = "doc" </> makeRelative "/" (normalise path) <.> "yaml"

-- | The key a decision's verdict is filed under: a page's is its path under doc, since the page
-- is the material; any other decision's is its id under comment. ref:DEC-doc-kind
decisionKey :: Decision ev -> VettingKey
decisionKey d = case decisionUnits d of
  (u :| _) | isDocUnit u -> DocKey (wherePath (decisionWhere d))
  _ -> CommentKey (decisionId d)
  where
    isDocUnit (UnitId segments) = NE.head segments == "folio" && case reverse (NE.toList segments) of
      (_ : "doc" : _) -> True
      _ -> False

-- | The ledger is its own subject, so its verdicts sit in one file named after it.
-- ref:DEC-vetting-layout
ledgerFile :: FilePath -> FilePath
ledgerFile name = "ledger" </> takeFileName name

-- | The registry is its own subject, so its verdicts sit in one file named after it.
-- ref:DEC-vetting-layout
registryFile :: FilePath -> FilePath
registryFile name = "registry" </> takeFileName name

-- | Everything a project asks a human to sign: its comments, its ledger, and its registry, each
-- placed in the file its verdict belongs in.
materials :: FilePath -> FilePath -> [Decision ev] -> Ledger -> Registry -> [Material]
materials ledgerName registryName decisions ledger registry =
  map commentMaterial decisions
    ++ [Material (LedgerKey k) (ledgerFile ledgerName) (ledgerDigest e) (entryQuestion e) | (k, e) <- Map.toList (ledgerEntries ledger)]
    ++ [Material (RegistryKey k) (registryFile registryName) (registryDigest r) (referenceTitle r) | (k, r) <- Map.toList (registryEntries registry)]
  where
    commentMaterial d = Material (decisionKey d) (materialFileOf d) (commentDigest (why d)) (whyText (why d))
    materialFileOf d = case decisionKey d of
      DocKey path -> docFile path
      _ -> commentFile (wherePath (decisionWhere d))
    why d = answerValue (decisionWhy d)

-- | Adds a pending entry for every material without one, in the material's file, and leaves the
-- rest alone.
ingest :: Vetting -> [Material] -> (Vetting, [VettingKey])
ingest vetting@(Vetting files) items = (Vetting (Map.unionWith Map.union files fresh), concatMap Map.keys (Map.elems fresh))
  where
    known = vettingEntries vetting
    fresh =
      Map.fromListWith
        Map.union
        [ (materialFile m, Map.singleton (materialKey m) (VettingEntry Pending (materialDigest m) Nothing Nothing Nothing))
        | m <- items
        , not (Map.member (materialKey m) known)
        ]

-- | Drops the pending rows whose material no longer exists, in the files the caller read whole,
-- since a pending row records no judgement and would otherwise be reported for ever after its
-- material is renamed or removed. A row with a verdict is never dropped: it is a signed record, and
-- its finding asks a human to retire it. Rows of declared kinds are the business of the tool that
-- raises them. Returns the vetting and the keys dropped. ref:DEC-comment-vetting
pruneVanished :: (FilePath -> Bool) -> Set.Set VettingKey -> Vetting -> (Vetting, [VettingKey])
pruneVanished readWhole present (Vetting files) =
  (Vetting (Map.filter (not . Map.null) kept), concat [Map.keys d | d <- Map.elems dropped])
  where
    split p entries
      | readWhole p = Map.partitionWithKey (\k e -> not (vanished k e)) entries
      | otherwise = (entries, Map.empty)
    pairs = Map.mapWithKey split files
    kept = Map.map fst pairs
    dropped = Map.map snd pairs
    vanished k e = entryVerdict e == Pending && not (Set.member k present) && not (isKind k)
    isKind k = case k of
      KindKey _ _ -> True
      _ -> False

-- | The line of each verdict in a file, which is what blame is asked about.
verdictLines :: Text -> Map VettingKey Int
verdictLines source = go Nothing (zip [1 ..] (T.lines source))
  where
    go _ [] = Map.empty
    go current ((n, line) : rest)
      | Just key <- topKey line = go (parseVettingKey key) rest
      | Just k <- current, "verdict:" `T.isPrefixOf` T.stripStart line = Map.insert k n (go current rest)
      | otherwise = go current rest
    topKey line
      | T.null line || isSpace (T.head line) = Nothing
      | Just body <- T.stripSuffix ":" (T.stripEnd line) = Just (unquote body)
      | otherwise = Nothing
    unquote body = case Yaml.decodeEither' (TE.encodeUtf8 body) of
      Right t -> t
      Left _ -> body

-- | The signer of each verdict from a blame of its file, with the co-authors of the signing
-- commit fetched once however many files name it, or an assertion when the line is uncommitted.
assess :: GitProvider -> FilePath -> Map FilePath Text -> Vetting -> IO (Map VettingKey (Answer Assessment Evidence))
assess provider dir sources (Vetting files) = do
  blamedFiles <- forM (Map.toList files) $ \(p, entries) -> do
    let source = Map.findWithDefault "" p sources
        path = dir </> p
        count = max 1 (length (T.lines source))
    blamed <- blameOf provider path (Span (Position 1 1) (Position count 1))
    let byLine = either (const Map.empty) (\ls -> Map.fromList [(blameFinalLine l, l) | l <- ls]) blamed
    pure (path, entries, verdictLines source, byLine)
  let signing = Map.fromList [(blameHash l, ()) | (_, _, _, byLine) <- blamedFiles, l <- Map.elems byLine, not (unsigned l)]
  coAuthors <- Map.traverseWithKey (\h _ -> either (const []) trailerPersons <$> messageOf provider h) signing
  pure
    ( Map.unions
        [ Map.fromList [(k, answer path e (Map.lookup k lineOf) byLine coAuthors) | (k, e) <- Map.toList entries]
        | (path, entries, lineOf, byLine) <- blamedFiles
        ]
    )
  where
    answer path e line byLine coAuthors = case line >>= (`Map.lookup` byLine) of
      Just l | not (unsigned l) ->
        Answer
          (Assessment (entryVerdict e) (Just (blameAuthor l)) (Just (blameAuthorTime l)) (Just (blameHash l)) (Map.findWithDefault [] (blameHash l) coAuthors))
          (DerivedFromGit GitBlame)
      _ -> Answer (Assessment (entryVerdict e) Nothing Nothing Nothing []) (Asserted (Assertion path (lineSpan (maybe 1 id line))))
    lineSpan n = Span (Position n 1) (Position n 1)
    unsigned l = T.all (== '0') (commitHashText (blameHash l))

-- | Puts assessments on the decisions of a model.
applyAssessments :: Map VettingKey (Answer Assessment Evidence) -> Model Evidence -> Model Evidence
applyAssessments assessments m = m {modelDecisions = map fill (modelDecisions m)}
  where
    fill d = d {decisionVetting = Map.lookup (decisionKey d) assessments}

-- | Pending, stale, bad, and deferred comments of one model as findings.
vettingFindings :: Maybe Text -> Vetting -> Map VettingKey (Answer Assessment ev) -> Model ev2 -> [Finding]
vettingFindings version vetting assessments m = concatMap check (modelDecisions m)
  where
    entries = vettingEntries vetting
    current = version >>= parseVersion
    check d = case decisionKey d of
      k@(DocKey _) -> page k d
      k -> comment k d
    -- A page's findings are a material's, named by the page.
    page k d = case Map.lookup k entries of
      Nothing -> [MaterialPending k]
      Just e
        | entryVerdict e == Pending -> [MaterialPending k]
        | entryDigest e /= commentDigest (answerValue (decisionWhy d)) -> [MaterialStale k]
        | otherwise ->
            uncommitted k assessments ++ case entryVerdict e of
              Good -> []
              Pending -> []
              Bad -> [MaterialBad k (entryNote e)]
              Deferred -> case entryRevisit e of
                Nothing -> [MaterialWithoutRevisit k]
                Just revisit
                  | Just now <- current, revisit <= now -> [MaterialDeferredPastRevisit k (renderVersion revisit) (renderVersion now)]
                  | otherwise -> [MaterialDeferred k (renderVersion revisit)]
              Word word -> [VerdictUnknown k word]
    comment k d =
      let w = decisionWhere d
          i = decisionId d
       in case Map.lookup k entries of
            Nothing -> [CommentPending i w]
            Just e
              | entryVerdict e == Pending -> [CommentPending i w]
              | entryDigest e /= commentDigest (answerValue (decisionWhy d)) -> [CommentStale i w]
              | otherwise ->
                  uncommitted k assessments ++ case entryVerdict e of
                    Good -> []
                    Pending -> []
                    Bad -> [CommentBad i w (entryNote e)]
                    Deferred -> case entryRevisit e of
                      Nothing -> [VerdictWithoutRevisit i w]
                      Just revisit
                        | Just now <- current, revisit <= now -> [CommentDeferredPastRevisit i w (renderVersion revisit) (renderVersion now)]
                        | otherwise -> [CommentDeferred i w (renderVersion revisit)]
                    Word word -> [VerdictUnknown k word]

uncommitted :: VettingKey -> Map VettingKey (Answer Assessment ev) -> [Finding]
uncommitted k assessments = case Map.lookup k assessments of
  Just (Answer a _) | assessmentBy a == Nothing -> [VerdictUncommitted k]
  _ -> []

-- | Pending, stale, bad, and deferred ledger and registry entries as findings, decided once per
-- project. ref:DEC-human-sign-off
materialFindings :: Maybe Text -> Vetting -> Map VettingKey (Answer Assessment ev) -> Ledger -> Registry -> [Finding]
materialFindings version vetting assessments ledger registry = concatMap check (materials "" "" [] ledger registry)
  where
    entries = vettingEntries vetting
    current = version >>= parseVersion
    check m =
      let k = materialKey m
       in case Map.lookup k entries of
            Nothing -> [MaterialPending k]
            Just e
              | entryVerdict e == Pending -> [MaterialPending k]
              | entryDigest e /= materialDigest m -> [MaterialStale k]
              | otherwise ->
                  uncommitted k assessments ++ case entryVerdict e of
                    Good -> []
                    Pending -> []
                    Bad -> [MaterialBad k (entryNote e)]
                    Deferred -> case entryRevisit e of
                      Nothing -> [MaterialWithoutRevisit k]
                      Just revisit
                        | Just now <- current, revisit <= now -> [MaterialDeferredPastRevisit k (renderVersion revisit) (renderVersion now)]
                        | otherwise -> [MaterialDeferred k (renderVersion revisit)]
                    Word word -> [VerdictUnknown k word]

-- | Rows of the kinds canon.yaml declares, which another tool raises and keeps fresh: canon
-- counts a row whose word is open as pending, records the signer of the rest, and reports a kind
-- or a word the declaration does not know. ref:DEC-vetting-kinds
kindFindings :: Map Text (Map Text Disposition) -> Vetting -> Map VettingKey (Answer Assessment ev) -> [Finding]
kindFindings kinds vetting assessments = concatMap check (Map.toList (vettingEntries vetting))
  where
    check (k, e) = case k of
      KindKey kind _ -> case Map.lookup kind kinds of
        Nothing -> [KindUndeclared k]
        Just declared -> case Map.lookup (verdictText (entryVerdict e)) declared of
          Nothing -> [VerdictUnknown k (verdictText (entryVerdict e))]
          Just DispositionOpen -> [KindPending k]
          Just _ -> uncommitted k assessments
      _ -> []

-- | Verdicts whose material no longer exists; rows of declared kinds are left to the tool that
-- raises them, since canon cannot know whether a mutant still exists. ref:DEC-vetting-kinds
orphanVerdictFindings :: Vetting -> Set.Set VettingKey -> [Finding]
orphanVerdictFindings vetting seen = [VerdictOrphan k | k <- Map.keys (vettingEntries vetting), not (Set.member k seen), not (isKind k)]
  where
    isKind k = case k of
      KindKey _ _ -> True
      _ -> False

-- | The findings a reviewer must act on, which the vet subcommand lists.
attention :: Finding -> Bool
attention f = case f of
  CommentPending {} -> True
  CommentStale {} -> True
  CommentDeferredPastRevisit {} -> True
  VerdictWithoutRevisit {} -> True
  VerdictOrphan _ -> True
  MaterialPending _ -> True
  MaterialStale _ -> True
  MaterialDeferredPastRevisit {} -> True
  MaterialWithoutRevisit _ -> True
  KindPending _ -> True
  KindUndeclared _ -> True
  VerdictUnknown _ _ -> True
  _ -> False

instance ToJSON VettingEntry where
  toJSON (VettingEntry verdict digest revisit note run) =
    object ["digest" .= digest, "note" .= note, "revisit" .= revisit, "run" .= run, "verdict" .= verdict]

instance FromJSON VettingEntry where
  parseJSON = withObject "VettingEntry" $ \o ->
    VettingEntry <$> o .: "verdict" <*> o .: "digest" <*> o .:? "revisit" <*> o .:? "note" <*> o .:? "run"
