-- | YAML nests by indentation and ends a block scalar where its lines stop being indented past
-- its key, which no context-free grammar sees, and a YAML comment documents the entry below it
-- only when nothing parts them. This hook, selected by the grammar's YAMLLexerBase superClass,
-- emits INDENT, DEDENT, and NEWLINE outside flow collections as Python's tokenizer does, treating
-- the content after a sequence entry's dash as indented to its own column; leaves a block scalar
-- at the first line not indented past the key or dash on its header's line; and holds each
-- comment back until the next code token has its layout tokens, hiding it unless it is on the
-- line directly above that token or directly above another such comment. ref:DEC-pulumi-yaml-grammar
module Canon.Antlr4.Lex.YAML
  ( YAMLLayout (..)
  , yamlLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText, Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: the columns of the open blocks, innermost first; the flow collection depth;
-- the end offset and position, type, and column of the last code token; the columns of the last
-- key and the last dash on the current line; the column a block scalar's lines must exceed; and
-- the held comment tokens, the line of the last held comment, and whether the comment being read
-- is hidden.
data YAMLLayout = YAMLLayout
  { columns :: [Int]
  , flowDepth :: Int
  , lastEnd :: Maybe (Int, Position)
  , lastType :: Text
  , lastColumn :: Int
  , lineKey :: Maybe Int
  , lineDash :: Maybe Int
  , scalarParent :: Int
  , held :: [Token]
  , heldLine :: Int
  , commentHidden :: Bool
  }
  deriving (Eq, Show)

-- | The hooks for the YAML grammar and its Pulumi dialect.
yamlLexerHooks :: LexerHooks YAMLLayout
yamlLexerHooks = LexerHooks (YAMLLayout [] 0 Nothing "" 0 Nothing Nothing 0 [] 0 False) onAction onEmit

-- | Records the indentation a block scalar's lines must exceed when its header is read, and leaves
-- the scalar at a line that does not exceed it.
onAction :: Name -> ActionText -> Text -> YAMLLayout -> (YAMLLayout, [HookEffect])
onAction rule _ matched s = case nameText rule of
  "BLOCK_SCALAR" -> (s {scalarParent = fromMaybe (fromMaybe 0 (lineDash s)) (lineKey s)}, [])
  "BLOCK_SCALAR_BREAK"
    | indentation + 1 > scalarParent s -> (s, [])
    | otherwise -> (s, [EffectPopMode])
  _ -> (s, [])
  where
    indentation = T.length (snd (T.breakOnEnd "\n" matched))

-- | Routes each token by what it is: the end of input, a comment token, block scalar text, or code.
onEmit :: Token -> YAMLLayout -> ([Token], YAMLLayout)
onEmit token s
  | isEofToken token = (map hidden (held s) ++ map (const (virtual s "DEDENT")) (drop 1 (columns s)) ++ [token], s {held = []})
  | tokenChannel token /= defaultChannelName = ([token], s)
  | ty == "DOC_OPEN" = opening token s
  | ty `elem` ["DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE"] =
      if commentHidden s then ([hidden token], s) else ([], s {held = held s ++ [token]})
  | ty == "BLOCK_SCALAR_TEXT" = ([token], s {lastEnd = Just (tokenEnd token, endPosition token)})
  | otherwise = code token s
  where
    ty = nameText (tokenType token)

-- | A comment after code on its line, or inside a flow collection, is hidden. Any other comment is
-- held; held comments that a blank line parts from it are hidden, since they document nothing.
opening :: Token -> YAMLLayout -> ([Token], YAMLLayout)
opening token s
  | flowDepth s > 0 || maybe False (\(_, Position l _) -> l == line token) (lastEnd s) = ([hidden token], s {commentHidden = True})
  | not (null (held s)) && line token /= heldLine s + 1 = (map hidden (held s), s {held = [token], heldLine = line token, commentHidden = False})
  | otherwise = ([], s {held = held s ++ [token], heldLine = line token, commentHidden = False})

-- | A code token gets its layout tokens, then the held comments if they end on the line directly
-- above it, then itself.
code :: Token -> YAMLLayout -> ([Token], YAMLLayout)
code token s =
  let (layout, s') = layoutFor token s
      comments
        | null (held s) = []
        | heldLine s + 1 == line token = held s
        | otherwise = map hidden (held s)
      newLine = maybe True (\(_, Position l _) -> line token > l) (lastEnd s)
      ty = nameText (tokenType token)
      column = positionColumn (tokenPosition token)
      depth'
        | ty `elem` ["FLOW_SEQ_OPEN", "FLOW_MAP_OPEN"] = flowDepth s + 1
        | ty `elem` ["FLOW_SEQ_CLOSE", "FLOW_MAP_CLOSE"] = max 0 (flowDepth s - 1)
        | otherwise = flowDepth s
      lineKey'
        | ty == "COLON" && flowDepth s == 0 = Just (lastColumn s)
        | newLine = Nothing
        | otherwise = lineKey s
      lineDash'
        | ty == "DASH" = Just column
        | newLine = Nothing
        | otherwise = lineDash s
   in ( layout ++ comments ++ [token]
      , s'
          { held = []
          , flowDepth = depth'
          , lastEnd = Just (tokenEnd token, endPosition token)
          , lastType = ty
          , lastColumn = column
          , lineKey = lineKey'
          , lineDash = lineDash'
          }
      )

-- | The layout tokens before a code token: none inside a flow collection or after other code on
-- its line, except INDENT for the first token after a sequence entry's dash; and on a new line,
-- INDENT when it is right of the current block, NEWLINE when level with it, and a DEDENT for each
-- block it is left of.
layoutFor :: Token -> YAMLLayout -> ([Token], YAMLLayout)
layoutFor token s = case lastEnd s of
  Nothing -> ([], s {columns = [column]})
  Just (_, Position previousLine _)
    | flowDepth s > 0 -> ([], s)
    | line token <= previousLine ->
        if lastType s == "DASH" then ([virtual s "INDENT"], s {columns = column : columns s}) else ([], s)
    | otherwise -> offside s column
  where
    column = positionColumn (tokenPosition token)

-- | INDENT, NEWLINE, or DEDENTs for the first token of a line, by its column. A line left of the
-- first line of the file is level with it.
offside :: YAMLLayout -> Int -> ([Token], YAMLLayout)
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
virtual :: YAMLLayout -> Text -> Token
virtual s kind = case lastEnd s of
  Just (offset, position) -> Token (Name kind) "" offset offset defaultChannelName position
  Nothing -> Token (Name kind) "" 0 0 defaultChannelName (Position 1 1)

-- | A token moved to the hidden channel.
hidden :: Token -> Token
hidden token = token {tokenChannel = hiddenChannelName}

-- | The line a token starts on.
line :: Token -> Int
line = positionLine . tokenPosition

-- | The position just past a token, which is on a later line for a token holding a line break.
endPosition :: Token -> Position
endPosition token =
  let Position l c = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position l (c + T.length single)
        _ -> Position (l + length parts - 1) (T.length (last parts) + 1)
