-- | The interpreter must give the trees ANTLR gives, including for left recursion and for the
-- canonically commented dialects. ref:DEC-precedence-climbing ref:DEC-haskell-dialect
module Canon.Antlr4.InterpretTest (tests) where

import Canon.Antlr4.Grammar (parseGrammarText)
import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, parseWithStrayComments, renderInterpretError, strayCommentRules)
import Canon.Antlr4.Lex
import Canon.Antlr4.Lex.Adaptor (antlrLexerHooks)
import Canon.Antlr4.Lex.JavaScript (javaScriptHooks)
import Canon.Antlr4.Lex.Python (pythonHooks)
import Canon.Antlr4.Parse
import Canon.Antlr4.Query (ruleNames)
import Canon.Antlr4.Read (ReadResult (..), readGrammarFile, renderReadError)
import Canon.Antlr4.Syntax (Grammar, Name (..), nameText)
import Canon.Antlr4.Token
import Canon.Span (Span)
import Control.Exception (evaluate)
import GHC.Conc (getAllocationCounter, setAllocationCounter)
import Data.Either (isLeft)
import System.Timeout (timeout)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
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
    , testProperty "a loop that can split its input many ways fails fast and parses as before" ambiguousLoopFailsFast
    , testProperty "the interpreted meta-grammar parses the parser meta-grammar" bootstrapParserGrammar
    , testProperty "the interpreted meta-grammar parses the lexer meta-grammar" bootstrapLexerGrammar
    , testProperty "the canonical dialect parses its own grammars" canonicalSelfHosting
    , testProperty "the canonical dialect parses a grammar without canonical comments" canonicalParsesUpstream
    , testProperty "the haskell dialect parses canon's own commented source" haskellDialectParsesCanon
    , testProperty "precedence climbing gives ANTLR's tree for expressions" precedenceClimbing
    , testProperty "case-insensitive grammars match either case" caseInsensitive
    , testProperty "the Haskell grammar parses a layout-sensitive module through the ported base lexer" haskellLayout
    , testProperty "the Haskell layout lexes a fragment whose first line is indented deeper than a later one" haskellFragmentDedentsBelowStart
    , testProperty "the Python base lexer port turns newlines into NEWLINE, INDENT, and DEDENT" pythonIndentation
    , testProperty "a predicate inside a block gates only its own alternative" predicateInBlock
    , testProperty "the JavaScript base lexer port decides whether a slash starts a regular expression" regexPredicate
    , testProperty "an empty match is allowed only when it changes mode" emptyMatchChangesMode
    , testProperty "a loop of statements that can each end two ways parses in polynomial time" loopsArePolynomial
    , testProperty "a lexer loop whose alternatives match the same characters stays linear" prop_aLexerLoopWhoseAlternativesMatchTheSameCharactersStaysLinear
    , testProperty "a stray comment where the grammar takes none is an orphan and a syntax error is still reported where it is" prop_aStrayCommentWhereTheGrammarTakesNoneIsAnOrphanAndASyntaxErrorIsStillReportedWhereItIs
    , testProperty "many stray comments are recovered in one parse whose cost grows with the file, not with the comments times the file" prop_manyStrayCommentsAreRecoveredInOneParseWhoseCostGrowsWithTheFileNotWithTheCommentsTimesTheFile
    , testProperty "a long generated file parses in work linear in its length" prop_aLongGeneratedFileParsesInWorkLinearInItsLength
    , testProperty "a lexer fragment of one-character alternatives and longer ones lexes as written" prop_aLexerFragmentOfOneCharacterAlternativesAndLongerOnesLexesAsWritten
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

ambiguousLoopGrammar :: Text
ambiguousLoopGrammar =
  T.unlines
    [ "grammar Splits;"
    , "start : (pair | single)* END EOF ;"
    , "pair : A A ;"
    , "single : A ;"
    , "A : 'a' ;"
    , "END : ';' ;"
    , "WS : [ ]+ -> skip ;"
    ]

-- | A loop whose items can split its input in exponentially many ways must fail in time linear in
-- its input, because canon reads a file that does not parse to report where it stops, and must
-- still give the tree it gave before loops were memoised. ref:DEC-loop-memo
ambiguousLoopFailsFast :: Property
ambiguousLoopFailsFast = withTests 1 $ property $ do
  g <- grammarOrFail ambiguousLoopGrammar
  failing <- lexOrFail g (T.replicate 60 "a ")
  outcome <- evalIO (timeout 10000000 (evaluate (either (const True) (const False) (parseTokens g (Name "start") failing))))
  outcome === Just True
  passing <- lexOrFail g "a a a ;"
  case parseTokens g (Name "start") passing of
    Right tree -> map (\r -> length (treeRuleNodes (Name r) tree)) ["pair", "single"] === [1, 1]
    Left err -> annotate (show err) >> failure

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
  length (treeRuleNodes (Name "ruleSpec") parserTree) === 70
  (expectedLexer, lexerTree) <- bootstrapWith canonicalDir (canonicalDir ++ "/ANTLRv4Lexer.g4")
  length (treeRuleNodes (Name "lexerRuleSpec") lexerTree) === length (ruleNames expectedLexer)
  length [() | spec <- treeRuleNodes (Name "ruleSpec") parserTree, _ <- treeRuleNodes (Name "canonicalComment") spec] === 70
  length (treeRuleNodes (Name "canonicalComment") lexerTree) === 68

-- | grammars-v4's grammars carry no canonical comments, and the dialect must read every one, so a
-- rule without a comment parses and the check reports the comment missing through the rule's
-- required label. ref:REQ-antlr4-support ref:DEC-grammar-carries-extraction-rules
canonicalParsesUpstream :: Property
canonicalParsesUpstream = withTests 1 $ property $ do
  result <- interpretWith canonicalDir "grammars/prolog/prolog.g4"
  case result of
    Left message -> annotate (T.unpack message) >> failure
    Right _ -> pure ()
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
        Labeled _ inner -> render inner
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

haskellLayout :: Property
haskellLayout = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/haskell/HaskellLexer.g4" "grammars/haskell/HaskellParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source =
        T.unlines
          [ "module Sample (double, Shape (..)) where"
          , ""
          , "import Data.List (sort)"
          , ""
          , "-- | A shape."
          , "data Shape = Circle Int | Square Int"
          , ""
          , "double :: Int -> Int"
          , "double x = let y = x in y + y"
          , ""
          , "area :: Shape -> Int"
          , "area s = case s of"
          , "  Circle r -> 3 * r * r"
          , "  Square w -> w * w"
          , ""
          , "main :: IO ()"
          , "main = do"
          , "  print (double 2)"
          , "  print (sort [3, 1, 2])"
          ]
  case interpretText interpreter (Name "module") "Sample.hs" source of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "sigdecl") tree) === 3
      length (treeRuleNodes (Name "ty_decl") tree) === 1
      assert (not (null (treeRuleNodes (Name "impdecl") tree)))

-- | A fragment cut from the middle of a file starts wherever its first token is; a later line
-- indented less than that has no block to close, and the layout must say so and go on rather
-- than emit virtual braces without end. ref:DEC-haskell-grammar-fixes
haskellFragmentDedentsBelowStart :: Property
haskellFragmentDedentsBelowStart = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/haskell/canonically_commented/HaskellLexer.g4" "grammars/haskell/canonically_commented/HaskellParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  case interpreterTokenize interpreter "  ) where\n\nimport Canon.Config\n" of
    Left err -> annotate (T.unpack (renderLexError err)) >> failure
    Right toks -> do
      assert (length toks < 40)
      assert ("import" `elem` map tokenText toks)

haskellDialectParsesCanon :: Property
haskellDialectParsesCanon = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/haskell/canonically_commented/HaskellLexer.g4" "grammars/haskell/canonically_commented/HaskellParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (interpretFile interpreter (Name "module") "src/Canon/Vetting.hs")
  tree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure result
  source <- evalIO (TIO.readFile "src/Canon/Vetting.hs")
  let openers = length (filter (T.isPrefixOf "-- |") (T.lines source))
  length (treeRuleNodes (Name "canonicalComment") tree) === openers
  length [() | n <- treeRuleNodes (Name "topdecl") tree, _ <- treeRuleNodes (Name "canonicalComment") n] === openers - 1

-- | Visible token types, which is what a parser sees.
visibleTypes :: [Token] -> [Text]
visibleTypes toks = [nameText (tokenType t) | t <- toks, tokenChannel t == defaultChannelName]

tableOrFail :: Grammar Span -> PropertyT IO LexerTable
tableOrFail g = either (\e -> annotate (T.unpack (renderLexError e)) >> failure) pure (buildLexerTable g)

lexWithOrFail :: LexerHooks s -> LexerTable -> Text -> PropertyT IO [Token]
lexWithOrFail hooks table source = either (\e -> annotate (T.unpack (renderLexError e)) >> failure) pure (tokenizeWith hooks table source)

pythonGrammar :: Text
pythonGrammar =
  T.unlines
    [ "lexer grammar Py;"
    , "tokens { INDENT, DEDENT }"
    , "NEWLINE: ({this.atStartOfInput()}? SPACES | ( '\\r'? '\\n' | '\\r' | '\\f') SPACES?) {this.onNewLine();};"
    , "NAME: [a-z_]+;"
    , "COLON: ':';"
    , "COMMA: ',';"
    , "OPEN_PAREN: '(' {this.openBrace();};"
    , "CLOSE_PAREN: ')' {this.closeBrace();};"
    , "SKIP_: (SPACES | COMMENT) -> skip;"
    , "fragment SPACES: [ \\t]+;"
    , "fragment COMMENT: '#' ~[\\r\\n\\f]*;"
    ]

pythonIndentation :: Property
pythonIndentation = withTests 1 $ property $ do
  g <- grammarOrFail pythonGrammar
  table <- tableOrFail g
  toks <- lexWithOrFail pythonHooks table "def f(a,\n  b):\n    x\n\n    # a comment line is not a statement\n    y\nz\n"
  visibleTypes toks
    === ["NAME", "NAME", "OPEN_PAREN", "NAME", "COMMA", "NAME", "CLOSE_PAREN", "COLON", "NEWLINE", "INDENT", "NAME", "NEWLINE", "NAME", "NEWLINE", "DEDENT", "NAME", "NEWLINE", "EOF"]
  unterminated <- lexWithOrFail pythonHooks table "if x:\n    y"
  visibleTypes unterminated === ["NAME", "NAME", "COLON", "NEWLINE", "INDENT", "NAME", "NEWLINE", "DEDENT", "EOF"]

predicateInBlock :: Property
predicateInBlock = withTests 1 $ property $ do
  g <- grammarOrFail pythonGrammar
  table <- tableOrFail g
  -- Leading spaces at the start of input are a NEWLINE only because the predicate in the first
  -- alternative of the block holds there; a newline later must not be refused by it.
  toks <- lexWithOrFail pythonHooks table "  x\ny\n"
  visibleTypes toks === ["NEWLINE", "INDENT", "NAME", "NEWLINE", "DEDENT", "NAME", "NEWLINE", "EOF"]

regexPredicate :: Property
regexPredicate = withTests 1 $ property $ do
  g <-
    grammarOrFail $
      T.unlines
        [ "lexer grammar J;"
        , "RegularExpressionLiteral: '/' {this.IsRegexPossible()}? ~[/\\n]+ '/';"
        , "Divide: '/';"
        , "Identifier: [a-z]+;"
        , "WS: [ \\n]+ -> skip;"
        ]
  table <- tableOrFail g
  withBase <- lexWithOrFail javaScriptHooks table "a / b / c"
  visibleTypes withBase === ["Identifier", "Divide", "Identifier", "Divide", "Identifier", "EOF"]
  atStart <- lexWithOrFail javaScriptHooks table "/ b / c"
  visibleTypes atStart === ["RegularExpressionLiteral", "Identifier", "EOF"]
  without <- lexWithOrFail noHooks table "a / b / c"
  assert ("RegularExpressionLiteral" `elem` visibleTypes without)

emptyMatchChangesMode :: Property
emptyMatchChangesMode = withTests 1 $ property $ do
  g <-
    grammarOrFail $
      T.unlines
        [ "lexer grammar G;"
        , "ID: [a-z]+ -> mode(NLSEMI);"
        , "LBRACK: '[';"
        , "WS: [ \\n]+ -> skip;"
        , "mode NLSEMI;"
        , "WS_N: [ ]+ -> skip;"
        , "EOS: '\\n'+ -> mode(DEFAULT_MODE);"
        , "OTHER: -> mode(DEFAULT_MODE), channel(HIDDEN);"
        ]
  table <- tableOrFail g
  toks <- lexWithOrFail noHooks table "a [b\n"
  visibleTypes toks === ["ID", "LBRACK", "ID", "EOS", "EOF"]
  looping <- grammarOrFail (T.unlines ["lexer grammar E;", "A: 'a'*;", "B: 'b';"])
  assert (isLeft (tokenize looping "c"))

loopsArePolynomial :: Property
loopsArePolynomial = withTests 1 $ property $ do
  g <-
    grammarOrFail $
      T.unlines
        [ "grammar S;"
        , "program: statement+ EOF;"
        , "statement: ID eos | SEMI;"
        , "eos: SEMI | {this.lineTerminatorAhead()}?;"
        , "ID: [a-z]+;"
        , "SEMI: ';';"
        , "WS: [ \\n]+ -> skip;"
        ]
  toks <- lexOrFail g (T.replicate 200 "a; ")
  case parseTokens g (Name "program") toks of
    Left err -> annotate (T.unpack (renderParseError err)) >> failure
    Right tree -> assert (not (null (treeRuleNodes (Name "statement") tree)))

-- | A grammar that names a comment rule in a strayComment option, whose orphan label accepts a
-- comment only before a statement.
strayGrammar :: Bool -> Text
strayGrammar withOption =
  T.unlines $
    [ "grammar Stray;"
    ]
      ++ ["options { strayComment = doc; }" | withOption]
      ++ [ "start : stmt* (orphan = doc)* EOF ;"
         , "stmt : (orphan = doc)* ID EQ expr SEMI ;"
         , "expr : ID (PLUS ID)* | why = doc ID KW ID ;"
         , "KW : 'as' ;"
         , "doc : OPEN ID* CLOSE ;"
         , "OPEN : '[[' ;"
         , "CLOSE : ']]' ;"
         , "EQ : '=' ;"
         , "PLUS : '+' ;"
         , "SEMI : ';' ;"
         , "ID : [a-z]+ ;"
         , "WS : [ ]+ -> skip ;"
         ]

-- | A doc comment may stand between any two tokens of a file the compiler accepts, so a dialect that
-- names its comment rule in a strayComment option must read a file with one where its grammar takes
-- none, report that comment as an orphan, and leave every other parse and every syntax error as it
-- was, at the token the parse stopped at; a grammar without the option is unchanged.
-- ref:REQ-rust-support ref:REQ-csharp-support ref:DEC-stray-comments
prop_aStrayCommentWhereTheGrammarTakesNoneIsAnOrphanAndASyntaxErrorIsStillReportedWhereItIs :: Property
prop_aStrayCommentWhereTheGrammarTakesNoneIsAnOrphanAndASyntaxErrorIsStillReportedWhereItIs = withTests 1 $ property $ do
  with <- grammarOrFail (strayGrammar True)
  without <- grammarOrFail (strayGrammar False)
  strayCommentRules with === [Name "doc"]
  strayCommentRules without === []
  let parse g source = case tokenize g source of
        Left err -> Left (renderLexError err)
        Right toks -> either (Left . renderParseError) Right (parseWithStrayComments (\_ _ _ _ -> True) g (Name "start") toks)
      orphans tree = case tree of
        RuleNode _ _ children -> sum (map orphans children)
        Labeled "orphan" _ -> 1 :: Int
        Labeled _ inner -> orphans inner
        TokenNode _ -> 0
      orphanTexts tree = case tree of
        RuleNode _ _ children -> concatMap orphanTexts children
        Labeled "orphan" inner -> [T.unwords (map tokenText (treeTokens inner))]
        Labeled _ inner -> orphanTexts inner
        TokenNode _ -> []
  -- Before a statement the grammar takes the comment, with the option or without it.
  fmap orphans (parse with "[[ a ]] x = y ;") === Right 1
  fmap orphans (parse without "[[ a ]] x = y ;") === Right 1
  -- Inside an expression, before a semicolon, and at the end of a statement only the option reads it.
  fmap orphanTexts (parse with "x = y [[ inside ]] + z [[ before semi ]] ; [[ last ]]") === Right ["[[ last ]]", "[[ inside ]]", "[[ before semi ]]"]
  assert (isLeft (parse without "x = y [[ inside ]] + z ;"))
  -- A path that reads the comment as a Why may carry the failure a token past it, and the comment
  -- is still taken for its cause.
  fmap orphanTexts (parse with "x = [[ why ]] z ;") === Right ["[[ why ]]"]
  fmap orphans (parse with "x = [[ why ]] z as w ;") === Right 0
  -- Two stray comments side by side leave the failure at the same token once the first is dropped,
  -- and both are still orphans.
  fmap orphanTexts (parse with "x = y [[ one ]] [[ two ]] ;") === Right ["[[ one ]]", "[[ two ]]"]
  -- A stray comment of any length is found, however far back its opener stands.
  fmap orphans (parse with ("x = y [[ " <> T.replicate 800 "w " <> "]] ;")) === Right 1
  -- A syntax error is reported where it is, with or without a stray comment before it.
  parse with "x = y + ; z = w ;" === parse without "x = y + ; z = w ;"
  parse with "x = [[ note ]] y + ; z = w ;" === Left "1:20: no parse at token SEMI@1:20 \";\""

-- | Grammars written for one target often list a character under two alternatives of a loop, as an
-- identifier part that is both a letter and a connector, and a backtracking lexer that continued
-- once per way of reaching a position doubled its work with each such character; canon reads the
-- grammars-v4 lexers as they are, so the loop must be linear however its alternatives overlap.
-- ref:REQ-javascript-support ref:DEC-lexer-performance
prop_aLexerLoopWhoseAlternativesMatchTheSameCharactersStaysLinear :: Property
prop_aLexerLoopWhoseAlternativesMatchTheSameCharactersStaysLinear = withTests 1 $ property $ do
  g <- grammarOrFail (T.unlines ["lexer grammar Overlap;", "ID : [a-z] ([a-z_] | '_' | [_a-z])* ;", "WS : [ ]+ -> skip ;"])
  toks <- lexOrFail g ("a" <> T.replicate 60 "_" <> "b c")
  map tokenText (filter (not . isEofToken) toks) === ["a" <> T.replicate 60 "_" <> "b", "c"]

-- | The bytes the current thread allocates while a value is forced.
allocationOf :: a -> IO Int
allocationOf value = do
  setAllocationCounter 0
  _ <- evaluate value
  negate . fromIntegral <$> getAllocationCounter

-- | A file may hold a doc comment inside an expression on every few lines, and each one costs the
-- dialect a round of recovery; a round that read the whole file again made the cost the comments
-- times the file, and a TypeScript checker of 53,000 lines with 40 such comments took three
-- minutes. A round reads only what the dropped comment changed, so twice the statements, each with a
-- stray comment, costs about twice the work, every comment is an orphan in order, and a syntax error
-- after them is reported where it is. ref:REQ-javascript-support ref:REQ-typescript-support
-- ref:DEC-stray-comments
prop_manyStrayCommentsAreRecoveredInOneParseWhoseCostGrowsWithTheFileNotWithTheCommentsTimesTheFile :: Property
prop_manyStrayCommentsAreRecoveredInOneParseWhoseCostGrowsWithTheFileNotWithTheCommentsTimesTheFile = withTests 1 $ property $ do
  g <- grammarOrFail (strayGrammar True)
  let word i = T.pack (map (\d -> toEnum (fromEnum d + 49)) (show i))
      source k = T.concat ["x = y [[ c" <> word i <> " ]] + z ; " | i <- [1 .. k :: Int]]
      parse text = case tokenize g text of
        Left err -> Left (renderLexError err)
        Right toks -> either (Left . renderParseError) Right (parseWithStrayComments (\_ _ _ _ -> True) g (Name "start") toks)
      orphanTexts tree = case tree of
        RuleNode _ _ children -> concatMap orphanTexts children
        Labeled "orphan" inner -> [T.unwords (map tokenText (treeTokens inner))]
        Labeled _ inner -> orphanTexts inner
        TokenNode _ -> []
  fmap orphanTexts (parse (source 300)) === Right ["[[ c" <> word i <> " ]]" | i <- [1 .. 300 :: Int]]
  let column = T.pack (show (T.length (source 300) + 9))
  parse (source 300 <> "x = y + ;") === Left ("1:" <> column <> ": no parse at token SEMI@1:" <> column <> " \";\"")
  small <- evalIO (allocationOf (fmap (length . orphanTexts) (parse (source 200))))
  large <- evalIO (allocationOf (fmap (length . orphanTexts) (parse (source 400))))
  annotate ("allocated " ++ show small ++ " and " ++ show large ++ " bytes")
  assert (large < 3 * small)

-- | A generated C# file of 31,000 lines took 58 seconds and 10 GB when every memo entry held its
-- trees; the recognizer keeps ends only and the tree is built along the one parse returned, so the
-- work of a file of simple statements grows with its length. Twice the statements cost about twice
-- the allocation, and each statement stays within a bound the old parser exceeded tenfold.
-- ref:REQ-csharp-support ref:DEC-parser-memory
prop_aLongGeneratedFileParsesInWorkLinearInItsLength :: Property
prop_aLongGeneratedFileParsesInWorkLinearInItsLength = withTests 1 $ property $ do
  loaded <- evalIO (loadInterpreter "grammars/csharp/CSharpLexer.g4" "grammars/csharp/CSharpParser.g4")
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  let source k =
        T.unlines $
          ["class C {", "  void M() {"]
            ++ [T.pack ("    Requests[" ++ show i ++ "].Request.Method = HttpMethods.GetCanonicalizedValue(\"PUT\");") | i <- [1 .. k :: Int]]
            ++ ["  }", "}"]
      statements tree = length (treeRuleNodes (Name "statement") tree)
      parse k = either (const 0) statements (interpretText interpreter (Name "compilation_unit") "Generated.cs" (source k))
  small <- evalIO (allocationOf (parse 1000))
  large <- evalIO (allocationOf (parse 2000))
  parse 2000 === 2000
  annotate ("allocated " ++ show small ++ " and " ++ show large ++ " bytes")
  assert (large < 3 * small)
  assert (large < 2000 * 4000000)

-- | The grammars-v4 lexers spell a character class as a fragment of alternatives, some one character
-- and some longer, as JavaScript's identifier start is a letter, a dollar, or a backslash escape. The
-- one-character alternatives are read as one test, which must give the tokens the fragment as written
-- gives. ref:REQ-javascript-support ref:DEC-lexer-performance
prop_aLexerFragmentOfOneCharacterAlternativesAndLongerOnesLexesAsWritten :: Property
prop_aLexerFragmentOfOneCharacterAlternativesAndLongerOnesLexesAsWritten = withTests 1 $ property $ do
  g <-
    grammarOrFail $
      T.unlines
        [ "grammar L;"
        , "start : (ID | NUM)* EOF ;"
        , "ID : Start Part* ;"
        , "NUM : Digit+ ;"
        , "WS : (' ' | Newline)+ -> skip ;"
        , "fragment Start : [a-z] | '$' | '\\\\' 'u' Digit Digit | Upper ;"
        , "fragment Part : Start | Digit | '_' ;"
        , "fragment Upper : 'A' | 'B' | 'C' ;"
        , "fragment Digit : '0' | '1' | '2' | [3-9] ;"
        , "fragment Newline : '\\r\\n' | '\\n' | '\\r' ;"
        ]
  toks <- lexOrFail g "ab_1 $C2 \\u12x\r\n42 B\nzz9"
  [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t)]
    === [("ID", "ab_1"), ("ID", "$C2"), ("ID", "\\u12x"), ("NUM", "42"), ("ID", "B"), ("ID", "zz9")]
