-- | A unit id names a file by its path, and a path may hold a space, as a Swift package's
-- "Parsable Types" directory does, while an id segment may not, so the path's whitespace is
-- percent-encoded and nothing else changes: an id written for such a file reads back, and the id
-- of every other path is the path itself, as it always was. ref:DEC-path-id-segments
-- ref:REQ-path-ids
module Canon.Model.IdTest (tests) where

import Canon.Model.Id
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T
import Hedgehog (Property, assert, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import System.FilePath (joinPath)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "ids"
    [ testProperty "a path without whitespace is its own id segments" prop_aPathWithoutWhitespaceIsItsOwnIdSegments
    , testProperty "a path with whitespace gives an id that reads back" prop_aPathWithWhitespaceGivesAnIdThatReadsBack
    ]

-- | Every path canon has given an id so far holds no whitespace, and its segments must stay what
-- they were, the path's directories and file name, so no existing id or digest changes.
-- ref:REQ-path-ids ref:DEC-path-id-segments
prop_aPathWithoutWhitespaceIsItsOwnIdSegments :: Property
prop_aPathWithoutWhitespaceIsItsOwnIdSegments = property $ do
  parts <- forAll (Gen.list (Range.linear 1 5) (Gen.filter (`notElem` [".", ".."]) (Gen.string (Range.linear 1 8) (Gen.element ("aZ09._-%+()[]#@é" :: String)))))
  pathIdSegments (joinPath parts) === map T.pack parts
  pathIdSegments ("./" <> joinPath parts) === map T.pack parts

-- | A path holding a space, a tab, or another whitespace character gives segments that are valid
-- id segments, so the id written for its file parses when the vetting files are read back, and
-- different names stay different. ref:REQ-path-ids ref:DEC-path-id-segments
prop_aPathWithWhitespaceGivesAnIdThatReadsBack :: Property
prop_aPathWithWhitespaceGivesAnIdThatReadsBack = withTests 1 $ property $ do
  pathIdSegments "Sources/ArgumentParser/Parsable Types/ParsableCommand.swift"
    === ["Sources", "ArgumentParser", "Parsable%20Types", "ParsableCommand.swift"]
  pathIdSegments "a\tb/c\160d" === ["a%09b", "c%C2%A0d"]
  let uid = UnitId (NonEmpty.fromList ("swift" : pathIdSegments "Parsable Types/A.swift" ++ ["struct", "A"]))
  parseUnitId (renderUnitId uid) === Just uid
  parseDecisionId (renderDecisionId (decisionIdFor uid)) === Just (decisionIdFor uid)
  assert (pathIdSegments "a b" /= pathIdSegments "a  b")
