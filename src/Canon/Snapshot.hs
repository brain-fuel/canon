-- | A side of a repository is the working tree, the index, or a commit. canon reads the working
-- tree where it lies, and the index or a commit from a snapshot it writes outside the repository
-- with `git restore`, which writes files only and never touches the index, HEAD or the working
-- tree; the snapshot is removed when the check is done. The precedent is git's own
-- `checkout-index --prefix`, and pre-commit's checking of what is staged, without its stash of
-- what is not. Every git call goes through the one runner. ref:DEC-check-sides ref:DEC-git-runner
module Canon.Snapshot
  ( SideSpec (..)
  , Side (..)
  , parseSide
  , renderSide
  , resolveSide
  , withSideProject
  ) where

import Canon.Git.Provider (renderGitError)
import Canon.Git.Shell (GitSide (..), gitIgnoredPaths, runGit, shellGitProvider, sideGitProvider)
import Canon.Project (Project, ProjectError, loadProjectWith, renderProjectError)
import Control.Exception (bracket)
import Control.Monad (forM_, unless)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory
  ( createDirectory
  , createDirectoryIfMissing
  , createDirectoryLink
  , createFileLink
  , doesDirectoryExist
  , doesPathExist
  , getTemporaryDirectory
  , makeAbsolute
  , removeDirectoryRecursive
  )
import System.FilePath (joinPath, normalise, takeDirectory, (</>))

-- | A side as the user names it: `:worktree`, `:index`, or any revision git can resolve to a commit.
data SideSpec = SpecWorkTree | SpecIndex | SpecRevision Text
  deriving (Eq, Show)

-- | A side resolved: a commit is named by its full hash, so every later git call reads the same
-- commit even if the branch moves.
data Side = WorkTree | Index | Commit Text
  deriving (Eq, Ord, Show)

-- | Reads a side from its spelling.
parseSide :: Text -> SideSpec
parseSide t = case t of
  ":worktree" -> SpecWorkTree
  ":index" -> SpecIndex
  _ -> SpecRevision t

-- | A resolved side as the user would write it.
renderSide :: Side -> Text
renderSide side = case side of
  WorkTree -> ":worktree"
  Index -> ":index"
  Commit hash -> T.take 12 hash

-- | Resolves a side in the repository holding a directory.
resolveSide :: FilePath -> SideSpec -> IO (Either Text Side)
resolveSide directory spec = case spec of
  SpecWorkTree -> pure (Right WorkTree)
  SpecIndex -> pure (Right Index)
  SpecRevision rev -> do
    result <- runGit directory ["rev-parse", "--verify", "--quiet", T.unpack rev ++ "^{commit}"]
    pure $ case result of
      Right out | not (T.null (T.strip out)) -> Right (Commit (T.strip out))
      Right _ -> Left (rev <> " does not name a commit")
      Left err -> Left (rev <> " does not name a commit: " <> renderGitError err)

-- | Runs an action over the project in a directory as one side holds it. The project's paths, and
-- the ids canon derives from them, are the same on every side; only the directory they are read
-- from differs, and the caller relocates what it reports.
withSideProject :: FilePath -> Side -> (FilePath -> Project -> IO a) -> IO (Either Text a)
withSideProject directory side action = case side of
  WorkTree -> do
    loaded <- loadProjectWith shellGitProvider Nothing directory
    either (pure . Left . renderProjectError) (fmap Right . action directory) loaded
  _ -> do
    located <- repositoryOf directory
    case located of
      Left err -> pure (Left err)
      Right (top, prefix) -> do
        temporary <- getTemporaryDirectory
        bracket (freshDirectory temporary) removeDirectoryRecursive $ \snapshot -> do
          let source = case side of
                Commit hash -> ["--source=" ++ T.unpack hash]
                _ -> []
          restored <- runGit top (["--work-tree=" ++ snapshot, "restore"] ++ source ++ ["--worktree", "--", ":/"])
          case restored of
            Left err -> pure (Left ("could not read " <> renderSide side <> ": " <> renderGitError err))
            Right _ -> do
              let projectRoot = normalise (snapshot </> prefix)
              createDirectoryIfMissing True projectRoot
              ignored <- gitIgnoredPaths directory
              mirrorIgnored directory projectRoot ignored
              let git = sideGitProvider (case side of
                    Commit hash -> CommitSide hash top snapshot
                    _ -> IndexSide top snapshot)
              loaded <- loadProjectWith git (Just ignored) projectRoot
              either (pure . Left . renderProjectError') (fmap Right . action projectRoot) loaded
  where
    renderProjectError' :: ProjectError -> Text
    renderProjectError' = renderProjectError

-- | The repository's top level and the directory's path below it.
repositoryOf :: FilePath -> IO (Either Text (FilePath, FilePath))
repositoryOf directory = do
  top <- runGit directory ["rev-parse", "--show-toplevel"]
  prefix <- runGit directory ["rev-parse", "--show-prefix"]
  pure $ case (top, prefix) of
    (Right t, Right p) -> Right (T.unpack (T.strip t), T.unpack (T.strip p))
    (Left err, _) -> Left ("not in a git repository: " <> renderGitError err)
    (_, Left err) -> Left ("not in a git repository: " <> renderGitError err)

-- | What git ignores is not on any side: it is the environment the project is read in, such as a
-- grammar checkout canon.yaml names. The snapshot links each ignored path to the working tree's,
-- and the walk skips them as it skips them there. canon's own cache is not linked, so a snapshot
-- never reads or writes the working tree's.
mirrorIgnored :: FilePath -> FilePath -> Set.Set [Text] -> IO ()
mirrorIgnored directory projectRoot ignored =
  forM_ (Set.toList ignored) $ \segments ->
    unless (take 1 segments == [".canon-cache"] || null segments) $ do
      let relative = joinPath (map T.unpack segments)
      target <- makeAbsolute (directory </> relative)
      let link = projectRoot </> relative
      present <- doesPathExist link
      exists <- doesPathExist target
      unless (present || not exists) $ do
        createDirectoryIfMissing True (takeDirectory link)
        isDirectory <- doesDirectoryExist target
        (if isDirectory then createDirectoryLink else createFileLink) target link

-- | A new directory under the temporary one, named so two checks never share it.
freshDirectory :: FilePath -> IO FilePath
freshDirectory temporary = go (0 :: Int)
  where
    go attempt = do
      stamp <- (round . (* 1000000) <$> getPOSIXTime) :: IO Integer
      let candidate = temporary </> ("canon-snapshot-" ++ show stamp ++ "-" ++ show attempt)
      taken <- doesPathExist candidate
      if taken then go (attempt + 1) else createDirectory candidate >> pure candidate
