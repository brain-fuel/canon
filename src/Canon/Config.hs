-- | canon.yaml is the one configuration file of a project, so its shape and defaults are defined
-- here alone.
module Canon.Config
  ( Config (..)
  , ConfigError (..)
  , defaultConfig
  , configFileName
  , defaultRegistryFileName
  , defaultDecisionsFileName
  , defaultVettingFileName
  , readConfigFile
  , loadConfig
  , renderConfigError
  ) where

import Canon.Profile (Profile)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml
import System.Directory (doesFileExist)

-- | The configuration: version, the three canonical files, ignore patterns, root, and language
-- profiles.
data Config = Config
  { configVersion :: Maybe Text
  , configRegistry :: FilePath
  , configDecisions :: FilePath
  , configVetting :: FilePath
  , configIgnore :: [Text]
  , configRoot :: FilePath
  , configLanguages :: Map Text Profile
  }
  deriving (Eq, Show)

-- | An unreadable configuration is an error, not a default.
data ConfigError = ConfigUnreadable FilePath Text
  deriving (Eq, Show)

-- | The fixed name of the configuration file.
configFileName :: FilePath
configFileName = "canon.yaml"

-- | The default registry file name, used when the configuration names none.
defaultRegistryFileName :: FilePath
defaultRegistryFileName = "canonical_refs.yaml"

-- | The default ledger file name.
defaultDecisionsFileName :: FilePath
defaultDecisionsFileName = "canonical_decisions.yaml"

-- | The default vetting file name.
defaultVettingFileName :: FilePath
defaultVettingFileName = "canonical_vetting.yaml"

-- | The configuration of a directory without canon.yaml.
defaultConfig :: Config
defaultConfig = Config Nothing defaultRegistryFileName defaultDecisionsFileName defaultVettingFileName [] "." Map.empty

-- | Reads and validates a configuration file.
readConfigFile :: FilePath -> IO (Either ConfigError Config)
readConfigFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . ConfigUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

-- | Loads the configuration of the current directory, defaulting when the file is absent.
loadConfig :: IO (Either ConfigError Config)
loadConfig = do
  present <- doesFileExist configFileName
  if present then readConfigFile configFileName else pure (Right defaultConfig)

-- | Renders a configuration error with its path.
renderConfigError :: ConfigError -> Text
renderConfigError (ConfigUnreadable path message) = T.concat [T.pack path, ": ", message]

instance ToJSON Config where
  toJSON (Config version registry decisions vetting ignore root languages) =
    object
      [ "decisions" .= decisions
      , "vetting" .= vetting
      , "ignore" .= ignore
      , "languages" .= languages
      , "registry" .= registry
      , "root" .= root
      , "version" .= version
      ]

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o ->
    Config
      <$> o .:? "version"
      <*> (fromMaybe defaultRegistryFileName <$> o .:? "registry")
      <*> (fromMaybe defaultDecisionsFileName <$> o .:? "decisions")
      <*> (fromMaybe defaultVettingFileName <$> o .:? "vetting")
      <*> (fromMaybe [] <$> o .:? "ignore")
      <*> (fromMaybe "." <$> o .:? "root")
      <*> (fromMaybe Map.empty <$> o .:? "languages")
