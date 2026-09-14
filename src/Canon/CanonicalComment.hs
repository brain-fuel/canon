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

data CanonicalComment = CanonicalComment
  { canonicalWhy :: Text
  , canonicalReferences :: [ReferenceKey]
  , canonicalLicenses :: [ReferenceKey]
  }
  deriving (Eq, Show)

docCommentBody :: Text -> Text
docCommentBody raw =
  T.strip (T.intercalate "\n" (map stripLeadingStar (T.lines (stripDelimiters raw))))
  where
    stripDelimiters t = dropSuffix "*/" (dropPrefix "/**" (T.strip t))
    dropPrefix p t = maybe t id (T.stripPrefix p t)
    dropSuffix s t = maybe t id (T.stripSuffix s t)
    stripLeadingStar line =
      let trimmed = T.stripStart line
       in T.strip (maybe trimmed id (T.stripPrefix "*" trimmed))

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

referenceTokens :: Text -> [ReferenceKey]
referenceTokens = keyedTokens referencePrefix

licenseTokens :: Text -> [ReferenceKey]
licenseTokens = keyedTokens licensePrefix

parseCanonicalComment :: Text -> CanonicalComment
parseCanonicalComment raw =
  let body = docCommentBody raw
   in CanonicalComment body (referenceTokens body) (licenseTokens body)

toWhy :: CanonicalComment -> Why
toWhy (CanonicalComment body references licenses) = Why body references licenses

mentionsLicense :: Text -> Bool
mentionsLicense body =
  any (`T.isInfixOf` T.toLower body) ["copyright", "all rights reserved", "licensed under", "spdx-license-identifier", "the \"bsd license\"", "mit license", "apache license", "gnu general public license"]
