module Canon.Git.Parse
  ( GitParseError (..)
  , logFormat
  , parseGitLog
  , parseBlamePorcelain
  , parseIsoTime
  , parseEpochTime
  ) where

import Canon.Git.Commit
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Read as TR
import Data.Time (UTCTime, zonedTimeToUTC)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)

newtype GitParseError = GitParseError Text
  deriving (Eq, Show)

recordSeparator :: Text
recordSeparator = "\x1e"

fieldSeparator :: Text
fieldSeparator = "\x1f"

logFormat :: Text
logFormat = "%x1e%H%x1f%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI%x1f%s%x1f"

parseGitLog :: Text -> Either GitParseError [Commit]
parseGitLog output = traverse parseRecord (filter (not . T.null . T.strip) (T.splitOn recordSeparator output))
  where
    parseRecord record = case T.splitOn fieldSeparator record of
      (hash : authorName : authorEmail : authoredAt : committerName : committerEmail : committedAt : subject : _) ->
        Commit (CommitHash hash) (Person authorName authorEmail)
          <$> parseIsoTime authoredAt
          <*> pure (Person committerName committerEmail)
          <*> parseIsoTime committedAt
          <*> pure subject
      fields -> Left (GitParseError (T.concat ["log record has ", T.pack (show (length fields)), " fields"]))

parseIsoTime :: Text -> Either GitParseError UTCTime
parseIsoTime t = case (iso8601ParseM trimmed, iso8601ParseM trimmed) of
  (Just zoned, _) -> Right (zonedTimeToUTC zoned)
  (Nothing, Just utcTime) -> Right utcTime
  _ -> Left (GitParseError ("unparsable time: " <> t))
  where
    trimmed = T.unpack (T.strip t)

parseEpochTime :: Text -> Either GitParseError UTCTime
parseEpochTime t = case TR.decimal (T.strip t) of
  Right (seconds, rest) | T.null rest -> Right (posixSecondsToUTCTime (fromInteger seconds))
  _ -> Left (GitParseError ("unparsable epoch time: " <> t))

data BlameHeader = BlameHeader CommitHash Int

data BlameFields = BlameFields
  { fieldsAuthor :: Maybe Text
  , fieldsAuthorMail :: Maybe Text
  , fieldsAuthorTime :: Maybe Text
  , fieldsCommitter :: Maybe Text
  , fieldsCommitterMail :: Maybe Text
  , fieldsCommitterTime :: Maybe Text
  , fieldsSummary :: Maybe Text
  }

emptyFields :: BlameFields
emptyFields = BlameFields Nothing Nothing Nothing Nothing Nothing Nothing Nothing

parseBlamePorcelain :: Text -> Either GitParseError [BlameLine]
parseBlamePorcelain output = go (T.lines output)
  where
    go remaining = case remaining of
      [] -> Right []
      (headerLine : rest) -> do
        header <- parseHeader headerLine
        (fields, content, afterEntry) <- collect emptyFields rest
        entry <- buildLine header fields content
        (entry :) <$> go afterEntry

    parseHeader line = case T.words line of
      (hash : _ : finalLine : _) -> case TR.decimal finalLine of
        Right (n, rest) | T.null rest -> Right (BlameHeader (CommitHash hash) n)
        _ -> Left (GitParseError ("unparsable blame header: " <> line))
      _ -> Left (GitParseError ("unparsable blame header: " <> line))

    collect fields remaining = case remaining of
      [] -> Left (GitParseError "blame entry without content line")
      (line : rest) -> case T.uncons line of
        Just ('\t', content) -> Right (fields, content, rest)
        _ ->
          let (key, value) = T.breakOn " " line
           in collect (record key (T.drop 1 value) fields) rest

    record key value fields = case key of
      "author" -> fields {fieldsAuthor = Just value}
      "author-mail" -> fields {fieldsAuthorMail = Just (stripAngles value)}
      "author-time" -> fields {fieldsAuthorTime = Just value}
      "committer" -> fields {fieldsCommitter = Just value}
      "committer-mail" -> fields {fieldsCommitterMail = Just (stripAngles value)}
      "committer-time" -> fields {fieldsCommitterTime = Just value}
      "summary" -> fields {fieldsSummary = Just value}
      _ -> fields

    stripAngles = T.dropAround (\c -> c == '<' || c == '>')

    buildLine (BlameHeader hash finalLine) fields content = do
      authorName <- required "author" (fieldsAuthor fields)
      authorMail <- required "author-mail" (fieldsAuthorMail fields)
      authorTime <- required "author-time" (fieldsAuthorTime fields) >>= parseEpochTime
      committerName <- required "committer" (fieldsCommitter fields)
      committerMail <- required "committer-mail" (fieldsCommitterMail fields)
      committerTime <- required "committer-time" (fieldsCommitterTime fields) >>= parseEpochTime
      summary <- required "summary" (fieldsSummary fields)
      Right
        ( BlameLine
            hash
            finalLine
            (Person authorName authorMail)
            authorTime
            (Person committerName committerMail)
            committerTime
            summary
            content
        )

    required name = maybe (Left (GitParseError ("blame entry missing " <> name))) Right
