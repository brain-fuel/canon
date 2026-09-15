-- | Canonical material that nobody has judged is not known to fulfil its purpose, so every
-- canonical comment, ledger entry, and registry entry carries a verdict, and the signer is whoever
-- wrote the verdict line, read from git blame, together with the co-authors of that commit.
-- ref:DEC-comment-vetting ref:DEC-human-sign-off
module Canon.Vetting
  ( VettingEntry (..)
  , Vetting (..)
  , VettingError (..)
  , Material (..)
  , emptyVetting
  , readVettingFile
  , writeVettingFile
  , renderVetting
  , renderVettingError
  , digestOf
  , commentDigest
  , ledgerDigest
  , registryDigest
  , materials
  , ingest
  , verdictLines
  , assess
  , applyAssessments
  , vettingFindings
  , materialFindings
  , orphanVerdictFindings
  , attention
  ) where

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
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.:?), (.=))
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isAlphaNum, isSpace)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import qualified Data.Yaml as Yaml

-- | A verdict with the digest of the material it applies to, an optional revisit version, and a
-- note.
data VettingEntry = VettingEntry
  { entryVerdict :: Verdict
  , entryDigest :: Text
  , entryRevisit :: Maybe Version
  , entryNote :: Maybe Text
  }
  deriving (Eq, Show)

-- | The vetting file keyed by what each verdict is about.
newtype Vetting = Vetting {vettingEntries :: Map VettingKey VettingEntry}
  deriving (Eq, Show)

-- | An unreadable vetting file is an error.
data VettingError = VettingUnreadable FilePath Text
  deriving (Eq, Show)

-- | One piece of canonical material as the vetting sees it: its key, the digest of what it says,
-- and the text a reviewer reads. ref:DEC-human-sign-off
data Material = Material
  { materialKey :: VettingKey
  , materialDigest :: Text
  , materialText :: Text
  }
  deriving (Eq, Show)

-- | No verdicts.
emptyVetting :: Vetting
emptyVetting = Vetting Map.empty

-- | Renders a vetting error.
renderVettingError :: VettingError -> Text
renderVettingError (VettingUnreadable path message) = T.concat [T.pack path, ": ", message]

-- | Reads a vetting file.
readVettingFile :: FilePath -> IO (Either VettingError Vetting)
readVettingFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . VettingUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

-- | Writes a vetting file in the fixed form the line scanner reads.
writeVettingFile :: FilePath -> Vetting -> IO ()
writeVettingFile path = TIO.writeFile path . renderVetting

-- | Renders entries one key per line so git blame attributes each verdict line to its author.
renderVetting :: Vetting -> Text
renderVetting (Vetting entries)
  | Map.null entries = "{}\n"
  | otherwise = T.concat (map render (Map.toList entries))
  where
    render (k, e) =
      T.concat
        ( [keyText (renderVettingKey k), ":\n", "  comment: ", entryDigest e, "\n"]
            ++ maybe [] (\n -> ["  note: ", quoted n, "\n"]) (entryNote e)
            ++ maybe [] (\r -> ["  revisit: ", renderVersion r, "\n"]) (entryRevisit e)
            ++ ["  verdict: ", verdictText (entryVerdict e), "\n"]
        )
    keyText k = if T.all plain k then k else quoted k
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

-- | Everything a project asks a human to sign: its comments, its ledger, and its registry.
materials :: [Decision ev] -> Ledger -> Registry -> [Material]
materials decisions ledger registry =
  map commentMaterial decisions
    ++ [Material (LedgerKey k) (ledgerDigest e) (entryQuestion e) | (k, e) <- Map.toList (ledgerEntries ledger)]
    ++ [Material (RegistryKey k) (registryDigest r) (referenceTitle r) | (k, r) <- Map.toList (registryEntries registry)]
  where
    commentMaterial d = Material (CommentKey (decisionId d)) (commentDigest (why d)) (whyText (why d))
    why d = answerValue (decisionWhy d)

-- | Adds a pending entry for every material without one and leaves the rest alone.
ingest :: Vetting -> [Material] -> (Vetting, [VettingKey])
ingest (Vetting entries) items = (Vetting (Map.union entries fresh), Map.keys fresh)
  where
    fresh =
      Map.fromList
        [ (materialKey m, VettingEntry Pending (materialDigest m) Nothing Nothing)
        | m <- items
        , not (Map.member (materialKey m) entries)
        ]

-- | The line of each verdict in the file, which is what blame is asked about.
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

-- | The signer of each verdict from blame, with the co-authors of the signing commit, or an
-- assertion when the line is uncommitted.
assess :: GitProvider -> FilePath -> Text -> Vetting -> IO (Map VettingKey (Answer Assessment Evidence))
assess provider path source (Vetting entries) = do
  let lineOf = verdictLines source
      count = max 1 (length (T.lines source))
  blamed <- blameOf provider path (Span (Position 1 1) (Position count 1))
  let byLine = either (const Map.empty) (\ls -> Map.fromList [(blameFinalLine l, l) | l <- ls]) blamed
      signing = Map.fromList [(blameHash l, ()) | l <- Map.elems byLine, not (unsigned l)]
  coAuthors <- Map.traverseWithKey (\h _ -> either (const []) trailerPersons <$> messageOf provider h) signing
  pure (Map.fromList [(k, answer e (Map.lookup k lineOf) byLine coAuthors) | (k, e) <- Map.toList entries])
  where
    answer e line byLine coAuthors = case line >>= (`Map.lookup` byLine) of
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
    fill d = d {decisionVetting = Map.lookup (CommentKey (decisionId d)) assessments}

-- | Pending, stale, bad, and deferred comments of one model as findings.
vettingFindings :: Maybe Text -> Vetting -> Map VettingKey (Answer Assessment ev) -> Model ev2 -> [Finding]
vettingFindings version (Vetting entries) assessments m = concatMap check (modelDecisions m)
  where
    current = version >>= parseVersion
    check d =
      let w = decisionWhere d
          i = decisionId d
       in case Map.lookup (CommentKey i) entries of
            Nothing -> [CommentPending i w]
            Just e
              | entryVerdict e == Pending -> [CommentPending i w]
              | entryDigest e /= commentDigest (answerValue (decisionWhy d)) -> [CommentStale i w]
              | otherwise ->
                  uncommitted (CommentKey i) assessments ++ case entryVerdict e of
                    Good -> []
                    Pending -> []
                    Bad -> [CommentBad i w (entryNote e)]
                    Deferred -> case entryRevisit e of
                      Nothing -> [VerdictWithoutRevisit i w]
                      Just revisit
                        | Just now <- current, revisit <= now -> [CommentDeferredPastRevisit i w (renderVersion revisit) (renderVersion now)]
                        | otherwise -> [CommentDeferred i w (renderVersion revisit)]

uncommitted :: VettingKey -> Map VettingKey (Answer Assessment ev) -> [Finding]
uncommitted k assessments = case Map.lookup k assessments of
  Just (Answer a _) | assessmentBy a == Nothing -> [VerdictUncommitted k]
  _ -> []

-- | Pending, stale, bad, and deferred ledger and registry entries as findings, decided once per
-- project. ref:DEC-human-sign-off
materialFindings :: Maybe Text -> Vetting -> Map VettingKey (Answer Assessment ev) -> Ledger -> Registry -> [Finding]
materialFindings version (Vetting entries) assessments ledger registry = concatMap check (materials [] ledger registry)
  where
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

-- | Verdicts whose material no longer exists.
orphanVerdictFindings :: Vetting -> Set.Set VettingKey -> [Finding]
orphanVerdictFindings (Vetting entries) seen = [VerdictOrphan k | k <- Map.keys entries, not (Set.member k seen)]

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
  _ -> False

instance ToJSON VettingEntry where
  toJSON (VettingEntry verdict digest revisit note) =
    object ["comment" .= digest, "note" .= note, "revisit" .= revisit, "verdict" .= verdict]

instance FromJSON VettingEntry where
  parseJSON = withObject "VettingEntry" $ \o ->
    VettingEntry <$> o .: "verdict" <*> o .: "comment" <*> o .:? "revisit" <*> o .:? "note"

instance ToJSON Vetting where
  toJSON = toJSON . vettingEntries

instance FromJSON Vetting where
  parseJSON v = Vetting <$> parseJSON v
