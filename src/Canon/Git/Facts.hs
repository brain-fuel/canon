-- | What a check needs from git about the whole repository is asked once per run, in a handful of
-- batched commands, rather than once per file: which paths the side's commit holds, the commit
-- that last changed each path, the first release holding each commit, and the described version.
-- Each answer is then a lookup. Blame and commit messages, the answers that cost a process per file
-- or per commit, are kept in canon's cache under keys made of exactly what decides them, so a
-- commit elsewhere in the repository leaves them valid. The precedents are git's own commit-graph,
-- which numbers commits so reachability is answered without walking history again, and name-rev
-- and describe --contains, which name a commit by the first tag that holds it.
-- ref:DEC-repository-facts ref:DEC-git-runner
module Canon.Git.Facts
  ( Facts (..)
  , Releases
  , repositoryFacts
  , factsProvider
  , bareProvider
  , releaseOf
  , releasesFrom
  , lastChangesFrom
  , factsStamp
  , stampExtraction
  ) where

import Canon.Extract.Grammar (Extraction (..))
import Canon.Git.Commit
import Canon.Git.Provider
import Canon.Git.Shell (GitSide (..), runGit)
import Canon.Model
import Canon.Span (Position (..), Span (..))
import Control.Concurrent (myThreadId)
import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict, encode)
import Data.Char (isDigit)
import Control.Monad.ST (ST, runST)
import Crypto.Hash.SHA256 (hashlazy)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Unboxed.Mutable as MU
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (makeRelative, normalise, (</>))

-- | The first release holding each commit, as arrays indexed by a commit's ordinal: the hashes in
-- the order git listed them, each commit's release as an index into the tag names or -1 for none,
-- and a map from hash to ordinal. Built once; every question is a lookup.
data Releases = Releases
  { releaseOrdinals :: Map.Map Text Int
  , releaseMarks :: U.Vector Int
  , releaseNames :: V.Vector Text
  }

-- | One side of the repository as a check reads it: the directory that stands for the repository's
-- top level (the working tree's own, or a snapshot's), which paths the side's commit holds, the
-- commit that last changed each, the releases, the described version, and the side's name for
-- cache keys.
data Facts = Facts
  { factsRoot :: FilePath
  , factsHeld :: Set.Set FilePath
  , factsLastChange :: Map.Map FilePath Text
  , factsReleases :: Releases
  , factsDescribe :: Maybe Text
  }

-- | Reads the facts of one side. A repository with no commit holds nothing and has no history; git
-- missing is the one error, since nothing else can be answered without it.
repositoryFacts :: FilePath -> GitSide -> IO (Either GitError Facts)
repositoryFacts directory side = do
  located <- case side of
    WorkTreeSide -> fmap (\t -> (T.unpack (T.strip t), T.unpack (T.strip t), "HEAD")) <$> runGit directory ["rev-parse", "--show-toplevel"]
    IndexSide top snapshot -> pure (Right (top, snapshot, "HEAD"))
    CommitSide hash top snapshot -> pure (Right (top, snapshot, T.unpack hash))
  case located of
    Left err -> pure (Left err)
    Right (top, root, revision) -> do
      held <- runGit top ["ls-tree", "-r", "--name-only", "-z", "--full-tree", revision]
      changes <- runGit top ["log", "--format=%x01%H", "-z", "--name-only", "--no-renames", revision]
      tags <- runGit top ["for-each-ref", "--sort=v:refname", "--format=%(objecttype) %(objectname) %(*objecttype) %(*objectname) %(refname:lstrip=2)", "refs/tags"]
      graph <- runGit top ["rev-list", "--parents", "--tags"]
      described <- runGit top (["describe", "--tags", "--always"] ++ if revision == "HEAD" then ["--dirty"] else [revision])
      canonicalRoot <- canonicalizePath root
      pure $ case (held, described) of
        (Left GitNotFound, _) -> Left GitNotFound
        (_, Left GitNotFound) -> Left GitNotFound
        _ ->
          Right
            Facts
              { factsRoot = canonicalRoot
              , factsHeld = either (const Set.empty) (Set.fromList . map T.unpack . filter (not . T.null) . T.splitOn "\0") held
              , factsLastChange = either (const Map.empty) lastChangesFrom changes
              , factsReleases = releasesFrom (either (const "") id tags) (either (const "") id graph)
              , factsDescribe = either (const Nothing) (\t -> let s = T.strip t in if T.null s then Nothing else Just s) described
              }

-- | Parses `git log --format=%x01%H -z --name-only`, newest first, into the commit that last
-- changed each path: the first one that names it.
lastChangesFrom :: Text -> Map.Map FilePath Text
lastChangesFrom = snd . foldl' step ("", Map.empty) . T.splitOn "\0"
  where
    step (current, acc) field =
      let token = T.dropWhile (== '\n') field
       in case T.uncons token of
            Just ('\1', hash) -> (hash, acc)
            Just _ -> (current, Map.insertWith (\_ old -> old) (T.unpack token) current acc)
            Nothing -> (current, acc)

-- | The first release holding each commit, from the tags in git's version order and the parents of
-- every commit a tag reaches. Tags are taken oldest first, and each marks the commits it reaches
-- that no earlier tag did; a commit an earlier tag marked has every ancestor marked already, so the
-- walk stops there and the whole graph is walked once. The first tag to mark a commit is the first
-- in version order that holds it, which is what `git tag --contains --sort=v:refname` lists first.
releasesFrom :: Text -> Text -> Releases
releasesFrom tagText graphText = Releases ordinals marks (V.fromList (map snd tags))
  where
    -- Each line is the tag's object type and name, the type and name it peels to (empty for a
    -- lightweight tag), and the tag's name, which holds no space; fields are split on single spaces
    -- so the empty ones keep their place.
    tags =
      [ (commit, name)
      | line <- T.lines tagText
      , (kind : object : peeledKind : peeledObject : name : _) <- [T.splitOn " " line]
      , Just commit <- [peeled kind object peeledKind peeledObject]
      , not (T.null name)
      ]
    peeled kind object peeledKind peeledObject
      | kind == "commit" = Just object
      | peeledKind == "commit" = Just peeledObject
      | otherwise = Nothing
    rows = [(hash, parents) | line <- T.lines graphText, (hash : parents) <- [T.words line]]
    hashes = V.fromList (map fst rows)
    ordinals = Map.fromList (zip (V.toList hashes) [0 ..])
    -- Parents as compressed rows: the parents of commit i are targets[offsets[i] .. offsets[i+1]).
    parentOrdinals = [[o | p <- parents, Just o <- [Map.lookup p ordinals]] | (_, parents) <- rows]
    offsets = U.fromList (scanl (+) 0 (map length parentOrdinals))
    targets = U.fromList (concat parentOrdinals)
    marks = runST $ do
      mark <- MU.replicate (V.length hashes) (-1)
      forM_ (zip [0 ..] tags) $ \(tagIndex, (commit, _)) ->
        case Map.lookup commit ordinals of
          Nothing -> pure ()
          Just start -> walk mark tagIndex [start]
      U.freeze mark
    walk :: MU.MVector s Int -> Int -> [Int] -> ST s ()
    walk mark tagIndex stack = case stack of
      [] -> pure ()
      (n : rest) -> do
        current <- MU.read mark n
        if current /= -1
          then walk mark tagIndex rest
          else do
            MU.write mark n tagIndex
            let from = offsets U.! n
                to = offsets U.! (n + 1)
            walk mark tagIndex ([targets U.! i | i <- [from .. to - 1]] ++ rest)

-- | The first release that holds a commit, if any does.
releaseOf :: Releases -> CommitHash -> Maybe Text
releaseOf releases (CommitHash hash) = do
  ordinal <- Map.lookup hash (releaseOrdinals releases)
  let mark = releaseMarks releases U.! ordinal
  if mark < 0 then Nothing else releaseNames releases V.!? mark

-- | A path as the side's commit names it, from the directory files are read from.
relativeTo :: Facts -> FilePath -> IO FilePath
relativeTo facts path = do
  absolute <- canonicalizePath path
  pure (normalise (makeRelative (factsRoot facts) absolute))

-- | What decides a file's blame, besides its content: whether the side's commit holds it, and the
-- commit that last changed it there, which fixes every commit its lines can be blamed on.
factsStamp :: Facts -> FilePath -> IO LBS.ByteString
factsStamp facts path = do
  relative <- relativeTo facts path
  let held = Set.member relative (factsHeld facts)
      changed = Map.findWithDefault "" relative (factsLastChange facts)
  pure (LBS.fromStrict (TE.encodeUtf8 (T.concat [T.pack relative, "\0", if held then "held" else "new", "\0", changed])))

-- | A provider for one side whose repository-wide answers come from the facts, and whose blames
-- and commit messages are kept in the cache under the project directory. Whether a file is held
-- and which release holds a commit cost no process; a blame costs one only the first time its
-- file, content, and history are seen; a message, once per commit ever.
factsProvider :: FilePath -> Facts -> GitProvider -> GitProvider
factsProvider cacheRoot facts inner =
  inner
    { committedIn = \path -> Right . (`Set.member` factsHeld facts) <$> relativeTo facts path
    , blameOf = \path sp -> do
        content <- try (LBS.readFile path)
        case content of
          Left (_ :: IOException) -> blameOf inner path sp
          Right bytes -> do
            stamp <- factsStamp facts path
            let Span (Position from _) (Position to _) = sp
                key = entryKey "blame-1" [stamp, LBS.fromStrict (TE.encodeUtf8 (T.pack (show (from, max from to)))), bytes]
            remembered cacheRoot key (blameOf inner path sp)
    , tagsContaining = \hash -> pure (Right (maybe [] pure (releaseOf (factsReleases facts) hash)))
    , describeVersion = pure (Right (factsDescribe facts))
    , messageOf = \hash -> remembered cacheRoot (entryKey "message-1" [LBS.fromStrict (TE.encodeUtf8 (commitHashText hash))]) (messageOf inner hash)
    }

-- | The provider extraction runs under before its result is cached: no described version and no
-- release, the two answers that change with every commit or tag anywhere in the repository. They
-- are stamped on afterwards, so a cached model stays valid until its own file or history changes.
bareProvider :: GitProvider -> GitProvider
bareProvider provider =
  provider
    { tagsContaining = \_ -> pure (Right [])
    , describeVersion = pure (Right Nothing)
    }

-- | Puts the side's described version on a model, and on every unit's When the first release that
-- holds the commit that introduced it.
stampExtraction :: Facts -> Extraction -> Extraction
stampExtraction facts (Extraction model findings) =
  Extraction model {modelDescribe = factsDescribe facts, modelUnits = map unit (modelUnits model)} findings
  where
    unit u = u {unitWhen = (\(Answer w ev) -> Answer (introduced w) ev) <$> unitWhen u, unitChildren = map unit (unitChildren u)}
    introduced w = w {whenIntroducedIn = releaseOf (factsReleases facts) (changeCommit (whenFirst w))}

entryKey :: Text -> [LBS.ByteString] -> FilePath
entryKey kind parts =
  T.unpack kind ++ "-" ++ T.unpack (TE.decodeUtf8 (Base16.encode (hashlazy (LBS.concat (concatMap (\p -> [LBS.fromStrict (TE.encodeUtf8 (T.pack (show (LBS.length p)))), ":", p]) parts)))))

-- | A git answer kept in the cache: read back when present, otherwise asked and written whole
-- under a temporary name and renamed, so a concurrent reader sees all of it or none. Errors are
-- not kept.
remembered :: (ToJSON a, FromJSON a) => FilePath -> FilePath -> IO (Either GitError a) -> IO (Either GitError a)
remembered cacheRoot name ask = do
  let directory = cacheRoot </> ".canon-cache"
      path = directory </> (name ++ ".json")
  present <- doesFileExist path
  stored <- if present then either (\(_ :: IOException) -> Nothing) Just <$> try (BS.readFile path) else pure Nothing
  case stored >>= either (const Nothing) Just . eitherDecodeStrict of
    Just value -> pure (Right value)
    Nothing -> do
      answer <- ask
      case answer of
        Right value -> do
          createDirectoryIfMissing True directory
          -- The thread and the clock name the partial file, so two writers, in one run or two, never
          -- write into the same one.
          writer <- myThreadId
          stamp <- (round . (* 1000000000) <$> getPOSIXTime) :: IO Integer
          let partial = path ++ "." ++ filter isDigit (show writer) ++ "-" ++ show stamp ++ ".partial"
          -- A cache that cannot be written is only slower; the answer stands either way.
          _ <- try (LBS.writeFile partial (encode value) >> renameFile partial path) :: IO (Either IOException ())
          pure (Right value)
        Left err -> pure (Left err)
