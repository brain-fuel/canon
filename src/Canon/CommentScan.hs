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
import Data.Maybe (isJust)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | Scans line and block comments by the given syntax, skipping strings so a marker inside one is
-- not a comment. Adjacent line comments merge only when they open alike, so a doc comment and a plain
-- comment on the next line stay apart. Where the syntax joins doc comments across blank lines, as
-- Gleam does, doc comments that open alike and stand apart only by blank lines merge too.
-- ref:DEC-rust-grammar ref:DEC-gleam-grammar
--
-- A doc attribute followed by a string, or by an opening parenthesis or a sigil and a string, is a
-- block comment from the attribute to the end of the string, and a delimiter of three or more
-- characters may span lines, as an Elixir heredoc does. Inside a string, an interpolation the syntax
-- names runs to its closer, skipping the strings and braces nested in it, so a quote inside it does
-- not end the string. ref:DEC-elixir-grammar ref:DEC-erlang-grammar
scanCommentsWith :: CommentSyntax -> Text -> [Located Comment]
scanCommentsWith syntax source = mergeLineComments (docOpenerOf syntax) blankBetween (go 0 source)
  where
    sourceLines = T.lines source
    blankBetween from to =
      commentJoinAcrossBlankLines syntax
        && all (T.null . T.strip) (take (to - from - 1) (drop from sourceLines))
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
            | Just (open, close) <- commentInterpolation syntax, open `T.isPrefixOf` s ->
                let len = T.length open + interpolationLength open close (T.drop (T.length open) s)
                 in walk (n + len) (T.drop len s)
            | otherwise -> walk (n + 1) (T.drop 1 s)
    interpolationLength open close = skip (0 :: Int) 0
      where
        skip depth n s = case T.uncons s of
          Nothing -> n
          Just (c, rest)
            | (d : _) <- [d | d <- commentStringDelimiters syntax, d `T.isPrefixOf` s] ->
                let len = stringLength d s in skip depth (n + len) (T.drop len s)
            | depth == 0 && close `T.isPrefixOf` s -> n + T.length close
            | open `T.isPrefixOf` s -> skip (depth + 1) (n + T.length open) (T.drop (T.length open) s)
            | c == '{' -> skip (depth + 1) (n + 1) rest
            | c == '}' -> skip (depth - 1) (n + 1) rest
            | otherwise -> skip depth (n + 1) rest
    docAttributeLength remaining =
      case [a | a <- sortOn (Down . T.length) (commentDocAttributes syntax), a `T.isPrefixOf` remaining] of
        (attribute : _)
          | not (maybe False (identifierChar . fst) (T.uncons (T.drop (T.length attribute) remaining))) ->
              let afterAttribute = T.drop (T.length attribute) remaining
                  spaces = T.takeWhile (\c -> c == ' ' || c == '\t') afterAttribute
                  afterSpaces = T.drop (T.length spaces) afterAttribute
                  paren = openParen afterSpaces
                  afterParen = T.drop (T.length paren) afterSpaces
                  sigil = sigilPrefix afterParen
                  value = T.drop (T.length sigil) afterParen
                  prefix = T.length attribute + T.length spaces + T.length paren + T.length sigil
               in case [d | d <- commentStringDelimiters syntax, d `T.isPrefixOf` value] of
                    (d : _) | not (T.null spaces) || not (T.null paren) || not (T.null sigil) -> Just (prefix + stringLength d value)
                    _ -> Nothing
        _ -> Nothing
    identifierChar c = isAlphaNum c || c == '_' || c == '?' || c == '!'
    lineLength remaining = T.length (T.takeWhile (\c -> c /= '\n' && c /= '\r') remaining)
    blockLength open close remaining =
      let (body, rest) = T.breakOn close (T.drop (T.length open) remaining)
       in T.length open + T.length body + (if T.null rest then 0 else T.length close)

-- | A sigil's name, such as Elixir's ~S or Erlang's ~ and ~b, ahead of the string it quotes.
sigilPrefix :: Text -> Text
sigilPrefix t = case T.uncons t of
  Just ('~', rest) -> T.cons '~' (T.takeWhile isAlpha rest)
  _ -> T.empty

-- | An opening parenthesis and the spaces after it, as in Erlang's -doc("...").
openParen :: Text -> Text
openParen t = case T.uncons t of
  Just ('(', rest) -> T.cons '(' (T.takeWhile (\c -> c == ' ' || c == '\t') rest)
  _ -> T.empty

-- | The contents of a doc attribute's string, without the attribute, the sigil, or the delimiters,
-- and dedented, so the Why of an Elixir @doc is its prose; text that is no doc attribute is
-- returned unchanged. ref:DEC-elixir-grammar
docAttributeBody :: CommentSyntax -> Text -> Text
docAttributeBody syntax text =
  case [a | a <- sortOn (Down . T.length) (commentDocAttributes syntax), a `T.isPrefixOf` stripped] of
    (attribute : _) ->
      let afterAttribute = T.stripStart (T.drop (T.length attribute) stripped)
          afterParen = T.stripStart (maybe afterAttribute id (T.stripPrefix "(" afterAttribute))
          value = T.drop (T.length (sigilPrefix afterParen)) afterParen
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

mergeLineComments :: (Text -> Maybe Text) -> (Int -> Int -> Bool) -> [Located Comment] -> [Located Comment]
mergeLineComments opener blankBetween comments = case comments of
  (a : b : rest)
    | adjacentLines a b -> mergeLineComments opener blankBetween (merged a b : rest)
    | otherwise -> a : mergeLineComments opener blankBetween (b : rest)
  _ -> comments
  where
    endLine c = positionLine (spanEnd (locatedSpan c))
    startLine c = positionLine (spanStart (locatedSpan c))
    adjacentLines a b =
      commentKind (locatedValue a) == LineComment
        && commentKind (locatedValue b) == LineComment
        && (endLine a + 1 == startLine b || (isJust (opener (commentText (locatedValue a))) && blankBetween (endLine a) (startLine b)))
        && opener (commentText (locatedValue a)) == opener (commentText (locatedValue b))
    merged a b =
      Located
        (Span (spanStart (locatedSpan a)) (spanEnd (locatedSpan b)))
        (Comment LineComment (commentText (locatedValue a) <> T.replicate (startLine b - endLine a) "\n" <> commentText (locatedValue b)))
