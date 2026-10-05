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
  , parseWithStrayComments
  , strayCommentRules
  , renderInterpretError
  ) where

import Canon.Antlr4.Lex
import Canon.Antlr4.Lex.Adaptor (hooksForGrammarWith, preprocesses)
import Canon.Antlr4.Parse
import Canon.Antlr4.Predicate (predicateHookFor)
import Canon.Antlr4.Read (ReadError (..), readGrammarFile, readResultGrammar, renderReadError)
import Canon.Antlr4.Query (grammarOptions, lookupRule, tokenReferences)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token (..), defaultChannelName, isEofToken)
import Canon.Preprocessor (Choice)
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (listToMaybe)
import qualified Data.Set as Set
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
  either (Left . InterpretParseError path) Right (parseWithStrayComments (predicateHookFor (interpreterParser interpreter)) (interpreterParser interpreter) start toks)

-- | The comment rules a parser grammar names in its strayComment options: rules whose matches may
-- stand anywhere in a file, as a doc comment may, though the grammar accepts them only where they
-- document something or where it labels them orphan. ref:DEC-stray-comments
strayCommentRules :: Grammar ann -> [Name]
strayCommentRules grammar = [NonEmpty.last v | Option (Name "strayComment") (OptionValueName (QualifiedName v)) <- grammarOptions grammar]

-- | How many tokens before the failure a stray comment may end and still be taken for its cause.
strayWindow :: Int
strayWindow = 3

-- | Parses the tokens, and where the parse fails at a stray comment, or within strayWindow tokens
-- after one, parses again without it and adds it to the root as an orphan, for as long as each
-- round moves the failure forward. A doc comment may stand between any two tokens, as inside an
-- expression, and no grammar can accept it everywhere without reading every expression
-- differently, so one the grammar does not accept where it stands documents nothing. A failure no
-- stray comment explains is reported where the parse stopped before the round that did not move
-- it, which is where the first parse stopped when no stray comment comes shortly before it. A
-- grammar that names no strayComment rule parses as before. ref:DEC-stray-comments
parseWithStrayComments :: PredicateHook -> Grammar ann -> Name -> [Token] -> Either ParseError ParseTree
parseWithStrayComments hook grammar start toks = case parseVisibleTokensWith hook grammar start visible of
  Left (ParseNoParse failure) | not (null strays) -> recover (length visible) visible [] failure
  other -> other
  where
    strays = strayCommentRules grammar
    visible = filter ((== defaultChannelName) . tokenChannel) toks
    plain = fmap (const ()) grammar
    openers = Set.fromList [t | r <- strays, Just rule <- [lookupRule r plain], t <- Set.toList (tokenReferences rule)]
    -- Each round drops one comment, so a file is parsed at most once more than it holds stray
    -- comments, and a syntax error with none at it costs one parse beyond the first.
    -- A round that drops a comment must move the failure forward, or the comment was not what
    -- stopped the parse and the failure is reported where it is.
    recover budget current found failure@(ParseFailure f _) = case strayAt current f of
      Just (k, e, comment) | budget > 0 -> do
        let rest = take k current ++ drop e current
        case parseVisibleTokensWith hook grammar start rest of
          Right tree -> Right (withOrphans (comment : found) tree)
          Left (ParseNoParse next)
            | reached next > reached failure -> recover (budget - 1) rest (comment : found) next
            | otherwise -> Left (ParseNoParse failure)
          Left other -> Left other
      _ -> Left (ParseNoParse failure)
    reached (ParseFailure _ tok) = maybe maxBound tokenStart tok
    withOrphans found tree = case tree of
      RuleNode name alternative children -> RuleNode name alternative (children ++ map (Labeled "orphan") (reverse found))
      other -> other
    -- The stray comment that starts at the failure or ends at most strayWindow tokens before it,
    -- nearest first: a grammar whose units take an optional comment may read one as a unit's Why and
    -- fail a token or two later, at the name of what it cannot document there.
    strayAt current f =
      listToMaybe
        [ (k, k + size, comment)
        | k <- [f, f - 1 .. max 0 (f - 400)]
        , Just tok <- [listToMaybe (drop k current)]
        , Set.member (tokenType tok) openers
        , r <- strays
        , Just comment <- [strayFrom r (takeWhile (not . isEofToken) (drop k current))]
        , let size = length (treeTokens comment)
        , size > 0
        , k == f || (k + size <= f && k + size >= f - strayWindow)
        ]
    -- The longest match of the comment rule at the start of the tokens, read by a rule that takes
    -- the comment and then any tokens.
    strayFrom r rest = case parseVisibleTokensWith hook (withStrayRule r) (Name "canonStrayComment") rest of
      Right (RuleNode _ _ (comment : _)) -> Just comment
      _ -> Nothing
    withStrayRule r = plain {grammarRules = grammarRules plain ++ [RuleParser (strayRule r)]}
    strayRule r =
      ParserRule
        { parserRuleAnn = ()
        , parserRuleName = Name "canonStrayComment"
        , parserRuleModifiers = []
        , parserRuleArguments = Nothing
        , parserRuleReturns = Nothing
        , parserRuleThrows = []
        , parserRuleLocals = Nothing
        , parserRulePrequel = []
        , parserRuleAlternatives =
            LabeledAlternative
              (Alternative () [] [ElementAtom () Nothing (AtomRuleRef r Nothing []) Nothing, ElementAtom () Nothing (AtomWildcard []) (Just (EbnfSuffix ZeroOrMore Greedy))])
              Nothing
              :| []
        , parserRuleHandlers = []
        , parserRuleFinally = Nothing
        }

-- | Reads and parses a file, so callers do not repeat the read.
interpretFile :: Interpreter -> Name -> FilePath -> IO (Either InterpretError ParseTree)
interpretFile interpreter start path = interpretText interpreter start path <$> TIO.readFile path
