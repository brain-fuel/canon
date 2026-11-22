-- | Who and When come from one blame per file rather than one log per unit, because the log was the
-- slow part. ref:DEC-extraction-cache
module Canon.Git.Fill
  ( fillGitFromBlame
  ) where

import Canon.Git.Commit
import Canon.Git.Derive (whenFromHistory, whoFromHistory)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Span (Position (..), Span (..))
import Data.List (nubBy, partition)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)

-- | Fills Who and When on every unit from one blame of the file, reporting once when git is
-- unavailable. A file with no text, such as an empty Python __init__.py, has no line git can
-- blame, so it is left as it is rather than reported. A file the side's commit does not hold, and
-- every line blame marks as not committed, has no author and no date: such a line is left out of
-- Who and When rather than credited to "Not Committed Yet", and the file is reported once,
-- informationally, so the state is visible without failing the check.
-- ref:DEC-git-runner ref:DEC-uncommitted-provenance
fillGitFromBlame :: GitProvider -> FilePath -> CodeUnit Evidence -> IO (CodeUnit Evidence, [Finding])
fillGitFromBlame provider path root = do
  let rootSpan = whereSpan (answerValue (unitWhere root))
  if spanStart rootSpan == spanEnd rootSpan
    then filled []
    else do
      held <- committedIn provider path
      case held of
        Left err -> pure (root, [GitUnavailable path err])
        Right False -> pure (root, [UncommittedFile path])
        Right True -> either (\err -> pure (root, [GitUnavailable path err])) filled =<< blameOf provider path rootSpan
  where
    filled entries = do
      let (uncommitted, committed) = partition (uncommittedHash . blameHash) entries
          byLine = Map.fromList [(blameFinalLine l, l) | l <- committed]
          firstCommits = nubBy (\a b -> commitHashText a == commitHashText b) [changeCommit (whenFirst w) | u <- allUnits root, Just w <- [whenOf byLine u]]
      tagMap <- Map.fromList <$> mapM (\h -> (,) (commitHashText h) . either (const []) id <$> tagsContaining provider h) firstCommits
      pure (fill byLine tagMap root, [UncommittedLines path (length uncommitted) | not (null uncommitted)])
    linesOf unit =
      let Span (Position from _) (Position to _) = whereSpan (answerValue (unitWhere unit))
       in [from .. max from to]
    commitsOf byLine unit =
      nubBy (\a b -> commitHash a == commitHash b) [toCommit l | line <- linesOf unit, Just l <- [Map.lookup line byLine]]
    whenOf byLine unit = whenFromHistory Nothing (commitsOf byLine unit)
    fill byLine tagMap unit =
      let commits = commitsOf byLine unit
          evidence = DerivedFromGit GitBlame
          introducedIn = listToMaybe (Map.findWithDefault [] (maybe "" (commitHashText . changeCommit . whenFirst) (whenFromHistory Nothing commits)) tagMap)
       in unit
            { unitWho = (`Answer` evidence) <$> whoFromHistory commits
            , unitWhen = (`Answer` evidence) <$> whenFromHistory introducedIn commits
            , unitChildren = map (fill byLine tagMap) (unitChildren unit)
            }
    toCommit l = Commit (blameHash l) (blameAuthor l) (blameAuthorTime l) (blameCommitter l) (blameCommitterTime l) (blameSummary l)
