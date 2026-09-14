module Canon.Model.Id
  ( UnitId (..)
  , DecisionId (..)
  , ReferenceKey (..)
  , renderUnitId
  , parseUnitId
  , decisionIdFor
  , renderDecisionId
  , parseDecisionId
  , isIdSegment
  , isReferenceKey
  ) where

import Data.Aeson
  ( FromJSON (..)
  , FromJSONKey (..)
  , FromJSONKeyFunction (..)
  , ToJSON (..)
  , ToJSONKey (..)
  , withText
  )
import Data.Aeson.Types (toJSONKeyText)
import Data.Char (isAlphaNum, isAscii)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T

newtype UnitId = UnitId {unitIdSegments :: NonEmpty Text}
  deriving (Eq, Ord, Show)

newtype DecisionId = DecisionId {decisionIdUnit :: UnitId}
  deriving (Eq, Ord, Show)

newtype ReferenceKey = ReferenceKey {referenceKeyText :: Text}
  deriving (Eq, Ord, Show)

renderUnitId :: UnitId -> Text
renderUnitId (UnitId segments) = T.intercalate "/" (NonEmpty.toList segments)

parseUnitId :: Text -> Maybe UnitId
parseUnitId t =
  let segments = T.splitOn "/" t
   in if all isIdSegment segments then UnitId <$> NonEmpty.nonEmpty segments else Nothing

isIdSegment :: Text -> Bool
isIdSegment s = not (T.null s) && not (T.any (== '/') s)

decisionIdFor :: UnitId -> DecisionId
decisionIdFor = DecisionId

decisionPrefix :: Text
decisionPrefix = "decision/"

renderDecisionId :: DecisionId -> Text
renderDecisionId (DecisionId unit) = decisionPrefix <> renderUnitId unit

parseDecisionId :: Text -> Maybe DecisionId
parseDecisionId t = T.stripPrefix decisionPrefix t >>= fmap DecisionId . parseUnitId

isReferenceKey :: Text -> Bool
isReferenceKey t = case T.uncons t of
  Just (c, rest) -> isKeyStart c && T.all isKeyChar rest
  Nothing -> False
  where
    isKeyStart c = isAscii c && isAlphaNum c
    isKeyChar c = isKeyStart c || c == '.' || c == '_' || c == '-'

instance ToJSON UnitId where
  toJSON = toJSON . renderUnitId

instance FromJSON UnitId where
  parseJSON = withText "UnitId" $ \t -> maybe (fail ("invalid unit id: " ++ T.unpack t)) pure (parseUnitId t)

instance ToJSON DecisionId where
  toJSON = toJSON . renderDecisionId

instance FromJSON DecisionId where
  parseJSON = withText "DecisionId" $ \t -> maybe (fail ("invalid decision id: " ++ T.unpack t)) pure (parseDecisionId t)

instance ToJSON ReferenceKey where
  toJSON = toJSON . referenceKeyText

instance FromJSON ReferenceKey where
  parseJSON = withText "ReferenceKey" parseKey

instance ToJSONKey ReferenceKey where
  toJSONKey = toJSONKeyText referenceKeyText

instance FromJSONKey ReferenceKey where
  fromJSONKey = FromJSONKeyTextParser parseKey

parseKey :: MonadFail m => Text -> m ReferenceKey
parseKey t
  | isReferenceKey t = pure (ReferenceKey t)
  | otherwise = fail ("invalid reference key: " ++ T.unpack t)
