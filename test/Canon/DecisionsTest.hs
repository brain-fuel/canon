module Canon.DecisionsTest (tests) where

import Canon.Decisions
import Canon.Model.Gen (genLedger, genVersion)
import Canon.Model.Id (ReferenceKey (..))
import Canon.Model.Yaml (decodeSorted, encodeSorted)
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Map.Strict as Map
import Hedgehog (Property, assert, evalIO, forAll, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "decisions"
    [ testProperty "ledger yaml round trip" ledgerRoundTrip
    , testProperty "version parse after render" versionRoundTrip
    , testProperty "an open decision without a revisit version is rejected" openNeedsRevisit
    , testProperty "the repository ledger loads with its open and decided entries" repositoryLedgerLoads
    ]

ledgerRoundTrip :: Property
ledgerRoundTrip = property $ do
  ledger <- forAll genLedger
  decodeSorted (encodeSorted ledger) === Right ledger

versionRoundTrip :: Property
versionRoundTrip = property $ do
  v <- forAll genVersion
  parseVersion (renderVersion v) === Just v

openNeedsRevisit :: Property
openNeedsRevisit = withTests 1 $ property $ do
  let bad = BS8.pack "K:\n  status: open\n  question: q\n  opened: 0.1.0.0\n"
      good = BS8.pack "K:\n  status: open\n  question: q\n  opened: 0.1.0.0\n  revisit: 0.2.0.0\n"
  assert (either (const True) (const False) (decodeSorted bad :: Either String Ledger))
  fmap (Map.keys . ledgerEntries) (decodeSorted good) === Right [ReferenceKey "K"]

repositoryLedgerLoads :: Property
repositoryLedgerLoads = withTests 1 $ property $ do
  result <- evalIO (readLedgerFile defaultLedgerFileName)
  case result of
    Left err -> fail (show err)
    Right ledger -> do
      fmap entryStatus (lookupDecision (ReferenceKey "DEC-parser-foundation") ledger) === Just Decided
      fmap entryStatus (lookupDecision (ReferenceKey "DEC-precedence-climbing") ledger) === Just Open
      assert (Map.size (ledgerEntries ledger) >= 8)
