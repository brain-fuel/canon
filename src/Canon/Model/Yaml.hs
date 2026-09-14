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

encodeSorted :: ToJSON a => a -> ByteString
encodeSorted = encodePretty (setConfCompare compare (setConfDropNull False defConfig))

decodeSorted :: FromJSON a => ByteString -> Either String a
decodeSorted = either (Left . Yaml.prettyPrintParseException) Right . Yaml.decodeEither'

encodeModel :: Model Evidence -> ByteString
encodeModel = encodeSorted

decodeModel :: ByteString -> Either String (Model Evidence)
decodeModel = decodeSorted
