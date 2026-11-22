-- | The shell provider runs git as a process, the only place canon starts one, through a runner
-- a host can replace when it has no processes of its own, as a WebAssembly runtime has not.
-- ref:DEC-git-runner
module Canon.Git.Shell
  ( shellGitProvider
  , GitSide (..)
  , sideGitProvider
  , runGit
  , gitIgnoredPaths
  , GitRunner
  , setGitRunner
  ) where

import Canon.Git.Commit (CommitHash (..))
import Canon.Git.Parse (logFormat, parseBlamePorcelain, parseGitLog)
import Canon.Git.Provider
import Canon.Span (Position (..), Span (..))
import Control.Exception (IOException, try)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Set (Set)
import qualified Data.Set as Set
import System.IO.Unsafe (unsafePerformIO)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import System.Exit (ExitCode (..))
import System.FilePath (makeRelative, takeDirectory, takeFileName)
import System.Process.Typed (proc, readProcess)

-- | What runs a git command: a directory and arguments in, the output or an error out.
-- ref:DEC-git-runner
type GitRunner = FilePath -> [String] -> IO (Either GitError Text)

-- | The runner in use, a process by default. A host with no processes installs its own before
-- the first call, and every provider function goes through it. ref:DEC-git-runner
gitRunner :: IORef GitRunner
gitRunner = unsafePerformIO (newIORef processRunner)
{-# NOINLINE gitRunner #-}

-- | Replaces the runner every git call goes through. ref:DEC-git-runner
setGitRunner :: GitRunner -> IO ()
setGitRunner = writeIORef gitRunner

-- | Runs one git command in a directory and returns its output or a git error.
runGit :: FilePath -> [String] -> IO (Either GitError Text)
runGit directory arguments = do
  runner <- readIORef gitRunner
  runner directory arguments

-- | The paths under a directory that git ignores and does not track, as segments from that
-- directory, a wholly ignored directory as one entry. Git answers from every .gitignore, the
-- repository's exclude file, and the user's excludes, so canon reads gitignore as git does. Outside
-- a repository, or with no git, nothing is ignored this way. ref:DEC-honour-gitignore
gitIgnoredPaths :: FilePath -> IO (Set [Text])
gitIgnoredPaths directory = do
  result <- runGit directory ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z"]
  pure $ case result of
    Left _ -> Set.empty
    Right out ->
      Set.fromList
        [ filter (not . T.null) (T.splitOn "/" path)
        | path <- T.splitOn "\0" out
        , not (T.null path)
        ]

processRunner :: GitRunner
processRunner directory arguments = do
  result <- try (readProcess (proc "git" ("-C" : directory : arguments)))
  pure $ case result of
    Left (_ :: IOException) -> Left GitNotFound
    Right (ExitSuccess, out, _) -> Right (decode out)
    Right (ExitFailure code, _, err) -> Left (GitFailed code (decode err))
  where
    decode = TE.decodeUtf8With lenientDecode . LBS.toStrict

lineRange :: Span -> String
lineRange (Span start end) =
  let first = positionLine start
      final = max first (positionLine end)
   in show first ++ "," ++ show final

-- | Which state of a repository a provider answers for. The working tree is read where it lies;
-- the index and a commit are read from a snapshot canon writes outside the repository, so each
-- names the repository's top level and the snapshot's, and a path in the snapshot is asked of git
-- as the same path in the repository. ref:DEC-check-sides
data GitSide
  = WorkTreeSide
  | IndexSide FilePath FilePath
  | CommitSide Text FilePath FilePath
  deriving (Eq, Show)

-- | The provider over the git executable, for the working tree.
shellGitProvider :: GitProvider
shellGitProvider = sideGitProvider WorkTreeSide

-- | The provider for one side. A line is blamed against the commit the side grows from: HEAD for
-- the working tree and the index, the commit itself for a commit. The index's content is given to
-- blame with --contents, so a staged line is not committed even if the working tree has moved on.
-- A file that commit does not hold is not blamed at all: none of its lines is committed.
-- ref:DEC-uncommitted-provenance ref:DEC-check-sides
sideGitProvider :: GitSide -> GitProvider
sideGitProvider side =
  GitProvider
    { historyOf = \path sp ->
        fmap (>>= parseWith parseGitLog) $
          runGit
            (takeDirectory path)
            ["log", "--format=" ++ T.unpack logFormat, "-L", lineRange sp ++ ":" ++ takeFileName path]
    , committedIn = \path -> do
        let (directory, name, commit) = case side of
              WorkTreeSide -> (takeDirectory path, takeFileName path, "HEAD")
              IndexSide top snapshot -> (top, makeRelative snapshot path, "HEAD")
              CommitSide hash top snapshot -> (top, makeRelative snapshot path, T.unpack hash)
        result <- runGit directory ["ls-tree", "--name-only", commit, "--", name]
        pure $ case result of
          Right out -> Right (not (T.null (T.strip out)))
          -- A repository with no commit yet holds no file.
          Left (GitFailed _ message) | "Not a valid object name" `T.isInfixOf` message -> Right False
          Left err -> Left err
    , blameOf = \path sp ->
        fmap (>>= parseWith parseBlamePorcelain) $ case side of
          WorkTreeSide ->
            runGit (takeDirectory path) ["blame", "--line-porcelain", "-L", lineRange sp, "--", takeFileName path]
          IndexSide top snapshot ->
            runGit top ["blame", "--line-porcelain", "-L", lineRange sp, "--contents", path, "--", makeRelative snapshot path]
          CommitSide hash top snapshot ->
            runGit top ["blame", "--line-porcelain", "-L", lineRange sp, T.unpack hash, "--", makeRelative snapshot path]
    , tagsContaining = \(CommitHash hash) ->
        fmap (fmap (filter (not . T.null) . map T.strip . T.lines)) $
          runGit (repository ".") ["tag", "--contains", T.unpack hash, "--sort=v:refname"]
    , describeVersion = do
        result <- case side of
          CommitSide hash top _ -> runGit top ["describe", "--tags", "--always", T.unpack hash]
          _ -> runGit (repository ".") ["describe", "--tags", "--always", "--dirty"]
        pure $ case result of
          Right out -> Right (nonEmptyText (T.strip out))
          Left GitNotFound -> Left GitNotFound
          Left _ -> Right Nothing
    , messageOf = \(CommitHash hash) -> runGit (repository ".") ["log", "-1", "--format=%B", T.unpack hash]
    }
  where
    parseWith parser = either (Left . GitUnparsable) Right . parser
    nonEmptyText t = if T.null t then Nothing else Just t
    repository here = case side of
      WorkTreeSide -> here
      IndexSide top _ -> top
      CommitSide _ top _ -> top
