-- | Comments are scanned by a profile's syntax for languages without a dialect, so attachment can
-- run without the grammar knowing about comments. ref:DEC-comment-attachment
module Canon.CommentScan
  ( scanCommentsWith
  , docOpenerOf
  , docAttributeBody
  ) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Lexical (lineTable, spanBetween)
import Canon.Profile (CommentSyntax (..))
import Canon.Span (Located (..), Position (..), Span (..))
import Data.Char (isAlpha, isAlphaNum)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | Scans line and block comments by the given syntax, skipping strings so a marker inside one is
-- not a comment. Adjacent line comments merge only when they open alike, so a doc comment and a plain
-- comment on the next line stay apart. ref:DEC-rust-grammar
--
-- A doc attribute followed by a string is a block comment from the attribute to the end of the
-- string, and a delimiter of three or more characters may span lines, as an Elixir heredoc does.
-- ref:DEC-elixir-grammar
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
        [] | Just len <- docAttributeLength remaining -> Just (Right (BlockComment, len))
        [] -> case (commentLine syntax, commentBlockOpen syntax, commentBlockClose syntax) of
          (Just line, _, _) | line `T.isPrefixOf` remaining -> Just (Right (LineComment, lineLength remaining))
          (_, Just open, Just close) | open `T.isPrefixOf` remaining -> Just (Right (BlockComment, blockLength open close remaining))
          _ -> Nothing
    stringLength delimiter remaining = walk (T.length delimiter) (T.drop (T.length delimiter) remaining)
      where
        walk n s = case T.uncons s of
          Nothing -> n
          Just ('\\', rest) -> walk (n + 2) (T.drop 1 rest)
          Just ('\n', _) | T.length delimiter < 3 -> n
          Just _
            | delimiter `T.isPrefixOf` s -> n + T.length delimiter
            | otherwise -> walk (n + 1) (T.drop 1 s)
    docAttributeLength remaining =
      case [a | a <- sortOn (Down . T.length) (commentDocAttributes syntax), a `T.isPrefixOf` remaining] of
        (attribute : _)
          | not (maybe False (identifierChar . fst) (T.uncons (T.drop (T.length attribute) remaining))) ->
              let afterAttribute = T.drop (T.length attribute) remaining
                  spaces = T.takeWhile (\c -> c == ' ' || c == '\t') afterAttribute
                  afterSpaces = T.drop (T.length spaces) afterAttribute
                  sigil = sigilPrefix afterSpaces
                  value = T.drop (T.length sigil) afterSpaces
               in case [d | d <- commentStringDelimiters syntax, d `T.isPrefixOf` value] of
                    (d : _) | not (T.null spaces) || not (T.null sigil) -> Just (T.length attribute + T.length spaces + T.length sigil + stringLength d value)
                    _ -> Nothing
        _ -> Nothing
    identifierChar c = isAlphaNum c || c == '_' || c == '?' || c == '!'
    lineLength remaining = T.length (T.takeWhile (\c -> c /= '\n' && c /= '\r') remaining)
    blockLength open close remaining =
      let (body, rest) = T.breakOn close (T.drop (T.length open) remaining)
       in T.length open + T.length body + (if T.null rest then 0 else T.length close)

-- | A sigil's name, such as ~S, ahead of the string it quotes.
sigilPrefix :: Text -> Text
sigilPrefix t = case T.uncons t of
  Just ('~', rest) | letters <- T.takeWhile isAlpha rest, not (T.null letters) -> T.cons '~' letters
  _ -> T.empty

-- | The contents of a doc attribute's string, without the attribute, the sigil, or the delimiters,
-- and dedented, so the Why of an Elixir @doc is its prose; text that is no doc attribute is
-- returned unchanged. ref:DEC-elixir-grammar
docAttributeBody :: CommentSyntax -> Text -> Text
docAttributeBody syntax text =
  case [a | a <- sortOn (Down . T.length) (commentDocAttributes syntax), a `T.isPrefixOf` stripped] of
    (attribute : _) ->
      let afterAttribute = T.stripStart (T.drop (T.length attribute) stripped)
          value = T.drop (T.length (sigilPrefix afterAttribute)) afterAttribute
       in case [d | d <- sortOn (Down . T.length) (commentStringDelimiters syntax), d `T.isPrefixOf` value] of
            (d : _) ->
              let inside = T.drop (T.length d) value
                  body = maybe inside id (T.stripSuffix d (T.stripEnd inside))
               in dedent body
            [] -> text
    [] -> text
  where
    stripped = T.stripStart text
    dedent body =
      let ls = T.lines body
          indents = [T.length (T.takeWhile (== ' ') l) | l <- ls, not (T.null (T.strip l))]
          margin = if null indents then 0 else minimum indents
       in T.strip (T.intercalate "\n" [T.stripEnd (T.drop margin l) | l <- ls])

-- | The longest doc-comment opener, outer or inner, that a comment's text starts with; a plain
-- comment has none. An opener followed by a slash, or one ending in a star followed by another, opens
-- a plain comment, as ////, /**/, and /*** do in Rust and C#, so commented-out documentation and
-- banners are not documentation.
-- ref:DEC-rust-grammar ref:DEC-csharp-grammar
docOpenerOf :: CommentSyntax -> Text -> Maybe Text
docOpenerOf syntax text =
  case sortOn (Down . T.length) [o | o <- commentOuterDoc syntax ++ commentInnerDoc syntax, opens o (T.stripStart text)] of
    (o : _) -> Just o
    [] -> Nothing
  where
    opens o t = case T.stripPrefix o t of
      Just rest -> case T.uncons rest of
        Just (c, _) -> c /= '/' && not ("*" `T.isSuffixOf` o && c == '*')
        Nothing -> True
      Nothing -> False

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
