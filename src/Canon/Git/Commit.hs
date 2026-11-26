-- | The git facts canon consumes, as plain values, so the shell and the static provider produce the
-- same thing.
module Canon.Git.Commit
  ( CommitHash (..)
  , Person (..)
  , Commit (..)
  , BlameLine (..)
  , uncommittedHash
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)

-- | A commit hash as text.
newtype CommitHash = CommitHash {commitHashText :: Text}
  deriving (Eq, Ord, Show)

-- | Whether a hash is git's placeholder for a line no commit holds: blame gives a staged, unstaged
-- or --contents line the all-zero hash and the author "Not Committed Yet", which is no person and
-- no change. ref:DEC-uncommitted-provenance
uncommittedHash :: CommitHash -> Bool
uncommittedHash (CommitHash hash) = not (T.null hash) && T.all (== '0') hash

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

instance ToJSON BlameLine where
  toJSON l =
    object
      [ "author" .= blameAuthor l
      , "authorTime" .= blameAuthorTime l
      , "committer" .= blameCommitter l
      , "committerTime" .= blameCommitterTime l
      , "content" .= blameContent l
      , "hash" .= blameHash l
      , "line" .= blameFinalLine l
      , "summary" .= blameSummary l
      ]

instance FromJSON BlameLine where
  parseJSON = withObject "BlameLine" $ \o ->
    BlameLine
      <$> o .: "hash"
      <*> o .: "line"
      <*> o .: "author"
      <*> o .: "authorTime"
      <*> o .: "committer"
      <*> o .: "committerTime"
      <*> o .: "summary"
      <*> o .: "content"
