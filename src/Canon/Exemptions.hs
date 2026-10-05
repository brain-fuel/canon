-- | A project just adopted owes more than anyone can pay at once, so a subject can be declared
-- not owed until a version, with a reason, in a file signed like every other ledger; the debt is
-- still raised and counted, only not yet due. ref:DEC-exemptions
module Canon.Exemptions
  ( Exemption (..)
  , Exemptions (..)
  , ExemptionsError (..)
  , emptyExemptions
  , readExemptionsFile
  , renderExemptionsError
  , exemptionFor
  , exemptionFindings
  , revisitLines
  ) where

import Canon.Ignore (isIgnored, parseIgnorePattern)
import Canon.Model.Finding (Finding (..))
import Canon.Version (Version, parseVersion, renderVersion)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Char (isSpace)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml as Yaml

-- | What an exemption covers: the kinds it applies to, none meaning all, why, and the version
-- by which it must be revisited, after which the check fails as an open decision does.
-- ref:DEC-exemptions
data Exemption = Exemption
  { exemptionKinds :: [Text]
  , exemptionReason :: Text
  , exemptionRevisit :: Version
  }
  deriving (Eq, Show)

-- | The exemptions file, keyed by subject: a path pattern in gitignore form, or a ledger,
-- registry, or vetting key written in full. ref:DEC-exemptions
newtype Exemptions = Exemptions {exemptionEntries :: Map Text Exemption}
  deriving (Eq, Show)

-- | An unreadable exemptions file is an error.
data ExemptionsError = ExemptionsUnreadable FilePath Text
  deriving (Eq, Show)

-- | No exemptions.
emptyExemptions :: Exemptions
emptyExemptions = Exemptions Map.empty

-- | Reads the exemptions file.
readExemptionsFile :: FilePath -> IO (Either ExemptionsError Exemptions)
readExemptionsFile path = do
  result <- Yaml.decodeFileEither path
  pure (either (Left . ExemptionsUnreadable path . T.pack . Yaml.prettyPrintParseException) Right result)

-- | Renders an exemptions error.
renderExemptionsError :: ExemptionsError -> Text
renderExemptionsError (ExemptionsUnreadable path message) = T.concat [T.pack path, ": ", message]

-- | The exemption covering a subject for a kind, if any: a path is matched by pattern, a key by
-- equality, and the kind must be among the exemption's kinds when it names any.
-- ref:DEC-exemptions
exemptionFor :: Exemptions -> Text -> Text -> Maybe (Text, Exemption)
exemptionFor (Exemptions entries) subject kind =
  case [(pat, e) | (pat, e) <- Map.toList entries, covers pat e] of
    (hit : _) -> Just hit
    [] -> Nothing
  where
    covers pat e = (pat == subject || matchesPath pat) && (null (exemptionKinds e) || kind `elem` exemptionKinds e)
    matchesPath pat = case parseIgnorePattern pat of
      Just p -> isIgnored [p] False (filter (not . T.null) (T.splitOn "/" subject))
      Nothing -> False

-- | An exemption at or past its revisit version fails the check, so the debt comes due on the
-- version that was named for it. ref:DEC-exemptions
exemptionFindings :: Maybe Text -> Exemptions -> [Finding]
exemptionFindings version (Exemptions entries) = case version >>= parseVersion of
  Nothing -> []
  Just now -> [ExemptionExpired pat (renderVersion (exemptionRevisit e)) (renderVersion now) | (pat, e) <- Map.toList entries, exemptionRevisit e <= now]

-- | The line of each entry's revisit, which is what blame is asked about to name who exempted.
-- ref:DEC-exemptions
revisitLines :: Text -> Map Text Int
revisitLines source = go Nothing (zip [1 ..] (T.lines source))
  where
    go _ [] = Map.empty
    go current ((n, line) : rest)
      | Just key <- topKey line = go (Just key) rest
      | Just k <- current, "revisit:" `T.isPrefixOf` T.stripStart line = Map.insert k n (go current rest)
      | otherwise = go current rest
    topKey line
      | T.null line || isSpace (T.head line) = Nothing
      | Just body <- T.stripSuffix ":" (T.stripEnd line) = Just (unquote body)
      | otherwise = Nothing
    unquote body = case Yaml.decodeEither' (TE.encodeUtf8 body) of
      Right t -> t
      Left _ -> body

instance ToJSON Exemption where
  toJSON (Exemption kinds reason revisit) = object ["kinds" .= kinds, "reason" .= reason, "revisit" .= renderVersion revisit]

instance FromJSON Exemption where
  parseJSON = withObject "Exemption" $ \o -> do
    kinds <- o .:? "kinds" .!= []
    reason <- o .: "reason"
    revisitText <- o .: "revisit"
    revisit <- maybe (fail ("not a version: " ++ T.unpack revisitText)) pure (parseVersion revisitText)
    pure (Exemption kinds reason revisit)

instance ToJSON Exemptions where
  toJSON = toJSON . exemptionEntries

instance FromJSON Exemptions where
  parseJSON v = Exemptions <$> parseJSON v
