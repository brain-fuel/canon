module Canon.Decisions
  ( DecisionStatus (..)
  , DecisionEntry (..)
  , Ledger (..)
  , LedgerError (..)
  , emptyLedger
  , lookupDecision
  , readLedgerFile
  , renderLedgerError
  , defaultLedgerFileName
  , statusText
  ) where

import Canon.Model.Id (ReferenceKey (..), UnitId)
import Canon.Version (Version)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml

data DecisionStatus = Open | Decided | Superseded
  deriving (Eq, Ord, Show, Enum, Bounded)

data DecisionEntry = DecisionEntry
  { entryStatus :: DecisionStatus
  , entryQuestion :: Text
  , entryAnswer :: Maybe Text
  , entryOpened :: Version
  , entryRevisit :: Maybe Version
  , entryDecided :: Maybe Version
  , entryBy :: Maybe ReferenceKey
  , entryRefs :: [ReferenceKey]
  , entryUnits :: [UnitId]
  }
  deriving (Eq, Show)

newtype Ledger = Ledger {ledgerEntries :: Map ReferenceKey DecisionEntry}
  deriving (Eq, Show)

data LedgerError = LedgerUnreadable FilePath Text
  deriving (Eq, Show)

defaultLedgerFileName :: FilePath
defaultLedgerFileName = "canonical_decisions.yaml"

emptyLedger :: Ledger
emptyLedger = Ledger Map.empty

lookupDecision :: ReferenceKey -> Ledger -> Maybe DecisionEntry
lookupDecision key = Map.lookup key . ledgerEntries

readLedgerFile :: FilePath -> IO (Either LedgerError Ledger)
readLedgerFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . LedgerUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

renderLedgerError :: LedgerError -> Text
renderLedgerError (LedgerUnreadable path message) = T.concat [T.pack path, ": ", message]

statusText :: DecisionStatus -> Text
statusText s = case s of
  Open -> "open"
  Decided -> "decided"
  Superseded -> "superseded"

instance ToJSON DecisionStatus where
  toJSON = toJSON . statusText

instance FromJSON DecisionStatus where
  parseJSON = withText "DecisionStatus" $ \t -> case [s | s <- [minBound .. maxBound], statusText s == t] of
    (s : _) -> pure s
    [] -> fail ("unknown decision status: " ++ T.unpack t)

instance ToJSON DecisionEntry where
  toJSON e =
    object
      [ "answer" .= entryAnswer e
      , "by" .= entryBy e
      , "decided" .= entryDecided e
      , "opened" .= entryOpened e
      , "question" .= entryQuestion e
      , "refs" .= entryRefs e
      , "revisit" .= entryRevisit e
      , "status" .= entryStatus e
      , "units" .= entryUnits e
      ]

instance FromJSON DecisionEntry where
  parseJSON = withObject "DecisionEntry" $ \o -> do
    status <- o .: "status"
    question <- o .: "question"
    answer <- o .:? "answer"
    opened <- o .: "opened"
    revisit <- o .:? "revisit"
    decided <- o .:? "decided"
    by <- o .:? "by"
    refs <- fromMaybe [] <$> o .:? "refs"
    units <- fromMaybe [] <$> o .:? "units"
    case status of
      Open | revisit == Nothing -> fail "an open decision needs a revisit version"
      Decided | answer == Nothing -> fail "a decided decision needs an answer"
      Decided | decided == Nothing -> fail "a decided decision needs the version it was decided in"
      Superseded | by == Nothing -> fail "a superseded decision needs the key that supersedes it"
      _ -> pure ()
    pure (DecisionEntry status question answer opened revisit decided by refs units)

instance ToJSON Ledger where
  toJSON = toJSON . ledgerEntries

instance FromJSON Ledger where
  parseJSON v = Ledger <$> parseJSON v
