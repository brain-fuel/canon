module Canon.Model.CheckTest (tests) where

import Canon.Model
import Canon.Model.Check
import Canon.Model.Finding
import Canon.Model.Gen (genModel, genReference, genUnitId)
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
  unresolvedOf (checkModel (fullRegistry m r) m) === []

droppedKeyReported :: Property
droppedKeyReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  case citedKeys m of
    [] -> pure ()
    keys -> do
      victim <- forAll (Gen.element keys)
      let registry = Registry (Map.delete victim (registryEntries (fullRegistry m r)))
      unresolvedOf (checkModel registry m) === [k | k <- keys, k == victim]

danglingReported :: Property
danglingReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  let known = Set.fromList (map unitId (modelAllUnits m))
      expected = [(decisionId d, u) | d <- modelDecisions m, u <- NonEmpty.toList (decisionUnits d), not (Set.member u known)]
  [(d, u) | DanglingDecision d _ u <- checkModel (fullRegistry m r) m] === expected
  fresh <- forAll genUnitId
  case modelDecisions m of
    [] -> pure ()
    (d : rest) | not (Set.member fresh known) -> do
      let altered = m {modelDecisions = d {decisionUnits = fresh NonEmpty.<| decisionUnits d} : rest}
      assert ((decisionId d, fresh) `elem` [(x, u) | DanglingDecision x _ u <- checkModel (fullRegistry m r) altered])
    _ -> pure ()

missingReported :: Property
missingReported = property $ do
  m <- forAll genModel
  r <- forAll genReference
  let expected = [unitId u | u <- modelAllUnits m, unitRequirement u == Required, null (decisionsFor (unitId u) m)]
  [u | MissingCanonicalComment u _ <- checkModel (fullRegistry m r) m] === expected
