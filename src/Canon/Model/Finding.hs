module Canon.Model.Finding
  ( Finding (..)
  , Severity (..)
  , findingSeverity
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
  | DecisionPastRevisit ReferenceKey Text Text
  | DecisionUncited ReferenceKey
  | DecisionSuccessorNotDecided ReferenceKey ReferenceKey
  | DecisionCitedWhileOpen DecisionId Where ReferenceKey
  | DecisionKeyCollision ReferenceKey
  | DecisionUnitMissing ReferenceKey UnitId
  deriving (Eq, Show)

data Severity = Failing | Informational
  deriving (Eq, Ord, Show)

findingSeverity :: Finding -> Severity
findingSeverity f = case f of
  DecisionUncited _ -> Informational
  DecisionCitedWhileOpen {} -> Informational
  _ -> Failing

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
  DecisionPastRevisit k revisit current ->
    T.concat ["decision ", referenceKeyText k, " is open past its revisit version ", revisit, " at version ", current]
  DecisionUncited k -> T.concat ["decision ", referenceKeyText k, " is decided but no canonical comment cites it"]
  DecisionSuccessorNotDecided k by ->
    T.concat ["decision ", referenceKeyText k, " is superseded by ", referenceKeyText by, ", which is not decided"]
  DecisionCitedWhileOpen d w k ->
    at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " cites open decision ", referenceKeyText k])
  DecisionKeyCollision k -> T.concat ["key ", referenceKeyText k, " is both a reference and a decision"]
  DecisionUnitMissing k u -> T.concat ["decision ", referenceKeyText k, " names missing unit ", renderUnitId u]
  where
    at path (Span (Position line column) _) message =
      T.concat [T.pack path, ":", T.pack (show line), ":", T.pack (show column), ": ", message]
