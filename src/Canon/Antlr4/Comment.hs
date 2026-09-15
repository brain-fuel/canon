-- | Comments carry the Why, so the reader keeps them with their spans instead of discarding them as
-- ANTLR does. ref:DEC-comment-reasons
module Canon.Antlr4.Comment
  ( Comment (..)
  , CommentKind (..)
  , scanComments
  ) where

import Canon.Antlr4.Lexical
  ( LineTable
  , isDocCommentStart
  , lineTable
  , scanAction
  , scanArgument
  , scanBlockComment
  , scanLineComment
  , scanName
  , scanStringLiteral
  , spanBetween
  )
import Canon.Antlr4.Syntax (Located (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

-- | Only doc comments are canonical, so the kind is kept to tell them from line and block comments.
data CommentKind = DocComment | BlockComment | LineComment
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | A comment with its span, so it can be bound to the unit directly below it.
data Comment = Comment
  { commentKind :: CommentKind
  , commentText :: Text
  }
  deriving (Eq, Show)

data Walk = Walk Int Text Text

-- | Scans comments out of grammar text independently of parsing, so a grammar that fails to parse
-- still yields its comments.
scanComments :: Text -> [Located Comment]
scanComments source = go (Walk 0 source T.empty)
  where
    table :: LineTable
    table = lineTable source

    go w@(Walk offset remaining lastName) = case T.uncons remaining of
      Nothing -> []
      Just (c, _) -> case c of
        '/'
          | "/*" `T.isPrefixOf` remaining ->
              let len = fromMaybe 2 (scanBlockComment remaining)
                  kind = if isDocCommentStart remaining then DocComment else BlockComment
               in emit kind len w
          | "//" `T.isPrefixOf` remaining -> emit LineComment (scanLineComment remaining) w
          | otherwise -> advance 1 w
        '\'' -> advance (fromMaybe 1 (scanStringLiteral remaining)) w
        '{'
          | lastName `elem` blockKeywords -> advance 1 w
          | otherwise -> advance (fromMaybe 1 (scanAction remaining)) w
        '[' -> advance (fromMaybe 1 (scanArgument remaining)) w
        _ -> case scanName remaining of
          Just len -> go (Walk (offset + len) (T.drop len remaining) (T.take len remaining))
          Nothing -> advance 1 w

    advance n (Walk offset remaining lastName) = go (Walk (offset + n) (T.drop n remaining) lastName)

    emit kind len (Walk offset remaining lastName) =
      Located (spanBetween table offset (offset + len)) (Comment kind (T.take len remaining))
        : go (Walk (offset + len) (T.drop len remaining) lastName)

    blockKeywords = ["options", "tokens", "channels"]
