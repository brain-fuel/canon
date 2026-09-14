module Canon.Git.Provider
  ( GitError (..)
  , GitProvider (..)
  , StaticGit (..)
  , staticGitProvider
  , staticGitProviderWith
  , renderGitError
  ) where

import Canon.Git.Commit
import Canon.Git.Parse (GitParseError (..))
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Canon.Span (Position (..), Span (..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

data GitError
  = GitNotFound
  | GitFailed Int Text
  | GitUnparsable GitParseError
  deriving (Eq, Show)

data GitProvider = GitProvider
  { historyOf :: FilePath -> Span -> IO (Either GitError [Commit])
  , blameOf :: FilePath -> Span -> IO (Either GitError [BlameLine])
  , tagsContaining :: CommitHash -> IO (Either GitError [Text])
  , describeVersion :: IO (Either GitError (Maybe Text))
  }

data StaticGit = StaticGit
  { staticCommits :: [Commit]
  , staticTags :: Map CommitHash [Text]
  , staticDescribe :: Maybe Text
  }

staticGitProvider :: [Commit] -> GitProvider
staticGitProvider commits = staticGitProviderWith (StaticGit commits Map.empty Nothing)

staticGitProviderWith :: StaticGit -> GitProvider
staticGitProviderWith static =
  GitProvider
    { historyOf = \_ _ -> pure (Right (staticCommits static))
    , blameOf = \_ (Span (Position from _) (Position to _)) ->
        pure (Right [blameLine line c | (line, c) <- zip [from .. max from to] (cycle' (staticCommits static))])
    , tagsContaining = \hash -> pure (Right (Map.findWithDefault [] hash (staticTags static)))
    , describeVersion = pure (Right (staticDescribe static))
    }

cycle' :: [a] -> [a]
cycle' xs = if null xs then [] else cycle xs

blameLine :: Int -> Commit -> BlameLine
blameLine line c = BlameLine (commitHash c) line (commitAuthor c) (commitAuthoredAt c) (commitCommitter c) (commitCommittedAt c) (commitSubject c) T.empty

renderGitError :: GitError -> Text
renderGitError e = case e of
  GitNotFound -> "git is not available"
  GitFailed code message -> T.concat ["git exited with ", T.pack (show code), ": ", T.strip message]
  GitUnparsable (GitParseError message) -> "git output could not be parsed: " <> message

instance ToJSON GitError where
  toJSON e = case e of
    GitNotFound -> object ["kind" .= ("notFound" :: Text)]
    GitFailed code message -> object ["code" .= code, "kind" .= ("failed" :: Text), "message" .= message]
    GitUnparsable (GitParseError message) -> object ["kind" .= ("unparsable" :: Text), "message" .= message]

instance FromJSON GitError where
  parseJSON = withObject "GitError" $ \o -> do
    kind <- o .: "kind"
    case (kind :: Text) of
      "notFound" -> pure GitNotFound
      "failed" -> GitFailed <$> o .: "code" <*> o .: "message"
      "unparsable" -> GitUnparsable . GitParseError <$> o .: "message"
      _ -> fail ("unknown git error kind: " ++ T.unpack kind)
