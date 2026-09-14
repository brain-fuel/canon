module Canon.Model.CheckTest (tests) where

import Canon.Model
import Canon.Model.Check
import Canon.Model.Finding
import Canon.Decisions
import Canon.Model.Gen (genDecisionEntry, genModel, genReference, genUnitId, genVersion)
import Canon.Registry
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Hedgehog (Property, assert, forAll, property, (===))
import qualified Hedgehog.Gen as Gen
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "check"
    [ testProperty "a registry holding every cited key yields no unresolved findings" fullRegistryResolves
    , testProperty "dropping one cited key yields exactly its unresolved findings" droppedKeyReported
    , testProperty "dangling decisions are exactly those naming unknown units" danglingReported
    , testProperty "every required unit without a decision is reported" missingReported
    , testProperty "open decisions past their revisit version are reported" pastRevisitReported
    , testProperty "decided decisions are uncited unless a comment cites them" uncitedReported
    , testProperty "a superseded decision needs a decided successor" successorReported
    , testProperty "citing an open decision is informational" citedWhileOpenInformational
    , testProperty "a key in both registry and ledger collides" collisionReported
    ]

citedKeys :: Model ev -> [ReferenceKey]
citedKeys m = concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions m)

fullRegistry :: Model ev -> Reference -> Registry
fullRegistry m r = Registry (Map.fromList [(k, r) | k <- citedKeys m])

unresolvedOf :: [Finding] -> [ReferenceKey]
unresolvedOf fs = [k | UnresolvedReference _ _ k <- fs]

fullRegistryResolves :: Property
fullRegistryResolves = property $ do
  m <- forAll genModel
  r <- forAll genReference
  unresolvedOf (checkModel (fullRegistry m r) emptyLedger m) === []

droppedKeyReported :: Property
droppedKeyReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  case citedKeys m of
    [] -> pure ()
    keys -> do
      victim <- forAll (Gen.element keys)
      let registry = Registry (Map.delete victim (registryEntries (fullRegistry m r)))
      unresolvedOf (checkModel registry emptyLedger m) === [k | k <- keys, k == victim]

danglingReported :: Property
danglingReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  let known = Set.fromList (map unitId (modelAllUnits m))
      expected = [(decisionId d, u) | d <- modelDecisions m, u <- NonEmpty.toList (decisionUnits d), not (Set.member u known)]
  [(d, u) | DanglingDecision d _ u <- checkModel (fullRegistry m r) emptyLedger m] === expected
  fresh <- forAll genUnitId
  case modelDecisions m of
    [] -> pure ()
    (d : rest) | not (Set.member fresh known) -> do
      let altered = m {modelDecisions = d {decisionUnits = fresh NonEmpty.<| decisionUnits d} : rest}
      assert ((decisionId d, fresh) `elem` [(x, u) | DanglingDecision x _ u <- checkModel (fullRegistry m r) emptyLedger altered])
    _ -> pure ()

missingReported :: Property
missingReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  let expected = [unitId u | u <- modelAllUnits m, unitRequirement u == Required, null (decisionsFor (unitId u) m)]
  [u | MissingCanonicalComment u _ <- checkModel (fullRegistry m r) emptyLedger m] === expected

ledgerOf :: [(ReferenceKey, DecisionEntry)] -> Ledger
ledgerOf = Ledger . Map.fromList

pastRevisitReported :: Property
pastRevisitReported = property $ do
  m <- forAll genModel
  e <- forAll genDecisionEntry
  now <- forAll genVersion
  let key = ReferenceKey "DEC-x"
      ledger = ledgerOf [(key, e)]
      findings = checkLedger (Just (renderVersion now)) emptyRegistry ledger m
      expected = entryStatus e == Open && maybe False (<= now) (entryRevisit e)
  ([k | DecisionPastRevisit k _ _ <- findings] == [key]) === expected
  [k | DecisionPastRevisit k _ _ <- checkLedger Nothing emptyRegistry ledger m] === []

uncitedReported :: Property
uncitedReported = property $ do
  m <- forAll genModel
  e <- forAll genDecisionEntry
  let key = ReferenceKey "DEC-x"
      ledger = ledgerOf [(key, e)]
      cited = key `elem` concatMap (whyReferences . answerValue . decisionWhy) (modelDecisions m)
      findings = checkLedger Nothing emptyRegistry ledger m
  ([k | DecisionUncited k <- findings] == [key]) === (entryStatus e == Decided && not cited)
  assert (all ((== Informational) . findingSeverity) [f | f@(DecisionUncited _) <- findings])

successorReported :: Property
successorReported = property $ do
  m <- forAll genModel
  e <- forAll genDecisionEntry
  successor <- forAll genDecisionEntry
  let key = ReferenceKey "DEC-x"
      byKey = ReferenceKey "DEC-y"
      ledger = ledgerOf [(key, e {entryStatus = Superseded, entryBy = Just byKey}), (byKey, successor)]
  (key `elem` [k | DecisionSuccessorNotDecided k _ <- checkLedger Nothing emptyRegistry ledger m]) === (entryStatus successor /= Decided)

citedWhileOpenInformational :: Property
citedWhileOpenInformational = property $ do
  m <- forAll genModel
  e <- forAll genDecisionEntry
  case modelDecisions m of
    [] -> pure ()
    (d : rest) -> do
      let key = ReferenceKey "DEC-x"
          why = answerValue (decisionWhy d)
          altered = m {modelDecisions = d {decisionWhy = (decisionWhy d) {answerValue = why {whyReferences = key : whyReferences why}}} : rest}
          ledger = ledgerOf [(key, e {entryStatus = Open, entryRevisit = Just (Version [9])})]
          findings = checkLedger Nothing emptyRegistry ledger altered
      assert (any (\f -> case f of DecisionCitedWhileOpen _ _ k -> k == key; _ -> False) findings)
      assert (all ((== Informational) . findingSeverity) [f | f@DecisionCitedWhileOpen {} <- findings])
      [k | UnresolvedReference _ _ k <- checkModel emptyRegistry ledger altered, k == key] === []

collisionReported :: Property
collisionReported = property $ do
  m <- forAll genModel
  e <- forAll genDecisionEntry
  r <- forAll genReference
  let key = ReferenceKey "DEC-x"
      registry = Registry (Map.fromList [(key, r)])
  [k | DecisionKeyCollision k <- checkLedger Nothing registry (ledgerOf [(key, e)]) m] === [key]
