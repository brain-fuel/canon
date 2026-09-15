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
  , genProfile
  , genFinding
  , genVersion
  , genDecisionEntry
  , genLedger
  , genVerdict
  , genAssessment
  , genVettingEntry
  , genVetting
  ) where

import Canon.Config (Config (..))
import Canon.Decisions (DecisionEntry (..), DecisionStatus (..), Ledger (..))
import Canon.Profile
import Canon.Model.Finding (Finding (..))
import Canon.Git.Provider (GitError (..))
import Canon.Git.Parse (GitParseError (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Version (PreReleaseIdentifier (..), Version (..), renderVersion)
import Canon.Git.Gen (genCommitHash, genPerson)
import Canon.Vetting (Vetting (..), VettingEntry (..))
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
genWhy = Why <$> genPlainText <*> Gen.list (Range.linear 0 3) genReferenceKey <*> Gen.list (Range.linear 0 2) genReferenceKey

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
    <*> Gen.maybe (genAnswer genAssessment)

genVerdict :: Gen Verdict
genVerdict = Gen.enumBounded

genAssessment :: Gen Assessment
genAssessment = Assessment <$> genVerdict <*> Gen.maybe genPerson <*> Gen.maybe genUTCTime <*> Gen.maybe genCommitHash

genVettingEntry :: Gen VettingEntry
genVettingEntry = VettingEntry <$> genVerdict <*> (("sha256:" <>) <$> Gen.text (Range.singleton 16) Gen.hexit) <*> Gen.maybe genVersion <*> Gen.maybe genPlainText

genVetting :: Gen Vetting
genVetting = Vetting . Map.fromList <$> Gen.list (Range.linear 0 4) ((,) <$> genDecisionId <*> genVettingEntry)

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
genConfig =
  Config
    <$> Gen.maybe genIdSegment
    <*> genPath
    <*> genPath
    <*> genPath
    <*> Gen.list (Range.linear 0 3) (T.pack <$> genPath)
    <*> genPath
    <*> (Map.fromList <$> Gen.list (Range.linear 0 2) ((,) <$> genIdSegment <*> genProfile))

genVersion :: Gen Version
genVersion =
  Version
    <$> genNumber
    <*> genNumber
    <*> genNumber
    <*> Gen.list (Range.linear 0 3) genPreReleaseIdentifier
    <*> Gen.list (Range.linear 0 2) genIdentifierText
  where
    genNumber = Gen.integral (Range.linear 0 20)
    genPreReleaseIdentifier =
      Gen.choice
        [ NumericIdentifier <$> genNumber
        , AlphanumericIdentifier <$> Gen.filter (not . T.all (`elem` ['0' .. '9'])) genIdentifierText
        ]
    genIdentifierText = Gen.text (Range.linear 1 6) (Gen.frequency [(8, Gen.alphaNum), (1, pure '-')])

genDecisionEntry :: Gen DecisionEntry
genDecisionEntry = do
  status <- Gen.enumBounded
  question <- genPlainText
  answer <- if status == Open then Gen.maybe genPlainText else Just <$> genPlainText
  opened <- genVersion
  revisit <- if status == Open then Just <$> genVersion else Gen.maybe genVersion
  decided <- if status == Open then Gen.maybe genVersion else Just <$> genVersion
  by <- if status == Superseded then Just <$> genReferenceKey else pure Nothing
  refs <- Gen.list (Range.linear 0 3) genReferenceKey
  units <- Gen.list (Range.linear 0 2) genUnitId
  pure (DecisionEntry status question answer opened revisit decided by refs units)

genLedger :: Gen Ledger
genLedger = Ledger . Map.fromList <$> Gen.list (Range.linear 0 4) ((,) <$> genReferenceKey <*> genDecisionEntry)

genProfile :: Gen Profile
genProfile =
  Profile
    <$> Gen.list (Range.linear 1 2) (T.cons '.' <$> genIdSegment)
    <*> Gen.choice [CombinedGrammarFile <$> genPath, SplitGrammarFiles <$> genPath <*> genPath]
    <*> (Name <$> genIdSegment)
    <*> Gen.list (Range.linear 0 3) genUnitRule
    <*> (CommentSyntax <$> Gen.maybe genIdSegment <*> Gen.maybe genIdSegment <*> Gen.maybe genIdSegment <*> Gen.list (Range.linear 0 2) genIdSegment)
  where
    genUnitRule =
      UnitRule
        <$> (Name <$> genIdSegment)
        <*> genIdSegment
        <*> Gen.choice [NameFromToken <$> (Name <$> genIdSegment) <*> Gen.int (Range.linear 1 3), NameFromRule . Name <$> genIdSegment]
        <*> Gen.bool
        <*> Gen.maybe ((,) <$> Gen.maybe (Name <$> genIdSegment) <*> Gen.list (Range.linear 1 3) genIdSegment)

genFinding :: Gen Finding
genFinding =
  Gen.choice
    [ UnresolvedReference <$> genDecisionId <*> genWhere <*> genReferenceKey
    , DanglingDecision <$> genDecisionId <*> genWhere <*> genUnitId
    , CommentPending <$> genDecisionId <*> genWhere
    , CommentStale <$> genDecisionId <*> genWhere
    , CommentBad <$> genDecisionId <*> genWhere <*> Gen.maybe genPlainText
    , CommentDeferred <$> genDecisionId <*> genWhere <*> (renderVersion <$> genVersion)
    , CommentDeferredPastRevisit <$> genDecisionId <*> genWhere <*> (renderVersion <$> genVersion) <*> (renderVersion <$> genVersion)
    , VerdictWithoutRevisit <$> genDecisionId <*> genWhere
    , VerdictOrphan <$> genDecisionId
    , VerdictUncommitted <$> genDecisionId
    , MissingCanonicalComment <$> genUnitId <*> genWhere
    , OrphanDocComment <$> genPath <*> genSpan
    , GitUnavailable <$> genPath <*> Gen.choice [pure GitNotFound, GitFailed <$> Gen.int (Range.linear 1 255) <*> genPlainText, GitUnparsable . GitParseError <$> genPlainText]
    , DecisionPastRevisit <$> genReferenceKey <*> genIdSegment <*> genIdSegment
    , DecisionUncited <$> genReferenceKey
    , DecisionSuccessorNotDecided <$> genReferenceKey <*> genReferenceKey
    , DecisionCitedWhileOpen <$> genDecisionId <*> genWhere <*> genReferenceKey
    , DecisionKeyCollision <$> genReferenceKey
    , DecisionUnitMissing <$> genReferenceKey <*> genUnitId
    , ExtractionFailed <$> genPath <*> genPlainText
    , ProjectUnusable <$> genPath <*> genPlainText
    , LicenseKeyNotLicense <$> genDecisionId <*> genWhere <*> genReferenceKey
    , LicenseTextWithoutKey <$> genDecisionId <*> genWhere
    ]
