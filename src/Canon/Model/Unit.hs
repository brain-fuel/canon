module Canon.Model.Unit
  ( CommentRequirement (..)
  , CodeUnit (..)
  , allUnits
  , lookupUnit
  ) where

import Canon.Model.Answer (Answer, How, What, When, Where, Who)
import Canon.Model.Id (UnitId)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.:?), (.=))
import Data.Text (Text)
import qualified Data.Text as T

data CommentRequirement = Required | Optional
  deriving (Eq, Ord, Show, Enum, Bounded)

data CodeUnit ev = CodeUnit
  { unitId :: UnitId
  , unitWhat :: Answer What ev
  , unitHow :: Answer How ev
  , unitWhere :: Answer Where ev
  , unitWho :: Maybe (Answer Who ev)
  , unitWhen :: Maybe (Answer When ev)
  , unitRequirement :: CommentRequirement
  , unitChildren :: [CodeUnit ev]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

allUnits :: CodeUnit ev -> [CodeUnit ev]
allUnits u = u : concatMap allUnits (unitChildren u)

lookupUnit :: UnitId -> [CodeUnit ev] -> Maybe (CodeUnit ev)
lookupUnit wanted roots = case [u | u <- concatMap allUnits roots, unitId u == wanted] of
  (u : _) -> Just u
  [] -> Nothing

requirementText :: CommentRequirement -> Text
requirementText r = case r of
  Required -> "required"
  Optional -> "optional"

instance ToJSON CommentRequirement where
  toJSON = toJSON . requirementText

instance FromJSON CommentRequirement where
  parseJSON = withText "CommentRequirement" $ \t -> case t of
    "required" -> pure Required
    "optional" -> pure Optional
    _ -> fail ("unknown comment requirement: " ++ T.unpack t)

instance ToJSON ev => ToJSON (CodeUnit ev) where
  toJSON u =
    object
      [ "children" .= unitChildren u
      , "how" .= unitHow u
      , "id" .= unitId u
      , "requirement" .= unitRequirement u
      , "what" .= unitWhat u
      , "when" .= unitWhen u
      , "where" .= unitWhere u
      , "who" .= unitWho u
      ]

instance FromJSON ev => FromJSON (CodeUnit ev) where
  parseJSON = withObject "CodeUnit" $ \o ->
    CodeUnit
      <$> o .: "id"
      <*> o .: "what"
      <*> o .: "how"
      <*> o .: "where"
      <*> o .:? "who"
      <*> o .:? "when"
      <*> o .: "requirement"
      <*> o .: "children"
