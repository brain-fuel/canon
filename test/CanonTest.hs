-- | The command line must parse and print as documented.
module CanonTest (tests) where

import Canon (Command (..), Scope (..), dispatch, parseCommand, usage, version)
import Canon.Snapshot (SideSpec (..))
import Hedgehog (property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
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
          parseCommand ["check", "--all", "x.g4"] === CommandCheck (Just "x.g4")
          parseCommand ["check", "--all"] === CommandCheck Nothing
          parseCommand ["files", "src"] === CommandFiles (Just "src")
          parseCommand ["parse", "l.g4", "p.g4", "start", "f"] === CommandParse "l.g4" "p.g4" "start" "f"
          parseCommand ["parse", "g.g4", "start", "f"] === CommandParseCombined "g.g4" "start" "f"
          parseCommand ["decisions"] === CommandDecisions
          parseCommand ["version"] === CommandVersion
    , testProperty "check and vet take the two sides of a diff" $
        withTests 1 $ property $ do
          parseCommand ["check", "--base", "main"] === CommandCheckScoped (Scope (SpecRevision "main") SpecWorkTree) Nothing
          parseCommand ["check", "--base", "v1", "--head", "HEAD", "src"] === CommandCheckScoped (Scope (SpecRevision "v1") (SpecRevision "HEAD")) (Just "src")
          parseCommand ["check", "--staged"] === CommandCheckScoped (Scope (SpecRevision "HEAD") SpecIndex) Nothing
          parseCommand ["check", "--unstaged", "src"] === CommandCheckScoped (Scope SpecIndex SpecWorkTree) (Just "src")
          parseCommand ["check", "--base", ":index", "--head", ":worktree"] === CommandCheckScoped (Scope SpecIndex SpecWorkTree) Nothing
          parseCommand ["vet", "--base", "main"] === CommandVetScoped (Scope (SpecRevision "main") SpecWorkTree)
          -- With no --base, the earlier side is the last release.
          parseCommand ["check"] === CommandCheckScoped (Scope SpecRelease SpecWorkTree) Nothing
          parseCommand ["check", "x.g4"] === CommandCheckScoped (Scope SpecRelease SpecWorkTree) (Just "x.g4")
          parseCommand ["check", "--head", "HEAD"] === CommandCheckScoped (Scope SpecRelease (SpecRevision "HEAD")) Nothing
          parseCommand ["check", "--base", ":release"] === CommandCheckScoped (Scope SpecRelease SpecWorkTree) Nothing
          parseCommand ["vet"] === CommandVetScoped (Scope SpecRelease SpecWorkTree)
          parseCommand ["vet", "--all"] === CommandVet
          parseCommand ["check", "--all", "--base", "main"] === CommandUsage
          parseCommand ["check", "--bogus"] === CommandUsage
    ]
