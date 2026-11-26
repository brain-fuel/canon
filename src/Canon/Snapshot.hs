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
  , resolveSideNamed
  , withSideProject
  ) where

import Canon.Git.Provider (renderGitError)
import Canon.Git.Shell (GitSide (..), gitIgnoredPaths, runGit)
import Canon.Config (defaultReleases)
import Canon.Project (Project (..), ProjectError, loadProjectWith, renderProjectError)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (IOException, bracket, try)
import System.IO.Unsafe (unsafePerformIO)
import Control.Monad (forM, forM_, unless)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Char8 as BS8
import Data.List (isPrefixOf, sortBy)
import Data.Containers.ListUtils (nubOrd)
import Data.Ord (Down (..), comparing)
import Data.Time.Clock (diffUTCTime, getCurrentTime, nominalDay)
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
  , doesFileExist
  , doesPathExist
  , getModificationTime
  , getTemporaryDirectory
  , listDirectory
  , makeAbsolute
  , removeDirectoryRecursive
  , renameDirectory
  )
import System.FilePath (joinPath, normalise, takeDirectory, (</>))

-- | A side as the user names it: `:worktree`, `:index`, `:release` for the newest release HEAD
-- holds, or any revision git can resolve to a commit. ref:DEC-check-since-release
data SideSpec = SpecWorkTree | SpecIndex | SpecRelease | SpecRevision Text
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
  ":release" -> SpecRelease
  _ -> SpecRevision t

-- | A resolved side as the user would write it.
renderSide :: Side -> Text
renderSide side = case side of
  WorkTree -> ":worktree"
  Index -> ":index"
  Commit hash -> T.take 12 hash

-- | Resolves a side in the repository holding a directory, the last release by the default tag
-- pattern.
resolveSide :: FilePath -> SideSpec -> IO (Either Text Side)
resolveSide directory = fmap (fmap snd) . resolveSideNamed defaultReleases directory

-- | Resolves a side, with the name to show for it: the tag for the last release, which is the
-- newest tag matching the project's release pattern that HEAD holds, as `git describe --abbrev=0`
-- finds it. With no such tag there is no last release, and the check says so rather than guess.
-- ref:DEC-check-since-release
resolveSideNamed :: Text -> FilePath -> SideSpec -> IO (Either Text (Text, Side))
resolveSideNamed releases directory spec = case spec of
  SpecRelease -> do
    found <- runGit directory ["describe", "--tags", "--abbrev=0", "--match", T.unpack releases, "HEAD"]
    case fmap T.strip found of
      Right tag | not (T.null tag) -> fmap (\side -> (tag <> " (" <> renderSide side <> ")", side)) <$> resolveSide directory (SpecRevision ("refs/tags/" <> tag))
      _ -> pure (Left ("no tag matching " <> releases <> " is reachable from HEAD, so there is no last release to check against; pass --base <revision>, or --all to check every file"))
  _ -> fmap (\side -> (renderSide side, side)) <$> resolveSpec directory spec

resolveSpec :: FilePath -> SideSpec -> IO (Either Text Side)
resolveSpec directory spec = case spec of
  SpecWorkTree -> pure (Right WorkTree)
  SpecIndex -> pure (Right Index)
  SpecRelease -> resolveSide directory SpecRelease
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
    loaded <- loadProjectWith WorkTreeSide Nothing directory
    either (pure . Left . renderProjectError) (fmap Right . action directory) loaded
  _ -> do
    located <- repositoryOf directory
    case located of
      Left err -> pure (Left err)
      Right (top, prefix) -> do
        temporary <- getTemporaryDirectory
        let readFrom snapshot = do
              let projectRoot = normalise (snapshot </> prefix)
              createDirectoryIfMissing True projectRoot
              ignored <- gitIgnoredPaths directory
              mirrorIgnored directory projectRoot ignored
              let gitSide = case side of
                    Commit hash -> CommitSide hash top snapshot
                    _ -> IndexSide top snapshot
              cache <- makeAbsolute directory
              loaded <- fmap (\p -> p {projectCache = cache}) <$> loadProjectWith gitSide (Just ignored) projectRoot
              either (pure . Left . renderProjectError') (fmap Right . action projectRoot) loaded
        case side of
          -- A commit never changes, so its snapshot is written once and kept for a later check
          -- against the same commit; the cache it reads and fills is the working project's.
          Commit hash -> do
            kept <- keptSnapshot temporary top hash
            either (pure . Left) readFrom kept
          _ ->
            bracket (freshDirectory temporary) removeDirectoryRecursive $ \snapshot -> do
              restored <- restoreInto top snapshot []
              either (pure . Left) (const (readFrom snapshot)) restored
  where
    restoreInto top snapshot source = withMVar restoring $ \() -> do
      restored <- runGit top (["--work-tree=" ++ snapshot, "restore"] ++ source ++ ["--worktree", "--", ":/"])
      pure (either (\err -> Left ("could not read " <> renderSide side <> ": " <> renderGitError err)) (const (Right ())) restored)
    -- The kept snapshot of a commit: reused when complete, otherwise written under a name of its
    -- own and renamed into place, so a check that stops halfway or runs beside another never
    -- leaves a partial one to be read. The least recently used beyond the newest few are removed.
    keptSnapshot temporary top hash = do
      let sides = temporary </> "canon-sides"
          name = repositoryKey top ++ "-" ++ T.unpack hash
          final = sides </> name
          complete = final </> ".canon-snapshot-complete"
      createDirectoryIfMissing True sides
      ready <- doesFileExist complete
      if ready
        then do
          touch complete
          pure (Right final)
        else do
          partial <- freshDirectory sides
          restored <- restoreInto top partial ["--source=" ++ T.unpack hash]
          case restored of
            Left err -> removeDirectoryRecursive partial >> pure (Left err)
            Right () -> do
              writeFile (partial </> ".canon-snapshot-complete") ""
              moved <- try (renameDirectory partial final) :: IO (Either IOException ())
              -- Another check may have kept the same commit first; its snapshot is as good.
              either (const (removeDirectoryRecursive partial)) pure moved
              pruneKept sides (repositoryKey top)
              pure (Right final)
    touch path = writeFile path ""
    renderProjectError' :: ProjectError -> Text
    renderProjectError' = renderProjectError

-- | Held while git writes a snapshot. `git restore` takes the repository's index lock even when it
-- writes only another work tree, so the two sides of a diff, read at once, write their snapshots
-- one after the other. It is the one lock canon holds, and it guards nothing but that call.
restoring :: MVar ()
restoring = unsafePerformIO (newMVar ())
{-# NOINLINE restoring #-}

-- | A short key for a repository, so kept snapshots of different repositories never share a name.
repositoryKey :: FilePath -> String
repositoryKey top = take 16 (BS8.unpack (Base16.encode (SHA256.hash (BS8.pack top))))

-- | Keeps the newest few snapshots of a repository, by when each was last read, and removes the
-- rest, so the kept snapshots of old commits do not pile up. Snapshots of any repository unread
-- for a week, and all beyond the newest few dozen, are removed too, since a repository deleted or
-- moved leaves its snapshots behind with no check of it to prune them.
pruneKept :: FilePath -> String -> IO ()
pruneKept sides key = do
  names <- listDirectory sides
  dated <- fmap concat $ forM names $ \n -> do
    let marker = sides </> n </> ".canon-snapshot-complete"
    present <- doesFileExist marker
    if present then (\t -> [(t, n)]) <$> getModificationTime marker else pure []
  now <- getCurrentTime
  let newest = sortBy (comparing (Down . fst)) dated
      own = [d | d@(_, n) <- newest, (key ++ "-") `isPrefixOf` n]
      stale =
        drop keptSnapshots own
          ++ drop keptAcrossRepositories newest
          ++ [d | d@(t, _) <- newest, diffUTCTime now t > 7 * nominalDay]
  forM_ (nubOrd (map snd stale)) $ \n -> try (removeDirectoryRecursive (sides </> n)) :: IO (Either IOException ())

-- | How many kept snapshots a repository keeps: the last release and a few other bases.
keptSnapshots :: Int
keptSnapshots = 4

-- | How many kept snapshots there are at most, of every repository together.
keptAcrossRepositories :: Int
keptAcrossRepositories = 32

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
