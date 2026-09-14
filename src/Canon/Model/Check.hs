module Canon.Model.Check
  ( checkModel
  , checkLedger
  , checkAll
  ) where

import Canon.Decisions
import Canon.Model
import Canon.Model.Finding
import Canon.Registry (Registry (..), lookupReference)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Data.Text (Text)

checkAll :: Maybe Text -> Registry -> Ledger -> Model ev -> [Finding]
checkAll version registry ledger m = checkModel registry ledger m ++ checkLedger version registry ledger m

checkModel :: Registry -> Ledger -> Model ev -> [Finding]
checkModel registry ledger m = unresolved ++ dangling ++ missing
  where
    units = modelAllUnits m
    knownIds = Set.fromList (map unitId units)
    resolves key = not (isNothing (lookupReference key registry)) || not (isNothing (lookupDecision key ledger))
    unresolved =
      [ UnresolvedReference (decisionId d) (decisionWhere d) key
      | d <- modelDecisions m
      , key <- whyReferences (answerValue (decisionWhy d))
      , not (resolves key)
      ]
    dangling =
      [ DanglingDecision (decisionId d) (decisionWhere d) u
      | d <- modelDecisions m
      , u <- NonEmpty.toList (decisionUnits d)
      , not (Set.member u knownIds)
      ]
    missing =
      [ MissingCanonicalComment (unitId u) (answerValue (unitWhere u))
      | u <- units
      , unitRequirement u == Required
      , null (decisionsFor (unitId u) m)
      ]

checkLedger :: Maybe Text -> Registry -> Ledger -> Model ev -> [Finding]
checkLedger version registry ledger m =
  collisions ++ pastRevisit ++ uncited ++ successors ++ citedWhileOpen ++ missingUnits
  where
    entries = Map.toList (ledgerEntries ledger)
    knownIds = Set.fromList (map unitId (modelAllUnits m))
    current = version >>= parseVersion
    citations = Set.fromList (concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions m))
    collisions = [DecisionKeyCollision k | (k, _) <- entries, Map.member k (registryEntries registry)]
    pastRevisit =
      [ DecisionPastRevisit k (renderVersion revisit) (renderVersion now)
      | (k, e) <- entries
      , entryStatus e == Open
      , Just revisit <- [entryRevisit e]
      , Just now <- [current]
      , revisit <= now
      ]
    uncited = [DecisionUncited k | (k, e) <- entries, entryStatus e == Decided, not (Set.member k citations)]
    successors =
      [ DecisionSuccessorNotDecided k by
      | (k, e) <- entries
      , entryStatus e == Superseded
      , Just by <- [entryBy e]
      , fmap entryStatus (lookupDecision by ledger) /= Just Decided
      ]
    citedWhileOpen =
      [ DecisionCitedWhileOpen (decisionId d) (decisionWhere d) key
      | d <- modelDecisions m
      , key <- whyReferences (answerValue (decisionWhy d))
      , fmap entryStatus (lookupDecision key ledger) == Just Open
      ]
    missingUnits =
      [ DecisionUnitMissing k u
      | (k, e) <- entries
      , u <- entryUnits e
      , not (null knownIds)
      , not (Set.member u knownIds)
      ]
