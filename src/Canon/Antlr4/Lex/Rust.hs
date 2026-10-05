-- | A Rust line doc comment ends at a line break the lexer hides, so the canonically commented
-- dialect's comment rule could end after any of its words, and canon's parser, which keeps a tree for
-- every end, took memory in the square of a comment's length: the standard library's pin.rs, whose
-- module documentation is 900 lines of //!, took 2.5 GB. This hook, selected by the RustLexerBase
-- superClass, emits an empty DOC_END token where a line doc comment ends, at the line break that
-- closes it, before a //// line that ends it, or at the end of the file, so the comment has one end.
-- The plain grammar has no doc comment tokens, and the hook leaves its tokens as they are.
-- ref:DEC-rust-dialect ref:DEC-parser-memory
module Canon.Antlr4.Lex.Rust
  ( rustLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token

-- | The hooks for the Rust grammars; the state is whether a line doc comment is open.
rustLexerHooks :: LexerHooks Bool
rustLexerHooks = LexerHooks False (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) onEmit

-- | Opens on a line doc comment's opener, and before the token that closes one emits DOC_END, empty
-- and on the default channel, where that token starts.
onEmit :: Token -> Bool -> ([Token], Bool)
onEmit token open
  | tokenType token `elem` openers = ([token], True)
  | open && (isEofToken token || tokenType token `elem` closers) = ([docEnd, token], False)
  | otherwise = ([token], open)
  where
    openers = [Name "DOC_OPEN", Name "INNER_DOC_OPEN"]
    closers = [Name "DOC_CLOSE", Name "INNER_DOC_CLOSE", Name "DOC_PLAIN_AFTER"]
    docEnd = Token (Name "DOC_END") "" (tokenStart token) (tokenStart token) defaultChannelName (tokenPosition token)
