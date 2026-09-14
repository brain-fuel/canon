module Canon.DecisionsTest (tests) where

import Canon.Decisions
import Canon.Version
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
    , testProperty "precedence follows the semantic versioning specification" semverPrecedence
    , testProperty "build metadata does not affect precedence" buildMetadataIgnored
    , testProperty "leading zeros and empty identifiers are rejected" strictSyntax
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
  let bad = BS8.pack "K:\n  status: open\n  question: q\n  opened: 0.1.0\n"
      good = BS8.pack "K:\n  status: open\n  question: q\n  opened: 0.1.0\n  revisit: 0.2.0\n"
  assert (either (const True) (const False) (decodeSorted bad :: Either String Ledger))
  fmap (Map.keys . ledgerEntries) (decodeSorted good) === Right [ReferenceKey "K"]

repositoryLedgerLoads :: Property
repositoryLedgerLoads = withTests 1 $ property $ do
  result <- evalIO (readLedgerFile defaultLedgerFileName)
  case result of
    Left err -> fail (show err)
    Right ledger -> do
      fmap entryStatus (lookupDecision (ReferenceKey "DEC-parser-foundation") ledger) === Just Decided
      fmap entryStatus (lookupDecision (ReferenceKey "DEC-precedence-climbing") ledger) === Just Decided
      fmap entryStatus (lookupDecision (ReferenceKey "DEC-nested-root-check") ledger) === Just Open
      assert (Map.size (ledgerEntries ledger) >= 8)

semverPrecedence :: Property
semverPrecedence = withTests 1 $ property $ do
  let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"]
  parsed <- maybe (fail "unparsable") pure (traverse parseVersion ordered)
  assert (and (zipWith (<) parsed (drop 1 parsed)))
  map renderVersion parsed === ordered

buildMetadataIgnored :: Property
buildMetadataIgnored = property $ do
  v <- forAll genVersion
  let stripped = v {versionBuild = []}
      tagged = v {versionBuild = ["build", "7"]}
  compare stripped tagged === EQ
  parseVersion (renderVersion tagged) === Just tagged

strictSyntax :: Property
strictSyntax = withTests 1 $ property $ do
  parseVersion "01.0.0" === Nothing
  parseVersion "1.0" === Nothing
  parseVersion "1.0.0.0" === Nothing
  parseVersion "1.0.0-" === Nothing
  parseVersion "1.0.0-01" === Nothing
  fmap versionPreRelease (parseVersion "1.0.0-x.7.z-9") === Just [AlphanumericIdentifier "x", NumericIdentifier 7, AlphanumericIdentifier "z-9"]
