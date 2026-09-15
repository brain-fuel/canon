-- | An interpreter turns a grammar value into a running lexer and parser at run time, because a
-- Rank2 record cannot hold a rule set known only when a file is read. ref:DEC-parser-generation
module Canon.Antlr4.Interpret
  ( Interpreter (..)
  , InterpretError (..)
  , loadInterpreter
  , loadCombinedInterpreter
  , interpretFile
  , interpretText
  , renderInterpretError
  ) where

import Canon.Antlr4.Lex
import Canon.Antlr4.Lex.Adaptor (hooksForGrammar)
import Canon.Antlr4.Parse
import Canon.Antlr4.Read (ReadError, readGrammarFile, readResultGrammar, renderReadError)
import Canon.Antlr4.Syntax (Grammar, Name)
import Canon.Antlr4.Token (Token)
import Canon.Span (Span)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

-- | Holds the compiled lexer and parser for one grammar pair, so that a language is loaded once and
-- reused across files.
data Interpreter = Interpreter
  { interpreterLexer :: Grammar Span
  , interpreterParser :: Grammar Span
  , interpreterTable :: LexerTable
  , interpreterTokenize :: Text -> Either LexError [Token]
  }

-- | Reading, lexing, and parsing can each fail, and a user needs to know which stage did.
data InterpretError
  = InterpretReadError ReadError
  | InterpretLexError FilePath LexError
  | InterpretParseError FilePath ParseError
  deriving (Eq, Show)

-- | One rendering for every stage so findings and command output agree.
renderInterpretError :: InterpretError -> Text
renderInterpretError e = case e of
  InterpretReadError err -> renderReadError err
  InterpretLexError path err -> T.concat [T.pack path, ":", renderLexError err]
  InterpretParseError path err -> T.concat [T.pack path, ":", renderParseError err]

-- | Loads a lexer and parser grammar pair, the split form grammars-v4 uses for most languages.
loadInterpreter :: FilePath -> FilePath -> IO (Either InterpretError Interpreter)
loadInterpreter lexerPath parserPath = do
  lexerResult <- readGrammarFile lexerPath
  parserResult <- readGrammarFile parserPath
  pure $ do
    lexerGrammar <- either (Left . InterpretReadError) (Right . readResultGrammar) lexerResult
    parserGrammar <- either (Left . InterpretReadError) (Right . readResultGrammar) parserResult
    build lexerPath lexerGrammar parserGrammar

-- | Loads a combined grammar, whose lexer rules and parser rules share one file.
loadCombinedInterpreter :: FilePath -> IO (Either InterpretError Interpreter)
loadCombinedInterpreter path = do
  result <- readGrammarFile path
  pure $ do
    grammar <- either (Left . InterpretReadError) (Right . readResultGrammar) result
    build path grammar grammar

build :: FilePath -> Grammar Span -> Grammar Span -> Either InterpretError Interpreter
build lexerPath lexerGrammar parserGrammar = do
  table <- either (Left . InterpretLexError lexerPath) Right (buildLexerTable lexerGrammar)
  let tokenizer = case hooksForGrammar lexerGrammar of
        SomeHooks hooks -> tokenizeWith hooks table
  Right (Interpreter lexerGrammar parserGrammar table tokenizer)

-- | Parses text with a start rule and returns the tree, taking the path only for messages.
interpretText :: Interpreter -> Name -> FilePath -> Text -> Either InterpretError ParseTree
interpretText interpreter start path source = do
  toks <- either (Left . InterpretLexError path) Right (interpreterTokenize interpreter source)
  either (Left . InterpretParseError path) Right (parseTokens (interpreterParser interpreter) start toks)

-- | Reads and parses a file, so callers do not repeat the read.
interpretFile :: Interpreter -> Name -> FilePath -> IO (Either InterpretError ParseTree)
interpretFile interpreter start path = interpretText interpreter start path <$> TIO.readFile path
