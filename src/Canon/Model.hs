-- | The canonical model: code units and decisions linked by id, with evidence on every answer, which
-- is what canon emits, checks, and enforces. ref:DEC-parser-foundation
module Canon.Model
  ( Model (..)
  , schemaVersion
  , modelAllUnits
  , decisionsFor
  , module Canon.Model.Id
  , module Canon.Model.Evidence
  , module Canon.Model.Answer
  , module Canon.Model.Unit
  , module Canon.Model.Decision
  ) where

import Canon.Model.Answer
import Canon.Model.Decision
import Canon.Model.Evidence
import Canon.Model.Id
import Canon.Model.Unit
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Text (Text)

-- | One file's model: language, versions, units, and decisions.
data Model ev = Model
  { modelLanguage :: Text
  , modelVersion :: Maybe Text
  , modelDescribe :: Maybe Text
  , modelUnits :: [CodeUnit ev]
  , modelDecisions :: [Decision ev]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | The schema version emitted with every model, so a reader can refuse what it does not understand.
schemaVersion :: Int
schemaVersion = 1

-- | Every unit in the tree, flattened.
modelAllUnits :: Model ev -> [CodeUnit ev]
modelAllUnits = concatMap allUnits . modelUnits

-- | The decisions bound to a unit.
decisionsFor :: UnitId -> Model ev -> [Decision ev]
decisionsFor wanted m = [d | d <- modelDecisions m, wanted `elem` decisionUnits d]

instance ToJSON ev => ToJSON (Model ev) where
  toJSON m =
    object
      [ "decisions" .= modelDecisions m
      , "describe" .= modelDescribe m
      , "language" .= modelLanguage m
      , "schemaVersion" .= schemaVersion
      , "units" .= modelUnits m
      , "version" .= modelVersion m
      ]

instance FromJSON ev => FromJSON (Model ev) where
  parseJSON = withObject "Model" $ \o -> do
    found <- o .: "schemaVersion"
    if found /= schemaVersion
      then fail ("unsupported schema version " ++ show found ++ ", expected " ++ show schemaVersion)
      else
        Model
          <$> o .: "language"
          <*> o .:? "version"
          <*> o .:? "describe"
          <*> o .: "units"
          <*> o .: "decisions"
