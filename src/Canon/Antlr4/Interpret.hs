-- | An interpreter turns a grammar value into a running lexer and parser at run time, because a
-- Rank2 record cannot hold a rule set known only when a file is read. ref:DEC-parser-generation
module Canon.Antlr4.Interpret
  ( Interpreter (..)
  , InterpretError (..)
  , loadInterpreter
  , loadCombinedInterpreter
  , interpretFile
  , interpretText
  , interpretTextWith
  , renderInterpretError
  ) where

import Canon.Antlr4.Lex
import Canon.Antlr4.Lex.Adaptor (hooksForGrammarWith, preprocesses)
import Canon.Antlr4.Parse
import Canon.Antlr4.Predicate (predicateHookFor)
import Canon.Antlr4.Read (ReadError (..), readGrammarFile, readResultGrammar, renderReadError)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token)
import Canon.Preprocessor (Choice)
import Data.Foldable (toList)
import System.FilePath (takeDirectory, (</>))
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
  , interpreterTokenizeWith :: Choice -> Text -> Either LexError [Token]
  , interpreterPreprocesses :: Bool
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
  lexerResult <- readGrammarWithImports lexerPath
  parserResult <- readGrammarWithImports parserPath
  pure $ do
    lexerGrammar <- lexerResult
    parserGrammar <- parserResult
    build lexerPath lexerGrammar parserGrammar

-- | Loads a combined grammar, whose lexer rules and parser rules share one file.
loadCombinedInterpreter :: FilePath -> IO (Either InterpretError Interpreter)
loadCombinedInterpreter path = do
  result <- readGrammarWithImports path
  pure $ do
    grammar <- result
    build path grammar grammar

-- | Reads a grammar and the grammars it imports, found beside it as ANTLR finds them, and appends
-- their rules and modes after its own so the importing grammar's definitions win, as ANTLR's do.
-- ref:DEC-more-languages
readGrammarWithImports :: FilePath -> IO (Either InterpretError (Grammar Span))
readGrammarWithImports path = go [] path
  where
    go seen file
      | file `elem` seen = pure (Left (InterpretReadError (ReadImportCycle file)))
      | otherwise = do
          result <- readGrammarFile file
          case result of
            Left err -> pure (Left (InterpretReadError err))
            Right read' -> do
              let grammar = readResultGrammar read'
                  imported = [n | PrequelImports names <- grammarPrequel grammar, Import _ (Name n) <- toList names]
              merged <- mapM (\n -> go (file : seen) (takeDirectory file </> (T.unpack n ++ ".g4"))) imported
              pure (foldr (\g acc -> acc >>= \main -> fmap (merge main) g) (Right grammar) merged)
    merge main extra =
      let names = [ruleName r | r <- grammarRules main]
       in main
            { grammarRules = grammarRules main ++ [r | r <- grammarRules extra, ruleName r `notElem` names]
            , grammarModes = grammarModes main ++ grammarModes extra
            }
    ruleName r = case r of
      RuleParser pr -> parserRuleName pr
      RuleLexer lr -> lexerRuleName lr

build :: FilePath -> Grammar Span -> Grammar Span -> Either InterpretError Interpreter
build lexerPath lexerGrammar parserGrammar = do
  table <- either (Left . InterpretLexError lexerPath) Right (buildLexerTable lexerGrammar)
  let tokenizer choice = case hooksForGrammarWith choice lexerGrammar of
        SomeHooks hooks -> tokenizeWith hooks table
  Right (Interpreter lexerGrammar parserGrammar table (tokenizer Nothing) tokenizer (preprocesses lexerGrammar))

-- | Parses text with a start rule and returns the tree, taking the path only for messages.
interpretText :: Interpreter -> Name -> FilePath -> Text -> Either InterpretError ParseTree
interpretText = interpretTextWith Nothing

-- | Parses text reading the conditional branches a build selects. ref:DEC-preprocessor-builds
interpretTextWith :: Choice -> Interpreter -> Name -> FilePath -> Text -> Either InterpretError ParseTree
interpretTextWith choice interpreter start path source = do
  toks <- either (Left . InterpretLexError path) Right (interpreterTokenizeWith interpreter choice source)
  either (Left . InterpretParseError path) Right (parseTokensWith (predicateHookFor (interpreterParser interpreter)) (interpreterParser interpreter) start toks)

-- | Reads and parses a file, so callers do not repeat the read.
interpretFile :: Interpreter -> Name -> FilePath -> IO (Either InterpretError ParseTree)
interpretFile interpreter start path = interpretText interpreter start path <$> TIO.readFile path
