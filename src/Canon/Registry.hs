module Canon.Registry
  ( ReferenceKind (..)
  , Reference (..)
  , Registry (..)
  , RegistryError (..)
  , emptyRegistry
  , lookupReference
  , readRegistryFile
  , renderRegistryError
  ) where

import Canon.Model.Id (ReferenceKey)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml

data ReferenceKind = Article | Paper | Ticket | Requirement | Package | Discussion | License
  deriving (Eq, Ord, Show, Enum, Bounded)

data Reference = Reference
  { referenceKind :: ReferenceKind
  , referenceTitle :: Text
  , referenceLocator :: Text
  }
  deriving (Eq, Show)

newtype Registry = Registry {registryEntries :: Map ReferenceKey Reference}
  deriving (Eq, Show)

data RegistryError = RegistryUnreadable FilePath Text
  deriving (Eq, Show)

emptyRegistry :: Registry
emptyRegistry = Registry Map.empty

lookupReference :: ReferenceKey -> Registry -> Maybe Reference
lookupReference key = Map.lookup key . registryEntries

readRegistryFile :: FilePath -> IO (Either RegistryError Registry)
readRegistryFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . RegistryUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

renderRegistryError :: RegistryError -> Text
renderRegistryError (RegistryUnreadable path message) = T.concat [T.pack path, ": ", message]

referenceKindText :: ReferenceKind -> Text
referenceKindText k = case k of
  Article -> "article"
  Paper -> "paper"
  Ticket -> "ticket"
  Requirement -> "requirement"
  Package -> "package"
  Discussion -> "discussion"
  License -> "license"

instance ToJSON ReferenceKind where
  toJSON = toJSON . referenceKindText

instance FromJSON ReferenceKind where
  parseJSON = withText "ReferenceKind" $ \t ->
    case [k | k <- [minBound .. maxBound], referenceKindText k == t] of
      (k : _) -> pure k
      [] -> fail ("unknown reference kind: " ++ T.unpack t)

instance ToJSON Reference where
  toJSON (Reference kind title locator) = object ["kind" .= kind, "locator" .= locator, "title" .= title]

instance FromJSON Reference where
  parseJSON = withObject "Reference" $ \o -> Reference <$> o .: "kind" <*> o .: "title" <*> o .: "locator"

instance ToJSON Registry where
  toJSON = toJSON . registryEntries

instance FromJSON Registry where
  parseJSON v = Registry <$> parseJSON v
