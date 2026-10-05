-- | The six answers and their evidence, as values, so that every language yields the same shape.
-- ref:DEC-comment-vetting
module Canon.Model.Answer
  ( Answer (..)
  , UnitKind (..)
  , What (..)
  , How (..)
  , Where (..)
  , Why (..)
  , Attribution (..)
  , Who (..)
  , Change (..)
  , When (..)
  , Verdict (..)
  , Assessment (..)
  , verdictText
  , parseVerdict
  , isVerdictWord
  ) where

import Canon.Git.Commit (CommitHash, Person)
import Canon.Model.Id (ReferenceKey)
import Canon.Span (Span)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Char (isAsciiLower, isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)

-- | A value with the evidence of how it is known.
data Answer a ev = Answer
  { answerValue :: a
  , answerEvidence :: ev
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A language-defined kind, kept as text so a dialect can name its own.
newtype UnitKind = UnitKind {unitKindText :: Text}
  deriving (Eq, Ord, Show)

-- | A name, a kind, and the signature when the language declares one apart from the body, so a
-- name and its type can be judged together. ref:DEC-binding-label
data What = What
  { whatName :: Text
  , whatKind :: UnitKind
  , whatSignature :: Maybe Text
  }
  deriving (Eq, Show)

-- | A body as text or as a span.
data How
  = HowText Text
  | HowAt Span
  deriving (Eq, Show)

-- | A path, a span, the chain of enclosing units, and an optional index.
data Where = Where
  { wherePath :: FilePath
  , whereSpan :: Span
  , whereChain :: [Text]
  , whereIndex :: Maybe Int
  }
  deriving (Eq, Show)

-- | Prose with the references and licenses it cites.
data Why = Why
  { whyText :: Text
  , whyReferences :: [ReferenceKey]
  , whyLicenses :: [ReferenceKey]
  }
  deriving (Eq, Show)

-- | A person with the commits they made.
data Attribution = Attribution
  { attributionPerson :: Person
  , attributionCommits :: [CommitHash]
  }
  deriving (Eq, Show)

-- | Authors and committers.
data Who = Who
  { whoAuthors :: [Attribution]
  , whoCommitters :: [Attribution]
  }
  deriving (Eq, Show)

-- | A commit and its time.
data Change = Change
  { changeCommit :: CommitHash
  , changeAt :: UTCTime
  }
  deriving (Eq, Show)

-- | First and last change and the version that introduced the unit.
data When = When
  { whenFirst :: Change
  , whenLast :: Change
  , whenIntroducedIn :: Maybe Text
  }
  deriving (Eq, Show)

-- | The states of a vetted comment, pending, good, bad, or deferred, or the word of a kind that
-- canon.yaml declares, whose meaning the declaration gives rather than canon.
-- ref:DEC-comment-vetting ref:DEC-vetting-kinds
data Verdict = Pending | Good | Bad | Deferred | Word Text
  deriving (Eq, Ord, Show)

-- | The text of a verdict as written in the vetting file.
verdictText :: Verdict -> Text
verdictText v = case v of
  Pending -> "pending"
  Good -> "good"
  Bad -> "bad"
  Deferred -> "deferred"
  Word w -> w

-- | Parses a verdict from that text; any other lower-case hyphenated word is a kind's own word.
parseVerdict :: Text -> Maybe Verdict
parseVerdict t = case t of
  "pending" -> Just Pending
  "good" -> Just Good
  "bad" -> Just Bad
  "deferred" -> Just Deferred
  _ | isVerdictWord t -> Just (Word t)
  _ -> Nothing

-- | A verdict word is lower-case letters, digits, and hyphens, so it reads as one token on its
-- line. ref:DEC-vetting-kinds
isVerdictWord :: Text -> Bool
isVerdictWord t = not (T.null t) && T.all (\c -> isAsciiLower c || isDigit c || c == '-') t

-- | A verdict with the person, time, and commit that made it, read from git, and the co-authors
-- the commit names, so an assisted sign-off is visible as such. ref:DEC-comment-vetting ref:DEC-human-sign-off
data Assessment = Assessment
  { assessmentVerdict :: Verdict
  , assessmentBy :: Maybe Person
  , assessmentAt :: Maybe UTCTime
  , assessmentCommit :: Maybe CommitHash
  , assessmentCoAuthors :: [Person]
  }
  deriving (Eq, Show)

instance ToJSON Verdict where
  toJSON = toJSON . verdictText

instance FromJSON Verdict where
  parseJSON = withText "Verdict" $ \t -> maybe (fail ("unknown verdict: " ++ show t)) pure (parseVerdict t)

instance ToJSON Assessment where
  toJSON (Assessment verdict by at commit coAuthors) = object ["at" .= at, "by" .= by, "coAuthors" .= coAuthors, "commit" .= commit, "verdict" .= verdict]

instance FromJSON Assessment where
  parseJSON = withObject "Assessment" $ \o -> Assessment <$> o .: "verdict" <*> o .:? "by" <*> o .:? "at" <*> o .:? "commit" <*> (fromMaybe [] <$> o .:? "coAuthors")

instance (ToJSON a, ToJSON ev) => ToJSON (Answer a ev) where
  toJSON (Answer value evidence) = object ["evidence" .= evidence, "value" .= value]

instance (FromJSON a, FromJSON ev) => FromJSON (Answer a ev) where
  parseJSON = withObject "Answer" $ \o -> Answer <$> o .: "value" <*> o .: "evidence"

instance ToJSON UnitKind where
  toJSON = toJSON . unitKindText

instance FromJSON UnitKind where
  parseJSON v = UnitKind <$> parseJSON v

instance ToJSON What where
  toJSON (What name kind signature) = object (["kind" .= kind, "name" .= name] ++ maybe [] (\s -> ["signature" .= s]) signature)

instance FromJSON What where
  parseJSON = withObject "What" $ \o -> What <$> o .: "name" <*> o .: "kind" <*> o .:? "signature"

instance ToJSON How where
  toJSON h = case h of
    HowText body -> object ["body" .= body]
    HowAt sp -> object ["at" .= sp]

instance FromJSON How where
  parseJSON = withObject "How" $ \o -> do
    body <- o .:? "body"
    at <- o .:? "at"
    case (body, at) of
      (Just b, Nothing) -> pure (HowText b)
      (Nothing, Just s) -> pure (HowAt s)
      _ -> fail "How needs exactly one of body or at"

instance ToJSON Where where
  toJSON (Where path sp chain index) =
    object ["chain" .= chain, "index" .= index, "path" .= path, "span" .= sp]

instance FromJSON Where where
  parseJSON = withObject "Where" $ \o ->
    Where <$> o .: "path" <*> o .: "span" <*> o .: "chain" <*> o .:? "index"

instance ToJSON Why where
  toJSON (Why text references licenses) = object ["licenses" .= licenses, "references" .= references, "text" .= text]

instance FromJSON Why where
  parseJSON = withObject "Why" $ \o -> Why <$> o .: "text" <*> o .: "references" <*> (fromMaybe [] <$> o .:? "licenses")

instance ToJSON Attribution where
  toJSON (Attribution person commits) = object ["commits" .= commits, "person" .= person]

instance FromJSON Attribution where
  parseJSON = withObject "Attribution" $ \o -> Attribution <$> o .: "person" <*> o .: "commits"

instance ToJSON Who where
  toJSON (Who authors committers) = object ["authors" .= authors, "committers" .= committers]

instance FromJSON Who where
  parseJSON = withObject "Who" $ \o -> Who <$> o .: "authors" <*> o .: "committers"

instance ToJSON Change where
  toJSON (Change commit at) = object ["at" .= at, "commit" .= commit]

instance FromJSON Change where
  parseJSON = withObject "Change" $ \o -> Change <$> o .: "commit" <*> o .: "at"

instance ToJSON When where
  toJSON (When first' last' introducedIn) =
    object ["first" .= first', "introducedIn" .= introducedIn, "last" .= last']

instance FromJSON When where
  parseJSON = withObject "When" $ \o -> When <$> o .: "first" <*> o .: "last" <*> o .:? "introducedIn"
