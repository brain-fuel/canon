-- | A check tells the truth in any state of the repository, and a check scoped to a diff reports
-- what changed between two sides of it, with files added, deleted and renamed. Each test builds a
-- small repository in a scratch directory and asks git for real, since the rules are about what git
-- answers. ref:DEC-uncommitted-provenance ref:DEC-check-sides ref:DEC-check-diff-scope
module Canon.DiffTest (tests) where

import Canon.Diff
import Canon.Extract.Grammar (Extraction (..))
import Canon.Git.Commit (BlameLine (..), CommitHash (..), Person (..))
import Canon.Git.Fill (fillGitFromBlame)
import Canon.Git.Provider (GitError, GitProvider (..), staticGitProvider)
import Canon.Model
import Canon.Git.Shell (runGit)
import Canon.Model.Finding (Finding (..), findingLocation)
import Canon.Project
import Canon.Scratch (withScratch)
import Canon.Snapshot
import Canon.Span (Position (..), Span (..))
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Control.Monad (when)
import Data.List (sort)
import Hedgehog (Gen, Property, annotateShow, assert, evalIO, failure, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getCurrentDirectory, removeDirectoryRecursive, removeFile)
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "diff"
    [ -- These run at once. On GHC 9.10.3 that wedged the runtime about one run in six on an
      -- 18-core machine: threads blocked on a black hole (the shared TMPDIR string) were never
      -- woken, GHC #26324, fixed in 9.14.1. ref:DEC-ghc-9-14
      testGroup "repositories" repositories
    , testProperty "a line blame marks as not committed is never an author" zeroHashNeverAuthors
    , testProperty "name-status output with renames, copies, additions and deletions parses" nameStatus
    , testProperty "hunk headers give the changed lines of the later side" hunkHeaders
    ]

repositories :: [TestTree]
repositories =
  [ testProperty "an untracked file is checked, and its material is uncommitted rather than a failure" untrackedFile
  , testProperty "a staged new file is uncommitted, not a failure" stagedNewFile
  , testProperty "uncommitted lines of a tracked file are reported and never authored" uncommittedLines
  , testProperty "a deleted file's verdicts are orphans in the diff" deletedFile
  , testProperty "a renamed file is in the diff whole, and its old verdicts are orphans" renamedFile
  , testProperty "a diff between two commits reads only those commits" betweenCommits
  , testProperty "a staged check sees what is staged and not the edit on top of it" stagedOnly
  , testProperty "an unstaged check sees the edit and not what is already staged" unstagedOnly
  , testProperty "a changed canon.yaml reports the findings it causes, and a version bump none" configChanged
  , testProperty "a cached model carries the releases and described version git gives now" releasesStamped
  , testProperty "a scoped check finds the same with a cold cache, one the working tree filled, and a warm one" sharedCacheChangesNothing
  ]

-- A Java project with the canonically commented grammar, so its units have canonical comments.
setUp :: FilePath -> IO ()
setUp root = do
  here <- getCurrentDirectory
  let grammar name = here </> "grammars/java/canonically_commented" </> name
  createDirectoryIfMissing True (root </> "src")
  writeFile
    (root </> "canon.yaml")
    (unlines ["version: 0.1.0", "languages:", "  java:", "    extensions: [.java]", "    lexer: " ++ grammar "JavaLexer.g4", "    parser: " ++ grammar "JavaParser.g4", "    start: compilationUnit"])
  _ <- git root ["init", "--quiet", "--initial-branch=main"]
  pure ()

-- | A class with one documented method.
javaClass :: String -> String -> String
javaClass name why = unlines ["package p;", "/** The " ++ name ++ " class. */", "public class " ++ name ++ " {", "  /** " ++ why ++ " */", "  public void m() {}", "}"]

git :: FilePath -> [String] -> IO (Either GitError Text)
git root arguments =
  runGit root (["-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] ++ arguments)

commitAll :: FilePath -> String -> IO ()
commitAll root message = do
  _ <- git root ["add", "--all"]
  _ <- git root ["commit", "--quiet", "--no-verify", "-m", message]
  pure ()

ingest :: FilePath -> IO ()
ingest root = do
  loaded <- loadProject root
  either (const (pure ())) (\p -> ingestProject p >> pure ()) loaded

check :: FilePath -> IO [Finding]
check root = loadProject root >>= either (const (pure [])) (`checkProject` Nothing)

scoped :: FilePath -> SideSpec -> SideSpec -> IO (Either Text Scoped)
scoped root base later = do
  b <- resolveSide root base
  h <- resolveSide root later
  case (b, h) of
    (Right b', Right h') -> scopedSurvey root b' h' Nothing
    (Left err, _) -> pure (Left err)
    (_, Left err) -> pure (Left err)

pathsOf :: [Finding] -> [FilePath]
pathsOf = mapMaybe (fmap fst . findingLocation)

gitFailures :: [Finding] -> [Finding]
gitFailures fs = [f | f@GitUnavailable {} <- fs]

untrackedFile :: Property
untrackedFile = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-untracked" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    check root
  annotateShow found
  gitFailures found === []
  [() | UncommittedFile p <- found, "src/B.java" `T.isSuffixOf` T.pack p] === [()]
  [() | UncommittedFile _ <- found] === [()]

stagedNewFile :: Property
stagedNewFile = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-staged-new" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    _ <- git root ["add", "src/B.java"]
    check root
  annotateShow found
  gitFailures found === []
  length [() | UncommittedFile p <- found, "src/B.java" `T.isSuffixOf` T.pack p] === 1

uncommittedLines :: Property
uncommittedLines = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-lines" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    writeFile (root </> "src/A.java") (javaClass "A" "Does a, and now more.")
    check root
  annotateShow found
  gitFailures found === []
  [n | UncommittedLines p n <- found, "src/A.java" `T.isSuffixOf` T.pack p] === [1]
  [() | UncommittedFile _ <- found] === []

deletedFile :: Property
deletedFile = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-deleted" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    removeFile (root </> "src/B.java")
    scoped root (SpecRevision "HEAD") SpecWorkTree
  case found of
    Left err -> annotateShow err >> failure
    Right s -> do
      annotateShow s
      let orphans = [k | VerdictOrphan k <- scopedFindings s]
      (not (null orphans), all (T.isInfixOf "\"B.java\"" . T.pack . show) orphans) === (True, True)
      [p | p <- pathsOf (scopedFindings s), "A.java" `T.isSuffixOf` T.pack p] === []

renamedFile :: Property
renamedFile = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-renamed" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    _ <- git root ["mv", "src/B.java", "src/C.java"]
    scoped root (SpecRevision "HEAD") SpecIndex
  case found of
    Left err -> annotateShow err >> failure
    Right s -> do
      annotateShow s
      let fs = scopedFindings s
      (not (null [k | VerdictOrphan k <- fs]), any (T.isSuffixOf "src/C.java" . T.pack) (pathsOf fs)) === (True, True)
      [p | p <- pathsOf fs, "A.java" `T.isSuffixOf` T.pack p] === []

betweenCommits :: Property
betweenCommits = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-commits" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    commitAll root "two"
    -- The working tree moves on; a diff between the commits must not see it.
    writeFile (root </> "src/D.java") (javaClass "D" "Does d.")
    writeFile (root </> "src/A.java") (javaClass "A" "Does a, differently.")
    scoped root (SpecRevision "HEAD~1") (SpecRevision "HEAD")
  case found of
    Left err -> annotateShow err >> failure
    Right s -> do
      annotateShow s
      let ps = pathsOf (scopedFindings s)
      (any (T.isSuffixOf "src/B.java" . T.pack) ps, any (\p -> any (`T.isSuffixOf` T.pack p) ["src/A.java", "src/D.java"]) ps) === (True, False)
      [() | UncommittedFile _ <- scopedFindings s] === []
      [() | UncommittedLines _ _ <- scopedFindings s] === []
      -- The material in scope is B's, the file the second commit added, and none of A's or D's.
      let material = map (T.pack . show) (Set.toList (scopedMaterial s))
      assert (any (T.isInfixOf "\"B.java\"") material)
      assert (not (any (\k -> T.isInfixOf "\"A.java\"" k || T.isInfixOf "\"D.java\"" k) material))

stagedOnly :: Property
stagedOnly = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-staged" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    _ <- git root ["add", "src/B.java"]
    writeFile (root </> "src/D.java") (javaClass "D" "Does d.")
    scoped root (SpecRevision "HEAD") SpecIndex
  case found of
    Left err -> annotateShow err >> failure
    Right s -> do
      annotateShow s
      let ps = pathsOf (scopedFindings s)
      (any (T.isSuffixOf "src/B.java" . T.pack) ps, any (T.isSuffixOf "src/D.java" . T.pack) ps) === (True, False)

unstagedOnly :: Property
unstagedOnly = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-unstaged" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    _ <- git root ["add", "src/B.java"]
    writeFile (root </> "src/D.java") (javaClass "D" "Does d.")
    scoped root SpecIndex SpecWorkTree
  case found of
    Left err -> annotateShow err >> failure
    Right s -> do
      annotateShow s
      let ps = pathsOf (scopedFindings s)
      (any (T.isSuffixOf "src/B.java" . T.pack) ps, any (T.isSuffixOf "src/D.java" . T.pack) ps) === (False, True)

configChanged :: Property
configChanged = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-config" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    commitAll root "one"
    ingest root
    commitAll root "vetting"
    -- A release bumps the version and nothing else, so it causes no finding.
    config <- readFile (root </> "canon.yaml")
    length config `seq` writeFile (root </> "canon.yaml") (unlines (map (\l -> if l == "version: 0.1.0" then "version: 0.2.0" else l) (lines config)))
    full <- check root
    bumped <- scoped root (SpecRevision "HEAD") SpecWorkTree
    -- Ignoring a file resolves its findings and orphans its verdicts, which it caused.
    appendFile (root </> "canon.yaml") "ignore: [src/B.java]\n"
    ignored <- scoped root (SpecRevision "HEAD") SpecWorkTree
    pure (full, bumped, ignored)
  case found of
    (full, Right bumped, Right ignored) -> do
      annotateShow (bumped, ignored)
      assert (not (null full))
      (scopedFindings bumped, scopedOutside bumped) === ([], length full)
      [() | VerdictOrphan _ <- scopedFindings ignored] === [(), ()]
      length (scopedFindings ignored) === 2
      assert (scopedResolved ignored > 0)
    (_, b, i) -> annotateShow (b, i) >> failure

nameStatus :: Property
nameStatus = withTests 1 $ property $ do
  let out = T.intercalate "\0" ["M", "a.hs", "R087", "old.hs", "new.hs", "A", "b.hs", "D", "c.hs", "C100", "x.hs", "y.hs", "T", "l.hs", ""]
  parseNameStatus out
    === Map.fromList [("a.hs", Modified), ("new.hs", Renamed "old.hs"), ("b.hs", Added), ("c.hs", Deleted), ("y.hs", Added), ("l.hs", Modified)]

hunkHeaders :: Property
hunkHeaders = withTests 1 $ property $ do
  let out =
        T.unlines
          [ "diff --git a.hs a.hs"
          , "--- a.hs"
          , "+++ a.hs"
          , "@@ -3 +3 @@ f"
          , "@@ -10,0 +11,4 @@"
          , "@@ -20,2 +24,0 @@"
          , "diff --git gone.hs gone.hs"
          , "--- gone.hs"
          , "+++ /dev/null"
          , "@@ -1,3 +0,0 @@"
          ]
  parseHunks out === Map.fromList [("a.hs", [(3, 3), (11, 14), (24, 24)])]

-- | Blame gives a line not yet committed the all-zero hash and the author "Not Committed Yet". Such a
-- line is no commit: a unit made only of them has no Who or When, and a unit that mixes them with
-- committed lines takes its Who from the committed ones alone. ref:DEC-uncommitted-provenance
zeroHashNeverAuthors :: Property
zeroHashNeverAuthors = withTests 1 $ property $ do
  let at seconds = posixSecondsToUTCTime (fromInteger seconds)
      alice = Person "Alice" "alice@example.invalid"
      nobody = Person "Not Committed Yet" "not.committed.yet"
      line n hash who = BlameLine (CommitHash hash) n who (at 1000) who (at 1000) "s" "x"
      zero = T.replicate 40 "0"
      blamed = [line 1 "abc1" alice, line 2 zero nobody, line 3 zero nobody]
      provider = (staticGitProvider []) {blameOf = \_ _ -> pure (Right blamed)}
      evidence = DerivedFromParse "a.x"
      unit name from to children =
        CodeUnit
          (UnitId ("x" :| ["a.x", name]))
          (Answer (What name (UnitKind "function") Nothing) evidence)
          (Answer (HowAt (Span (Position from 1) (Position to 1))) evidence)
          (Answer (Where "a.x" (Span (Position from 1) (Position to 1)) [] Nothing) evidence)
          Nothing
          Nothing
          Optional
          False
          children
      root = unit "file" 1 3 [unit "mixed" 1 2 [], unit "fresh" 3 3 []]
  (filled, findings) <- evalIO (fillGitFromBlame provider "a.x" root)
  annotateShow filled
  findings === [UncommittedLines "a.x" 2]
  case unitChildren filled of
    [mixed, fresh] -> do
      (unitWho fresh, unitWhen fresh) === (Nothing, Nothing)
      (fmap (T.isInfixOf "Not Committed Yet" . T.pack . show) (unitWho mixed)) === Just False
    _ -> failure

-- | A model read from the cache is stamped with the side as it stands, so a tag made after the
-- entry was written still names the release that introduced a unit, and the described version is
-- git's. Lightweight and annotated tags both count. ref:DEC-repository-facts
releasesStamped :: Property
releasesStamped = withTests 1 $ property $ do
  found <- evalIO $ withScratch "diff-releases" $ \root -> do
    setUp root
    writeFile (root </> "src/A.java") (javaClass "A" "Does a.")
    commitAll root "one"
    _ <- git root ["tag", "v0.1.0"]
    writeFile (root </> "src/B.java") (javaClass "B" "Does b.")
    commitAll root "two"
    _ <- git root ["tag", "-a", "-m", "second", "v0.2.0"]
    writeFile (root </> "src/C.java") (javaClass "C" "Does c.")
    commitAll root "three"
    before <- stamps root
    _ <- git root ["tag", "v0.3.0"]
    after <- stamps root
    described <- git root ["describe", "--tags", "--always", "--dirty"]
    pure (before, after, either (const Nothing) (Just . T.strip) described)
  annotateShow found
  let (before, after, described) = found
  before === [("A", Just "v0.1.0", Just "v0.2.0-1-g"), ("B", Just "v0.2.0", Just "v0.2.0-1-g"), ("C", Nothing, Just "v0.2.0-1-g")]
  after === [("A", Just "v0.1.0", Just "v0.3.0"), ("B", Just "v0.2.0", Just "v0.3.0"), ("C", Just "v0.3.0", Just "v0.3.0")]
  described === Just "v0.3.0"
  where
    stamps root = do
      loaded <- loadProject root
      case loaded of
        Left _ -> pure []
        Right project -> do
          survey <- surveyProject project Nothing
          pure
            [ (T.unpack (T.takeWhile (/= '.') (T.pack (reverse (takeWhile (/= '/') (reverse path))))), release, fmap (T.take (T.length "v0.2.0-1-g")) (modelDescribe model))
            | (path, Right (Extraction model _)) <- surveyExtracted survey
            , let release = case [w | u <- modelAllUnits model, Just (Answer w _) <- [unitWhen u]] of
                    (w : _) -> whenIntroducedIn w
                    [] -> Nothing
            ]

-- | One edit in a random history: a file written with one of a few texts, or deleted.
data Edit = Write Int Int | Delete Int
  deriving (Show)

genEdits :: Gen [Edit]
genEdits = Gen.list (Range.linear 1 4) (Gen.choice [Write <$> Gen.int (Range.linear 0 3) <*> Gen.int (Range.linear 0 2), Delete <$> Gen.int (Range.linear 0 3)])

applyEdit :: FilePath -> Edit -> IO ()
applyEdit root e = case e of
  Write file text -> writeFile (root </> "src" </> (name file ++ ".java")) (javaClass (name file) (["Does a.", "Does b.", "Does c."] !! text))
  Delete file -> do
    present <- doesFileExist (root </> "src" </> (name file ++ ".java"))
    when present (removeFile (root </> "src" </> (name file ++ ".java")))
  where
    name i = ["A", "B", "C", "D"] !! i

-- | Every side reads and writes one cache, each entry under paths from the project root, so a
-- scoped check over a random history must find the same whether the cache starts empty, holds
-- only what the working tree's check wrote, or holds everything. ref:DEC-extraction-cache
sharedCacheChangesNothing :: Property
sharedCacheChangesNothing = withTests 4 $ property $ do
  released <- forAll genEdits
  later <- forAll genEdits
  edited <- forAll genEdits
  bump <- forAll Gen.bool
  found <- evalIO $ withScratch "diff-shared-cache" $ \root -> do
    setUp root
    mapM_ (applyEdit root) (Write 0 0 : released)
    commitAll root "release"
    ingest root
    commitAll root "vetting"
    _ <- git root ["tag", "v0.1.0"]
    mapM_ (applyEdit root) later
    when bump $ do
      config <- readFile (root </> "canon.yaml")
      length config `seq` writeFile (root </> "canon.yaml") (unlines (map (\l -> if l == "version: 0.1.0" then "version: 0.2.0" else l) (lines config)))
    commitAll root "later"
    mapM_ (applyEdit root) edited
    let cache = root </> ".canon-cache"
        clear = doesDirectoryExist cache >>= \present -> when present (removeDirectoryRecursive cache)
        summary = fmap (\s -> (sort (map show (scopedFindings s)), scopedOutside s, scopedResolved s))
    clear
    cold <- summary <$> scoped root SpecRelease SpecWorkTree
    clear
    _ <- check root
    filled <- summary <$> scoped root SpecRelease SpecWorkTree
    warm <- summary <$> scoped root SpecRelease SpecWorkTree
    pure (cold, filled, warm)
  annotateShow found
  let (cold, filled, warm) = found
  assert (either (const False) (const True) cold)
  filled === cold
  warm === cold
