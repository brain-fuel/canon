module Canon.RegistryTest (tests) where

import Canon.Config
import Canon.Model.Gen (genConfig, genRegistry)
import Canon.Model.Id (ReferenceKey (..))
import Canon.Model.Yaml (decodeSorted, encodeSorted)
import Canon.Registry
import qualified Data.Map.Strict as Map
import Hedgehog (Property, assert, evalIO, forAll, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "registry and config"
    [ testProperty "registry yaml round trip" registryRoundTrip
    , testProperty "config yaml round trip" configRoundTrip
    , testProperty "the repository registry loads" repositoryRegistryLoads
    , testProperty "the repository config loads" repositoryConfigLoads
    ]

registryRoundTrip :: Property
registryRoundTrip = property $ do
  r <- forAll genRegistry
  decodeSorted (encodeSorted r) === Right r

configRoundTrip :: Property
configRoundTrip = property $ do
  c <- forAll genConfig
  decodeSorted (encodeSorted c) === Right c

repositoryRegistryLoads :: Property
repositoryRegistryLoads = withTests 1 $ property $ do
  result <- evalIO (readRegistryFile defaultRegistryFileName)
  case result of
    Left err -> fail (show err)
    Right registry -> do
      assert (Map.size (registryEntries registry) >= 4)
      fmap referenceKind (lookupReference (ReferenceKey "warth-2008") registry) === Just Paper

repositoryConfigLoads :: Property
repositoryConfigLoads = withTests 1 $ property $ do
  result <- evalIO (readConfigFile configFileName)
  case result of
    Left err -> fail (show err)
    Right config -> do
      configRegistry config === defaultRegistryFileName
      configVersion config === Just "0.1.0"
