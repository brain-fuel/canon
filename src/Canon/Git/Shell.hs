-- | The shell provider runs git as a process, the only place canon starts one, through a runner
-- a host can replace when it has no processes of its own, as a WebAssembly runtime has not.
-- ref:DEC-git-runner
module Canon.Git.Shell
  ( shellGitProvider
  , runGit
  , GitRunner
  , setGitRunner
  ) where

import Canon.Git.Commit (CommitHash (..))
import Canon.Git.Parse (logFormat, parseBlamePorcelain, parseGitLog)
import Canon.Git.Provider
import Canon.Span (Position (..), Span (..))
import Control.Exception (IOException, try)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO.Unsafe (unsafePerformIO)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName)
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

-- | The provider over the git executable.
shellGitProvider :: GitProvider
shellGitProvider =
  GitProvider
    { historyOf = \path sp ->
        fmap (>>= parseWith parseGitLog) $
          runGit
            (takeDirectory path)
            ["log", "--format=" ++ T.unpack logFormat, "-L", lineRange sp ++ ":" ++ takeFileName path]
    , blameOf = \path sp ->
        fmap (>>= parseWith parseBlamePorcelain) $
          runGit (takeDirectory path) ["blame", "--line-porcelain", "-L", lineRange sp, "--", takeFileName path]
    , tagsContaining = \(CommitHash hash) ->
        fmap (fmap (filter (not . T.null) . map T.strip . T.lines)) $
          runGit "." ["tag", "--contains", T.unpack hash, "--sort=v:refname"]
    , describeVersion = do
        result <- runGit "." ["describe", "--tags", "--always", "--dirty"]
        pure $ case result of
          Right out -> Right (nonEmptyText (T.strip out))
          Left GitNotFound -> Left GitNotFound
          Left _ -> Right Nothing
    , messageOf = \(CommitHash hash) -> runGit "." ["log", "-1", "--format=%B", T.unpack hash]
    }
  where
    parseWith parser = either (Left . GitUnparsable) Right . parser
    nonEmptyText t = if T.null t then Nothing else Just t
