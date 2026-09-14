module Canon.Git.Fill
  ( fillGitFromBlame
  ) where

import Canon.Git.Commit
import Canon.Git.Derive (whenFromHistory, whoFromHistory)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Span (Position (..), Span (..))
import Data.List (nubBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe)

fillGitFromBlame :: GitProvider -> FilePath -> CodeUnit Evidence -> IO (CodeUnit Evidence, [Finding])
fillGitFromBlame provider path root = do
  let rootSpan = whereSpan (answerValue (unitWhere root))
  blamed <- blameOf provider path rootSpan
  case blamed of
    Left err -> pure (root, [GitUnavailable path err])
    Right entries -> do
      let byLine = Map.fromList [(blameFinalLine l, l) | l <- entries]
          firstCommits = nubBy (\a b -> commitHashText a == commitHashText b) [changeCommit (whenFirst w) | u <- allUnits root, Just w <- [whenOf byLine u]]
      tagMap <- Map.fromList <$> mapM (\h -> (,) (commitHashText h) . either (const []) id <$> tagsContaining provider h) firstCommits
      pure (fill byLine tagMap root, [])
  where
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
