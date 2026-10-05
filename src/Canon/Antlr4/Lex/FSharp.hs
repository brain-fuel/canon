-- | F#'s offside rule makes indentation part of the syntax, and canon's F# grammar reads it as
-- tokens: this hook, selected by the grammar's FSharpLexerBase superClass, emits INDENT, DEDENT,
-- and NEWLINE outside brackets as Python's tokenizer does, BRNL at each new line inside brackets,
-- and reads the branches of each #if that a build selects, as Canon.Preprocessor chooses them,
-- hiding the others.
-- ref:DEC-fsharp-grammar
module Canon.Antlr4.Lex.FSharp
  ( FSharpLayout (..)
  , Held (..)
  , fsharpLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, Choice, directiveOf, reading, stepBranchesWith)
import Canon.Span (Position (..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: one entry per open #if, holding whether its current branch is read and whether
-- any branch of it has been; the columns of the open layout blocks, innermost first; the bracket
-- depth; the end offset and position of the last code token, and its type; the build whose branches
-- are read; the tokens held since a less-than sign that may open a type application; the doc
-- comment tokens held for the next code token; and how many columns a byte order mark takes from the
-- first line, which the offside rule does not count.
data FSharpLayout = FSharpLayout
  { conditions :: Branches
  , columns :: [Int]
  , depth :: Int
  , lastEnd :: Maybe (Int, Position)
  , lastType :: Text
  , build :: Choice
  , held :: Maybe Held
  , docs :: [Token]
  , skew :: Int
  }
  deriving (Eq, Show)

-- | The tokens held since a less-than sign touching a name, newest first, with the angle and
-- parenthesis depth reached in them.
data Held = Held
  { heldTokens :: [Token]
  , heldAngles :: Int
  , heldParens :: Int
  }
  deriving (Eq, Show)

-- | The hooks for the F# grammar, reading the branches a build selects. ref:DEC-preprocessor-builds
fsharpLexerHooks :: Choice -> LexerHooks FSharpLayout
fsharpLexerHooks choice = LexerHooks (FSharpLayout [] [] 0 Nothing "" choice Nothing [] 0) (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) onEmit

-- | A less-than sign touching the name before it may open a type application, as in
-- f< ^a when ... > or List<int>, whose angle brackets F# lets span lines like any brackets. The hook
-- holds the tokens from it until its closing greater-than sign, and then lays them out as inside
-- brackets; a token no type application holds, such as an equals sign outside parentheses or a let,
-- shows it was a comparison, and the held tokens are laid out as usual. ref:DEC-fsharp-grammar
onEmit :: Token -> FSharpLayout -> ([Token], FSharpLayout)
onEmit token s = case held s of
  Just h
    | isEofToken token || ends h -> replay False (reverse (token : heldTokens h)) s {held = Nothing}
    | otherwise ->
        let h' = track h
         in if heldAngles h' == 0
              then replay True (reverse (token : heldTokens h)) s {held = Nothing}
              else ([], s {held = Just h' {heldTokens = token : heldTokens h}})
  Nothing
    | opensApplication -> ([], s {held = Just (Held [token] 1 0)})
    | otherwise -> step False token s
  where
    ty = nameText (tokenType token)
    visible = tokenChannel token == defaultChannelName
    opensApplication =
      visible
        && active s
        && ty == "LESS"
        && lastType s `elem` ["IDENTIFIER", "BACKTICK_IDENTIFIER"]
        && maybe False ((== tokenStart token) . fst) (lastEnd s)
    ends h =
      visible
        && ( length (heldTokens h) > 256
               || (heldParens h == 0 && ty `elem` ["EQUALS", "LET", "TYPE", "MODULE", "NAMESPACE", "OPEN", "MEMBER", "BANG_KEYWORD", "DO", "SEMI", "BAR"])
           )
    track h
      | not visible = h
      | ty == "LESS" && heldParens h == 0 = h {heldAngles = heldAngles h + 1}
      | ty == "GREATER" && heldParens h == 0 = h {heldAngles = heldAngles h - 1}
      | ty `elem` openers = h {heldParens = heldParens h + 1}
      | ty `elem` closers = h {heldParens = max 0 (heldParens h - 1)}
      | otherwise = h

-- | Lays out held tokens, with their angle brackets as brackets when they were a type application.
-- A less-than or greater-than sign inside parentheses is an operator, as in the constraint
-- (static member (<): 'T * 'T -> bool), so only those outside them are brackets.
replay :: Bool -> [Token] -> FSharpLayout -> ([Token], FSharpLayout)
replay angles toks s0 = go toks (0 :: Int) s0 []
  where
    go [] _ s acc = (concat (reverse acc), s)
    go (t : rest) parens s acc =
      let ty = nameText (tokenType t)
          visible = tokenChannel t == defaultChannelName
          parens'
            | visible && ty `elem` openers = parens + 1
            | visible && ty `elem` closers = max 0 (parens - 1)
            | otherwise = parens
          (out, s') = step (angles && parens == 0) t s
       in go rest parens' s' (out : acc)

-- | The tokens of a doc comment in the canonically commented dialect. The hook holds them until the
-- next code token has produced its layout tokens, and emits them just before it, so a doc comment is
-- never the first token of a line and sits right before the declaration it documents, as the Haskell
-- port does. ref:DEC-fsharp-dialect
docTypes :: [Text]
docTypes = ["DOC_OPEN", "DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE"]

-- | Whether a held doc comment has not been closed by its line's end.
docOpen :: FSharpLayout -> Bool
docOpen s = case reverse (docs s) of
  (t : _) -> nameText (tokenType t) /= "DOC_END"
  [] -> False

-- | The empty token that closes a line doc comment, placed where its last token ends, so the
-- comment rule ends at one token instead of after any of its words: a rule that may end anywhere
-- makes the parser keep a tree per possible end, quadratic in the comment's length.
-- ref:DEC-fsharp-dialect
docEnd :: FSharpLayout -> Token
docEnd s = case reverse (docs s) of
  (t : _) -> Token (Name "DOC_END") "" (tokenEnd t) (tokenEnd t) defaultChannelName (endPosition t)
  [] -> virtual s "DOC_END"

openers, closers :: [Text]
openers = ["LPAREN", "LBRACK", "LBRACE", "LBRACKBAR", "LBRACEBAR", "LATTR"]
closers = ["RPAREN", "RBRACK", "RBRACE", "BARRBRACK", "BARRBRACE", "RATTR"]

step :: Bool -> Token -> FSharpLayout -> ([Token], FSharpLayout)
step angles token s
  | ty `elem` ["IF_DIRECTIVE", "ELSE_DIRECTIVE", "ENDIF_DIRECTIVE"], Just d <- directiveOf (tokenText token) =
      ([token], s {conditions = stepBranchesWith (build s) Map.empty d (conditions s)})
  | ty == "BYTE_ORDER_MARK" = ([token], s {skew = T.length (tokenText token)})
  | ty `elem` ["DOC_CLOSE", "DOC_PLAIN_AFTER"] && docOpen s = ([token], s {docs = docs s ++ [docEnd s]})
  | isEofToken token = (map (const (virtual s "DEDENT")) (drop 1 (columns s)) ++ docs s ++ [docEnd s | docOpen s] ++ [token], s {docs = []})
  | tokenChannel token /= defaultChannelName = ([token], s)
  | not (active s) = ([token {tokenChannel = hiddenChannelName}], s)
  | ty `elem` docTypes = ([], s {docs = docs s ++ [token]})
  | otherwise = (layout ++ docs s ++ [token], s' {depth = depth', lastEnd = Just (tokenEnd token, endPosition token), lastType = ty, docs = []})
  where
    ty = nameText (tokenType token)
    Position line written = tokenPosition token
    column = if line == 1 then written - skew s else written
    depth'
      | ty `elem` openers || (angles && ty == "LESS") = depth s + 1
      | ty `elem` closers || (angles && ty == "GREATER") = max 0 (depth s - 1)
      | otherwise = depth s
    (layout, s') = case lastEnd s of
      Nothing -> ([], s {columns = [column]})
      Just (_, Position previousLine _)
        | line <= previousLine -> ([], s)
        | depth s > 0 -> ([virtual s "BRNL"], s)
        | otherwise -> offside s column

-- | The layout tokens before the first token of a line outside brackets: INDENT when it is right of
-- the current block, NEWLINE when it is level with it, and a DEDENT for each block it is left of,
-- then NEWLINE when it lands on an open block's column or INDENT when it lands between two. A line
-- left of the first line of the file is level with it.
offside :: FSharpLayout -> Int -> ([Token], FSharpLayout)
offside s column = case columns s of
  [] -> ([], s {columns = [column]})
  (top : _)
    | column > top -> ([virtual s "INDENT"], s {columns = column : columns s})
    | column == top -> ([virtual s "NEWLINE"], s)
    | otherwise ->
        let (remaining, closed) = close (columns s) (0 :: Int)
            dedents = replicate closed (virtual s "DEDENT")
         in case remaining of
              (top' : _)
                | top' < column -> (dedents ++ [virtual s "INDENT"], s {columns = column : remaining})
              _ -> (dedents ++ [virtual s "NEWLINE"], s {columns = remaining})
  where
    close cols n = case cols of
      (c : rest@(_ : _)) | c > column -> close rest (n + 1)
      _ -> (cols, n)

-- | A layout token, empty and placed where the last code token ends, so it widens no span.
virtual :: FSharpLayout -> Text -> Token
virtual s kind = case lastEnd s of
  Just (offset, position) -> Token (Name kind) "" offset offset defaultChannelName position
  Nothing -> Token (Name kind) "" 0 0 defaultChannelName (Position 1 1)

active :: FSharpLayout -> Bool
active = reading . conditions

endPosition :: Token -> Position
endPosition token =
  let Position line column = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position line (column + T.length single)
        _ -> Position (line + length parts - 1) (T.length (last parts) + 1)
