module Canon.Git.Gen
  ( genCommitHash
  , genPerson
  , genCommit
  , genBlameLine
  , renderGitLog
  , renderBlamePorcelain
  ) where

import Canon.Git.Commit
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, utc, utcToZonedTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Time.Format.ISO8601 (iso8601Show)
import Hedgehog (Gen)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

genCommitHash :: Gen CommitHash
genCommitHash = CommitHash <$> Gen.text (Range.singleton 40) (Gen.element ("0123456789abcdef" :: String))

genWord :: Gen Text
genWord = Gen.text (Range.linear 1 10) Gen.alphaNum

genPhrase :: Gen Text
genPhrase = T.unwords <$> Gen.list (Range.linear 1 4) genWord

genPerson :: Gen Person
genPerson = Person <$> genPhrase <*> ((\u d -> T.concat [u, "@", d, ".example"]) <$> genWord <*> genWord)

genTime :: Gen UTCTime
genTime = posixSecondsToUTCTime . fromInteger <$> Gen.integral (Range.linear 0 2000000000)

genCommit :: Gen Commit
genCommit = Commit <$> genCommitHash <*> genPerson <*> genTime <*> genPerson <*> genTime <*> genPhrase

genBlameLine :: Gen BlameLine
genBlameLine =
  BlameLine
    <$> genCommitHash
    <*> Gen.int (Range.linear 1 1000)
    <*> genPerson
    <*> genTime
    <*> genPerson
    <*> genTime
    <*> genPhrase
    <*> Gen.text (Range.linear 0 40) (Gen.frequency [(8, Gen.alphaNum), (1, Gen.element (" ;:(){}" :: String))])

renderGitLog :: [Commit] -> Text
renderGitLog = T.concat . map renderRecord
  where
    renderRecord c =
      T.concat
        [ "\x1e"
        , T.intercalate
            "\x1f"
            [ commitHashText (commitHash c)
            , personName (commitAuthor c)
            , personEmail (commitAuthor c)
            , isoTime (commitAuthoredAt c)
            , personName (commitCommitter c)
            , personEmail (commitCommitter c)
            , isoTime (commitCommittedAt c)
            , commitSubject c
            ]
        , "\x1f\n\ndiff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-old\n+new\n"
        ]
    isoTime t = T.pack (if even (round (utcTimeToPOSIXSeconds t) :: Integer) then iso8601Show t else iso8601Show (utcToZonedTime utc t))

renderBlamePorcelain :: [BlameLine] -> Text
renderBlamePorcelain = T.concat . map renderEntry
  where
    renderEntry l =
      T.unlines
        [ T.unwords [commitHashText (blameHash l), T.pack (show (blameFinalLine l)), T.pack (show (blameFinalLine l)), "1"]
        , "author " <> personName (blameAuthor l)
        , T.concat ["author-mail <", personEmail (blameAuthor l), ">"]
        , "author-time " <> epoch (blameAuthorTime l)
        , "author-tz +0000"
        , "committer " <> personName (blameCommitter l)
        , T.concat ["committer-mail <", personEmail (blameCommitter l), ">"]
        , "committer-time " <> epoch (blameCommitterTime l)
        , "committer-tz +0000"
        , "summary " <> blameSummary l
        , "filename x"
        , "\t" <> blameContent l
        ]
    epoch = T.pack . show . (truncate :: Rational -> Integer) . toRational . utcTimeToPOSIXSeconds
