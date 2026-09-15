module Canon.Model.Answer
  ( Answer (..)
  , UnitKind (..)
  , What (..)
  , How (..)
  , Where (..)
  , Why (..)
  , Attribution (..)
  , Who (..)
  , Change (..)
  , When (..)
  , Verdict (..)
  , Assessment (..)
  , verdictText
  , parseVerdict
  ) where

import Canon.Git.Commit (CommitHash, Person)
import Canon.Model.Id (ReferenceKey)
import Canon.Span (Span)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Time (UTCTime)

data Answer a ev = Answer
  { answerValue :: a
  , answerEvidence :: ev
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

newtype UnitKind = UnitKind {unitKindText :: Text}
  deriving (Eq, Ord, Show)

data What = What
  { whatName :: Text
  , whatKind :: UnitKind
  }
  deriving (Eq, Show)

data How
  = HowText Text
  | HowAt Span
  deriving (Eq, Show)

data Where = Where
  { wherePath :: FilePath
  , whereSpan :: Span
  , whereChain :: [Text]
  , whereIndex :: Maybe Int
  }
  deriving (Eq, Show)

data Why = Why
  { whyText :: Text
  , whyReferences :: [ReferenceKey]
  , whyLicenses :: [ReferenceKey]
  }
  deriving (Eq, Show)

data Attribution = Attribution
  { attributionPerson :: Person
  , attributionCommits :: [CommitHash]
  }
  deriving (Eq, Show)

data Who = Who
  { whoAuthors :: [Attribution]
  , whoCommitters :: [Attribution]
  }
  deriving (Eq, Show)

data Change = Change
  { changeCommit :: CommitHash
  , changeAt :: UTCTime
  }
  deriving (Eq, Show)

data When = When
  { whenFirst :: Change
  , whenLast :: Change
  , whenIntroducedIn :: Maybe Text
  }
  deriving (Eq, Show)

data Verdict = Pending | Good | Bad | Deferred
  deriving (Eq, Ord, Show, Enum, Bounded)

verdictText :: Verdict -> Text
verdictText v = case v of
  Pending -> "pending"
  Good -> "good"
  Bad -> "bad"
  Deferred -> "deferred"

parseVerdict :: Text -> Maybe Verdict
parseVerdict t = case [v | v <- [minBound .. maxBound], verdictText v == t] of
  (v : _) -> Just v
  [] -> Nothing

data Assessment = Assessment
  { assessmentVerdict :: Verdict
  , assessmentBy :: Maybe Person
  , assessmentAt :: Maybe UTCTime
  , assessmentCommit :: Maybe CommitHash
  }
  deriving (Eq, Show)

instance ToJSON Verdict where
  toJSON = toJSON . verdictText

instance FromJSON Verdict where
  parseJSON = withText "Verdict" $ \t -> maybe (fail ("unknown verdict: " ++ show t)) pure (parseVerdict t)

instance ToJSON Assessment where
  toJSON (Assessment verdict by at commit) = object ["at" .= at, "by" .= by, "commit" .= commit, "verdict" .= verdict]

instance FromJSON Assessment where
  parseJSON = withObject "Assessment" $ \o -> Assessment <$> o .: "verdict" <*> o .:? "by" <*> o .:? "at" <*> o .:? "commit"

instance (ToJSON a, ToJSON ev) => ToJSON (Answer a ev) where
  toJSON (Answer value evidence) = object ["evidence" .= evidence, "value" .= value]

instance (FromJSON a, FromJSON ev) => FromJSON (Answer a ev) where
  parseJSON = withObject "Answer" $ \o -> Answer <$> o .: "value" <*> o .: "evidence"

instance ToJSON UnitKind where
  toJSON = toJSON . unitKindText

instance FromJSON UnitKind where
  parseJSON v = UnitKind <$> parseJSON v

instance ToJSON What where
  toJSON (What name kind) = object ["kind" .= kind, "name" .= name]

instance FromJSON What where
  parseJSON = withObject "What" $ \o -> What <$> o .: "name" <*> o .: "kind"

instance ToJSON How where
  toJSON h = case h of
    HowText body -> object ["body" .= body]
    HowAt sp -> object ["at" .= sp]

instance FromJSON How where
  parseJSON = withObject "How" $ \o -> do
    body <- o .:? "body"
    at <- o .:? "at"
    case (body, at) of
      (Just b, Nothing) -> pure (HowText b)
      (Nothing, Just s) -> pure (HowAt s)
      _ -> fail "How needs exactly one of body or at"

instance ToJSON Where where
  toJSON (Where path sp chain index) =
    object ["chain" .= chain, "index" .= index, "path" .= path, "span" .= sp]

instance FromJSON Where where
  parseJSON = withObject "Where" $ \o ->
    Where <$> o .: "path" <*> o .: "span" <*> o .: "chain" <*> o .:? "index"

instance ToJSON Why where
  toJSON (Why text references licenses) = object ["licenses" .= licenses, "references" .= references, "text" .= text]

instance FromJSON Why where
  parseJSON = withObject "Why" $ \o -> Why <$> o .: "text" <*> o .: "references" <*> (fromMaybe [] <$> o .:? "licenses")

instance ToJSON Attribution where
  toJSON (Attribution person commits) = object ["commits" .= commits, "person" .= person]

instance FromJSON Attribution where
  parseJSON = withObject "Attribution" $ \o -> Attribution <$> o .: "person" <*> o .: "commits"

instance ToJSON Who where
  toJSON (Who authors committers) = object ["authors" .= authors, "committers" .= committers]

instance FromJSON Who where
  parseJSON = withObject "Who" $ \o -> Who <$> o .: "authors" <*> o .: "committers"

instance ToJSON Change where
  toJSON (Change commit at) = object ["at" .= at, "commit" .= commit]

instance FromJSON Change where
  parseJSON = withObject "Change" $ \o -> Change <$> o .: "commit" <*> o .: "at"

instance ToJSON When where
  toJSON (When first' last' introducedIn) =
    object ["first" .= first', "introducedIn" .= introducedIn, "last" .= last']

instance FromJSON When where
  parseJSON = withObject "When" $ \o -> When <$> o .: "first" <*> o .: "last" <*> o .:? "introducedIn"
