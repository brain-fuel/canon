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

data ConfigError = ConfigUnreadable FilePath Text
  deriving (Eq, Show)

configFileName :: FilePath
configFileName = "canon.yaml"

defaultRegistryFileName :: FilePath
defaultRegistryFileName = "canonical_refs.yaml"

defaultDecisionsFileName :: FilePath
defaultDecisionsFileName = "canonical_decisions.yaml"

defaultVettingFileName :: FilePath
defaultVettingFileName = "canonical_vetting.yaml"

defaultConfig :: Config
defaultConfig = Config Nothing defaultRegistryFileName defaultDecisionsFileName defaultVettingFileName [] "." Map.empty

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
