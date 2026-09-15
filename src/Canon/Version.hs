-- | Versions follow Semantic Versioning 2.0.0 exactly, including precedence, because the ledger
-- compares them. ref:DEC-decision-ledger
module Canon.Version
  ( Version (..)
  , PreReleaseIdentifier (..)
  , parseVersion
  , renderVersion
  , precedence
  , canonVersion
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), withText)
import Data.Char (isAlphaNum, isAscii, isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Read as TR

-- | Numeric identifiers compare numerically and before alphanumeric ones, as the specification says.
data PreReleaseIdentifier
  = NumericIdentifier Integer
  | AlphanumericIdentifier Text
  deriving (Eq, Show)

instance Ord PreReleaseIdentifier where
  compare a b = case (a, b) of
    (NumericIdentifier x, NumericIdentifier y) -> compare x y
    (NumericIdentifier _, AlphanumericIdentifier _) -> LT
    (AlphanumericIdentifier _, NumericIdentifier _) -> GT
    (AlphanumericIdentifier x, AlphanumericIdentifier y) -> compare x y

-- | Major, minor, patch, pre-release, and build metadata.
data Version = Version
  { versionMajor :: Integer
  , versionMinor :: Integer
  , versionPatch :: Integer
  , versionPreRelease :: [PreReleaseIdentifier]
  , versionBuild :: [Text]
  }
  deriving (Eq, Show)

-- | The key by which versions order, with build metadata ignored.
precedence :: Version -> (Integer, Integer, Integer, Bool, [PreReleaseIdentifier])
precedence v = (versionMajor v, versionMinor v, versionPatch v, null (versionPreRelease v), versionPreRelease v)

instance Ord Version where
  compare a b = compare (precedence a) (precedence b)

-- | Parses a version exactly as the specification allows.
parseVersion :: Text -> Maybe Version
parseVersion input = do
  let (core, afterCore) = T.break (\c -> c == '-' || c == '+') (T.strip input)
      (preText, buildText) = case T.uncons afterCore of
        Just ('-', rest) -> let (p, b) = T.break (== '+') rest in (Just p, T.stripPrefix "+" b)
        Just ('+', rest) -> (Nothing, Just rest)
        _ -> (Nothing, Nothing)
  [major, minor, patch] <- traverse numeric (T.splitOn "." core)
  pre <- maybe (Just []) (traverse preRelease . T.splitOn ".") preText
  build <- maybe (Just []) (traverse buildIdentifier . T.splitOn ".") buildText
  Just (Version major minor patch pre build)
  where
    numeric t
      | T.null t = Nothing
      | T.length t > 1 && T.head t == '0' = Nothing
      | T.all isDigit t = either (const Nothing) (Just . fst) (TR.decimal t)
      | otherwise = Nothing
    preRelease t
      | T.null t = Nothing
      | T.all isDigit t = NumericIdentifier <$> numeric t
      | T.all isIdentifierChar t = Just (AlphanumericIdentifier t)
      | otherwise = Nothing
    buildIdentifier t
      | not (T.null t) && T.all isIdentifierChar t = Just t
      | otherwise = Nothing
    isIdentifierChar c = (isAscii c && isAlphaNum c) || c == '-'

-- | Renders a version.
renderVersion :: Version -> Text
renderVersion v =
  T.concat
    [ T.intercalate "." (map (T.pack . show) [versionMajor v, versionMinor v, versionPatch v])
    , if null (versionPreRelease v) then "" else "-" <> T.intercalate "." (map renderIdentifier (versionPreRelease v))
    , if null (versionBuild v) then "" else "+" <> T.intercalate "." (versionBuild v)
    ]
  where
    renderIdentifier i = case i of
      NumericIdentifier n -> T.pack (show n)
      AlphanumericIdentifier t -> t

instance ToJSON Version where
  toJSON = toJSON . renderVersion

instance FromJSON Version where
  parseJSON = withText "Version" $ \t -> maybe (fail ("not a semantic version: " ++ T.unpack t)) pure (parseVersion t)

-- | canon's own version, part of every cache key so a new canon never reads an old extraction.
-- ref:DEC-extraction-cache
canonVersion :: String
canonVersion = "0.1.0"
