module Canon.CanonicalComment
  ( CanonicalComment (..)
  , docCommentBody
  , referenceTokens
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

referenceTokens :: Text -> [ReferenceKey]
referenceTokens = nub . mapMaybe keyOf . T.words
  where
    keyOf token = do
      rest <- T.stripPrefix referencePrefix token
      let key = T.dropWhileEnd (`elem` (".,;:)!?" :: String)) rest
      if isReferenceKey key then Just (ReferenceKey key) else Nothing

parseCanonicalComment :: Text -> CanonicalComment
parseCanonicalComment raw =
  let body = docCommentBody raw
   in CanonicalComment body (referenceTokens body)

toWhy :: CanonicalComment -> Why
toWhy (CanonicalComment body references) = Why body references
