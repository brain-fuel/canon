-- | Scala 3 lets indentation stand for braces, and canon's Scala grammar reads it as tokens: this
-- hook, selected by the grammar's ScalaLexerBase superClass, inserts INDENT, OUTDENT, and NEWLINE
-- where the Optional Braces section of the Scala 3 reference does, outside parentheses and
-- brackets, and in the canonically commented dialect places each Scaladoc comment right before the
-- code token it precedes. ref:DEC-scala-indentation ref:scala3-indentation
module Canon.Antlr4.Lex.Scala
  ( ScalaLayout (..)
  , Region (..)
  , Bracket (..)
  , scalaLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | What a parenthesis or bracket encloses: the condition of an old-style if, while, or for, after
-- whose closing parenthesis an indented region may start; the parameters of an extension, after
-- which its methods may be indented; or anything else.
data Bracket = PlainBracket | ConditionBracket | ExtensionBracket
  deriving (Eq, Show)

-- | A region the hook tracks. Statements are separated and indented only in the file's region and
-- in braces, each with the width of its first line and the widths of the indented regions opened
-- in it, innermost first, each marked when it is the region of case clauses that a match or catch
-- opened at its own width. Inside parentheses and brackets line breaks are not significant.
data Region
  = Braces (Maybe Int) [(Int, Bool)]
  | Brackets Bracket
  deriving (Eq, Show)

-- | The hook state: the open regions, innermost first and the file's last; the end offset and
-- position of the last code token, its type, and the type before it; whether an indented region
-- may start after the last code token; whether the tokens since an extension keyword are its
-- parameters; and the Scaladoc tokens held until the next code token.
data ScalaLayout = ScalaLayout
  { regions :: [Region]
  , lastEnd :: Maybe (Int, Position)
  , lastType :: Text
  , previousType :: Text
  , lastOpens :: Bool
  , extensionHeader :: Bool
  , docs :: [Token]
  }
  deriving (Eq, Show)

-- | The hooks for the Scala grammar. ref:DEC-scala-indentation
scalaLexerHooks :: LexerHooks ScalaLayout
scalaLexerHooks = LexerHooks (ScalaLayout [Braces Nothing []] Nothing "" "" False False []) (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) onEmit

-- | The tokens of a Scaladoc comment in the canonically commented dialect. The hook holds them until
-- the next code token has produced its layout tokens, and emits them just before it, so a line
-- holding only a comment is blank to the layout, as it is to the compiler. ref:DEC-scala-dialect
docTypes :: [Text]
docTypes = ["DOC_OPEN", "DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE", "DOC_CLOSE"]

-- | The tokens after which the reference lets an indented region start.
openers :: [Text]
openers =
  [ "EQUALS", "FAT_ARROW", "CONTEXT_ARROW", "LEFT_ARROW", "CATCH", "DO", "ELSE", "FINALLY", "FOR", "IF"
  , "MATCH", "RETURN", "THEN", "THROW", "TRY", "WHILE", "YIELD", "WITH", "COLON"
  ]

-- | The tokens that can end a statement: names, soft keywords, literals, this, return, and closing
-- brackets.
terminators :: [Text]
terminators =
  [ "ID", "BACKQUOTED_ID", "OP", "NUMBER", "STRING", "MULTILINE_STRING", "INTERPOLATED_STRING"
  , "INTERPOLATED_MULTILINE_STRING", "CHARACTER", "SYMBOL", "THIS", "RETURN", "RPAREN", "RBRACK", "RBRACE"
  , "AS", "DERIVES", "END", "EXTENSION", "INFIX", "INLINE", "OPAQUE", "OPEN", "TRANSPARENT", "USING"
  ]

-- | The keywords an end marker may name, which end a statement after end.
endTags :: [Text]
endTags = ["IF", "WHILE", "FOR", "MATCH", "TRY", "NEW", "THIS", "VAL", "GIVEN", "EXTENSION"]

-- | The tokens that cannot begin a statement, so a line starting with one continues the line above;
-- an operator at the start of a line is a leading infix operator.
continuations :: [Text]
continuations =
  [ "THEN", "ELSE", "DO", "CATCH", "FINALLY", "YIELD", "MATCH", "WITH", "EXTENDS", "DERIVES", "DOT", "COMMA"
  , "COLON", "EQUALS", "FAT_ARROW", "CONTEXT_ARROW", "LEFT_ARROW", "SUBTYPE", "SUPERTYPE", "HASH", "RPAREN"
  , "RBRACK", "RBRACE", "SEMI", "OP"
  ]

onEmit :: Token -> ScalaLayout -> ([Token], ScalaLayout)
onEmit token s
  | isEofToken token = (replicate (sum (map indentsOf (regions s))) (virtual s "OUTDENT") ++ docs s ++ [token], s {docs = []})
  | tokenChannel token /= defaultChannelName = ([token], s)
  | ty `elem` docTypes = ([], s {docs = docs s ++ [token]})
  | otherwise =
      let (layout, s1) = if newLine then atLineStart ty column s else ([], s)
          (closing, s2, opensAfterBracket) = brackets ty s1
          opens
            | lastType s == "END" = False
            | ty `elem` ["RPAREN", "RBRACK"] = opensAfterBracket
            | otherwise = ty `elem` openers
          header = case regions s2 of
            (Braces _ _ : _)
              | ty == "EXTENSION" -> True
              | ty `elem` ["LPAREN", "LBRACK", "RPAREN", "RBRACK"] -> extensionHeader s2
              | otherwise -> False
            _ -> extensionHeader s2
       in ( layout ++ closing ++ docs s ++ [token]
          , s2
              { lastEnd = Just (tokenEnd token, endPosition token)
              , lastType = ty
              , previousType = lastType s
              , lastOpens = opens
              , extensionHeader = header
              , docs = []
              }
          )
  where
    ty = nameText (tokenType token)
    Position line column = tokenPosition token
    newLine = case lastEnd s of
      Nothing -> True
      Just (_, Position previousLine _) -> line > previousLine

indentsOf :: Region -> Int
indentsOf region = case region of
  Braces _ indents -> length indents
  Brackets _ -> 0

-- | Opens and closes the regions of brackets and braces. A closing bracket closes the regions
-- opened inside it, with an OUTDENT for each indented region left open, and says whether it ends
-- an old-style condition or an extension's parameters, after which an indented region may start.
-- A closing brace never closes the file's region.
brackets :: Text -> ScalaLayout -> ([Token], ScalaLayout, Bool)
brackets ty s = case ty of
  "LPAREN" -> open (Brackets (bracketKind True))
  "LBRACK" -> open (Brackets (bracketKind False))
  "LBRACE" -> open (Braces Nothing [])
  "RPAREN" -> closeBracket
  "RBRACK" -> closeBracket
  "RBRACE" -> closeBrace
  _ -> ([], s, False)
  where
    open region = ([], s {regions = region : regions s}, False)
    bracketKind paren
      | paren && lastType s `elem` ["IF", "WHILE", "FOR"] = ConditionBracket
      | extensionHeader s, (Braces _ _ : _) <- regions s = ExtensionBracket
      | otherwise = PlainBracket
    closeBracket =
      let (inner, rest) = break isBracket (regions s)
       in case rest of
            (Brackets kind : outer) | not (null outer) -> (outdents inner, s {regions = outer}, kind /= PlainBracket)
            _ -> ([], s, False)
    closeBrace =
      let (inner, rest) = break isBraces (regions s)
       in case rest of
            (region : outer) | not (null outer) -> (outdents (inner ++ [region]), s {regions = outer}, False)
            _ -> ([], s, False)
    outdents closed = replicate (sum (map indentsOf closed)) (virtual s "OUTDENT")
    isBracket region = case region of
      Brackets _ -> True
      Braces _ _ -> False
    isBraces = not . isBracket

-- | The layout tokens before the first code token of a line, by the rules of the reference. In a
-- region of braces or the file's region whose width is not yet known, the line sets it. Otherwise
-- an OUTDENT closes each indented region the line is left of, and a region of case clauses at
-- whose width a line starts with anything but case; a line right of the current width starts an
-- indented region when the last token may start one and continues the line above when it may not;
-- a case level with a match or catch at the end of the line above starts a region of case clauses;
-- and NEWLINE separates two statements level with each other, unless the last token cannot end a
-- statement or the next cannot begin one, or after an OUTDENT, unless the next cannot begin one. A
-- line left of the region's own width is level with it.
atLineStart :: Text -> Int -> ScalaLayout -> ([Token], ScalaLayout)
atLineStart ty column s = case regions s of
  (Braces Nothing _ : outer) ->
    ( [virtual s "NEWLINE" | lastType s /= "LBRACE", not (lastOpens s), separates]
    , s {regions = Braces (Just column) [] : outer}
    )
  (Braces (Just base) indents : outer) ->
    let (closed, remaining) = closeIndents indents
        width = case remaining of
          ((w, _) : _) -> w
          [] -> base
        put is = s {regions = Braces (Just base) is : outer}
     in if closed > 0
          then (replicate closed (virtual s "OUTDENT") ++ [virtual s "NEWLINE" | column <= width, canBegin], put remaining)
          else
            if column > width
              then
                if lastOpens s
                  then ([virtual s "INDENT"], put ((column, False) : indents))
                  else ([], s)
              else
                if column == width && ty == "CASE" && lastType s `elem` ["MATCH", "CATCH"]
                  then ([virtual s "INDENT"], put ((column, True) : indents))
                  else ([virtual s "NEWLINE" | separates], s)
  _ -> ([], s)
  where
    closeIndents is = case is of
      ((w, cases) : rest)
        | column < w || (cases && column == w && ty /= "CASE") ->
            let (n, remaining) = closeIndents rest in (n + 1, remaining)
      _ -> (0 :: Int, is)
    canBegin = ty `notElem` continuations
    separates = canBegin && terminates
    terminates =
      lastType s `elem` terminators
        || (previousType s == "END" && lastType s `elem` endTags)
        || (previousType s == "DOT" && lastType s == "TYPE")

-- | A layout token, empty and placed where the last code token ends, so it widens no span.
virtual :: ScalaLayout -> Text -> Token
virtual s kind = case lastEnd s of
  Just (offset, position) -> Token (Name kind) "" offset offset defaultChannelName position
  Nothing -> Token (Name kind) "" 0 0 defaultChannelName (Position 1 1)

endPosition :: Token -> Position
endPosition token =
  let Position line column = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position line (column + T.length single)
        _ -> Position (line + length parts - 1) (T.length (last parts) + 1)
