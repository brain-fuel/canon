module Canon.Vetting
  ( VettingEntry (..)
  , Vetting (..)
  , VettingError (..)
  , emptyVetting
  , readVettingFile
  , writeVettingFile
  , renderVetting
  , renderVettingError
  , commentDigest
  , ingest
  , verdictLines
  , assess
  , applyAssessments
  , vettingFindings
  , orphanVerdictFindings
  , attention
  ) where

import Canon.Git.Commit (BlameLine (..), CommitHash (..))
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
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

data VettingEntry = VettingEntry
  { entryVerdict :: Verdict
  , entryDigest :: Text
  , entryRevisit :: Maybe Version
  , entryNote :: Maybe Text
  }
  deriving (Eq, Show)

newtype Vetting = Vetting {vettingEntries :: Map DecisionId VettingEntry}
  deriving (Eq, Show)

data VettingError = VettingUnreadable FilePath Text
  deriving (Eq, Show)

emptyVetting :: Vetting
emptyVetting = Vetting Map.empty

renderVettingError :: VettingError -> Text
renderVettingError (VettingUnreadable path message) = T.concat [T.pack path, ": ", message]

readVettingFile :: FilePath -> IO (Either VettingError Vetting)
readVettingFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . VettingUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

writeVettingFile :: FilePath -> Vetting -> IO ()
writeVettingFile path = TIO.writeFile path . renderVetting

renderVetting :: Vetting -> Text
renderVetting (Vetting entries)
  | Map.null entries = "{}\n"
  | otherwise = T.concat (map render (Map.toList entries))
  where
    render (d, e) =
      T.concat
        ( [keyText (renderDecisionId d), ":\n", "  comment: ", entryDigest e, "\n"]
            ++ maybe [] (\n -> ["  note: ", quoted n, "\n"]) (entryNote e)
            ++ maybe [] (\r -> ["  revisit: ", renderVersion r, "\n"]) (entryRevisit e)
            ++ ["  verdict: ", verdictText (entryVerdict e), "\n"]
        )
    keyText k = if T.all plain k then k else quoted k
    plain c = isAlphaNum c || c `elem` ("/._-#+~@" :: String)
    quoted t = TE.decodeUtf8 (LBS.toStrict (encode t))

commentDigest :: Why -> Text
commentDigest why = "sha256:" <> T.take 16 (TE.decodeUtf8 (Base16.encode (hash (TE.encodeUtf8 (whyText why)))))

ingest :: Vetting -> [Decision ev] -> (Vetting, [DecisionId])
ingest (Vetting entries) decisions = (Vetting (Map.union entries fresh), Map.keys fresh)
  where
    fresh =
      Map.fromList
        [ (decisionId d, VettingEntry Pending (commentDigest (answerValue (decisionWhy d))) Nothing Nothing)
        | d <- decisions
        , not (Map.member (decisionId d) entries)
        ]

verdictLines :: Text -> Map DecisionId Int
verdictLines source = go Nothing (zip [1 ..] (T.lines source))
  where
    go _ [] = Map.empty
    go current ((n, line) : rest)
      | Just key <- topKey line = go (parseDecisionId key) rest
      | Just d <- current, "verdict:" `T.isPrefixOf` T.stripStart line = Map.insert d n (go current rest)
      | otherwise = go current rest
    topKey line
      | T.null line || isSpace (T.head line) = Nothing
      | Just body <- T.stripSuffix ":" (T.stripEnd line) = Just (unquote body)
      | otherwise = Nothing
    unquote body = case Yaml.decodeEither' (TE.encodeUtf8 body) of
      Right t -> t
      Left _ -> body

assess :: GitProvider -> FilePath -> Text -> Vetting -> IO (Map DecisionId (Answer Assessment Evidence))
assess provider path source (Vetting entries) = do
  let lineOf = verdictLines source
      count = max 1 (length (T.lines source))
  blamed <- blameOf provider path (Span (Position 1 1) (Position count 1))
  let byLine = either (const Map.empty) (\ls -> Map.fromList [(blameFinalLine l, l) | l <- ls]) blamed
  pure (Map.fromList [(d, answer d e (Map.lookup d lineOf) byLine) | (d, e) <- Map.toList entries])
  where
    answer d e line byLine = case line >>= (`Map.lookup` byLine) of
      Just l | not (uncommitted l) -> Answer (Assessment (entryVerdict e) (Just (blameAuthor l)) (Just (blameAuthorTime l)) (Just (blameHash l))) (DerivedFromGit GitBlame)
      _ -> Answer (Assessment (entryVerdict e) Nothing Nothing Nothing) (Asserted (Assertion path (lineSpan (maybe 1 id line))))
      where
        _unused = d
    lineSpan n = Span (Position n 1) (Position n 1)
    uncommitted l = T.all (== '0') (commitHashText (blameHash l))

applyAssessments :: Map DecisionId (Answer Assessment Evidence) -> Model Evidence -> Model Evidence
applyAssessments assessments m = m {modelDecisions = map fill (modelDecisions m)}
  where
    fill d = d {decisionVetting = Map.lookup (decisionId d) assessments}

vettingFindings :: Maybe Text -> Vetting -> Map DecisionId (Answer Assessment ev) -> Model ev2 -> [Finding]
vettingFindings version (Vetting entries) assessments m = concatMap check (modelDecisions m)
  where
    current = version >>= parseVersion
    check d =
      let w = decisionWhere d
          i = decisionId d
       in case Map.lookup i entries of
            Nothing -> [CommentPending i w]
            Just e
              | entryVerdict e == Pending -> [CommentPending i w]
              | entryDigest e /= commentDigest (answerValue (decisionWhy d)) -> [CommentStale i w]
              | otherwise ->
                  uncommitted i ++ case entryVerdict e of
                    Good -> []
                    Pending -> []
                    Bad -> [CommentBad i w (entryNote e)]
                    Deferred -> case entryRevisit e of
                      Nothing -> [VerdictWithoutRevisit i w]
                      Just revisit
                        | Just now <- current, revisit <= now -> [CommentDeferredPastRevisit i w (renderVersion revisit) (renderVersion now)]
                        | otherwise -> [CommentDeferred i w (renderVersion revisit)]
    uncommitted i = case Map.lookup i assessments of
      Just (Answer a _) | assessmentBy a == Nothing -> [VerdictUncommitted i]
      _ -> []

orphanVerdictFindings :: Vetting -> Set.Set DecisionId -> [Finding]
orphanVerdictFindings (Vetting entries) seen = [VerdictOrphan d | d <- Map.keys entries, not (Set.member d seen)]

attention :: Finding -> Bool
attention f = case f of
  CommentPending {} -> True
  CommentStale {} -> True
  CommentDeferredPastRevisit {} -> True
  VerdictWithoutRevisit {} -> True
  VerdictOrphan _ -> True
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
