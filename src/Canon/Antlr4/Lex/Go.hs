-- | A Go doc comment is an ordinary comment directly above a declaration, so only where it sits tells
-- it from a plain one. The canonically commented Go lexer asks this hook, as GoLexerBase, whether a
-- comment stands where a doc comment may: at the start of its line, at the top level of a file,
-- inside a grouped const, type, or var declaration, or inside a struct or interface type. The hook
-- also holds a doc comment's tokens until the next code token and hides them when a blank line or
-- the end of the file comes first, since go/doc reads such a comment as documenting nothing.
-- ref:DEC-go-dialect ref:go-doc-comments
module Canon.Antlr4.Lex.Go
  ( GoState (..)
  , goLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect, LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Data.Char (isSpace)
import Data.Text (Text)
import qualified Data.Text as T

-- | Whether the last token ended a line, the open brackets innermost first, each saying whether a
-- declaration may stand directly inside it, the type of the last code token, and the doc comment
-- being held, if any.
data GoState = GoState
  { goLineStart :: Bool
  , goFrames :: [Bool]
  , goLastCode :: Maybe Text
  , goHeld :: Maybe Held
  }
  deriving (Eq, Show)

-- | A held doc comment: its tokens and the hidden tokens after it, in reverse, whether its closing
-- token is still to come, and how many line breaks followed it.
data Held = Held
  { heldTokens :: [Token]
  , heldInComment :: Bool
  , heldNewlines :: Int
  }
  deriving (Eq, Show)

-- | The hooks for GoLexerBase.
goLexerHooks :: LexerHooks GoState
goLexerHooks = LexerHooks (GoState True [] Nothing Nothing) onAction onPredicate onEmit

onAction :: Name -> ActionText -> Text -> Text -> GoState -> (GoState, [HookEffect])
onAction _ _ _ _ s = (s, [])

-- | isDocPosition holds at the start of a line whose innermost bracket admits a declaration, or
-- outside every bracket; a leading ! negates it.
onPredicate :: Name -> ActionText -> Text -> Int -> GoState -> Bool
onPredicate _ predicate _ _ s
  | "isDocPosition" `T.isInfixOf` raw = if "!" `T.isInfixOf` raw then not docPosition else docPosition
  | otherwise = True
  where
    raw = actionTextRaw predicate
    docPosition = goLineStart s && case goFrames s of
      (admits : _) -> admits
      [] -> True

onEmit :: Token -> GoState -> ([Token], GoState)
onEmit token s0 = case goHeld s of
  Nothing
    | opensDoc -> ([], s {goHeld = Just (Held [token] True 0)})
    | otherwise -> ([token], s)
  Just held
    | opensDoc -> (release held (blankAfter held), s {goHeld = Just (Held [token] True 0)})
    | isEofToken token -> (release held True ++ [token], s {goHeld = Nothing})
    | heldInComment held ->
        let closing = kind `elem` ["DOC_CLOSE", "DOC_BLOCK_CLOSE"]
         in ([], s {goHeld = Just held {heldTokens = token : heldTokens held, heldInComment = not closing, heldNewlines = if closing then newlines else 0}})
    | tokenChannel token /= defaultChannelName -> ([], s {goHeld = Just held {heldTokens = token : heldTokens held, heldNewlines = heldNewlines held + newlines}})
    | otherwise -> (release held (blankAfter held) ++ [token], s {goHeld = Nothing})
  where
    kind = nameText (tokenType token)
    opensDoc = kind `elem` ["DOC_OPEN", "DOC_BLOCK_OPEN"]
    newlines = T.count "\n" (tokenText token)
    s = track token s0

-- | Whether a blank line followed a held doc comment, which then documents nothing.
blankAfter :: Held -> Bool
blankAfter held = not (heldInComment held) && heldNewlines held >= 2

-- | Releases a held doc comment in source order, on the hidden channel when it documents nothing.
release :: Held -> Bool -> [Token]
release held hide = [if hide && tokenChannel t == defaultChannelName then t {tokenChannel = hiddenChannelName} else t | t <- reverse (heldTokens held)]

-- | Follows line starts and brackets: a token of whitespace with a line break starts a line and other
-- whitespace keeps the line's state, and a parenthesis after const, type, or var or a brace after
-- struct or interface opens a bracket a declaration may stand directly inside, unless a bracket
-- around it does not admit one, as a function body does not: what a function declares locally is
-- no part of its package's documentation.
track :: Token -> GoState -> GoState
track token s = lined {goFrames = frames, goLastCode = lastCode}
  where
    text = tokenText token
    kind = nameText (tokenType token)
    lined
      | T.all isSpace text = if T.any (`elem` ("\r\n" :: String)) text then s {goLineStart = True} else s
      | otherwise = s {goLineStart = False}
    code = tokenChannel token == defaultChannelName && not ("DOC_" `T.isPrefixOf` kind) && not (isEofToken token)
    frames
      | not code = goFrames s
      | kind == "L_PAREN" = (enclosingAdmits && goLastCode s `elem` map Just ["CONST", "TYPE", "VAR"]) : goFrames s
      | kind == "L_CURLY" = (enclosingAdmits && goLastCode s `elem` map Just ["STRUCT", "INTERFACE"]) : goFrames s
      | kind == "L_BRACKET" = False : goFrames s
      | kind `elem` ["R_PAREN", "R_CURLY", "R_BRACKET"] = drop 1 (goFrames s)
      | otherwise = goFrames s
    lastCode = if code then Just kind else goLastCode s
    enclosingAdmits = case goFrames s of
      (admits : _) -> admits
      [] -> True
