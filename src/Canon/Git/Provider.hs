module Canon.Git.Provider
  ( GitError (..)
  , GitProvider (..)
  , StaticGit (..)
  , staticGitProvider
  , staticGitProviderWith
  , renderGitError
  ) where

import Canon.Git.Commit (BlameLine, Commit, CommitHash)
import Canon.Git.Parse (GitParseError (..))
import Canon.Span (Span)
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
    , blameOf = \_ _ -> pure (Right [])
    , tagsContaining = \hash -> pure (Right (Map.findWithDefault [] hash (staticTags static)))
    , describeVersion = pure (Right (staticDescribe static))
    }

renderGitError :: GitError -> Text
renderGitError e = case e of
  GitNotFound -> "git is not available"
  GitFailed code message -> T.concat ["git exited with ", T.pack (show code), ": ", T.strip message]
  GitUnparsable (GitParseError message) -> "git output could not be parsed: " <> message
