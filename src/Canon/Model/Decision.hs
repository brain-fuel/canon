module Canon.Model.Decision
  ( Decision (..)
  ) where

import Canon.Model.Answer (Answer, Assessment, Where, Why)
import Canon.Model.Id (DecisionId, UnitId)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.List.NonEmpty (NonEmpty)

data Decision ev = Decision
  { decisionId :: DecisionId
  , decisionUnits :: NonEmpty UnitId
  , decisionWhy :: Answer Why ev
  , decisionWhere :: Where
  , decisionVetting :: Maybe (Answer Assessment ev)
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

instance ToJSON ev => ToJSON (Decision ev) where
  toJSON d =
    object
      [ "id" .= decisionId d
      , "units" .= decisionUnits d
      , "vetting" .= decisionVetting d
      , "where" .= decisionWhere d
      , "why" .= decisionWhy d
      ]

instance FromJSON ev => FromJSON (Decision ev) where
  parseJSON = withObject "Decision" $ \o ->
    Decision <$> o .: "id" <*> o .: "units" <*> o .: "why" <*> o .: "where" <*> o .:? "vetting"
