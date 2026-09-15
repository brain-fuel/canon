-- | Every finding canon can report is one constructor here, with its severity and rendering, so a
-- finding cannot exist without a message.
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
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Text (Text)
import qualified Data.Text as T

-- | The findings, one constructor each.
data Finding
  = UnresolvedReference DecisionId Where ReferenceKey
  | DanglingDecision DecisionId Where UnitId
  | MissingCanonicalComment UnitId Where
  | OrphanDocComment FilePath Span
  | GitUnavailable FilePath GitError
  | DecisionPastRevisit ReferenceKey Text Text
  | DecisionUncited ReferenceKey
  | DecisionSuccessorNotDecided ReferenceKey ReferenceKey
  | DecisionCitedWhileOpen DecisionId Where ReferenceKey
  | DecisionKeyCollision ReferenceKey
  | DecisionUnitMissing ReferenceKey UnitId
  | ExtractionFailed FilePath Text
  | LicenseKeyNotLicense DecisionId Where ReferenceKey
  | LicenseTextWithoutKey DecisionId Where
  | CommentPending DecisionId Where
  | CommentStale DecisionId Where
  | CommentBad DecisionId Where (Maybe Text)
  | CommentDeferred DecisionId Where Text
  | CommentDeferredPastRevisit DecisionId Where Text Text
  | VerdictWithoutRevisit DecisionId Where
  | VerdictOrphan VettingKey
  | VerdictUncommitted VettingKey
  | MaterialPending VettingKey
  | MaterialStale VettingKey
  | MaterialBad VettingKey (Maybe Text)
  | MaterialDeferred VettingKey Text
  | MaterialDeferredPastRevisit VettingKey Text Text
  | MaterialWithoutRevisit VettingKey
  | TestWithoutRequirement UnitId Where
  | RequirementUntested ReferenceKey
  deriving (Eq, Show)

-- | Failing findings fail the check; informational ones do not.
data Severity = Failing | Informational
  deriving (Eq, Ord, Show)

-- | The severity of each finding, decided in one place.
findingSeverity :: Finding -> Severity
findingSeverity f = case f of
  DecisionUncited _ -> Informational
  DecisionCitedWhileOpen {} -> Informational
  LicenseTextWithoutKey {} -> Informational
  CommentDeferred {} -> Informational
  MaterialDeferred {} -> Informational
  VerdictUncommitted _ -> Informational
  _ -> Failing

-- | Renders a finding as path, line, column, and message.
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
  DecisionPastRevisit k revisit current ->
    T.concat ["decision ", referenceKeyText k, " is open past its revisit version ", revisit, " at version ", current]
  DecisionUncited k -> T.concat ["decision ", referenceKeyText k, " is decided but no canonical comment cites it"]
  DecisionSuccessorNotDecided k by ->
    T.concat ["decision ", referenceKeyText k, " is superseded by ", referenceKeyText by, ", which is not decided"]
  DecisionCitedWhileOpen d w k ->
    at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " cites open decision ", referenceKeyText k])
  DecisionKeyCollision k -> T.concat ["key ", referenceKeyText k, " is both a reference and a decision"]
  DecisionUnitMissing k u -> T.concat ["decision ", referenceKeyText k, " names missing unit ", renderUnitId u]
  ExtractionFailed path message -> T.concat [T.pack path, ": ", message]
  LicenseKeyNotLicense d w k ->
    at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " cites ", referenceKeyText k, " as a license but the registry entry is not a license"])
  LicenseTextWithoutKey d w ->
    at (wherePath w) (whereSpan w) (renderDecisionId d <> " reads like a license or copyright notice but cites no license key")
  CommentPending d w -> at (wherePath w) (whereSpan w) (renderDecisionId d <> " is pending vetting")
  CommentStale d w -> at (wherePath w) (whereSpan w) (renderDecisionId d <> " changed since its verdict and is pending vetting again")
  CommentBad d w note -> at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " was vetted bad", maybe "" (": " <>) note])
  CommentDeferred d w revisit -> at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " is deferred until ", revisit])
  CommentDeferredPastRevisit d w revisit current ->
    at (wherePath w) (whereSpan w) (T.concat [renderDecisionId d, " is deferred past its revisit version ", revisit, " at version ", current])
  VerdictWithoutRevisit d w -> at (wherePath w) (whereSpan w) (renderDecisionId d <> " is deferred without a revisit version")
  VerdictOrphan k -> T.concat ["verdict for ", renderVettingKey k, " names canonical material that no longer exists"]
  VerdictUncommitted k -> T.concat ["verdict for ", renderVettingKey k, " is not committed, so its signer is unknown"]
  MaterialPending k -> materialName k <> " is pending sign-off"
  MaterialStale k -> materialName k <> " changed since its verdict and is pending sign-off again"
  MaterialBad k note -> T.concat [materialName k, " was vetted bad", maybe "" (": " <>) note]
  MaterialDeferred k revisit -> T.concat [materialName k, " is deferred until ", revisit]
  MaterialDeferredPastRevisit k revisit current -> T.concat [materialName k, " is deferred past its revisit version ", revisit, " at version ", current]
  MaterialWithoutRevisit k -> materialName k <> " is deferred without a revisit version"
  TestWithoutRequirement u w -> at (wherePath w) (whereSpan w) ("test " <> renderUnitId u <> " cites no requirement")
  RequirementUntested k -> T.concat ["requirement ", referenceKeyText k, " is cited by no test"]
  where
    materialName k = case k of
      CommentKey d -> "comment " <> renderDecisionId d
      LedgerKey r -> "decision " <> referenceKeyText r
      RegistryKey r -> "reference " <> referenceKeyText r
    at path (Span (Position line column) _) message =
      T.concat [T.pack path, ":", T.pack (show line), ":", T.pack (show column), ": ", message]

instance ToJSON Finding where
  toJSON f = case f of
    UnresolvedReference d w k -> object ["decision" .= d, "key" .= k, "kind" .= ("unresolvedReference" :: Text), "where" .= w]
    DanglingDecision d w u -> object ["decision" .= d, "kind" .= ("danglingDecision" :: Text), "unit" .= u, "where" .= w]
    MissingCanonicalComment u w -> object ["kind" .= ("missingCanonicalComment" :: Text), "unit" .= u, "where" .= w]
    OrphanDocComment path sp -> object ["kind" .= ("orphanDocComment" :: Text), "path" .= path, "span" .= sp]
    GitUnavailable path err -> object ["error" .= err, "kind" .= ("gitUnavailable" :: Text), "path" .= path]
    DecisionPastRevisit k revisit current -> object ["current" .= current, "key" .= k, "kind" .= ("decisionPastRevisit" :: Text), "revisit" .= revisit]
    DecisionUncited k -> object ["key" .= k, "kind" .= ("decisionUncited" :: Text)]
    DecisionSuccessorNotDecided k by -> object ["by" .= by, "key" .= k, "kind" .= ("decisionSuccessorNotDecided" :: Text)]
    DecisionCitedWhileOpen d w k -> object ["decision" .= d, "key" .= k, "kind" .= ("decisionCitedWhileOpen" :: Text), "where" .= w]
    DecisionKeyCollision k -> object ["key" .= k, "kind" .= ("decisionKeyCollision" :: Text)]
    DecisionUnitMissing k u -> object ["key" .= k, "kind" .= ("decisionUnitMissing" :: Text), "unit" .= u]
    ExtractionFailed path message -> object ["kind" .= ("extractionFailed" :: Text), "message" .= message, "path" .= path]
    LicenseKeyNotLicense d w k -> object ["decision" .= d, "key" .= k, "kind" .= ("licenseKeyNotLicense" :: Text), "where" .= w]
    LicenseTextWithoutKey d w -> object ["decision" .= d, "kind" .= ("licenseTextWithoutKey" :: Text), "where" .= w]
    CommentPending d w -> object ["decision" .= d, "kind" .= ("commentPending" :: Text), "where" .= w]
    CommentStale d w -> object ["decision" .= d, "kind" .= ("commentStale" :: Text), "where" .= w]
    CommentBad d w note -> object ["decision" .= d, "kind" .= ("commentBad" :: Text), "note" .= note, "where" .= w]
    CommentDeferred d w revisit -> object ["decision" .= d, "kind" .= ("commentDeferred" :: Text), "revisit" .= revisit, "where" .= w]
    CommentDeferredPastRevisit d w revisit current -> object ["current" .= current, "decision" .= d, "kind" .= ("commentDeferredPastRevisit" :: Text), "revisit" .= revisit, "where" .= w]
    VerdictWithoutRevisit d w -> object ["decision" .= d, "kind" .= ("verdictWithoutRevisit" :: Text), "where" .= w]
    VerdictOrphan k -> object ["key" .= k, "kind" .= ("verdictOrphan" :: Text)]
    VerdictUncommitted k -> object ["key" .= k, "kind" .= ("verdictUncommitted" :: Text)]
    MaterialPending k -> object ["key" .= k, "kind" .= ("materialPending" :: Text)]
    MaterialStale k -> object ["key" .= k, "kind" .= ("materialStale" :: Text)]
    MaterialBad k note -> object ["key" .= k, "kind" .= ("materialBad" :: Text), "note" .= note]
    MaterialDeferred k revisit -> object ["key" .= k, "kind" .= ("materialDeferred" :: Text), "revisit" .= revisit]
    MaterialDeferredPastRevisit k revisit current -> object ["current" .= current, "key" .= k, "kind" .= ("materialDeferredPastRevisit" :: Text), "revisit" .= revisit]
    MaterialWithoutRevisit k -> object ["key" .= k, "kind" .= ("materialWithoutRevisit" :: Text)]
    TestWithoutRequirement u w -> object ["kind" .= ("testWithoutRequirement" :: Text), "unit" .= u, "where" .= w]
    RequirementUntested k -> object ["key" .= k, "kind" .= ("requirementUntested" :: Text)]

instance FromJSON Finding where
  parseJSON = withObject "Finding" $ \o -> do
    kind <- o .: "kind"
    case (kind :: Text) of
      "unresolvedReference" -> UnresolvedReference <$> o .: "decision" <*> o .: "where" <*> o .: "key"
      "danglingDecision" -> DanglingDecision <$> o .: "decision" <*> o .: "where" <*> o .: "unit"
      "missingCanonicalComment" -> MissingCanonicalComment <$> o .: "unit" <*> o .: "where"
      "orphanDocComment" -> OrphanDocComment <$> o .: "path" <*> o .: "span"
      "gitUnavailable" -> GitUnavailable <$> o .: "path" <*> o .: "error"
      "decisionPastRevisit" -> DecisionPastRevisit <$> o .: "key" <*> o .: "revisit" <*> o .: "current"
      "decisionUncited" -> DecisionUncited <$> o .: "key"
      "decisionSuccessorNotDecided" -> DecisionSuccessorNotDecided <$> o .: "key" <*> o .: "by"
      "decisionCitedWhileOpen" -> DecisionCitedWhileOpen <$> o .: "decision" <*> o .: "where" <*> o .: "key"
      "decisionKeyCollision" -> DecisionKeyCollision <$> o .: "key"
      "decisionUnitMissing" -> DecisionUnitMissing <$> o .: "key" <*> o .: "unit"
      "extractionFailed" -> ExtractionFailed <$> o .: "path" <*> o .: "message"
      "licenseKeyNotLicense" -> LicenseKeyNotLicense <$> o .: "decision" <*> o .: "where" <*> o .: "key"
      "licenseTextWithoutKey" -> LicenseTextWithoutKey <$> o .: "decision" <*> o .: "where"
      "commentPending" -> CommentPending <$> o .: "decision" <*> o .: "where"
      "commentStale" -> CommentStale <$> o .: "decision" <*> o .: "where"
      "commentBad" -> CommentBad <$> o .: "decision" <*> o .: "where" <*> o .:? "note"
      "commentDeferred" -> CommentDeferred <$> o .: "decision" <*> o .: "where" <*> o .: "revisit"
      "commentDeferredPastRevisit" -> CommentDeferredPastRevisit <$> o .: "decision" <*> o .: "where" <*> o .: "revisit" <*> o .: "current"
      "verdictWithoutRevisit" -> VerdictWithoutRevisit <$> o .: "decision" <*> o .: "where"
      "verdictOrphan" -> VerdictOrphan <$> o .: "key"
      "verdictUncommitted" -> VerdictUncommitted <$> o .: "key"
      "materialPending" -> MaterialPending <$> o .: "key"
      "materialStale" -> MaterialStale <$> o .: "key"
      "materialBad" -> MaterialBad <$> o .: "key" <*> o .:? "note"
      "materialDeferred" -> MaterialDeferred <$> o .: "key" <*> o .: "revisit"
      "materialDeferredPastRevisit" -> MaterialDeferredPastRevisit <$> o .: "key" <*> o .: "revisit" <*> o .: "current"
      "materialWithoutRevisit" -> MaterialWithoutRevisit <$> o .: "key"
      "testWithoutRequirement" -> TestWithoutRequirement <$> o .: "unit" <*> o .: "where"
      "requirementUntested" -> RequirementUntested <$> o .: "key"
      _ -> fail ("unknown finding kind: " ++ T.unpack kind)
