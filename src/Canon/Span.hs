-- | Positions and spans are shared by every language so that findings and models locate things the
-- same way.
module Canon.Span
  ( Position (..)
  , Span (..)
  , Located (..)
  , spanHull
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty

-- | A line and column, both one-based as editors count.
data Position = Position
  { positionLine :: Int
  , positionColumn :: Int
  }
  deriving (Eq, Ord, Show)

-- | A start and an end position.
data Span = Span
  { spanStart :: Position
  , spanEnd :: Position
  }
  deriving (Eq, Ord, Show)

-- | A value with its span.
data Located a = Located
  { locatedSpan :: Span
  , locatedValue :: a
  }
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

-- | The smallest span covering two spans.
spanHull :: NonEmpty Span -> Span
spanHull spans = Span (minimum (NonEmpty.map spanStart spans)) (maximum (NonEmpty.map spanEnd spans))

instance ToJSON Position where
  toJSON (Position line column) = object ["column" .= column, "line" .= line]

instance FromJSON Position where
  parseJSON = withObject "Position" $ \o -> Position <$> o .: "line" <*> o .: "column"

instance ToJSON Span where
  toJSON (Span start end) = object ["end" .= end, "start" .= start]

instance FromJSON Span where
  parseJSON = withObject "Span" $ \o -> Span <$> o .: "start" <*> o .: "end"
