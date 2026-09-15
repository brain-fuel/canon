-- | The body of a canonical comment and its citations, normalised the same way whatever language it
-- came from. ref:DEC-comment-reasons
module Canon.CanonicalComment
  ( CanonicalComment (..)
  , docCommentBody
  , referenceTokens
  , licenseTokens
  , mentionsLicense
  , parseCanonicalComment
  , toWhy
  ) where

import Canon.Model.Answer (Why (..))
import Canon.Model.Id (ReferenceKey (..), isReferenceKey)
import Data.List (nub)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T

-- | The three things a comment can carry: prose, references, and licenses.
data CanonicalComment = CanonicalComment
  { canonicalWhy :: Text
  , canonicalReferences :: [ReferenceKey]
  , canonicalLicenses :: [ReferenceKey]
  }
  deriving (Eq, Show)

-- | Strips the delimiters and line markers of every supported comment form, so the Why is prose
-- alone.
docCommentBody :: Text -> Text
docCommentBody raw =
  T.strip (T.intercalate "\n" (map stripLineMarker (T.lines (stripDelimiters raw))))
  where
    stripDelimiters t = foldr dropSuffix (foldr dropPrefix (T.strip t) ["/**", "{-|", "--|", "-- |"]) ["*/", "-}"]
    dropPrefix p t = maybe t id (T.stripPrefix p t)
    dropSuffix s t = maybe t id (T.stripSuffix s t)
    stripLineMarker line = T.strip (withoutMarker (T.stripStart line))
    withoutMarker trimmed = case T.stripPrefix "--" trimmed of
      Just rest -> maybe rest id (T.stripPrefix "|" (T.stripStart rest))
      Nothing -> maybe trimmed id (T.stripPrefix "*" trimmed)

referencePrefix :: Text
referencePrefix = "ref:"

licensePrefix :: Text
licensePrefix = "license:"

keyedTokens :: Text -> Text -> [ReferenceKey]
keyedTokens prefix = nub . mapMaybe keyOf . T.words
  where
    keyOf token = do
      rest <- T.stripPrefix prefix token
      let key = T.dropWhileEnd (`elem` (".,;:)!?" :: String)) rest
      if isReferenceKey key then Just (ReferenceKey key) else Nothing

-- | The ref keys cited in a body, in order and without repeats.
referenceTokens :: Text -> [ReferenceKey]
referenceTokens = keyedTokens referencePrefix

-- | The license keys cited in a body.
licenseTokens :: Text -> [ReferenceKey]
licenseTokens = keyedTokens licensePrefix

-- | Parses a raw comment into its body and citations, for languages without a dialect.
parseCanonicalComment :: Text -> CanonicalComment
parseCanonicalComment raw =
  let body = docCommentBody raw
   in CanonicalComment body (referenceTokens body) (licenseTokens body)

-- | Converts a parsed comment into the model's Why.
toWhy :: CanonicalComment -> Why
toWhy (CanonicalComment body references licenses) = Why body references licenses

-- | Detects text that reads like a license notice, so a notice without a license key is reported.
mentionsLicense :: Text -> Bool
mentionsLicense body =
  any (`T.isInfixOf` T.toLower body) ["copyright", "all rights reserved", "licensed under", "spdx-license-identifier", "the \"bsd license\"", "mit license", "apache license", "gnu general public license"]
