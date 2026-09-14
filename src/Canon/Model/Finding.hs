module Canon.Model.Finding
  ( Finding (..)
  , renderFinding
  ) where

import Canon.Git.Provider (GitError, renderGitError)
import Canon.Model.Answer (Where (..))
import Canon.Model.Id
import Canon.Span (Position (..), Span (..))
import Data.Text (Text)
import qualified Data.Text as T

data Finding
  = UnresolvedReference DecisionId Where ReferenceKey
  | DanglingDecision DecisionId Where UnitId
  | MissingCanonicalComment UnitId Where
  | OrphanDocComment FilePath Span
  | GitUnavailable FilePath GitError
  | NotCanonical FilePath Position Text
  | CanonicalGrammarUnusable FilePath Text
  deriving (Eq, Show)

renderFinding :: Finding -> Text
renderFinding f = case f of
  UnresolvedReference d w k ->
    at (wherePath w) (whereSpan w) (T.concat ["unresolved reference ", referenceKeyText k, " in ", renderDecisionId d])
  DanglingDecision d w u ->
    at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " refers to missing unit ", renderUnitId u])
  MissingCanonicalComment u w ->
    at (wherePath w) (whereSpan w) ("missing canonical comment on " <> renderUnitId u)
  OrphanDocComment path sp -> at path sp "doc comment is not attached to any unit"
  GitUnavailable path err -> T.concat [T.pack path, ": ", renderGitError err]
  NotCanonical path pos message -> at path (Span pos pos) ("not canonically commented: " <> message)
  CanonicalGrammarUnusable path message -> T.concat [T.pack path, ": canonical grammar unusable: ", message]
  where
    at path (Span (Position line column) _) message =
      T.concat [T.pack path, ":", T.pack (show line), ":", T.pack (show column), ": ", message]
