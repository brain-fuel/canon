-- | Models are emitted as YAML with alphabetical keys so that output is stable and diffs are
-- meaningful.
module Canon.Model.Yaml
  ( encodeModel
  , decodeModel
  , encodeSorted
  , decodeSorted
  ) where

import Canon.Model (Model)
import Canon.Model.Evidence (Evidence)
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString (ByteString)
import qualified Data.Yaml as Yaml
import Data.Yaml.Pretty (defConfig, encodePretty, setConfCompare, setConfDropNull)

-- | Encodes any value with sorted keys and nulls kept.
encodeSorted :: ToJSON a => a -> ByteString
encodeSorted = encodePretty (setConfCompare compare (setConfDropNull False defConfig))

-- | Decodes what encodeSorted wrote.
decodeSorted :: FromJSON a => ByteString -> Either String a
decodeSorted = either (Left . Yaml.prettyPrintParseException) Right . Yaml.decodeEither'

-- | Encodes a model with its schema version.
encodeModel :: Model Evidence -> ByteString
encodeModel = encodeSorted

-- | Decodes a model, rejecting another schema version.
decodeModel :: ByteString -> Either String (Model Evidence)
decodeModel = decodeSorted
