module CanonTest (tests) where

import Canon (dispatch, usage)
import Hedgehog (property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "unit"
    [ testProperty "version subcommand prints the version" $
        withTests 1 $ property (dispatch ["version"] === "canon 0.1.0.0")
    , testProperty "unknown arguments print usage" $
        withTests 1 $ property (dispatch [] === usage)
    ]
