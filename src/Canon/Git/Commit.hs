-- | The git facts canon consumes, as plain values, so the shell and the static provider produce the
-- same thing.
module Canon.Git.Commit
  ( CommitHash (..)
  , Person (..)
  , Commit (..)
  , BlameLine (..)
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)
import Data.Time (UTCTime)

-- | A commit hash as text.
newtype CommitHash = CommitHash {commitHashText :: Text}
  deriving (Eq, Ord, Show)

-- | A name and email, the identity git records.
data Person = Person
  { personName :: Text
  , personEmail :: Text
  }
  deriving (Eq, Ord, Show)

-- | A commit as git log reports it.
data Commit = Commit
  { commitHash :: CommitHash
  , commitAuthor :: Person
  , commitAuthoredAt :: UTCTime
  , commitCommitter :: Person
  , commitCommittedAt :: UTCTime
  , commitSubject :: Text
  }
  deriving (Eq, Show)

-- | One line of blame output, with the commit that last changed it.
data BlameLine = BlameLine
  { blameHash :: CommitHash
  , blameFinalLine :: Int
  , blameAuthor :: Person
  , blameAuthorTime :: UTCTime
  , blameCommitter :: Person
  , blameCommitterTime :: UTCTime
  , blameSummary :: Text
  , blameContent :: Text
  }
  deriving (Eq, Show)

instance ToJSON CommitHash where
  toJSON = toJSON . commitHashText

instance FromJSON CommitHash where
  parseJSON v = CommitHash <$> parseJSON v

instance ToJSON Person where
  toJSON (Person name email) = object ["email" .= email, "name" .= name]

instance FromJSON Person where
  parseJSON = withObject "Person" $ \o -> Person <$> o .: "name" <*> o .: "email"
