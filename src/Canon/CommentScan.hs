module Canon.CommentScan
  ( scanCommentsWith
  ) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Lexical (lineTable, spanBetween)
import Canon.Profile (CommentSyntax (..))
import Canon.Span (Located (..), Position (..), Span (..))
import Data.Text (Text)
import qualified Data.Text as T

scanCommentsWith :: CommentSyntax -> Text -> [Located Comment]
scanCommentsWith syntax source = mergeLineComments (go 0 source)
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

mergeLineComments :: [Located Comment] -> [Located Comment]
mergeLineComments comments = case comments of
  (a : b : rest)
    | adjacentLines a b -> mergeLineComments (merged a b : rest)
    | otherwise -> a : mergeLineComments (b : rest)
  _ -> comments
  where
    adjacentLines a b =
      commentKind (locatedValue a) == LineComment
        && commentKind (locatedValue b) == LineComment
        && positionLine (spanEnd (locatedSpan a)) + 1 == positionLine (spanStart (locatedSpan b))
    merged a b =
      Located
        (Span (spanStart (locatedSpan a)) (spanEnd (locatedSpan b)))
        (Comment LineComment (commentText (locatedValue a) <> "\n" <> commentText (locatedValue b)))
