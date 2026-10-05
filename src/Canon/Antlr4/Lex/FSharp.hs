-- | F#'s offside rule makes indentation part of the syntax, and canon's F# grammar reads it as
-- tokens: this hook, selected by the grammar's FSharpLexerBase superClass, emits INDENT, DEDENT,
-- and NEWLINE outside brackets as Python's tokenizer does, BRNL at each new line inside brackets,
-- and reads one branch of each #if, as Canon.Preprocessor chooses it, hiding the others.
-- ref:DEC-fsharp-grammar
module Canon.Antlr4.Lex.FSharp
  ( FSharpLayout (..)
  , fsharpLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, directiveOf, reading, stepBranches)
import Canon.Span (Position (..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: one entry per open #if, holding whether its current branch is read and whether
-- any branch of it has been; the columns of the open layout blocks, innermost first; the bracket
-- depth; and the end offset and position of the last code token.
data FSharpLayout = FSharpLayout
  { conditions :: Branches
  , columns :: [Int]
  , depth :: Int
  , lastEnd :: Maybe (Int, Position)
  }
  deriving (Eq, Show)

-- | The hooks for the F# grammar.
fsharpLexerHooks :: LexerHooks FSharpLayout
fsharpLexerHooks = LexerHooks (FSharpLayout [] [] 0 Nothing) (\_ _ _ s -> (s, [])) onEmit

onEmit :: Token -> FSharpLayout -> ([Token], FSharpLayout)
onEmit token s
  | ty `elem` ["IF_DIRECTIVE", "ELSE_DIRECTIVE", "ENDIF_DIRECTIVE"], Just d <- directiveOf (tokenText token) =
      ([token], s {conditions = stepBranches Map.empty d (conditions s)})
  | isEofToken token = (map (const (virtual s "DEDENT")) (drop 1 (columns s)) ++ [token], s)
  | tokenChannel token /= defaultChannelName = ([token], s)
  | not (active s) = ([token {tokenChannel = hiddenChannelName}], s)
  | otherwise = (layout ++ [token], s' {depth = depth', lastEnd = Just (tokenEnd token, endPosition token)})
  where
    ty = nameText (tokenType token)
    Position line column = tokenPosition token
    depth'
      | ty `elem` ["LPAREN", "LBRACK", "LBRACE", "LBRACKBAR", "LBRACEBAR", "LATTR"] = depth s + 1
      | ty `elem` ["RPAREN", "RBRACK", "RBRACE", "BARRBRACK", "BARRBRACE", "RATTR"] = max 0 (depth s - 1)
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
