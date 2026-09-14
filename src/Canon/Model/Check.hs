module Canon.Model.Check
  ( checkModel
  ) where

import Canon.Model
import Canon.Model.Finding
import Canon.Registry (Registry, lookupReference)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (isNothing)
import qualified Data.Set as Set

checkModel :: Registry -> Model ev -> [Finding]
checkModel registry m = unresolved ++ dangling ++ missing
  where
    units = modelAllUnits m
    knownIds = Set.fromList (map unitId units)
    unresolved =
      [ UnresolvedReference (decisionId d) (decisionWhere d) key
      | d <- modelDecisions m
      , key <- whyReferences (answerValue (decisionWhy d))
      , isNothing (lookupReference key registry)
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
