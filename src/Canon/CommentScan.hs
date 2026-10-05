-- | Comments are scanned by a profile's syntax for languages without a dialect, so attachment can
-- run without the grammar knowing about comments. ref:DEC-comment-attachment
module Canon.CommentScan
  ( scanCommentsWith
  , docOpenerOf
  ) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Lexical (lineTable, spanBetween)
import Canon.Profile (CommentSyntax (..))
import Canon.Span (Located (..), Position (..), Span (..))
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | Scans line and block comments by the given syntax, skipping strings so a marker inside one is
-- not a comment. Adjacent line comments merge only when they open alike, so a doc comment and a plain
-- comment on the next line stay apart. ref:DEC-rust-grammar
scanCommentsWith :: CommentSyntax -> Text -> [Located Comment]
scanCommentsWith syntax source = mergeLineComments (docOpenerOf syntax) (go 0 source)
  where
    table = lineTable source
    go offset remaining
      | T.null remaining = []
      | otherwise = case firstMatch remaining of
          Just (Left len) -> go (offset + len) (T.drop len remaining)
          Just (Right (kind, len)) ->
            Located (spanBetween table offset (offset + len)) (Comment kind (T.take len remaining))
              : go (offset + len) (T.drop len remaining)
          Nothing -> go (offset + 1) (T.drop 1 remaining)
    firstMatch remaining =
      case [d | d <- commentStringDelimiters syntax, d `T.isPrefixOf` remaining] of
        (d : _) -> Just (Left (stringLength d remaining))
        [] -> case (commentLine syntax, commentBlockOpen syntax, commentBlockClose syntax) of
          (Just line, _, _) | line `T.isPrefixOf` remaining -> Just (Right (LineComment, lineLength remaining))
          (_, Just open, Just close) | open `T.isPrefixOf` remaining -> Just (Right (BlockComment, blockLength open close remaining))
          _ -> Nothing
    stringLength delimiter remaining = walk (T.length delimiter) (T.drop (T.length delimiter) remaining)
      where
        walk n s = case T.uncons s of
          Nothing -> n
          Just ('\\', rest) -> walk (n + 2) (T.drop 1 rest)
          Just ('\n', _) -> n
          Just _
            | delimiter `T.isPrefixOf` s -> n + T.length delimiter
            | otherwise -> walk (n + 1) (T.drop 1 s)
    lineLength remaining = T.length (T.takeWhile (\c -> c /= '\n' && c /= '\r') remaining)
    blockLength open close remaining =
      let (body, rest) = T.breakOn close (T.drop (T.length open) remaining)
       in T.length open + T.length body + (if T.null rest then 0 else T.length close)

-- | The longest doc-comment opener, outer or inner, that a comment's text starts with; a plain
-- comment has none.
docOpenerOf :: CommentSyntax -> Text -> Maybe Text
docOpenerOf syntax text =
  case sortOn (Down . T.length) [o | o <- commentOuterDoc syntax ++ commentInnerDoc syntax, o `T.isPrefixOf` T.stripStart text] of
    (o : _) -> Just o
    [] -> Nothing

mergeLineComments :: (Text -> Maybe Text) -> [Located Comment] -> [Located Comment]
mergeLineComments opener comments = case comments of
  (a : b : rest)
    | adjacentLines a b -> mergeLineComments opener (merged a b : rest)
    | otherwise -> a : mergeLineComments opener (b : rest)
  _ -> comments
  where
    adjacentLines a b =
      commentKind (locatedValue a) == LineComment
        && commentKind (locatedValue b) == LineComment
        && positionLine (spanEnd (locatedSpan a)) + 1 == positionLine (spanStart (locatedSpan b))
        && opener (commentText (locatedValue a)) == opener (commentText (locatedValue b))
    merged a b =
      Located
        (Span (spanStart (locatedSpan a)) (spanEnd (locatedSpan b)))
        (Comment LineComment (commentText (locatedValue a) <> "\n" <> commentText (locatedValue b)))
