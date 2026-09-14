module Canon.Model.Gen
  ( genPosition
  , genSpan
  , genIdSegment
  , genUnitId
  , genDecisionId
  , genReferenceKey
  , genEvidence
  , genPath
  , genPlainText
  , genUTCTime
  , genWhat
  , genHow
  , genWhere
  , genWhy
  , genWho
  , genWhen
  , genAnswer
  , genCodeUnit
  , genDecisionOver
  , genModel
  , genReference
  , genRegistry
  , genConfig
  ) where

import Canon.Config (Config (..))
import Canon.Git.Gen (genCommitHash, genPerson)
import Canon.Model
import Canon.Registry (Reference (..), Registry (..))
import Canon.Span
import Data.Char (isPrint)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Hedgehog (Gen)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

genPosition :: Gen Position
genPosition = Position <$> Gen.int (Range.linear 1 500) <*> Gen.int (Range.linear 1 120)

genSpan :: Gen Span
genSpan = do
  a <- genPosition
  b <- genPosition
  pure (Span (min a b) (max a b))

genIdSegment :: Gen Text
genIdSegment = Gen.text (Range.linear 1 10) Gen.alphaNum

nonEmptyOf :: Range.Range Int -> Gen a -> Gen (NonEmpty a)
nonEmptyOf range gen = NonEmpty.fromList <$> Gen.list (Range.linear 1 (Range.upperBound 99 range)) gen

genUnitId :: Gen UnitId
genUnitId = UnitId <$> nonEmptyOf (Range.linear 1 4) genIdSegment

genDecisionId :: Gen DecisionId
genDecisionId = DecisionId <$> genUnitId

genReferenceKey :: Gen ReferenceKey
genReferenceKey =
  ReferenceKey
    <$> Gen.choice
      [ T.singleton <$> Gen.alphaNum
      , (\first middle final -> T.concat [T.singleton first, middle, T.singleton final])
          <$> Gen.alphaNum
          <*> Gen.text (Range.linear 0 8) (Gen.frequency [(8, Gen.alphaNum), (1, Gen.element ("._-" :: String))])
          <*> Gen.alphaNum
      ]

genPath :: Gen FilePath
genPath = T.unpack <$> Gen.text (Range.linear 1 20) (Gen.frequency [(5, Gen.alphaNum), (1, Gen.element ("/._-" :: String))])

genPlainText :: Gen Text
genPlainText = Gen.text (Range.linear 0 30) (Gen.filter isPrint Gen.unicode)

genUTCTime :: Gen UTCTime
genUTCTime = posixSecondsToUTCTime . fromInteger <$> Gen.integral (Range.linear 0 2000000000)

genEvidence :: Gen Evidence
genEvidence =
  Gen.choice
    [ DerivedFromGit <$> Gen.enumBounded
    , DerivedFromParse <$> genPath
    , Verified <$> (Verification <$> Gen.enumBounded <*> genPlainText)
    , Asserted <$> (Assertion <$> genPath <*> genSpan)
    ]

genWhat :: Gen What
genWhat = What <$> genIdSegment <*> (UnitKind <$> genIdSegment)

genHow :: Gen How
genHow = Gen.choice [HowText <$> genPlainText, HowAt <$> genSpan]

genWhere :: Gen Where
genWhere = Where <$> genPath <*> genSpan <*> Gen.list (Range.linear 0 3) genIdSegment <*> Gen.maybe (Gen.int (Range.linear 0 100))

genWhy :: Gen Why
genWhy = Why <$> genPlainText <*> Gen.list (Range.linear 0 3) genReferenceKey

genAttribution :: Gen Attribution
genAttribution = Attribution <$> genPerson <*> Gen.list (Range.linear 1 3) genCommitHash

genWho :: Gen Who
genWho = Who <$> Gen.list (Range.linear 0 3) genAttribution <*> Gen.list (Range.linear 0 3) genAttribution

genChange :: Gen Change
genChange = Change <$> genCommitHash <*> genUTCTime

genWhen :: Gen When
genWhen = When <$> genChange <*> genChange <*> Gen.maybe genIdSegment

genAnswer :: Gen a -> Gen (Answer a Evidence)
genAnswer gen = Answer <$> gen <*> genEvidence

genCodeUnit :: Gen (CodeUnit Evidence)
genCodeUnit =
  Gen.recursive
    Gen.choice
    [genCodeUnitWith (pure [])]
    [genCodeUnitWith (Gen.list (Range.linear 0 3) genCodeUnit)]

genCodeUnitWith :: Gen [CodeUnit Evidence] -> Gen (CodeUnit Evidence)
genCodeUnitWith genChildren =
  CodeUnit
    <$> genUnitId
    <*> genAnswer genWhat
    <*> genAnswer genHow
    <*> genAnswer genWhere
    <*> Gen.maybe (genAnswer genWho)
    <*> Gen.maybe (genAnswer genWhen)
    <*> Gen.enumBounded
    <*> genChildren

genDecisionOver :: [UnitId] -> Gen (Decision Evidence)
genDecisionOver known =
  Decision
    <$> genDecisionId
    <*> nonEmptyOf (Range.linear 1 2) (if null known then genUnitId else Gen.frequency [(9, Gen.element known), (1, genUnitId)])
    <*> genAnswer genWhy
    <*> genWhere

genModel :: Gen (Model Evidence)
genModel = do
  units <- Gen.list (Range.linear 0 3) genCodeUnit
  let known = map unitId (concatMap allUnits units)
  Model
    <$> genIdSegment
    <*> Gen.maybe genIdSegment
    <*> Gen.maybe genIdSegment
    <*> pure units
    <*> Gen.list (Range.linear 0 3) (genDecisionOver known)

genReference :: Gen Reference
genReference = Reference <$> Gen.enumBounded <*> genPlainText <*> genPlainText

genRegistry :: Gen Registry
genRegistry = Registry . Map.fromList <$> Gen.list (Range.linear 0 5) ((,) <$> genReferenceKey <*> genReference)

genConfig :: Gen Config
genConfig = Config <$> Gen.maybe genIdSegment <*> genPath
