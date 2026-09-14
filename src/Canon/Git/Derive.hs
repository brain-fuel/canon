module Canon.Git.Derive
  ( whoFromHistory
  , whenFromHistory
  ) where

import Canon.Git.Commit
import Canon.Model.Answer (Attribution (..), Change (..), When (..), Who (..))
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

whoFromHistory :: [Commit] -> Maybe Who
whoFromHistory commits = case commits of
  [] -> Nothing
  _ -> Just (Who (attributions commitAuthor) (attributions commitCommitter))
  where
    attributions person =
      [ Attribution p hashes
      | (p, hashes) <- Map.toList (Map.fromListWith (flip (++)) [(person c, [commitHash c]) | c <- commits])
      ]

whenFromHistory :: Maybe Text -> [Commit] -> Maybe When
whenFromHistory introducedIn commits = case sortOn commitAuthoredAt commits of
  [] -> Nothing
  ordered@(earliest : _) ->
    let latest = last ordered
     in Just (When (change earliest) (change latest) introducedIn)
  where
    change c = Change (commitHash c) (commitAuthoredAt c)
