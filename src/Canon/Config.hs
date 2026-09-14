module Canon.Config
  ( Config (..)
  , ConfigError (..)
  , defaultConfig
  , configFileName
  , defaultRegistryFileName
  , readConfigFile
  , loadConfig
  , renderConfigError
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml
import System.Directory (doesFileExist)

data Config = Config
  { configVersion :: Maybe Text
  , configRegistry :: FilePath
  }
  deriving (Eq, Show)

data ConfigError = ConfigUnreadable FilePath Text
  deriving (Eq, Show)

configFileName :: FilePath
configFileName = "canon.yaml"

defaultRegistryFileName :: FilePath
defaultRegistryFileName = "canonical_refs.yaml"

defaultConfig :: Config
defaultConfig = Config Nothing defaultRegistryFileName

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

instance ToJSON Config where
  toJSON (Config version registry) = object ["registry" .= registry, "version" .= version]

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o ->
    Config <$> o .:? "version" <*> (fromMaybe defaultRegistryFileName <$> o .:? "registry")
