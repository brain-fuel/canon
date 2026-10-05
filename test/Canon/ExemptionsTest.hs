-- | An exemption covers a path by pattern and a key by name, for its kinds, and comes due at its
-- revisit version. ref:DEC-exemptions
module Canon.ExemptionsTest (tests) where

import Canon.Exemptions
import Canon.Model.Finding (Finding (..))
import Canon.Version (parseVersion)
import qualified Data.Map.Strict as Map
import Hedgehog (Property, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "exemptions"
    [ testProperty "a pattern covers its paths for its kinds and a key covers itself" coverage
    , testProperty "an exemption at its revisit version is expired" expiry
    , testProperty "the revisit line of each entry is found" revisitScan
    ]

v :: String -> Maybe a -> a
v label = maybe (error label) id

coverage :: Property
coverage = withTests 1 $ property $ do
  let at = v "version" (parseVersion "0.3.0")
      ex = Exemptions (Map.fromList [("lang_samples/**", Exemption [] "samples" at), ("src/Wavelet/Mut/Record.hs", Exemption ["mutant"] "being replaced" at), ("ledger/DEC-x", Exemption [] "not yet" at)])
  fmap fst (exemptionFor ex "lang_samples/java-gson/A.java" "comment") === Just "lang_samples/**"
  fmap fst (exemptionFor ex "src/Wavelet/Mut/Record.hs" "mutant") === Just "src/Wavelet/Mut/Record.hs"
  fmap fst (exemptionFor ex "src/Wavelet/Mut/Record.hs" "comment") === Nothing
  fmap fst (exemptionFor ex "ledger/DEC-x" "ledger") === Just "ledger/DEC-x"
  fmap fst (exemptionFor ex "src/Other.hs" "comment") === Nothing

expiry :: Property
expiry = withTests 1 $ property $ do
  let at = v "version" (parseVersion "0.3.0")
      ex = Exemptions (Map.singleton "src/**" (Exemption [] "later" at))
  [p | ExemptionExpired p _ _ <- exemptionFindings (Just "0.2.0") ex] === []
  [p | ExemptionExpired p _ _ <- exemptionFindings (Just "0.3.0") ex] === ["src/**"]
  [p | ExemptionExpired p _ _ <- exemptionFindings Nothing ex] === []

revisitScan :: Property
revisitScan = withTests 1 $ property $ do
  let source = "\"lang_samples/**\":\n  reason: samples\n  revisit: 1.0.0\nsrc/A.hs:\n  kinds: [mutant]\n  reason: x\n  revisit: 0.3.0\n"
  revisitLines source === Map.fromList [("lang_samples/**", 3), ("src/A.hs", 7)]
