module Canon.Antlr4.Escape
  ( EscapeError (..)
  , CharSetItem (..)
  , decodeStringLiteral
  , encodeStringLiteral
  , decodeCharSet
  , isWellFormedStringLiteralRaw
  , isWellFormedCharSetRaw
  , isWellFormedActionRaw
  , isWellFormedArgumentRaw
  ) where

import Canon.Antlr4.Lexical (scanAction, scanArgument, scanCharSet, scanStringLiteral)
import Canon.Antlr4.Syntax (CharSet (..), StringLiteral (..))
import Data.Char (chr, isHexDigit, ord)
import Data.Text (Text)
import qualified Data.Text as T
import Numeric (readHex, showHex)

data EscapeError
  = InvalidEscape Text
  | UnterminatedEscape
  | CodePointOutOfRange Integer
  | InvalidRange Char Char
  deriving (Eq, Show)

data CharSetItem
  = CharSetSingle Char
  | CharSetRange Char Char
  | CharSetProperty Bool Text
  deriving (Eq, Show)

decodeStringLiteral :: StringLiteral -> Either EscapeError Text
decodeStringLiteral (StringLiteral raw) = T.pack <$> go raw
  where
    go t = case T.uncons t of
      Nothing -> Right []
      Just ('\\', rest) -> do
        (c, remaining) <- decodeOneEscape rest
        (c :) <$> go remaining
      Just (c, rest) -> (c :) <$> go rest

decodeOneEscape :: Text -> Either EscapeError (Char, Text)
decodeOneEscape t = case T.uncons t of
  Nothing -> Left UnterminatedEscape
  Just (c, rest) -> case c of
    'b' -> Right ('\b', rest)
    't' -> Right ('\t', rest)
    'n' -> Right ('\n', rest)
    'f' -> Right ('\f', rest)
    'r' -> Right ('\r', rest)
    '"' -> Right ('"', rest)
    '\'' -> Right ('\'', rest)
    '\\' -> Right ('\\', rest)
    'u' -> decodeUnicodeEscape rest
    _ -> Left (InvalidEscape (T.cons '\\' (T.take 1 t)))

decodeUnicodeEscape :: Text -> Either EscapeError (Char, Text)
decodeUnicodeEscape t = case T.uncons t of
  Just ('{', rest) ->
    let (digits, afterDigits) = T.span isHexDigit rest
     in case T.uncons afterDigits of
          Just ('}', remaining) | not (T.null digits) -> (,remaining) <$> codePoint digits
          _ -> Left (InvalidEscape (T.pack "\\u{"))
  _ ->
    let digits = T.take 4 t
     in if T.length digits == 4 && T.all isHexDigit digits
          then (,T.drop 4 t) <$> codePoint digits
          else Left (InvalidEscape (T.append (T.pack "\\u") digits))

codePoint :: Text -> Either EscapeError Char
codePoint digits = case readHex (T.unpack digits) of
  [(n, "")]
    | n <= 0x10FFFF -> Right (chr (fromInteger n))
    | otherwise -> Left (CodePointOutOfRange n)
  _ -> Left (InvalidEscape digits)

encodeStringLiteral :: Text -> StringLiteral
encodeStringLiteral = StringLiteral . T.concatMap encodeChar
  where
    encodeChar c = case c of
      '\'' -> "\\'"
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      '\b' -> "\\b"
      '\f' -> "\\f"
      _
        | ord c < 0x20 || ord c == 0x7F -> T.pack ("\\u" ++ pad4 (showHex (ord c) ""))
        | ord c > 0xFFFF -> T.pack ("\\u{" ++ showHex (ord c) "}")
        | otherwise -> T.singleton c
    pad4 s = replicate (4 - length s) '0' ++ s

decodeCharSet :: CharSet -> Either EscapeError [CharSetItem]
decodeCharSet (CharSet raw) = do
  atoms <- go raw
  ranges atoms
  where
    go t = case T.uncons t of
      Nothing -> Right []
      Just ('\\', rest) -> case T.uncons rest of
        Nothing -> Left UnterminatedEscape
        Just (']', remaining) -> (Left ']' :) <$> go remaining
        Just ('-', remaining) -> (Left '-' :) <$> go remaining
        Just (p, remaining) | p == 'p' || p == 'P' -> do
          (name, afterName) <- propertyName remaining
          (Right (CharSetProperty (p == 'p') name) :) <$> go afterName
        Just _ -> do
          (c, remaining) <- decodeOneEscape rest
          (Left c :) <$> go remaining
      Just ('-', rest) -> (Right (CharSetSingle '-') :) <$> go rest
      Just (c, rest) -> (Left c :) <$> go rest
    propertyName t = case T.uncons t of
      Just ('{', rest) ->
        let (name, afterName) = T.breakOn "}" rest
         in if T.null afterName then Left (InvalidEscape "\\p{") else Right (name, T.drop 1 afterName)
      _ -> Left (InvalidEscape "\\p")
    ranges atoms = case atoms of
      [] -> Right []
      (Left lo : Right (CharSetSingle '-') : Left hi : rest)
        | lo <= hi -> (CharSetRange lo hi :) <$> ranges rest
        | otherwise -> Left (InvalidRange lo hi)
      (Left c : rest) -> (CharSetSingle c :) <$> ranges rest
      (Right item : rest) -> (item :) <$> ranges rest

isWellFormedStringLiteralRaw :: Text -> Bool
isWellFormedStringLiteralRaw t = scanStringLiteral (T.concat ["'", t, "'"]) == Just (T.length t + 2)

isWellFormedCharSetRaw :: Text -> Bool
isWellFormedCharSetRaw t = scanCharSet (T.concat ["[", t, "]"]) == Just (T.length t + 2)

isWellFormedActionRaw :: Text -> Bool
isWellFormedActionRaw t = scanAction (T.concat ["{", t, "}"]) == Just (T.length t + 2)

isWellFormedArgumentRaw :: Text -> Bool
isWellFormedArgumentRaw t = scanArgument (T.concat ["[", t, "]"]) == Just (T.length t + 2)
