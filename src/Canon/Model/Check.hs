-- | Every check over a model lives here, so that a finding has one definition.
-- ref:DEC-decision-ledger ref:DEC-test-requirement-check
module Canon.Model.Check
  ( checkModel
  , checkLedger
  , checkTests
  , checkAll
  , checkFile
  , checkProjectWide
  , requirementsCitedByTests
  ) where

import Canon.Decisions
import Canon.Version (parseVersion, renderVersion)
import Canon.Model
import Canon.Model.Finding
import Canon.CanonicalComment (mentionsLicense)
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), lookupReference)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Data.Text (Text)

-- | Runs every check over one model as if it were the whole project, as `canon model` reports a
-- single file.
checkAll :: Maybe Text -> Registry -> Ledger -> Model ev -> [Finding]
checkAll version registry ledger m = checkModel registry ledger m ++ checkLedger version registry ledger m ++ checkTests registry m

-- | The checks whose answer depends on one file alone. A project runs them per file and
-- `checkProjectWide` once, so the ledger and the registry are walked once rather than once per
-- file. ref:DEC-decision-ledger ref:DEC-test-requirement-check
checkFile :: Registry -> Ledger -> Model ev -> [Finding]
checkFile registry ledger m = checkModel registry ledger m ++ citedWhileOpen ledger m ++ testsWithoutRequirement registry m

-- | The checks whose answer depends on every file: the ledger's own consistency, the decided
-- decisions no file cites, the requirements no test cites, and the units an entry names that no
-- file has, each answered from the union of what the files cite, test, and define.
-- ref:DEC-decision-ledger ref:DEC-test-requirement-check
checkProjectWide :: Maybe Text -> Registry -> Ledger -> Set.Set ReferenceKey -> Set.Set ReferenceKey -> Set.Set UnitId -> [Finding]
checkProjectWide version registry ledger cited tested known =
  ledgerConsistency version registry ledger
    ++ [DecisionUncited k | (k, e) <- Map.toList (ledgerEntries ledger), entryStatus e == Decided, not (Set.member k cited)]
    ++ [DecisionUnitMissing k u | not (Set.null known), (k, e) <- Map.toList (ledgerEntries ledger), u <- entryUnits e, not (Set.member u known)]
    ++ [RequirementUntested k | (k, r) <- Map.toList (registryEntries registry), referenceKind r == Requirement, not (Set.member k tested)]

-- | The requirement keys the file's tests cite, which the project unions to decide untested
-- requirements.
requirementsCitedByTests :: Registry -> Model ev -> Set.Set ReferenceKey
requirementsCitedByTests registry m =
  Set.fromList
    [ key
    | let byUnit = decisionsByUnit m
    , u <- modelAllUnits m
    , unitTest u
    , d <- Map.findWithDefault [] (unitId u) byUnit
    , key <- whyReferences (answerValue (decisionWhy d))
    , fmap referenceKind (lookupReference key registry) == Just Requirement
    ]

-- | A commented test must cite a requirement, and a requirement must be cited by a test.
-- ref:DEC-test-requirement-check
checkTests :: Registry -> Model ev -> [Finding]
checkTests registry m = testsWithoutRequirement registry m ++ untested
  where
    cited = requirementsCitedByTests registry m
    untested =
      [ RequirementUntested k
      | (k, r) <- Map.toList (registryEntries registry)
      , referenceKind r == Requirement
      , not (Set.member k cited)
      ]

-- | References resolve, license keys are licenses, decisions name existing units, and required units
-- have comments.
checkModel :: Registry -> Ledger -> Model ev -> [Finding]
checkModel registry ledger m = unresolved ++ licenseKinds ++ licenseText ++ dangling ++ missing
  where
    units = modelAllUnits m
    knownIds = Set.fromList (map unitId units)
    resolves key = not (isNothing (lookupReference key registry)) || not (isNothing (lookupDecision key ledger))
    unresolved =
      [ UnresolvedReference (decisionId d) (decisionWhere d) key
      | d <- modelDecisions m
      , key <- whyReferences (answerValue (decisionWhy d)) ++ whyLicenses (answerValue (decisionWhy d))
      , not (resolves key)
      ]
    licenseKinds =
      [ LicenseKeyNotLicense (decisionId d) (decisionWhere d) key
      | d <- modelDecisions m
      , key <- whyLicenses (answerValue (decisionWhy d))
      , Just entry <- [lookupReference key registry]
      , referenceKind entry /= License
      ]
    licenseText =
      [ LicenseTextWithoutKey (decisionId d) (decisionWhere d)
      | d <- modelDecisions m
      , let why = answerValue (decisionWhy d)
      , null (whyLicenses why)
      , mentionsLicense (whyText why)
      ]
    dangling =
      [ DanglingDecision (decisionId d) (decisionWhere d) u
      | d <- modelDecisions m
      , u <- NonEmpty.toList (decisionUnits d)
      , not (Set.member u knownIds)
      ]
    -- Every unit some decision binds, once, so a unit is looked up rather than searched for.
    bound = Set.fromList [u | d <- modelDecisions m, u <- NonEmpty.toList (decisionUnits d)]
    missing =
      [ MissingCanonicalComment (unitId u) (answerValue (unitWhere u))
      | u <- units
      , unitRequirement u == Required
      , not (Set.member (unitId u) bound)
      ]

-- | The ledger checks: revisit versions, citations, successors, collisions, and named units.
-- ref:DEC-decision-ledger
checkLedger :: Maybe Text -> Registry -> Ledger -> Model ev -> [Finding]
checkLedger version registry ledger m =
  collisions ++ pastRevisit ++ uncited ++ successors ++ citedWhileOpen ledger m ++ missingUnits
  where
    entries = Map.toList (ledgerEntries ledger)
    knownIds = Set.fromList (map unitId (modelAllUnits m))
    citations = Set.fromList (concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions m))
    consistency = ledgerConsistency version registry ledger
    collisions = [f | f@DecisionKeyCollision {} <- consistency]
    pastRevisit = [f | f@DecisionPastRevisit {} <- consistency]
    successors = [f | f@DecisionSuccessorNotDecided {} <- consistency]
    uncited = [DecisionUncited k | (k, e) <- entries, entryStatus e == Decided, not (Set.member k citations)]
    missingUnits =
      [ DecisionUnitMissing k u
      | (k, e) <- entries
      , u <- entryUnits e
      , not (null knownIds)
      , not (Set.member u knownIds)
      ]

-- | What the ledger says of itself: a key that is also a registry key, an open decision past its
-- revisit version, and a superseded decision whose successor is not decided.
ledgerConsistency :: Maybe Text -> Registry -> Ledger -> [Finding]
ledgerConsistency version registry ledger = collisions ++ pastRevisit ++ successors
  where
    entries = Map.toList (ledgerEntries ledger)
    current = version >>= parseVersion
    collisions = [DecisionKeyCollision k | (k, _) <- entries, Map.member k (registryEntries registry)]
    pastRevisit =
      [ DecisionPastRevisit k (renderVersion revisit) (renderVersion now)
      | (k, e) <- entries
      , entryStatus e == Open
      , Just revisit <- [entryRevisit e]
      , Just now <- [current]
      , revisit <= now
      ]
    successors =
      [ DecisionSuccessorNotDecided k by
      | (k, e) <- entries
      , entryStatus e == Superseded
      , Just by <- [entryBy e]
      , fmap entryStatus (lookupDecision by ledger) /= Just Decided
      ]

-- | A comment that cites a decision still open.
citedWhileOpen :: Ledger -> Model ev -> [Finding]
citedWhileOpen ledger m =
  [ DecisionCitedWhileOpen (decisionId d) (decisionWhere d) key
  | d <- modelDecisions m
  , key <- whyReferences (answerValue (decisionWhy d))
  , fmap entryStatus (lookupDecision key ledger) == Just Open
  ]

-- | A commented test whose comment cites no requirement.
testsWithoutRequirement :: Registry -> Model ev -> [Finding]
testsWithoutRequirement registry m =
  [ TestWithoutRequirement (unitId u) (answerValue (unitWhere u))
  | u <- modelAllUnits m
  , unitTest u
  , let ds = Map.findWithDefault [] (unitId u) byUnit
  , not (null ds)
  , not (any (\d -> any (\k -> fmap referenceKind (lookupReference k registry) == Just Requirement) (whyReferences (answerValue (decisionWhy d)))) ds)
  ]
  where
    byUnit = decisionsByUnit m

-- | The decisions bound to each unit, in the model's order, built once per model.
decisionsByUnit :: Model ev -> Map.Map UnitId [Decision ev]
decisionsByUnit m = Map.fromListWith (flip (++)) [(u, [d]) | d <- modelDecisions m, u <- NonEmpty.toList (decisionUnits d)]
