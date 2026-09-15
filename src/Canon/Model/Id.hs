-- | Ids are path-based and never index-based, so they survive reordering and reformatting.
module Canon.Model.Id
  ( UnitId (..)
  , DecisionId (..)
  , ReferenceKey (..)
  , VettingKey (..)
  , renderVettingKey
  , parseVettingKey
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
import Data.Char (isAlphaNum, isAscii, isSpace)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T

-- | A unit id: language, file path segments, then kind and name at each nesting level.
newtype UnitId = UnitId {unitIdSegments :: NonEmpty Text}
  deriving (Eq, Ord, Show)

-- | A decision id is its unit id with a prefix.
newtype DecisionId = DecisionId {decisionIdUnit :: UnitId}
  deriving (Eq, Ord, Show)

-- | A registry or ledger key.
newtype ReferenceKey = ReferenceKey {referenceKeyText :: Text}
  deriving (Eq, Ord, Show)

-- | Renders an id with slashes.
renderUnitId :: UnitId -> Text
renderUnitId (UnitId segments) = T.intercalate "/" (NonEmpty.toList segments)

-- | Parses an id, rejecting bad segments.
parseUnitId :: Text -> Maybe UnitId
parseUnitId t =
  let segments = T.splitOn "/" t
   in if all isIdSegment segments then UnitId <$> NonEmpty.nonEmpty segments else Nothing

-- | A segment is non-empty and holds no slash or space, so operators like a parenthesised plus are
-- valid names.
isIdSegment :: Text -> Bool
isIdSegment s = not (T.null s) && not (T.any (\c -> c == '/' || isSpace c) s)

-- | The decision id of a unit.
decisionIdFor :: UnitId -> DecisionId
decisionIdFor = DecisionId

decisionPrefix :: Text
decisionPrefix = "decision/"

-- | Renders a decision id.
renderDecisionId :: DecisionId -> Text
renderDecisionId (DecisionId unit) = decisionPrefix <> renderUnitId unit

-- | Parses a decision id.
parseDecisionId :: Text -> Maybe DecisionId
parseDecisionId t = T.stripPrefix decisionPrefix t >>= fmap DecisionId . parseUnitId

-- | A key starts and ends alphanumerically, so sentence punctuation after a citation is not part of
-- it.
isReferenceKey :: Text -> Bool
isReferenceKey t = case (T.uncons t, T.unsnoc t) of
  (Just (first, _), Just (_, final)) -> isKeyEnd first && isKeyEnd final && T.all isKeyChar t
  _ -> False
  where
    isKeyEnd c = isAscii c && isAlphaNum c
    isKeyChar c = isKeyEnd c || c == '.' || c == '_' || c == '-'

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

-- | What a verdict is about: a canonical comment, a ledger entry, or a registry entry, so one
-- vetting file signs off every kind of canonical material. ref:DEC-human-sign-off
data VettingKey
  = CommentKey DecisionId
  | LedgerKey ReferenceKey
  | RegistryKey ReferenceKey
  deriving (Eq, Ord, Show)

-- | Renders a vetting key; a comment key is its decision id, the others carry a prefix.
renderVettingKey :: VettingKey -> Text
renderVettingKey k = case k of
  CommentKey d -> renderDecisionId d
  LedgerKey (ReferenceKey r) -> "ledger/" <> r
  RegistryKey (ReferenceKey r) -> "registry/" <> r

-- | Parses a vetting key by its prefix.
parseVettingKey :: Text -> Maybe VettingKey
parseVettingKey t
  | Just r <- T.stripPrefix "ledger/" t, isReferenceKey r = Just (LedgerKey (ReferenceKey r))
  | Just r <- T.stripPrefix "registry/" t, isReferenceKey r = Just (RegistryKey (ReferenceKey r))
  | otherwise = CommentKey <$> parseDecisionId t

instance ToJSON VettingKey where
  toJSON = toJSON . renderVettingKey

instance FromJSON VettingKey where
  parseJSON = withText "VettingKey" $ \t -> maybe (fail ("invalid vetting key: " ++ T.unpack t)) pure (parseVettingKey t)

instance ToJSONKey VettingKey where
  toJSONKey = toJSONKeyText renderVettingKey

instance FromJSONKey VettingKey where
  fromJSONKey = FromJSONKeyTextParser (\t -> maybe (fail ("invalid vetting key: " ++ T.unpack t)) pure (parseVettingKey t))

instance ToJSONKey DecisionId where
  toJSONKey = toJSONKeyText renderDecisionId

instance FromJSONKey DecisionId where
  fromJSONKey = FromJSONKeyTextParser (\t -> maybe (fail ("invalid decision id: " ++ T.unpack t)) pure (parseDecisionId t))

instance ToJSONKey ReferenceKey where
  toJSONKey = toJSONKeyText referenceKeyText

instance FromJSONKey ReferenceKey where
  fromJSONKey = FromJSONKeyTextParser parseKey

parseKey :: MonadFail m => Text -> m ReferenceKey
parseKey t
  | isReferenceKey t = pure (ReferenceKey t)
  | otherwise = fail ("invalid reference key: " ++ T.unpack t)
