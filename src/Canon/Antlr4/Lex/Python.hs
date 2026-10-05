-- | Python's blocks are indentation, and the grammars-v4 lexer leaves the INDENT and DEDENT
-- tokens to a base class that watches each newline; this is that base class as a hook.
-- ref:DEC-more-languages
module Canon.Antlr4.Lex.Python
  ( PythonState (..)
  , pythonHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Data.Text (Text)
import qualified Data.Text as T

-- | The indentation stack, how many brackets are open, and the tokens to append after the
-- newline being emitted.
data PythonState = PythonState
  { pyIndents :: [Int]
  , pyOpened :: Int
  , pyPending :: [Text]
  }
  deriving (Eq, Show)

-- | The hooks for Python3LexerBase.
pythonHooks :: LexerHooks PythonState
pythonHooks = LexerHooks (PythonState [] 0 []) onAction onPredicate onEmit

calls :: ActionText -> Text -> Bool
calls action method = method `T.isInfixOf` actionTextRaw action

onPredicate :: Name -> ActionText -> Text -> Int -> PythonState -> Bool
onPredicate _ predicate _ start _
  | calls predicate "atStartOfInput" = start == 0
  | otherwise = True

-- | A newline inside brackets, or one followed by a blank or comment line, is skipped; otherwise
-- the indentation after it is compared with the stack and INDENT or DEDENT tokens follow.
onAction :: Name -> ActionText -> Text -> Text -> PythonState -> (PythonState, [HookEffect])
onAction _ action matched lookahead s
  | calls action "openBrace" = (s {pyOpened = pyOpened s + 1}, [])
  | calls action "closeBrace" = (s {pyOpened = pyOpened s - 1}, [])
  | calls action "onNewLine" =
      let spaces = T.filter (`notElem` ("\r\n\f" :: String)) matched
          blankOrCommentNext = T.length lookahead >= 2 && T.head lookahead `elem` ("\r\n\f#" :: String)
       in if pyOpened s > 0 || blankOrCommentNext
            then (s, [EffectSkip])
            else
              let indent = indentation spaces
                  previous = case pyIndents s of
                    (i : _) -> i
                    [] -> 0
               in if indent == previous
                    then (s, [])
                    else
                      if indent > previous
                        then (s {pyIndents = indent : pyIndents s, pyPending = ["INDENT"]}, [])
                        else
                          let (popped, rest) = span (> indent) (pyIndents s)
                           in (s {pyIndents = rest, pyPending = map (const "DEDENT") popped}, [])
  | otherwise = (s, [])

-- | Tabs count to the next multiple of eight, as the base class counts them.
indentation :: Text -> Int
indentation = T.foldl' step 0
  where
    step count c = if c == '\t' then count + 8 - (count `mod` 8) else count + 1

onEmit :: Token -> PythonState -> ([Token], PythonState)
onEmit token s
  | tokenType token == eofTokenName && not (null (pyIndents s)) =
      (virtual token "NEWLINE" : map (const (virtual token "DEDENT")) (pyIndents s) ++ [token], s {pyIndents = [], pyPending = []})
  | nameText (tokenType token) == "NEWLINE" = (token : map (virtual token) (pyPending s), s {pyPending = []})
  | otherwise = ([token], s)

virtual :: Token -> Text -> Token
virtual after kind = Token (Name kind) "" (tokenEnd after) (tokenEnd after) defaultChannelName (tokenPosition after)
