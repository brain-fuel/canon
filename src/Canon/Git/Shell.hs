module Canon.Git.Shell
  ( shellGitProvider
  , runGit
  ) where

import Canon.Git.Commit (CommitHash (..))
import Canon.Git.Parse (logFormat, parseBlamePorcelain, parseGitLog)
import Canon.Git.Provider
import Canon.Span (Position (..), Span (..))
import Control.Exception (IOException, try)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName)
import System.Process.Typed (proc, readProcess)

runGit :: FilePath -> [String] -> IO (Either GitError Text)
runGit directory arguments = do
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
    }
  where
    parseWith parser = either (Left . GitUnparsable) Right . parser
    nonEmptyText t = if T.null t then Nothing else Just t
