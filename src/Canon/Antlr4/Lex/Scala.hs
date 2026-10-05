-- | Scala 3 lets indentation stand for braces, and the grammars-v4 Scala 3 lexer leaves the INDENT
-- and DEDENT tokens, and which line breaks separate statements, to a Java base lexer modelled on the
-- Dotty scanner. This is that base lexer, Scala3LexerBase, ported as a hook selected by the
-- grammar's superClass. It keeps a stack of regions, top level, indented block, braces, and
-- parentheses or brackets, and at each line break compares the next line's indentation with the
-- innermost indented block. ref:DEC-scala-indentation ref:scala3-indentation
module Canon.Antlr4.Lex.Scala
  ( ScalaLayout (..)
  , Region (..)
  , Pending (..)
  , scalaLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | A region the layout is inside: the file, an indented block, braces, or parentheses and brackets,
-- inside which line breaks never separate statements.
data Region = TopLevel | Indented | InBraces | InParens
  deriving (Eq, Show)

-- | A line break waiting for the first code token of the next line, which decides what it is, with
-- the whitespace that starts that line and any hidden tokens after it.
data Pending = Pending
  { pendingBreak :: Token
  , pendingSpace :: Maybe Token
  , pendingHidden :: [Token]
  }
  deriving (Eq, Show)

-- | The hook state: the regions, innermost first; the indentation of each open indented block above
-- the file's, innermost first; the type and end of the last token on the default channel; whether a
-- code token has been read; the pending line break; and the doc-comment tokens of the dialect held
-- until the next code token.
data ScalaLayout = ScalaLayout
  { regions :: [Region]
  , indents :: [Int]
  , lastType :: Text
  , lastEnd :: Maybe (Int, Position)
  , started :: Bool
  , pending :: Maybe Pending
  , docs :: [Token]
  }
  deriving (Eq, Show)

-- | The hooks for the Scala 3 grammar. The upstream class reads one token ahead; the port holds a
-- line break until the next code token arrives instead. Every layout token, a NEWLINE that
-- separates statements as much as an INDENT or a DEDENT, is empty and placed where the last code
-- token ends, and the source's own line breaks and indentation are hidden, so the stream stays in
-- source order. The file's own indentation is its first code token's column rather than the first
-- column, so a file indented as a whole reads as one that is not. ref:DEC-scala-indentation
scalaLexerHooks :: LexerHooks ScalaLayout
scalaLexerHooks = LexerHooks (ScalaLayout [TopLevel] [0] "" Nothing False Nothing []) (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) onEmit

-- | The tokens of a doc comment in the canonically commented dialect. A line holding only a doc
-- comment is blank to the layout, as a line holding only a plain comment is, and the comment is
-- emitted just before the next code token, after its layout tokens, so it sits right before the
-- definition it documents. ref:DEC-scala-dialect
docTypes :: [Text]
docTypes = ["DOC_OPEN", "DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE", "DOC_CLOSE"]

-- | Emits a token with the layout tokens before it: a line break is held until the first code token
-- of the next line decides it, a doc comment until the next code token, and a code token first
-- resolves the held line break and then opens or closes the regions it delimits.
-- ref:DEC-scala-indentation
onEmit :: Token -> ScalaLayout -> ([Token], ScalaLayout)
onEmit token s
  | isEofToken token =
      let (layout, s1) = maybe ([], s) (\p -> resolve token p s) (pending s)
          (closing, s2) = drain s1
       in (layout ++ closing ++ docs s ++ heldHidden (pending s) ++ [token], s2 {pending = Nothing, docs = []})
  | ty == "NEWLINE" && tokenChannel token == defaultChannelName =
      if not (started s)
        then ([hide token], s)
        else case pending s of
          Nothing -> ([], s {pending = Just (Pending token Nothing [])})
          Just p -> (heldHidden (Just p), s {pending = Just (Pending token Nothing [])})
  | tokenChannel token /= defaultChannelName = case pending s of
      Just p
        | ty == "WS", Nothing <- pendingSpace p, null (pendingHidden p) -> ([], s {pending = Just p {pendingSpace = Just token}})
        | otherwise -> ([], s {pending = Just p {pendingHidden = pendingHidden p ++ [token]}})
      Nothing -> ([token], s)
  | ty `elem` docTypes = ([], s {docs = docs s ++ [token]})
  | not (started s) = onEmit token s {started = True, indents = [positionColumn (tokenPosition token) - 1]}
  | otherwise =
      let (layout, s1) = maybe ([], s) (\p -> resolve token p s) (pending s)
          (before, s2) = structural ty s1
       in ( layout ++ before ++ docs s ++ heldHidden (pending s) ++ [token]
          , s2 {lastType = ty, lastEnd = Just (tokenEnd token, endPosition token), started = True, pending = Nothing, docs = []}
          )
  where
    ty = nameText (tokenType token)

-- | The source's line break and the whitespace and comments after it, hidden.
heldHidden :: Maybe Pending -> [Token]
heldHidden = maybe [] (\p -> map hide (pendingBreak p : maybe [] pure (pendingSpace p) ++ pendingHidden p))

-- | Decides a line break once the first code token of the next line is known, as Scala3LexerBase's
-- handleNewlineToken does: a line right of the innermost indented block after a token that may open
-- one, or after a closing parenthesis outside brackets and braces, as an extension's parameters end,
-- opens a block with INDENT; a line left of it closes blocks with DEDENT; and a NEWLINE separates
-- statements where the previous token can end one, the next can start one and does not continue it,
-- and no parenthesis is open. A line starting with a dot continues a method chain.
-- ref:DEC-scala-indentation
resolve :: Token -> Pending -> ScalaLayout -> ([Token], ScalaLayout)
resolve next p s
  | newIndent < current =
      let (dedents, s1) = dedentTo newIndent s0
          ended = if null dedents then lastType s0 else "DEDENT"
          top' = headOr TopLevel (regions s1)
          again = top' /= InParens && separates ended
       in (newline ++ dedents ++ [virtual s "NEWLINE" | again], s1 {lastType = if again then "NEWLINE" else ended})
  | willIndent = (newline ++ [virtual s "INDENT"], s0 {regions = Indented : regions s0, indents = newIndent : indents s0, lastType = "INDENT"})
  | otherwise = (newline, s0)
  where
    nextType = nameText (tokenType next)
    newIndent
      | isEofToken next = 0
      | otherwise = maybe 0 (indentLength . tokenText) (pendingSpace p)
    current = headOr 0 (indents s)
    top = headOr TopLevel (regions s)
    isDot = nextType == "DOT"
    rparenOpens = lastType s == "RPAREN" && top `notElem` [InParens, InBraces] && nextType `notElem` ["EXTENDS", "WITH"]
    willIndent = newIndent > current && not isDot && (canStartIndent (lastType s) || rparenOpens)
    separates previous =
      not isDot
        && not (isEofToken next)
        && nextType /= "RBRACE"
        && canEndStat previous
        && canStartStat nextType
        && not (isStatContinuation nextType)
    surface
      | newIndent < current || willIndent = False
      | top == InParens = False
      | top == InBraces = not isDot && canEndStat (lastType s) && canStartStat nextType && not (isStatContinuation nextType)
      | newIndent > current = False
      | otherwise = separates (lastType s)
    newline = [virtual s "NEWLINE" | surface]
    s0 = if surface then s {lastType = "NEWLINE"} else s

-- | The regions a code token opens or closes. A comma or a closing parenthesis or bracket first closes
-- the indented blocks opened inside the brackets it belongs to, as a lambda's body passed as an
-- argument is. The upstream class closes the indented blocks on top of the stack whatever lies below
-- them, which ended an indented enum body at the comma of case A, B; the port closes them only when
-- brackets enclose them. ref:DEC-scala-indentation
structural :: Text -> ScalaLayout -> ([Token], ScalaLayout)
structural ty s
  | ty `elem` ["LPAREN", "LBRACKET"] = ([], s {regions = InParens : regions s})
  | ty == "COMMA" = drainInParens s
  | ty `elem` ["RPAREN", "RBRACKET"] =
      let (dedents, s1) = drainInParens s
       in (dedents, s1 {regions = popIf InParens (regions s1)})
  | ty == "LBRACE" = ([], s {regions = InBraces : regions s})
  | ty == "RBRACE" = ([], s {regions = popIf InBraces (regions s)})
  | otherwise = ([], s)
  where
    popIf r rs = case rs of
      (r' : rest) | r' == r -> rest
      _ -> rs

-- | Closes every indented block on top of the region stack.
drain :: ScalaLayout -> ([Token], ScalaLayout)
drain = dedentTo (-1)

-- | Closes the indented blocks on top of the region stack when brackets lie right below them.
drainInParens :: ScalaLayout -> ([Token], ScalaLayout)
drainInParens s = case dropWhile (== Indented) (regions s) of
  (InParens : _) -> drain s
  _ -> ([], s)

-- | Closes the indented blocks on top of the region stack deeper than an indentation.
dedentTo :: Int -> ScalaLayout -> ([Token], ScalaLayout)
dedentTo column = go []
  where
    go acc s = case (regions s, indents s) of
      (Indented : rs, i : is) | i > column -> go (virtual s "DEDENT" : acc) s {regions = rs, indents = is, lastType = "DEDENT"}
      _ -> (acc, s)

-- | The tokens that can end a statement: Dotty's canEndStatTokens, with the keywords an end marker
-- may name.
canEndStat :: Text -> Bool
canEndStat t =
  t
    `elem` [ "Id", "Varid", "BacktickId", "Op", "IntegerLiteral", "FloatingPointLiteral", "BooleanLiteral", "CharacterLiteral"
           , "StringLiteral", "InterpolatedStringLiteral", "SymbolLiteral", "NullLiteral", "QuoteId", "USCORE", "THIS", "SUPER"
           , "RETURN", "TYPE", "GIVEN", "RPAREN", "RBRACE", "RBRACKET", "DEDENT", "NEWLINE"
           , "IF", "WHILE", "FOR", "MATCH", "TRY", "VAL", "NEW", "EXTENSION"
           ]

-- | The tokens that continue a statement on the next line: Dotty's isStatCtdTokens.
isStatContinuation :: Text -> Bool
isStatContinuation t = t `elem` ["THEN", "ELSE", "DO", "CATCH", "FINALLY", "YIELD", "MATCH"]

-- | The tokens that can start a statement: Dotty's canStartStatTokens, with the soft keywords.
canStartStat :: Text -> Bool
canStartStat t =
  t
    `elem` [ "Id", "Varid", "BacktickId", "Op", "IntegerLiteral", "FloatingPointLiteral", "BooleanLiteral", "CharacterLiteral"
           , "StringLiteral", "InterpolatedStringLiteral", "SymbolLiteral", "NullLiteral", "QuoteId", "USCORE", "THIS", "SUPER"
           , "NEW", "RETURN", "THROW", "IF", "WHILE", "FOR", "TRY", "LBRACE", "LPAREN", "LBRACKET", "QUOTE", "INDENT", "AT"
           , "CASE", "END", "DEF", "VAL", "VAR", "TYPE", "GIVEN", "ABSTRACT", "FINAL", "PRIVATE", "PROTECTED", "OVERRIDE"
           , "SEALED", "CLASS", "TRAIT", "OBJECT", "ENUM", "IMPORT", "EXPORT", "PACKAGE", "INLINE", "LAZY", "IMPLICIT"
           , "EXTENSION", "OPEN", "INFIX", "TRANSPARENT", "OPAQUE", "AS", "DERIVES", "USING"
           ]

-- | The tokens after which a deeper line opens an indented block: Dotty's canStartIndentTokens.
canStartIndent :: Text -> Bool
canStartIndent t =
  t
    `elem` [ "THEN", "ELSE", "DO", "CATCH", "FINALLY", "YIELD", "MATCH", "COLON", "WITH", "ASSIGN", "ARROW", "CTXARROW"
           , "LARROW", "WHILE", "TRY", "FOR", "IF", "THROW", "RETURN"
           ]

-- | The width of a line's leading whitespace, with a tab to the next multiple of eight and a form feed
-- restarting the count, as the base class measures it.
indentLength :: Text -> Int
indentLength = T.foldl' step 0
  where
    step n c = case c of
      ' ' -> n + 1
      '\t' -> (n `div` 8 + 1) * 8
      '\f' -> 0
      _ -> n

-- | A layout token, empty and placed where the last code token ends, so it widens no span.
virtual :: ScalaLayout -> Text -> Token
virtual s kind = case lastEnd s of
  Just (offset, position) -> Token (Name kind) "" offset offset defaultChannelName position
  Nothing -> Token (Name kind) "" 0 0 defaultChannelName (Position 1 1)

hide :: Token -> Token
hide token = token {tokenChannel = hiddenChannelName}

headOr :: a -> [a] -> a
headOr d xs = case xs of
  (x : _) -> x
  [] -> d

endPosition :: Token -> Position
endPosition token =
  let Position line column = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position line (column + T.length single)
        _ -> Position (line + length parts - 1) (T.length (last parts) + 1)
