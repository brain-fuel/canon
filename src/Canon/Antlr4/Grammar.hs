-- | The reader is one scannerless grammar record on grammatical-parsers, because a record that knows
-- whether it is inside a parser or lexer rule makes a separate lexer adaptor unnecessary.
-- ref:DEC-parser-foundation
module Canon.Antlr4.Grammar
  ( G4 (..)
  , Offsets (..)
  , ParseError (..)
  , g4Grammar
  , fixedGrammar
  , parseGrammarText
  ) where

import Canon.Antlr4.Lexical
import Canon.Antlr4.Syntax
import Control.Applicative (empty, many, optional, (<|>))
import Control.Monad (guard, void, when)
import Data.Functor (($>))
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Rank2.TH
import qualified Text.Grampa as G
import Text.Grampa.PEG.Packrat (Parser)
import qualified Text.Parser.Input.Position as Position

-- | The reader annotates every node with input offsets, from which spans are computed afterwards,
-- because grampa works on offsets.
data Offsets = Offsets
  { offsetsStartFromEnd :: Int
  , offsetsEndFromEnd :: Int
  }
  deriving (Eq, Show)

-- | A reader failure carries where it happened, so a grammar file error is reported at a position.
data ParseError = ParseError
  { parseErrorPosition :: Position
  , parseErrorExpected :: [Text]
  , parseErrorMessage :: Text
  }
  deriving (Eq, Show)

-- | The grammar record: one field per ANTLR meta-grammar production, so the reader is the
-- meta-grammar written as Haskell.
data G4 p = G4
  { grammarSpec :: p (Grammar Offsets)
  , prequelConstruct :: p Prequel
  , optionsSpec :: p [Option]
  , option :: p Option
  , optionValue :: p OptionValue
  , namedAction :: p NamedAction
  , ruleSpec :: p (Rule Offsets)
  , parserRuleSpec :: p (ParserRule Offsets)
  , lexerRuleSpec :: p (LexerRule Offsets)
  , modeSpec :: p (Mode Offsets)
  , labeledAlt :: p (LabeledAlternative Offsets)
  , alternative :: p (Alternative Offsets)
  , element :: p (Element Offsets)
  , atom :: p Atom
  , block :: p (Block Offsets)
  , ebnfSuffix :: p EbnfSuffix
  , lexerAlt :: p (LexerAlternative Offsets)
  , lexerElement :: p (LexerElement Offsets)
  , lexerAtom :: p LexerAtom
  , lexerCommand :: p LexerCommand
  , notSet :: p NotSet
  , setElement :: p SetElement
  , characterRange :: p CharRange
  , terminalDef :: p Terminal
  , elementOptions :: p [ElementOption]
  , elementOption :: p ElementOption
  , identifier :: p Name
  , ruleRef :: p Name
  , tokenRef :: p Name
  , qualifiedIdentifier :: p QualifiedName
  , stringLiteral :: p StringLiteral
  , actionBlock :: p ActionText
  , argActionBlock :: p ArgumentText
  , charSet :: p CharSet
  , intLiteral :: p Integer
  }

$(Rank2.TH.deriveAll ''G4)

type P = Parser G4 Text

isWsChar :: Char -> Bool
isWsChar c = c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f'

blockKeywords :: [Text]
blockKeywords = ["options", "tokens", "channels"]

positionFromEnd :: P Int
positionFromEnd = (\(Down n) -> n) <$> G.getSourcePos

scanned :: (Text -> Maybe Int) -> P Text
scanned scan = do
  input <- G.getInput
  case scan input of
    Just n | n > 0 -> G.take n
    _ -> empty

ws :: P ()
ws = G.skipMany (void (G.satisfyCharInput isWsChar) <|> void (scanned commentLength))
  where
    commentLength t
      | "/*" `T.isPrefixOf` t = scanBlockComment t
      | "//" `T.isPrefixOf` t = Just (scanLineComment t)
      | otherwise = Nothing

lexeme :: P a -> P a
lexeme p = ws *> p

symbol :: Text -> P ()
symbol t = lexeme (void (G.string t))

symbolNotFollowedBy :: Text -> (Char -> Bool) -> P ()
symbolNotFollowedBy t excluded = lexeme (G.string t *> G.notFollowedBy (G.satisfyCharInput excluded))

keywordToken :: Text -> P ()
keywordToken k = lexeme (G.string k *> G.notFollowedBy (G.satisfyCharInput isNameChar))

blockKeyword :: Text -> P ()
blockKeyword k = lexeme (G.string k *> G.skipMany (G.satisfyCharInput isWsChar) *> void (G.char '{'))

nameToken :: P Name
nameToken = lexeme $ do
  t <- scanned scanName
  guard (not (Set.member t reservedWords))
  when (t `elem` blockKeywords) $
    G.notFollowedBy (G.skipMany (G.satisfyCharInput isWsChar) *> G.char '{')
  pure (Name t)

delimited :: (Text -> Maybe Int) -> P Text
delimited scan = lexeme (stripDelimiters <$> scanned scan)
  where
    stripDelimiters t = T.drop 1 (T.dropEnd 1 t)

withOffsets :: P (Offsets -> a) -> P a
withOffsets p = do
  ws
  start <- positionFromEnd
  build <- p
  end <- positionFromEnd
  pure (build (Offsets start end))

sepBy1NE :: P a -> P () -> P (NonEmpty a)
sepBy1NE p sep = (:|) <$> p <*> many (sep *> p)

sepBy :: P a -> P () -> P [a]
sepBy p sep = ((:) <$> p <*> many (sep *> p)) <|> pure []

optionalList :: P [a] -> P [a]
optionalList p = fromMaybe [] <$> optional p

-- | The record filled in with its productions, before the fixpoint that ties recursive references
-- together.
g4Grammar :: G.GrammarBuilder G4 G4 Parser Text
g4Grammar G4{..} =
  G4
    { grammarSpec =
        (\kind name prequel rules modes -> Grammar kind name prequel rules modes)
          <$> grammarKindP
          <*> identifier
          <* symbol ";"
          <*> many prequelConstruct
          <*> many ruleSpec
          <*> many modeSpec
          <* ws
    , prequelConstruct =
        PrequelOptions <$> optionsSpec
          <|> PrequelImports <$> (keywordToken "import" *> sepBy1NE importP (symbol ",") <* symbol ";")
          <|> PrequelTokens <$> nameBlock "tokens"
          <|> PrequelChannels <$> nameBlock "channels"
          <|> PrequelAction <$> (symbol "@" *> optional (actionScopeName <* symbol "::")) <*> namedActionBody
    , optionsSpec = blockKeyword "options" *> many (option <* symbol ";") <* symbol "}"
    , option = Option <$> identifier <* symbol "=" <*> optionValue
    , optionValue =
        OptionValueName <$> qualifiedIdentifier
          <|> OptionValueString <$> stringLiteral
          <|> OptionValueAction <$> actionBlock
          <|> OptionValueInt <$> intLiteral
    , namedAction = symbol "@" *> namedActionBody
    , ruleSpec = RuleParser <$> parserRuleSpec <|> RuleLexer <$> lexerRuleSpec
    , parserRuleSpec =
        withOffsets $
          (\mods name args rets throws locals prequel alts handlers fin ann ->
             ParserRule ann name mods args rets throws locals prequel alts handlers fin)
            <$> many ruleModifier
            <*> ruleRef
            <*> optional argActionBlock
            <*> optional (keywordToken "returns" *> argActionBlock)
            <*> optionalList (keywordToken "throws" *> ((:) <$> qualifiedIdentifier <*> many (symbol "," *> qualifiedIdentifier)))
            <*> optional (keywordToken "locals" *> argActionBlock)
            <*> many (RulePrequelOptions <$> optionsSpec <|> RulePrequelAction <$> namedAction)
            <* symbol ":"
            <*> sepBy1NE labeledAlt (symbol "|")
            <* symbol ";"
            <*> many (ExceptionHandler <$> (keywordToken "catch" *> argActionBlock) <*> actionBlock)
            <*> optional (keywordToken "finally" *> actionBlock)
    , lexerRuleSpec =
        withOffsets $
          (\isFragment name opts alts ann -> LexerRule ann name isFragment opts alts)
            <$> (maybe False (const True) <$> optional (keywordToken "fragment"))
            <*> tokenRef
            <*> optionalList optionsSpec
            <* symbol ":"
            <*> sepBy1NE lexerAlt (symbol "|")
            <* symbol ";"
    , modeSpec =
        withOffsets $
          (\name rules ann -> Mode ann name rules)
            <$> (keywordToken "mode" *> identifier <* symbol ";")
            <*> many lexerRuleSpec
    , labeledAlt = LabeledAlternative <$> alternative <*> optional (symbol "#" *> identifier)
    , alternative =
        withOffsets $
          (\opts elements ann -> Alternative ann opts elements)
            <$> optionalList elementOptions
            <*> many element
    , element =
        withOffsets $
          labeledElement
            <|> (\a s ann -> ElementAtom ann Nothing a s) <$> atom <*> optional ebnfSuffix
            <|> (\b s ann -> ElementBlock ann Nothing b s) <$> block <*> optional ebnfSuffix
            <|> (\body form opts ann -> ElementAction ann form body opts)
              <$> actionBlock
              <*> actionForm
              <*> optionalList elementOptions
    , atom =
        AtomTerminal <$> terminalDef
          <|> AtomRuleRef <$> ruleRef <*> optional argActionBlock <*> optionalList elementOptions
          <|> AtomNotSet <$> notSet
          <|> AtomWildcard <$> wildcard
    , block =
        symbol "("
          *> ( (\(opts, actions) alts -> Block opts actions alts)
                 <$> (blockPrefix <|> pure ([], []))
                 <*> sepBy1NE alternative (symbol "|")
             )
          <* symbol ")"
    , ebnfSuffix =
        (\q g -> EbnfSuffix q g)
          <$> (Optional <$ symbol "?" <|> ZeroOrMore <$ symbol "*" <|> OneOrMore <$ symbolNotFollowedBy "+" (== '='))
          <*> (NonGreedy <$ symbol "?" <|> pure Greedy)
    , lexerAlt =
        withOffsets $
          (\elements commands ann -> LexerAlternative ann elements commands)
            <$> many lexerElement
            <*> optionalList (symbol "->" *> ((:) <$> lexerCommand <*> many (symbol "," *> lexerCommand)))
    , lexerElement =
        withOffsets $
          (\a s ann -> LexerElementAtom ann a s) <$> lexerAtom <*> optional ebnfSuffix
            <|> (\alts s ann -> LexerElementBlock ann alts s)
              <$> (symbol "(" *> sepBy1NE lexerAlt (symbol "|") <* symbol ")")
              <*> optional ebnfSuffix
            <|> (\body form ann -> LexerElementAction ann form body) <$> actionBlock <*> actionForm
    , lexerAtom =
        LexerAtomRange <$> characterRange
          <|> LexerAtomTerminal <$> terminalDef
          <|> LexerAtomNotSet <$> notSet
          <|> LexerAtomCharSet <$> charSet
          <|> LexerAtomWildcard <$> wildcard
    , lexerCommand =
        LexerCommand
          <$> (identifier <|> Name "mode" <$ keywordToken "mode")
          <*> optional (symbol "(" *> (CommandArgumentName <$> identifier <|> CommandArgumentInt <$> intLiteral) <* symbol ")")
    , notSet =
        symbol "~"
          *> ( NotSet
                 <$> ( (:| []) <$> setElement
                         <|> symbol "(" *> sepBy1NE setElement (symbol "|") <* symbol ")"
                     )
             )
    , setElement =
        SetRange <$> characterRange
          <|> SetTerminal <$> terminalDef
          <|> SetCharSet <$> charSet
    , characterRange = CharRange <$> stringLiteral <* symbol ".." <*> stringLiteral
    , terminalDef =
        TerminalToken <$> tokenRef <*> optionalList elementOptions
          <|> TerminalLiteral <$> stringLiteral <*> optionalList elementOptions
    , elementOptions = symbol "<" *> ((:) <$> elementOption <*> many (symbol "," *> elementOption)) <* symbol ">"
    , elementOption =
        ElementOptionAssign <$> identifier <* symbol "=" <*> optionValue
          <|> ElementOptionFlag <$> qualifiedIdentifier
    , identifier = nameToken
    , ruleRef = do
        name <- nameToken
        guard (not (nameIsTokenName name))
        pure name
    , tokenRef = do
        name <- nameToken
        guard (nameIsTokenName name)
        pure name
    , qualifiedIdentifier = QualifiedName <$> sepBy1NE identifier (symbolNotFollowedBy "." (== '.'))
    , stringLiteral = StringLiteral <$> delimited scanStringLiteral
    , actionBlock = ActionText <$> delimited scanAction
    , argActionBlock = ArgumentText <$> delimited scanArgument
    , charSet = CharSet <$> delimited scanCharSet
    , intLiteral = lexeme (read . T.unpack <$> scanned scanInt)
    }
  where
    grammarKindP =
      (keywordToken "lexer" *> keywordToken "grammar" $> LexerGrammar)
        <|> (keywordToken "parser" *> keywordToken "grammar" $> ParserGrammar)
        <|> (keywordToken "grammar" $> CombinedGrammar)
    importP =
      Import <$> (Just <$> identifier <* symbol "=") <*> identifier
        <|> Import Nothing <$> identifier
    nameBlock keyword = blockKeyword keyword *> sepBy identifier (symbol ",") <* optional (symbol ",") <* symbol "}"
    actionScopeName =
      identifier
        <|> Name "lexer" <$ keywordToken "lexer"
        <|> Name "parser" <$ keywordToken "parser"
    namedActionBody = NamedAction <$> identifier <*> actionBlock
    ruleModifier =
      RuleModifierPublic <$ keywordToken "public"
        <|> RuleModifierPrivate <$ keywordToken "private"
        <|> RuleModifierProtected <$ keywordToken "protected"
        <|> RuleModifierFragment <$ keywordToken "fragment"
    labeledElement = do
      name <- identifier
      kind <- LabelAppend <$ symbol "+=" <|> LabelAssign <$ symbol "="
      let label = Just (Label name kind)
      (\a s ann -> ElementAtom ann label a s) <$> atom <*> optional ebnfSuffix
        <|> (\b s ann -> ElementBlock ann label b s) <$> block <*> optional ebnfSuffix
    actionForm = SemanticPredicate <$ symbol "?" <|> pure EmbeddedAction
    blockPrefix = (,) <$> optionalList optionsSpec <*> many namedAction <* symbol ":"
    wildcard = symbolNotFollowedBy "." (== '.') *> optionalList elementOptions

-- | The grammar after grampa has tied the knot, which is the value that parses.
fixedGrammar :: G4 (Parser G4 Text)
fixedGrammar = G.fixGrammar g4Grammar

-- | Parses a whole grammar file to its representation with offsets, the only entry point the reader
-- exposes.
parseGrammarText :: Text -> Either ParseError (Grammar Span)
parseGrammarText source =
  case grammarSpec (G.parseComplete fixedGrammar source) of
    Left failure -> Left (toParseError failure)
    Right g -> Right (fmap toSpan g)
  where
    total = T.length source
    table = lineTable source
    toSpan (Offsets start end) = spanBetween table (total - start) (total - end)
    toParseError failure@(G.ParseFailure pos (G.FailureDescription statics literals) errors) =
      ParseError
        { parseErrorPosition = positionAt table (Position.offset source pos)
        , parseErrorExpected = map T.pack statics ++ literals ++ map T.pack errors
        , parseErrorMessage = G.failureDescription source failure 2
        }
