-- | The scanners for the parts of a grammar file that are not context-free, such as actions and
-- character sets, so the grammar record stays declarative. ref:DEC-parser-foundation
module Canon.Antlr4.Lexical
  ( scanEscape
  , scanStringLiteral
  , scanDoubleQuoteLiteral
  , scanTripleQuoteLiteral
  , scanBacktickLiteral
  , scanAction
  , scanArgument
  , scanCharSet
  , scanBlockComment
  , scanLineComment
  , scanName
  , scanInt
  , isDocCommentStart
  , LineTable
  , lineTable
  , positionAt
  , spanBetween
  ) where

import Canon.Antlr4.Syntax (Position (..), Span (..), isNameChar, isNameStartChar)
import Control.Applicative ((<|>))
import Data.Char (isDigit, isHexDigit)
import qualified Data.IntMap.Strict as IntMap
import Data.Text (Text)
import qualified Data.Text as T

-- | Scans one escape sequence, the unit shared by literals and character sets.
scanEscape :: Text -> Maybe Int
scanEscape t = case T.uncons t of
  Just ('\\', rest) -> case T.uncons rest of
    Nothing -> Just 1
    Just ('u', afterU) -> Just (2 + T.length (T.take 4 (T.takeWhile isHexDigit afterU)))
    Just _ -> Just 2
  _ -> Nothing

scanQuoted :: Char -> Bool -> Text -> Maybe Int
scanQuoted quote allowNewline t = case T.uncons t of
  Just (c, rest) | c == quote -> go 1 rest
  _ -> Nothing
  where
    go n s = case T.uncons s of
      Nothing -> Nothing
      Just (c, rest)
        | c == quote -> Just (n + 1)
        | c == '\\' -> scanEscape s >>= \k -> go (n + k) (T.drop k s)
        | not allowNewline && (c == '\r' || c == '\n') -> Nothing
        | otherwise -> go (n + 1) rest

-- | Scans a single-quoted literal, respecting escapes so a quote inside one does not end it.
scanStringLiteral :: Text -> Maybe Int
scanStringLiteral = scanQuoted '\'' False

-- | Scans a double-quoted literal inside an action, so its braces do not count as nesting.
scanDoubleQuoteLiteral :: Text -> Maybe Int
scanDoubleQuoteLiteral = scanQuoted '"' False

-- | Scans a backtick literal inside an action, for the same reason.
scanBacktickLiteral :: Text -> Maybe Int
scanBacktickLiteral = scanQuoted '`' False

-- | Scans a triple-quoted literal inside an action, trying the shorter reading first because ANTLR
-- is non-greedy here.
scanTripleQuoteLiteral :: Text -> Maybe Int
scanTripleQuoteLiteral t
  | "\"\"\"" `T.isPrefixOf` t = go 3 (T.drop 3 t)
  | otherwise = Nothing
  where
    go n s
      | T.null s = Nothing
      | "\"\"\"" `T.isPrefixOf` s = Just (n + 3)
      | T.head s == '\\' = scanEscape s >>= \k -> go (n + k) (T.drop k s)
      | otherwise = go (n + 1) (T.tail s)

-- | Scans a braced action to its matching brace, skipping strings and comments as ANTLR does.
scanAction :: Text -> Maybe Int
scanAction t = case T.uncons t of
  Just ('{', rest) -> go 1 rest
  _ -> Nothing
  where
    go n s = case T.uncons s of
      Nothing -> Nothing
      Just (c, rest) -> case c of
        '}' -> Just (n + 1)
        '{' -> continueWith (scanAction s)
        '\'' -> continueWith (scanStringLiteral s)
        '"' -> shortest (continueWith (scanTripleQuoteLiteral s)) (continueWith (scanDoubleQuoteLiteral s))
        '`' -> continueWith (scanBacktickLiteral s)
        '/'
          | "/*" `T.isPrefixOf` s, Just k <- scanTerminatedBlockComment s -> go (n + k) (T.drop k s)
          | "//" `T.isPrefixOf` s -> let k = scanLineComment s in go (n + k) (T.drop k s)
          | otherwise -> go (n + 1) rest
        '\\' -> case T.uncons rest of
          Nothing -> Nothing
          Just _ -> go (n + 2) (T.tail rest)
        _ -> go (n + 1) rest
      where
        continueWith m = m >>= \k -> go (n + k) (T.drop k s)
    shortest a b = case (a, b) of
      (Just x, Just y) -> Just (min x y)
      _ -> a <|> b

scanTerminatedBlockComment :: Text -> Maybe Int
scanTerminatedBlockComment t
  | "/*" `T.isPrefixOf` t =
      let (body, rest) = T.breakOn "*/" (T.drop 2 t)
       in if T.null rest then Nothing else Just (2 + T.length body + 2)
  | otherwise = Nothing

-- | Scans a bracketed argument block to its matching bracket.
scanArgument :: Text -> Maybe Int
scanArgument t = case T.uncons t of
  Just ('[', rest) -> go 1 rest
  _ -> Nothing
  where
    go n s = case T.uncons s of
      Nothing -> Nothing
      Just (c, rest) -> case c of
        ']' -> Just (n + 1)
        '[' -> scanArgument s >>= \k -> go (n + k) (T.drop k s)
        '\\' -> case T.uncons rest of
          Nothing -> Nothing
          Just _ -> go (n + 2) (T.tail rest)
        '"' -> orSingle (scanDoubleQuoteLiteral s)
        '\'' -> orSingle (scanStringLiteral s)
        _ -> go (n + 1) rest
      where
        orSingle m = case m of
          Just k -> go (n + k) (T.drop k s)
          Nothing -> go (n + 1) (T.tail s)

-- | Scans a bracketed character set, where a closing bracket may be escaped.
scanCharSet :: Text -> Maybe Int
scanCharSet t = case T.uncons t of
  Just ('[', rest) -> go 1 rest
  _ -> Nothing
  where
    go n s = case T.uncons s of
      Nothing -> Nothing
      Just (c, rest) -> case c of
        ']' -> Just (n + 1)
        '\\' -> case T.uncons rest of
          Nothing -> Nothing
          Just _ -> go (n + 2) (T.tail rest)
        _ -> go (n + 1) rest

-- | Tells a doc comment opener from a block comment opener, because only doc comments are canonical.
isDocCommentStart :: Text -> Bool
isDocCommentStart t = "/**" `T.isPrefixOf` t && not ("/**/" `T.isPrefixOf` t)

-- | Scans a block comment to its closer.
scanBlockComment :: Text -> Maybe Int
scanBlockComment t
  | "/*" `T.isPrefixOf` t =
      let (body, rest) = T.breakOn "*/" (T.drop 2 t)
       in Just (2 + T.length body + (if T.null rest then 0 else 2))
  | otherwise = Nothing

-- | Scans a line comment to the end of the line.
scanLineComment :: Text -> Int
scanLineComment t
  | "//" `T.isPrefixOf` t = 2 + T.length (T.takeWhile (\c -> c /= '\r' && c /= '\n') (T.drop 2 t))
  | otherwise = 0

-- | Scans an identifier.
scanName :: Text -> Maybe Int
scanName t = case T.uncons t of
  Just (c, rest) | isNameStartChar c -> Just (1 + T.length (T.takeWhile isNameChar rest))
  _ -> Nothing

-- | Scans an integer.
scanInt :: Text -> Maybe Int
scanInt t = case T.uncons t of
  Just ('0', _) -> Just 1
  Just (c, rest) | isDigit c -> Just (1 + T.length (T.takeWhile isDigit rest))
  _ -> Nothing

-- | Line start offsets, so offsets become positions in constant time.
newtype LineTable = LineTable (IntMap.IntMap Int)

-- | Builds the line table for a text once.
lineTable :: Text -> LineTable
lineTable = LineTable . IntMap.fromList . zip' . go 0 . T.unpack
  where
    zip' starts = zip starts [1 ..]
    go offset s = offset : case s of
      [] -> []
      ('\r' : '\n' : rest) -> go (offset + 2) rest
      ('\r' : rest) -> go (offset + 1) rest
      ('\n' : rest) -> go (offset + 1) rest
      (_ : rest) -> skipToBreak (offset + 1) rest
    skipToBreak offset s = case s of
      [] -> []
      ('\r' : '\n' : rest) -> go (offset + 2) rest
      ('\r' : rest) -> go (offset + 1) rest
      ('\n' : rest) -> go (offset + 1) rest
      (_ : rest) -> skipToBreak (offset + 1) rest

-- | Converts an offset to a line and column using the table.
positionAt :: LineTable -> Int -> Position
positionAt (LineTable starts) offset = case IntMap.lookupLE offset starts of
  Just (lineStart, line) -> Position line (offset - lineStart + 1)
  Nothing -> Position 1 (offset + 1)

-- | Builds the span between two offsets.
spanBetween :: LineTable -> Int -> Int -> Span
spanBetween table start end = Span (positionAt table start) (positionAt table end)
