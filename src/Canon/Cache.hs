module Canon.Cache
  ( CacheKey (..)
  , cacheDirectoryName
  , cacheKey
  , lookupCached
  , storeCached
  ) where

import Canon.Extract.Grammar (Extraction (..))
import Canon.Model (schemaVersion)
import Canon.Model.Yaml (decodeSorted, encodeSorted)
import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 (hashlazy)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))

newtype CacheKey = CacheKey {cacheKeyText :: Text}
  deriving (Eq, Show)

cacheDirectoryName :: FilePath
cacheDirectoryName = ".canon-cache"

cacheKey :: [LBS.ByteString] -> CacheKey
cacheKey parts =
  CacheKey (TE.decodeUtf8 (Base16.encode (hashlazy (LBS.concat (LBS.pack (map (fromIntegral . fromEnum) (show schemaVersion)) : parts)))))

newtype CachedExtraction = CachedExtraction Extraction

instance ToJSON CachedExtraction where
  toJSON (CachedExtraction (Extraction model findings)) = object ["findings" .= findings, "model" .= model]

instance FromJSON CachedExtraction where
  parseJSON = withObject "CachedExtraction" $ \o -> CachedExtraction <$> (Extraction <$> o .: "model" <*> o .: "findings")

cachePath :: FilePath -> CacheKey -> FilePath
cachePath directory (CacheKey key) = directory </> cacheDirectoryName </> (T.unpack key ++ ".yaml")

lookupCached :: FilePath -> CacheKey -> IO (Maybe Extraction)
lookupCached directory key = do
  let path = cachePath directory key
  present <- doesFileExist path
  if not present
    then pure Nothing
    else do
      bytes <- try (BS.readFile path)
      pure $ case bytes of
        Left (_ :: IOException) -> Nothing
        Right content -> either (const Nothing) (\(CachedExtraction e) -> Just e) (decodeSorted content)

storeCached :: FilePath -> CacheKey -> Extraction -> IO ()
storeCached directory key extraction = do
  createDirectoryIfMissing True (directory </> cacheDirectoryName)
  result <- try (BS.writeFile (cachePath directory key) (encodeSorted (CachedExtraction extraction)))
  case result of
    Left (_ :: IOException) -> pure ()
    Right () -> pure ()
