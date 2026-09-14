module CanonTest (tests) where

import Canon (Command (..), dispatch, parseCommand, usage, version)
import Hedgehog (property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "cli"
    [ testProperty "version subcommand prints the version" $
        withTests 1 $ property (dispatch ["version"] === version)
    , testProperty "unknown arguments print usage" $
        withTests 1 $ property (dispatch [] === usage)
    , testProperty "model and check take a path" $
        withTests 1 $ property $ do
          parseCommand ["model", "x.g4"] === CommandModel "x.g4"
          parseCommand ["check", "x.g4"] === CommandCheck "x.g4"
          parseCommand ["check"] === CommandUsage
          parseCommand ["parse", "l.g4", "p.g4", "start", "f"] === CommandParse "l.g4" "p.g4" "start" "f"
          parseCommand ["parse", "g.g4", "start", "f"] === CommandParseCombined "g.g4" "start" "f"
          parseCommand ["version"] === CommandVersion
    ]
