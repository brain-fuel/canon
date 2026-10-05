-- | canon.yaml is the one configuration file of a project, so its shape and defaults are defined
-- here alone.
module Canon.Config
  ( Config (..)
  , Runtime (..)
  , Disposition (..)
  , defaultExemptionsFileName
  , defaultRunsFileName
  , dispositionText
  , parseDisposition
  , ConfigError (..)
  , defaultConfig
  , builtinKinds
  , configFileName
  , defaultRegistryFileName
  , defaultDecisionsFileName
  , defaultVettingDirectory
  , readConfigFile
  , loadConfig
  , renderConfigError
  ) where

import Canon.Profile (Profile)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml
import System.Directory (doesFileExist)

-- | The configuration: version, the registry and ledger files, the vetting directory, ignore
-- patterns, root, language profiles, and the kinds of vetting rows other tools raise.
data Config = Config
  { configVersion :: Maybe Text
  , configRegistry :: FilePath
  , configDecisions :: FilePath
  , configVetting :: FilePath
  , configIgnore :: [Text]
  , configRoot :: FilePath
  , configLanguages :: Map Text Profile
  , configKinds :: Map Text (Map Text Disposition)
  , configExemptions :: FilePath
  , configRuns :: FilePath
  , configRuntime :: Maybe Runtime
  }
  deriving (Eq, Show)

-- | The test and mutation runtime whose artefacts the tax tools read: its name, where its
-- artefacts are, the package directory whose sources its report names, and the tests directory
-- whose sources the page shows. canon carries it because canon.yaml is every tool's file.
-- ref:DEC-canon-is-the-format
data Runtime = Runtime
  { runtimeName :: Text
  , runtimeArtefacts :: FilePath
  , runtimePackage :: FilePath
  , runtimeTests :: FilePath
  , runtimeCommand :: Maybe Text
  }
  deriving (Eq, Show)

-- | The default exemptions file name. ref:DEC-exemptions
defaultExemptionsFileName :: FilePath
defaultExemptionsFileName = "canonical_exemptions.yaml"

-- | The default runs file name, where the tax tools record every run verdicts were decided
-- against. ref:DEC-canon-is-the-format
defaultRunsFileName :: FilePath
defaultRunsFileName = "canonical_runs.yaml"

-- | What a verdict word of a declared kind does to its row: open leaves the material pending,
-- closed retires it, work leaves something to do, and deferred parks it. canon knows a kind only
-- through this table, so it can count what is open without knowing what the kind is about.
-- ref:DEC-vetting-kinds
data Disposition = DispositionOpen | DispositionClosed | DispositionWork | DispositionDeferred
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The text of a disposition as written in canon.yaml.
dispositionText :: Disposition -> Text
dispositionText d = case d of
  DispositionOpen -> "open"
  DispositionClosed -> "closed"
  DispositionWork -> "work"
  DispositionDeferred -> "deferred"

-- | Parses a disposition from that text.
parseDisposition :: Text -> Maybe Disposition
parseDisposition t = case [d | d <- [minBound .. maxBound], dispositionText d == t] of
  (d : _) -> Just d
  [] -> Nothing

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

-- | The default vetting directory, which holds a file per kind and subject. ref:DEC-vetting-layout
defaultVettingDirectory :: FilePath
defaultVettingDirectory = "canonical_vetting"

-- | The configuration of a directory without canon.yaml.
defaultConfig :: Config
defaultConfig = Config Nothing defaultRegistryFileName defaultDecisionsFileName defaultVettingDirectory [] "." Map.empty builtinKinds defaultExemptionsFileName defaultRunsFileName Nothing

-- | The kinds every project has without declaring them: name, the What queue of Rice's Tax, with
-- canon's four words. canon raises no row of it and judges none; knowing the kind only means an
-- undeclared row is never reported and an exemption can cover it. ref:DEC-name-kind
builtinKinds :: Map Text (Map Text Disposition)
builtinKinds = Map.singleton "name" (Map.fromList [("pending", DispositionOpen), ("good", DispositionClosed), ("bad", DispositionWork), ("deferred", DispositionDeferred)])

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
  toJSON (Config version registry decisions vetting ignore root languages kinds exemptions runs runtime) =
    object
      [ "decisions" .= decisions
      , "exemptions" .= exemptions
      , "vetting" .= vetting
      , "ignore" .= ignore
      , "kinds" .= kinds
      , "languages" .= languages
      , "registry" .= registry
      , "root" .= root
      , "runs" .= runs
      , "runtime" .= runtime
      , "version" .= version
      ]

instance ToJSON Runtime where
  toJSON (Runtime name artefacts package tests command) = object (["artefacts" .= artefacts, "name" .= name, "package" .= package, "tests" .= tests] ++ maybe [] (\c -> ["command" .= c]) command)

instance FromJSON Runtime where
  parseJSON = withObject "Runtime" $ \o -> Runtime <$> o .: "name" <*> (fromMaybe ".mut" <$> o .:? "artefacts") <*> (fromMaybe "." <$> o .:? "package") <*> (fromMaybe "test" <$> o .:? "tests") <*> o .:? "command"

instance ToJSON Disposition where
  toJSON = toJSON . dispositionText

instance FromJSON Disposition where
  parseJSON = Yaml.withText "Disposition" $ \t -> maybe (fail ("unknown disposition: " ++ T.unpack t)) pure (parseDisposition t)

instance FromJSON Config where
  parseJSON = withObject "Config" $ \o ->
    Config
      <$> o .:? "version"
      <*> (fromMaybe defaultRegistryFileName <$> o .:? "registry")
      <*> (fromMaybe defaultDecisionsFileName <$> o .:? "decisions")
      <*> (fromMaybe defaultVettingDirectory <$> o .:? "vetting")
      <*> (fromMaybe [] <$> o .:? "ignore")
      <*> (fromMaybe "." <$> o .:? "root")
      <*> (fromMaybe Map.empty <$> o .:? "languages")
      <*> (flip Map.union builtinKinds . fromMaybe Map.empty <$> o .:? "kinds")
      <*> (fromMaybe defaultExemptionsFileName <$> o .:? "exemptions")
      <*> (fromMaybe defaultRunsFileName <$> o .:? "runs")
      <*> o .:? "runtime"
