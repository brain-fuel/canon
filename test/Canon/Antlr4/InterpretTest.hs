module Canon.Antlr4.InterpretTest (tests) where

import Canon.Antlr4.Grammar (parseGrammarText)
import Canon.Antlr4.Lex
import Canon.Antlr4.Lex.Adaptor (antlrLexerHooks)
import Canon.Antlr4.Parse
import Canon.Antlr4.Query (ruleNames)
import Canon.Antlr4.Read (ReadResult (..), readGrammarFile, renderReadError)
import Canon.Antlr4.Syntax (Grammar, Name (..))
import Canon.Antlr4.Token
import Canon.Span (Span)
import Data.Either (isLeft)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "interpret"
    [ testProperty "words and numbers lex to the expected token types" wordsAndNumbers
    , testProperty "the longest match wins and ties go to the earlier rule" longestMatch
    , testProperty "non-greedy loops stop at the first closer" nonGreedyComment
    , testProperty "lexer modes push and pop" lexerModes
    , testProperty "left-recursive rules parse" leftRecursion
    , testProperty "a parse failure reports the furthest token" failurePosition
    , testProperty "the interpreted meta-grammar parses the parser meta-grammar" bootstrapParserGrammar
    , testProperty "the interpreted meta-grammar parses the lexer meta-grammar" bootstrapLexerGrammar
    , testProperty "the canonical dialect parses its own grammars" canonicalSelfHosting
    , testProperty "the canonical dialect rejects the upstream parser grammar" canonicalRejectsUpstream
    , testProperty "precedence climbing gives ANTLR's tree for expressions" precedenceClimbing
    , testProperty "case-insensitive grammars match either case" caseInsensitive
    ]

grammarOrFail :: Text -> PropertyT IO (Grammar Span)
grammarOrFail source = case parseGrammarText source of
  Left err -> annotate (show err) >> failure
  Right g -> pure g

lexOrFail :: Grammar Span -> Text -> PropertyT IO [Token]
lexOrFail g source = case tokenize g source of
  Left err -> annotate (T.unpack (renderLexError err)) >> failure
  Right toks -> pure toks

wordsGrammar :: Text
wordsGrammar =
  T.unlines
    [ "grammar Words;"
    , "start : item* EOF ;"
    , "item : ID | INT ;"
    , "ID : [a-z]+ ;"
    , "INT : [0-9]+ ;"
    , "WS : [ \\t\\r\\n]+ -> skip ;"
    ]

wordsAndNumbers :: Property
wordsAndNumbers = property $ do
  g <- grammarOrFail wordsGrammar
  pieces <- forAll (Gen.list (Range.linear 0 12) (Gen.choice [Gen.text (Range.linear 1 6) Gen.lower, Gen.text (Range.linear 1 6) Gen.digit]))
  toks <- lexOrFail g (T.unwords pieces)
  let visible = filter (not . isEofToken) toks
  map tokenText visible === pieces
  map (nameText . tokenType) visible === [if T.all (`elem` ['0' .. '9']) piece then "INT" else "ID" | piece <- pieces]
  case parseTokens g (Name "start") toks of
    Left err -> annotate (T.unpack (renderParseError err)) >> failure
    Right tree -> length (treeRuleNodes (Name "item") tree) === length pieces

longestMatch :: Property
longestMatch = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["lexer grammar L;", "A : 'a' ;", "AB : 'ab' ;", "A2 : 'a' ;", "B : 'b' ;"])
  toks <- lexOrFail g "aabab"
  map (nameText . tokenType) toks === ["A", "AB", "AB", "EOF"]

nonGreedyComment :: Property
nonGreedyComment = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["lexer grammar L;", "COMMENT : '/*' .*? '*/' ;", "WORD : [a-z]+ ;", "WS : ' '+ -> skip ;"])
  toks <- lexOrFail g "/* a */ x /* b */"
  map tokenText (filter (not . isEofToken) toks) === ["/* a */", "x", "/* b */"]

lexerModes :: Property
lexerModes = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["lexer grammar L;", "OPEN : '<' -> pushMode(Inside) ;", "TEXT : ~[<]+ ;", "mode Inside;", "CLOSE : '>' -> popMode ;", "NAME : [a-z]+ ;"])
  toks <- lexOrFail g "ab<cd>ef"
  map (nameText . tokenType) toks === ["TEXT", "OPEN", "NAME", "CLOSE", "TEXT", "EOF"]

leftRecursion :: Property
leftRecursion = property $ do
  g <- grammarOrFail (T.unlines ["grammar E;", "start : expr EOF ;", "expr : expr '*' expr | expr '+' expr | INT ;", "INT : [0-9]+ ;", "WS : ' '+ -> skip ;"])
  operands <- forAll (Gen.list (Range.linear 1 5) (Gen.text (Range.linear 1 3) Gen.digit))
  operators <- forAll (Gen.list (Range.singleton (length operands - 1)) (Gen.element ["+", "*"]))
  let source = T.concat (concat (zipWith (\o op -> [o, op]) operands (operators ++ [""])))
  toks <- lexOrFail g source
  case parseTokens g (Name "start") toks of
    Left err -> annotate (T.unpack (renderParseError err)) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "expr") tree) === 2 * length operands - 1
      map tokenText (filter (not . isEofToken) (treeTokens tree)) === filter (not . T.null) (concat (zipWith (\o op -> [o, op]) operands (operators ++ [""])))

failurePosition :: Property
failurePosition = withTests 1 $ property $ do
  g <- grammarOrFail wordsGrammar
  toks <- lexOrFail g "ab 12 cd"
  let broken = [t | t <- toks, not (isEofToken t)]
  case parseTokens g (Name "start") broken of
    Left (ParseNoParse (ParseFailure i _)) -> i === 3
    other -> annotate (show other) >> failure

readOrFail :: FilePath -> PropertyT IO (Grammar Span)
readOrFail path = do
  result <- evalIO (readGrammarFile path)
  case result of
    Left err -> annotate (T.unpack (renderReadError err)) >> failure
    Right r -> pure (readResultGrammar r)

bootstrap :: FilePath -> PropertyT IO (Grammar Span, ParseTree)
bootstrap = bootstrapWith "grammars/antlr4"

bootstrapWith :: FilePath -> FilePath -> PropertyT IO (Grammar Span, ParseTree)
bootstrapWith grammarDir target = do
  result <- interpretWith grammarDir target
  tree <- either (\e -> annotate (T.unpack e) >> failure) pure result
  expected <- readOrFail target
  pure (expected, tree)

interpretWith :: FilePath -> FilePath -> PropertyT IO (Either Text ParseTree)
interpretWith grammarDir target = do
  lexerGrammar <- readOrFail (grammarDir ++ "/ANTLRv4Lexer.g4")
  parserGrammar <- readOrFail (grammarDir ++ "/ANTLRv4Parser.g4")
  table <- either (\e -> annotate (T.unpack (renderLexError e)) >> failure) pure (buildLexerTable lexerGrammar)
  source <- evalIO (TIO.readFile target)
  pure $ do
    toks <- either (Left . renderLexError) Right (tokenizeWith antlrLexerHooks table source)
    either (Left . renderParseError) Right (parseTokens parserGrammar (Name "grammarSpec") toks)

canonicalDir :: FilePath
canonicalDir = "grammars/antlr4/canonically_commented"

canonicalSelfHosting :: Property
canonicalSelfHosting = withTests 1 $ property $ do
  (expectedParser, parserTree) <- bootstrapWith canonicalDir (canonicalDir ++ "/ANTLRv4Parser.g4")
  ruleNamesInTree parserTree === map nameText (ruleNames expectedParser)
  length (treeRuleNodes (Name "ruleSpec") parserTree) === 67
  (expectedLexer, lexerTree) <- bootstrapWith canonicalDir (canonicalDir ++ "/ANTLRv4Lexer.g4")
  length (treeRuleNodes (Name "lexerRuleSpec") lexerTree) === length (ruleNames expectedLexer)
  length [() | spec <- treeRuleNodes (Name "ruleSpec") parserTree, tok <- treeTokens spec, nameText (tokenType tok) == "DOC_COMMENT"] === 67

canonicalRejectsUpstream :: Property
canonicalRejectsUpstream = withTests 1 $ property $ do
  result <- interpretWith canonicalDir "grammars/antlr4/ANTLRv4Parser.g4"
  case result of
    Left message -> assert ("no parse" `T.isInfixOf` message)
    Right _ -> failure
  accepted <- interpretWith "grammars/antlr4" (canonicalDir ++ "/ANTLRv4Parser.g4")
  assert (either (const False) (const True) accepted)

ruleNamesInTree :: ParseTree -> [Text]
ruleNamesInTree tree =
  [ tokenText t
  | spec <- treeRuleNodes (Name "ruleSpec") tree
  , (t : _) <- [[tok | tok <- treeTokens spec, nameText (tokenType tok) `elem` ["RULE_REF", "TOKEN_REF"]]]
  ]

bootstrapParserGrammar :: Property
bootstrapParserGrammar = withTests 1 $ property $ do
  (expected, tree) <- bootstrap "grammars/antlr4/ANTLRv4Parser.g4"
  length (treeRuleNodes (Name "ruleSpec") tree) === 67
  ruleNamesInTree tree === map nameText (ruleNames expected)

bootstrapLexerGrammar :: Property
bootstrapLexerGrammar = withTests 1 $ property $ do
  (expected, tree) <- bootstrap "grammars/antlr4/ANTLRv4Lexer.g4"
  length (treeRuleNodes (Name "lexerRuleSpec") tree) === 68
  length (treeRuleNodes (Name "modeSpec") tree) === 2
  let names = [tokenText t | spec <- treeRuleNodes (Name "lexerRuleSpec") tree, (t : _) <- [[tok | tok <- treeTokens spec, nameText (tokenType tok) == "TOKEN_REF"]]]
  names === map nameText (ruleNames expected)
  assert (isLeft (parseTokens expected (Name "grammarSpec") []))

precedenceClimbing :: Property
precedenceClimbing = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["grammar P;", "start : expr EOF ;", "expr : <assoc=right> expr '^' expr | expr '*' expr | expr '+' expr | '-' expr | INT ;", "INT : [0-9]+ ;"])
  let shapeOf source = do
        toks <- either (const Nothing) Just (tokenize g source)
        tree <- either (const Nothing) Just (parseTokens g (Name "start") toks)
        pure (render tree)
      render tree = case tree of
        RuleNode (Name "start") _ (e : _) -> render e
        RuleNode _ _ [single] -> render single
        RuleNode _ _ children -> T.concat ["(", T.unwords (map render children), ")"]
        TokenNode t -> tokenText t
  shapeOf "1*2+3" === Just "((1 * 2) + 3)"
  shapeOf "1+2*3" === Just "(1 + (2 * 3))"
  shapeOf "1+2+3" === Just "((1 + 2) + 3)"
  shapeOf "2^3^4" === Just "(2 ^ (3 ^ 4))"
  shapeOf "-1+2" === Just "(- (1 + 2))"

caseInsensitive :: Property
caseInsensitive = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["lexer grammar CI;", "options { caseInsensitive = true; }", "BEGIN : 'begin' ;", "ID : [a-z]+ ;", "WS : ' '+ -> skip ;"])
  toks <- lexOrFail g "Begin BEGIN xyz XYZ"
  map (nameText . tokenType) toks === ["BEGIN", "BEGIN", "ID", "ID", "EOF"]
