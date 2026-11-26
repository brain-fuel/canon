-- | Extractions are cached by content so that a second check re-reads only what changed, and the key
-- holds everything that reaches the model so a stale entry cannot lie. A failed parse is cached
-- too, because a file the grammar rejects is the most expensive parse there is and the answer
-- does not change until the file or the grammar does. Entries are JSON, which only canon reads, because
-- decoding them is most of a warm check and JSON decodes several times faster than YAML. An entry
-- names its file as the working project names it, from `./`, whichever side it was read from, so
-- a snapshot of a commit reads and writes the entries the working tree's check made.
-- ref:DEC-extraction-cache
module Canon.Cache
  ( CacheKey (..)
  , cacheDirectoryName
  , cacheKey
  , lookupCached
  , storeCached
  , sharedPath
  ) where

import Canon.Extract.Grammar (Extraction (..))
import Canon.Model (schemaVersion)
import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 (hashlazy)
import Control.Concurrent (myThreadId)
import Data.Aeson (FromJSON (..), Result (..), ToJSON (..), Value (..), eitherDecodeStrict, encode, fromJSON, object, withObject, (.:), (.:?), (.=))
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Char (isDigit)
import Data.Time.Clock.POSIX (getPOSIXTime)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (addTrailingPathSeparator, makeRelative, normalise, (</>))

-- | A digest of every input to an extraction.
newtype CacheKey = CacheKey {cacheKeyText :: Text}
  deriving (Eq, Show)

-- | The cache lives in one named directory so it can be ignored and deleted.
cacheDirectoryName :: FilePath
cacheDirectoryName = ".canon-cache"

-- | Digests the parts of a key in order.
cacheKey :: [LBS.ByteString] -> CacheKey
cacheKey parts =
  CacheKey (TE.decodeUtf8 (Base16.encode (hashlazy (LBS.concat ("extraction-6:" : LBS.pack (map (fromIntegral . fromEnum) (show schemaVersion)) : parts)))))

newtype CachedExtraction = CachedExtraction (Either Text Extraction)

instance ToJSON CachedExtraction where
  toJSON (CachedExtraction (Right (Extraction model findings))) = object ["findings" .= findings, "model" .= model]
  toJSON (CachedExtraction (Left message)) = object ["failed" .= message]

instance FromJSON CachedExtraction where
  parseJSON = withObject "CachedExtraction" $ \o -> do
    failed <- o .:? "failed"
    case failed of
      Just message -> pure (CachedExtraction (Left message))
      Nothing -> CachedExtraction . Right <$> (Extraction <$> o .: "model" <*> o .: "findings")

cachePath :: FilePath -> CacheKey -> FilePath
cachePath directory (CacheKey key) = directory </> cacheDirectoryName </> (T.unpack key ++ ".json")

-- | The path a file has in an entry and its key: from `./`, as a check of the working project
-- run there names it. ref:DEC-extraction-cache
sharedPath :: FilePath -> FilePath -> FilePath
sharedPath root path
  | atHere root = path
  | otherwise = "./" ++ makeRelative (normalise root) (normalise path)

atHere :: FilePath -> Bool
atHere root = root `elem` [".", "./"]

-- | Rewrites every path in an entry from one root to another. A path is a string that starts with
-- the root; an entry holds no other string that does.
reroot :: String -> String -> Value -> Value
reroot from to v = case v of
  String s -> String (maybe s (T.pack to <>) (T.stripPrefix (T.pack from) s))
  Object o -> Object (KeyMap.map (reroot from to) o)
  Array a -> Array (fmap (reroot from to) a)
  _ -> v

rootPrefix :: FilePath -> String
rootPrefix = addTrailingPathSeparator . normalise

-- | Reads an extraction back, with its paths under the project root it is read for, treating any
-- unreadable entry as a miss.
lookupCached :: FilePath -> FilePath -> CacheKey -> IO (Maybe (Either Text Extraction))
lookupCached root directory key = do
  let path = cachePath directory key
  present <- doesFileExist path
  if not present
    then pure Nothing
    else do
      bytes <- try (BS.readFile path)
      pure $ case bytes of
        Left (_ :: IOException) -> Nothing
        Right content
          | atHere root -> either (const Nothing) (\(CachedExtraction e) -> Just e) (eitherDecodeStrict content)
          | otherwise -> case eitherDecodeStrict content of
              Left _ -> Nothing
              Right value -> case fromJSON (reroot "./" (rootPrefix root) value) of
                Success (CachedExtraction e) -> Just e
                Error _ -> Nothing

-- | Writes an extraction under its key, with its paths from `./`. It is written to a name of its
-- own and renamed into place, so a check running beside this one never reads half an entry.
storeCached :: FilePath -> FilePath -> CacheKey -> Either Text Extraction -> IO ()
storeCached root directory key extraction = do
  createDirectoryIfMissing True (directory </> cacheDirectoryName)
  writer <- myThreadId
  stamp <- (round . (* 1000000000) <$> getPOSIXTime) :: IO Integer
  let final = cachePath directory key
      partial = final ++ "." ++ filter isDigit (show writer) ++ "-" ++ show stamp ++ ".partial"
      value = toJSON (CachedExtraction extraction)
      shared = if atHere root then value else reroot (rootPrefix root) "./" value
  result <- try (LBS.writeFile partial (encode shared) >> renameFile partial final)
  case result of
    Left (_ :: IOException) -> pure ()
    Right () -> pure ()
