-- | A check scoped to a diff reports the findings on the material that changed between two sides
-- of a repository: two commits, a commit and the index or the working tree, or the index and the
-- working tree. git says which paths changed, with renames, and which lines changed on the later
-- side; canon reads both sides in full and keeps a finding when it lies in a changed unit of a
-- changed file, when it is about material whose text or verdict changed, or when the earlier side
-- did not have it, wherever it lies. Files added and renamed are in scope whole. So a change to
-- canon.yaml, the exemptions, the registry, the ledger or a grammar reports the findings it causes
-- in files it did not touch, and a release's version bump reports nothing by itself. The precedents
-- are `git diff --name-status -M`, review tools that report only on changed lines, and lint
-- baselines and SonarQube's new-code period, which report what is new since a reference point.
-- ref:DEC-check-diff-scope ref:DEC-check-sides
module Canon.Diff
  ( PathStatus (..)
  , Diff (..)
  , Scoped (..)
  , Reading (..)
  , diffSides
  , scopedSurvey
  , parseNameStatus
  , parseHunks
  , scopeFindings
  , relocate
  ) where

import Canon.Extract.Grammar (Extraction (..))
import Canon.Git.Provider (renderGitError)
import Canon.Git.Shell (runGit)
import Canon.Model
import Canon.Model.Finding (Finding (..), findingKey, findingLocation, renderFinding)
import Canon.Project
import Canon.Snapshot
import Canon.Span (Position (..), Span (..))
import Canon.Vetting (Material (..))
import Control.Concurrent.Async (concurrently)
import Data.Aeson (Result (..), Value (..), fromJSON, toJSON)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Char (isDigit)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (addTrailingPathSeparator, makeRelative, normalise)

-- | How a path changed. A renamed path is keyed by its new name and remembers its old one.
data PathStatus = Added | Modified | Deleted | Renamed FilePath
  deriving (Eq, Show)

-- | The paths that changed between two sides, relative to the project directory, and the lines
-- that changed on the later side of each modified one.
data Diff = Diff
  { diffPaths :: Map.Map FilePath PathStatus
  , diffLines :: Map.Map FilePath [(Int, Int)]
  }
  deriving (Eq, Show)

-- | The findings a diff keeps, how many it leaves out, how many the earlier side had that the
-- later one does not, and the material the diff bears on: the material whose text or verdict
-- changed or is new, the material a kept finding is about, and the material of files added or
-- renamed. A tool built on canon scopes its own view of the material by that, and by the paths that
-- changed, relative to the project and not deleted.
-- ref:DEC-check-since-release
data Scoped = Scoped
  { scopedFindings :: [Finding]
  , scopedOutside :: Int
  , scopedResolved :: Int
  , scopedTexts :: Map.Map VettingKey Text
  , scopedMaterial :: Set.Set VettingKey
  , scopedPaths :: Set.Set FilePath
  }
  deriving (Eq, Show)

-- | The arguments that make `git diff` compare two sides, earlier first. The working tree is never
-- an object git can name, so a comparison ending at it leaves the later side out, and one
-- starting from it is the reverse of the comparison the other way.
rangeArguments :: Side -> Side -> [String]
rangeArguments base headSide = case (base, headSide) of
  (Commit a, Commit b) -> [T.unpack a, T.unpack b]
  (Commit a, Index) -> ["--cached", T.unpack a]
  (Commit a, WorkTree) -> [T.unpack a]
  (Index, WorkTree) -> []
  (Index, Commit b) -> ["-R", "--cached", T.unpack b]
  (WorkTree, Commit b) -> ["-R", T.unpack b]
  (WorkTree, Index) -> ["-R"]
  _ -> []

-- | What changed between two sides of the repository holding a directory, as paths relative to it.
-- Files git neither tracks nor ignores are on the working tree only, so they are added when the
-- later side is the working tree and deleted when the earlier side is.
diffSides :: FilePath -> Side -> Side -> IO (Either Text Diff)
diffSides directory base headSide
  | base == headSide = pure (Right (Diff Map.empty Map.empty))
  | otherwise = do
      let common = ["-c", "core.quotePath=false", "diff", "--no-ext-diff", "--no-color", "--relative", "-M"]
          range = rangeArguments base headSide
      statuses <- runGit directory (common ++ ["--name-status", "-z"] ++ range ++ ["--"])
      hunks <- runGit directory (common ++ ["--no-prefix", "-U0"] ++ range ++ ["--"])
      untracked <-
        if WorkTree `elem` [base, headSide]
          then runGit directory ["ls-files", "--others", "--exclude-standard", "-z"]
          else pure (Right "")
      pure $ case (statuses, hunks, untracked) of
        (Right s, Right h, Right u) ->
          let fresh = [p | p <- map T.unpack (T.splitOn "\0" u), not (null p)]
              loose = Map.fromList [(p, if headSide == WorkTree then Added else Deleted) | p <- fresh]
           in Right (Diff (Map.union (parseNameStatus s) loose) (parseHunks h))
        (Left err, _, _) -> Left ("git diff failed: " <> renderGitError err)
        (_, Left err, _) -> Left ("git diff failed: " <> renderGitError err)
        (_, _, Left err) -> Left ("git ls-files failed: " <> renderGitError err)

-- | Parses `git diff --name-status -z`: a status, then one path, or two for a rename or copy.
parseNameStatus :: Text -> Map.Map FilePath PathStatus
parseNameStatus = Map.fromList . go . filter (not . T.null) . T.splitOn "\0"
  where
    go fields = case fields of
      (status : rest) -> case T.unpack (T.take 1 status) of
        "R" | (old : new : more) <- rest -> (T.unpack new, Renamed (T.unpack old)) : go more
        "C" | (_ : new : more) <- rest -> (T.unpack new, Added) : go more
        "A" | (path : more) <- rest -> (T.unpack path, Added) : go more
        "D" | (path : more) <- rest -> (T.unpack path, Deleted) : go more
        _ | (path : more) <- rest -> (T.unpack path, Modified) : go more
        _ -> []
      [] -> []

-- | Parses the hunk headers of `git diff -U0 --no-prefix`: the lines each hunk covers on the later
-- side. A hunk that only removes lines covers the line it follows, so the unit it was cut from
-- counts as changed.
parseHunks :: Text -> Map.Map FilePath [(Int, Int)]
parseHunks text = Map.fromListWith (flip (++)) (go Nothing (T.lines text))
  where
    go current lines' = case lines' of
      [] -> []
      (l : rest)
        | Just path <- T.stripPrefix "+++ " l ->
            go (if path == "/dev/null" then Nothing else Just (T.unpack path)) rest
        | "@@ " `T.isPrefixOf` l, Just path <- current, Just range <- newRange l ->
            (path, [range]) : go current rest
        | otherwise -> go current rest
    newRange l = case [w | w <- T.words l, "+" `T.isPrefixOf` w] of
      (w : _) ->
        let (start, count) = T.breakOn "," (T.drop 1 w)
            n = if T.null count then 1 else number (T.drop 1 count)
            s = number start
         in if T.all isDigit start && not (T.null start) then Just (if n == 0 then (max 1 s, max 1 s) else (s, s + n - 1)) else Nothing
      [] -> Nothing
    number t = if T.null t || not (T.all isDigit t) then 0 else read (T.unpack t)

-- | One side read in full: its findings as the check reports them, its material texts, its
-- verdicts, and the spans of the units of each file, all with paths relative to the project.
data Reading = Reading
  { readingFindings :: [Finding]
  , readingTexts :: Map.Map VettingKey Text
  , readingVerdicts :: Map.Map VettingKey Text
  , readingUnits :: Map.Map FilePath [(Int, Int)]
  , readingFiles :: Map.Map VettingKey FilePath
  }

readSide :: FilePath -> Side -> Maybe FilePath -> IO (Either Text Reading)
readSide directory side target = withSideProject directory side $ \root project -> do
  survey <- surveyProject project target
  let relocated = map (relocate root) (surveyReport project survey)
      units =
        Map.fromListWith
          (++)
          [ (relative root (wherePath w), [spanLines (whereSpan w)])
          | (_, Right e) <- surveyExtracted survey
          , u <- modelAllUnits (extractionModel e)
          , let w = answerValue (unitWhere u)
          ]
  pure
    Reading
      { readingFindings = relocated
      , readingTexts = Map.fromList [(materialKey m, materialText m) | m <- surveyMaterials survey]
      , readingVerdicts = Map.map (T.pack . show . assessmentVerdict . answerValue) (surveyAssessments survey)
      , readingUnits = units
      , readingFiles = Map.fromList [(materialKey m, relative root (materialFile m)) | m <- surveyMaterials survey]
      }
  where
    spanLines (Span (Position from _) (Position to _)) = (from, max from to)

-- | Reads both sides and keeps the findings the diff between them bears on. ref:DEC-check-diff-scope
scopedSurvey :: FilePath -> Side -> Side -> Maybe FilePath -> IO (Either Text Scoped)
scopedSurvey directory base headSide target = do
  diffed <- diffSides directory base headSide
  case diffed of
    Left err -> pure (Left err)
    Right diff -> do
      -- The sides share nothing but the cache, which is written whole or not at all, so they are
      -- read at once.
      (before, after) <- concurrently (readSide directory base target) (readSide directory headSide target)
      pure (scopeFindings diff <$> before <*> after)

-- | The findings of the later side a diff bears on. Pure, so the rule is tested without git.
scopeFindings :: Diff -> Reading -> Reading -> Scoped
scopeFindings diff before after =
  Scoped
    { scopedFindings = kept
    , scopedOutside = length (readingFindings after) - length kept
    , scopedResolved = length [f | f <- readingFindings before, renderFinding f `Set.notMember` afterSet]
    , scopedTexts = readingTexts after
    , scopedMaterial =
        changedKeys
          `Set.union` Set.fromList [k | f <- kept, Just k <- [findingKey f]]
          `Set.union` Set.fromList [k | (k, file) <- Map.toList (readingFiles after), wholeChange (normalise file)]
    , scopedPaths = Set.fromList [normalise p | (p, status) <- Map.toList paths, status /= Deleted]
    }
  where
    paths = diffPaths diff
    beforeSet = Set.fromList (map renderFinding (readingFindings before))
    afterSet = Set.fromList (map renderFinding (readingFindings after))
    keys m = Set.fromList (Map.keys m)
    changedKeys =
      Set.fromList
        [ k
        | k <- Set.toList (Set.union (keys (readingTexts before)) (keys (readingTexts after)))
        , Map.lookup k (readingTexts before) /= Map.lookup k (readingTexts after)
        ]
        `Set.union` Set.fromList
          [ k
          | k <- Set.toList (Set.union (keys (readingVerdicts before)) (keys (readingVerdicts after)))
          , Map.lookup k (readingVerdicts before) /= Map.lookup k (readingVerdicts after)
          ]
    -- The lines of a modified file that changed, widened to every unit they touch.
    touched path =
      let hunks = Map.findWithDefault [] path (diffLines diff)
          units = Map.findWithDefault [] path (readingUnits after)
       in hunks ++ [u | u <- units, any (overlaps u) hunks, not (wholeFile u)]
    wholeFile (from, _) = from <= 1
    wholeChange file = case Map.lookup file paths of
      Just Added -> True
      Just (Renamed _) -> True
      _ -> False
    overlaps (a, b) (c, d) = a <= d && c <= b
    kept = filter inScope (readingFindings after)
    new f = renderFinding f `Set.notMember` beforeSet
    inScope f
      | maybe False (`Set.member` changedKeys) (findingKey f) = True
      | new f = True
      | otherwise = case findingLocation f of
          Just (path, lines') -> case Map.lookup (normalise path) paths of
            Just Modified -> maybe True (\r -> any (overlaps r) (touched (normalise path))) lines'
            Just _ -> True
            Nothing -> False
          Nothing -> False

-- | A finding read from a snapshot names the snapshot's paths; it is given the project's, so the
-- two sides' findings compare and print alike.
relocate :: FilePath -> Finding -> Finding
relocate root f = case fromJSON (rewrite (toJSON f)) of
  Success moved -> moved
  Error _ -> f
  where
    rewrite v = case v of
      String s -> String (T.pack (relative root (T.unpack s)))
      Object o -> Object (KeyMap.map rewrite o)
      Array a -> Array (fmap rewrite a)
      _ -> v

relative :: FilePath -> FilePath -> FilePath
relative root path
  | addTrailingPathSeparator (normalise root) `isPrefix` normalise path = makeRelative (normalise root) (normalise path)
  | root == "." || root == "./" = if "./" `isPrefix` path then drop 2 path else path
  | otherwise = path
  where
    isPrefix a b = take (length a) b == a
