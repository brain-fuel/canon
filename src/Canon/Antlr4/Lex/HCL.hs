-- | HCL ends an attribute at a line break except inside brackets, closes a heredoc at a line that
-- holds only its delimiter word, and has no doc comment syntax, so a comment documents the block
-- directly below it. No context-free lexer sees any of these, and this hook, selected by the
-- grammar's HCLLexerBase superClass, supplies them: it hides line breaks inside parentheses,
-- brackets, and interpolations; it records each heredoc's delimiter and closes the heredoc at it;
-- and it hides a comment that is not the first thing on its line or that sits inside brackets,
-- and the line break between a comment line and the line directly below it, so the parser sees a
-- comment group joined to what it documents. ref:DEC-hcl-grammar
module Canon.Antlr4.Lex.HCL
  ( HCLLexerState (..)
  , hclLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText, Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: the open brackets, innermost first, by token type; the delimiter words of the
-- open heredocs, innermost first, and whether the heredoc text being read starts its line; whether
-- a comment is being read and whether it is hidden; the line on which the last visible token other
-- than a line break ends; whether the current line holds code or a visible comment; and the line
-- break held back until the next token shows whether it parts a comment from what follows, with
-- whether its line held only a comment; and the type of the last code token.
data HCLLexerState = HCLLexerState
  { brackets :: [Text]
  , heredocs :: [Text]
  , heredocLineStart :: Bool
  , comment :: Maybe Bool
  , lastLine :: Int
  , lineCode :: Bool
  , lineComment :: Bool
  , pending :: Maybe (Token, Bool)
  , lastCode :: Text
  }
  deriving (Eq, Show)

-- | The hooks for the HCL grammar and its dialect.
hclLexerHooks :: LexerHooks HCLLexerState
hclLexerHooks = LexerHooks (HCLLexerState [] [] False Nothing 0 False False Nothing "") onAction onEmit

-- | Records a heredoc's delimiter when it opens, and closes the heredoc at a line that starts with
-- the delimiter and holds nothing else.
onAction :: Name -> ActionText -> Text -> HCLLexerState -> (HCLLexerState, [HookEffect])
onAction rule _ matched s = case nameText rule of
  "HEREDOC_OPEN" -> (s {heredocs = delimiter : heredocs s, heredocLineStart = True}, [])
  "HEREDOC_TEXT" -> case heredocs s of
    (word : rest)
      | heredocLineStart s && T.strip matched == word ->
          (s {heredocs = rest}, [EffectPopMode, EffectSetType (Name "HEREDOC_CLOSE")])
    _ -> (s, [])
  _ -> (s, [])
  where
    delimiter = T.takeWhile (\c -> isAlphaNum c || c == '_' || c == '-') (T.dropWhile (`elem` ("<-" :: String)) matched)

-- | Routes each token by what it is: a line break, a comment token, or code.
onEmit :: Token -> HCLLexerState -> ([Token], HCLLexerState)
onEmit token s0
  | tokenChannel token /= defaultChannelName = ([token], s0)
  | isEofToken token = (flushVisible s0 ++ [token], s0 {pending = Nothing})
  | ty == "NEWLINE" = newline token s
  | ty `elem` ["DOC_OPEN", "DOC_BLOCK_OPEN"] = opening token s
  | ty `elem` ["DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE"] = inside token s
  | ty == "DOC_BLOCK_CLOSE" = let (out, s') = inside token s in (out, s' {comment = Nothing})
  | otherwise = code token s
  where
    ty = nameText (tokenType token)
    s = s0 {heredocLineStart = ty `elem` ["HEREDOC_OPEN", "HEREDOC_NEWLINE"]}

-- | A line break ends a line comment. Inside brackets, or directly after an opening brace, it is
-- hidden; elsewhere it is held back.
newline :: Token -> HCLLexerState -> ([Token], HCLLexerState)
newline token s
  | insideBrackets s || lastCode s == "LBRACE" = ([hidden token], ended)
  | otherwise =
      ( flushVisible s
      , ended {pending = Just (token, lineComment s && not (lineCode s)), lineCode = False, lineComment = False}
      )
  where
    ended = s {comment = Nothing}

-- | A comment is hidden inside brackets or after code on its line. A visible comment directly
-- below a comment line joins it, so the held line break between them is hidden.
opening :: Token -> HCLLexerState -> ([Token], HCLLexerState)
opening token s =
  let hide = insideBrackets s || line token <= lastLine s
      held = release token s
   in if hide
        then (held ++ [hidden token], s {pending = Nothing, comment = Just True})
        else (held ++ [token], s {pending = Nothing, comment = Just False, lineComment = True, lastLine = endLine token})

-- | A token inside a comment shares the comment's visibility.
inside :: Token -> HCLLexerState -> ([Token], HCLLexerState)
inside token s = case comment s of
  Just True -> ([hidden token], s)
  _ -> ([token], s {lastLine = endLine token})

-- | Code directly below a comment line binds that comment, so the held line break is hidden.
-- Brackets are tracked so that line breaks inside them can be hidden; a brace whose first token is
-- for opens an object for expression, inside which HCL ignores line breaks too.
code :: Token -> HCLLexerState -> ([Token], HCLLexerState)
code token s =
  (release token s ++ [token], s {pending = Nothing, brackets = brackets', lineCode = True, lastLine = endLine token, lastCode = ty})
  where
    ty = nameText (tokenType token)
    brackets'
      | ty `elem` ["LPAREN", "LBRACK", "LBRACE", "TEMPLATE_INTERP", "TEMPLATE_DIRECTIVE"] = ty : brackets s
      | ty `elem` ["RPAREN", "RBRACK", "RBRACE"] = drop 1 (brackets s)
      | ty == "IDENTIFIER" && tokenText token == "for" && lastCode s == "LBRACE" = "FOR_BRACE" : drop 1 (brackets s)
      | otherwise = brackets s

-- | The held line break before a token on the next line: hidden when its line held only a
-- comment, so the comment joins that token, and visible otherwise.
release :: Token -> HCLLexerState -> [Token]
release token s = case pending s of
  Just (held, commentOnly)
    | commentOnly && line token == line held + 1 -> [hidden held]
    | otherwise -> [held]
  Nothing -> []

-- | The held line break, visible, when a blank line or the end of input follows it.
flushVisible :: HCLLexerState -> [Token]
flushVisible s = maybe [] (\(held, _) -> [held]) (pending s)

-- | Line breaks and comments inside parentheses, brackets, and interpolations are not structure.
insideBrackets :: HCLLexerState -> Bool
insideBrackets s = case brackets s of
  (top : _) -> top `elem` ["LPAREN", "LBRACK", "TEMPLATE_INTERP", "TEMPLATE_DIRECTIVE", "FOR_BRACE"]
  [] -> False

-- | A token moved to the hidden channel.
hidden :: Token -> Token
hidden token = token {tokenChannel = hiddenChannelName}

-- | The line a token starts on.
line :: Token -> Int
line = positionLine . tokenPosition

-- | The line a token ends on, which is later than its first for a token holding a line break.
endLine :: Token -> Int
endLine token = line token + T.count "\n" (T.dropEnd 1 (tokenText token))
