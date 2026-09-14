module Canon.Model.Evidence
  ( GitSource (..)
  , VerificationKind (..)
  , Verification (..)
  , Assertion (..)
  , Evidence (..)
  , isDerivedFromGit
  ) where

import Canon.Span (Span)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.=))
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T

data GitSource = GitLog | GitBlame | GitTags | GitDescribe
  deriving (Eq, Ord, Show, Enum, Bounded)

data VerificationKind = PropertyTest | UnitTest | MutationRun | DecisionCoverage
  deriving (Eq, Ord, Show, Enum, Bounded)

data Verification = Verification
  { verificationKind :: VerificationKind
  , verificationName :: Text
  }
  deriving (Eq, Show)

data Assertion = Assertion
  { assertionPath :: FilePath
  , assertionSpan :: Span
  }
  deriving (Eq, Show)

data Evidence
  = DerivedFromGit GitSource
  | DerivedFromParse FilePath
  | Verified Verification
  | Asserted Assertion
  deriving (Eq, Show)

isDerivedFromGit :: Evidence -> Bool
isDerivedFromGit e = case e of
  DerivedFromGit _ -> True
  _ -> False

gitSourceText :: GitSource -> Text
gitSourceText s = case s of
  GitLog -> "log"
  GitBlame -> "blame"
  GitTags -> "tags"
  GitDescribe -> "describe"

verificationKindText :: VerificationKind -> Text
verificationKindText k = case k of
  PropertyTest -> "propertyTest"
  UnitTest -> "unitTest"
  MutationRun -> "mutationRun"
  DecisionCoverage -> "decisionCoverage"

enumFromText :: (Enum a, Bounded a) => String -> (a -> Text) -> Text -> Parser a
enumFromText label render t = case [x | x <- [minBound .. maxBound], render x == t] of
  (x : _) -> pure x
  [] -> fail ("unknown " ++ label ++ ": " ++ T.unpack t)

instance ToJSON GitSource where
  toJSON = toJSON . gitSourceText

instance FromJSON GitSource where
  parseJSON = withText "GitSource" (enumFromText "git source" gitSourceText)

instance ToJSON VerificationKind where
  toJSON = toJSON . verificationKindText

instance FromJSON VerificationKind where
  parseJSON = withText "VerificationKind" (enumFromText "verification kind" verificationKindText)

instance ToJSON Evidence where
  toJSON e = case e of
    DerivedFromGit s -> object ["source" .= ("git" :: Text), "via" .= s]
    DerivedFromParse path -> object ["path" .= path, "source" .= ("parse" :: Text)]
    Verified (Verification kind name) -> object ["kind" .= kind, "name" .= name, "source" .= ("verified" :: Text)]
    Asserted (Assertion path sp) -> object ["path" .= path, "source" .= ("asserted" :: Text), "span" .= sp]

instance FromJSON Evidence where
  parseJSON = withObject "Evidence" $ \o -> do
    source <- o .: "source"
    case (source :: Text) of
      "git" -> DerivedFromGit <$> o .: "via"
      "parse" -> DerivedFromParse <$> o .: "path"
      "verified" -> Verified <$> (Verification <$> o .: "kind" <*> o .: "name")
      "asserted" -> Asserted <$> (Assertion <$> o .: "path" <*> o .: "span")
      _ -> fail ("unknown evidence source: " ++ T.unpack source)
