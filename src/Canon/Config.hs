module Canon.Config
  ( Config (..)
  , CanonicalGrammar (..)
  , ConfigError (..)
  , defaultConfig
  , configFileName
  , defaultRegistryFileName
  , defaultDecisionsFileName
  , readConfigFile
  , loadConfig
  , renderConfigError
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml
import System.Directory (doesFileExist)

data CanonicalGrammar = CanonicalGrammar
  { canonicalLexer :: FilePath
  , canonicalParser :: FilePath
  , canonicalStartRule :: Text
  }
  deriving (Eq, Show)

data Config = Config
  { configVersion :: Maybe Text
  , configRegistry :: FilePath
  , configDecisions :: FilePath
  , configCanonical :: Map Text CanonicalGrammar
  , configIgnore :: [Text]
  }
  deriving (Eq, Show)

data ConfigError = ConfigUnreadable FilePath Text
  deriving (Eq, Show)

configFileName :: FilePath
configFileName = "canon.yaml"

defaultRegistryFileName :: FilePath
defaultRegistryFileName = "canonical_refs.yaml"

defaultDecisionsFileName :: FilePath
defaultDecisionsFileName = "canonical_decisions.yaml"

defaultConfig :: Config
defaultConfig = Config Nothing defaultRegistryFileName defaultDecisionsFileName Map.empty []

readConfigFile :: FilePath -> IO (Either ConfigError Config)
readConfigFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . ConfigUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

loadConfig :: IO (Either ConfigError Config)
loadConfig = do
  present <- doesFileExist configFileName
  if present then readConfigFile configFileName else pure (Right defaultConfig)

renderConfigError :: ConfigError -> Text
renderConfigError (ConfigUnreadable path message) = T.concat [T.pack path, ": ", message]

instance ToJSON CanonicalGrammar where
  toJSON (CanonicalGrammar lexer parser start) = object ["lexer" .= lexer, "parser" .= parser, "start" .= start]

instance FromJSON CanonicalGrammar where
  parseJSON = withObject "CanonicalGrammar" $ \o -> CanonicalGrammar <$> o .: "lexer" <*> o .: "parser" <*> o .: "start"

instance ToJSON Config where
  toJSON (Config version registry decisions canonical ignore) =
    object
      [ "canonical" .= canonical
      , "decisions" .= decisions
      , "ignore" .= ignore
      , "registry" .= registry
      , "version" .= version
      ]

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o ->
    Config
      <$> o .:? "version"
      <*> (fromMaybe defaultRegistryFileName <$> o .:? "registry")
      <*> (fromMaybe defaultDecisionsFileName <$> o .:? "decisions")
      <*> (fromMaybe Map.empty <$> o .:? "canonical")
      <*> (fromMaybe [] <$> o .:? "ignore")
