-- | Syntax highlighting from the language's own lexer: the tokens the check reads are classified
-- into a few classes a stylesheet colours, generically from the shape of the grammar and from
-- the profile's overrides, and laid over the text line by line so the pieces of a line tile it
-- exactly. A text the lexer refuses is plain. The classes are keyword, comment, string, number,
-- type, meta, name, and plain. ref:DEC-highlight-by-lexer
module Canon.Highlight
  ( Piece (..)
  , Classifier (..)
  , classifierFor
  , highlightLines
  , plainLines
  , classes
  ) where

import Canon.Antlr4.Escape (decodeStringLiteral)
import Canon.Antlr4.Interpret (Interpreter (..))
import Canon.Antlr4.Query (implicitLiteralTokens, lexerRules)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token (..), hiddenChannelName, isEofToken)
import Data.Char (isAlpha, isAlphaNum, isSpace, isUpper, toLower)
import Data.List (sortOn)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

-- | A run of one line with its class.
data Piece = Piece
  { pieceClass :: Text
  , pieceText :: Text
  }
  deriving (Eq, Show)

-- | What a grammar's tokens are: the names that are keywords, read from the grammar, and the
-- names the profile assigns to a class outright.
data Classifier = Classifier
  { classifierKeywords :: Set Name
  , classifierOverrides :: Map Name Text
  }
  deriving (Eq, Show)

-- | The classes, in the order a stylesheet lists them.
classes :: [Text]
classes = ["keyword", "comment", "string", "number", "type", "meta", "name", "plain"]

-- | Reads the classifier off a grammar: a lexer rule whose every alternative is one alphabetic
-- literal is a keyword, as is an implicit literal of letters; the profile's map, class to token
-- names, is inverted into overrides.
classifierFor :: Map Text [Text] -> Interpreter -> Classifier
classifierFor overrides interpreter = Classifier (Set.fromList (named ++ implicit)) inverted
  where
    grammar = interpreterLexer interpreter
    named = [lexerRuleName l | l <- lexerRules grammar, not (lexerRuleIsFragment l), all literalAlternative (NonEmpty.toList (lexerRuleAlternatives l))]
    literalAlternative alt = case lexerAlternativeElements alt of
      [LexerElementAtom _ (LexerAtomTerminal (TerminalLiteral s _)) Nothing] -> alphabetic s
      _ -> False
    implicit = [Name (T.pack ("T__" ++ show i)) | (i, s) <- zip [0 :: Int ..] (implicitLiteralTokens grammar), alphabetic s]
    alphabetic s = case decodeStringLiteral s of
      Right t -> not (T.null t) && T.all isAlpha t
      Left _ -> False
    inverted = Map.fromList [(Name n, cls) | (cls, names) <- Map.toList overrides, n <- names]

-- | Every line plain.
plainLines :: Text -> [[Piece]]
plainLines source = [[Piece "plain" l] | l <- T.lines source]

-- | The lines of a text with their pieces. The tokens are laid over the text by their offsets, a
-- gap the lexer skipped is a comment when it holds anything but whitespace, and a piece that
-- spans lines is split at each line break with its class repeated.
highlightLines :: Classifier -> Interpreter -> Text -> [[Piece]]
highlightLines classifier interpreter source = case interpreterTokenize interpreter source of
  Left _ -> plainLines source
  Right toks ->
    let real = dropOverlaps (sortOn tokenStart [t | t <- toks, not (isEofToken t), tokenEnd t > tokenStart t, slice (tokenStart t) (tokenEnd t) == tokenText t])
        pieces = walk 0 "plain" False real
     in map merge (splitLines (T.lines source) pieces)
  where
    n = T.length source
    slice from to = T.take (to - from) (T.drop from source)
    dropOverlaps ts = go 0 ts
      where
        go _ [] = []
        go end (t : rest)
          | tokenStart t < end = go end rest
          | otherwise = t : go (tokenEnd t) rest
    -- Whitespace between two tokens of one class keeps that class, so a comment the lexer read
    -- word by word is one piece again.
    walk at previous inPragma ts = case ts of
      [] -> gap at n previous "plain"
      (t : rest) ->
        let (cls, inPragma') = classify t inPragma
         in gap at (tokenStart t) previous cls ++ [Piece cls (tokenText t)] ++ walk (tokenEnd t) cls inPragma' rest
    gap from to before after
      | to <= from = []
      | T.all isSpace text = [Piece (if before == after then before else "plain") text]
      | otherwise = [Piece "comment" text]
      where
        text = slice from to
    classify t inPragma
      | T.all isSpace (tokenText t) = ("plain", inPragma)
      | Just cls <- Map.lookup (tokenType t) (classifierOverrides classifier) = (cls, inPragma)
      | pragmaName && opens = ("meta", True)
      | pragmaName && closes = ("meta", False)
      | inPragma = ("meta", True)
      | pragmaName = ("meta", inPragma)
      | Set.member (tokenType t) (classifierKeywords classifier) = ("keyword", inPragma)
      | "DOC_" `T.isPrefixOf` name || "COMMENT" `T.isInfixOf` upper || tokenChannel t == hiddenChannelName = ("comment", inPragma)
      | any (`T.isPrefixOf` upper) ["STRING", "CHAR", "TEXT_BLOCK"] = ("string", inPragma)
      | any (`T.isPrefixOf` upper) ["DECIMAL", "OCTAL", "HEX", "BINARY", "INTEGER", "FLOAT", "NUMBER"] = ("number", inPragma)
      | typeLike (tokenText t) = ("type", inPragma)
      | otherwise = ("plain", inPragma)
      where
        name = nameText (tokenType t)
        upper = T.toUpper name
        lower = T.map toLower name
        pragmaName = "pragma" `T.isInfixOf` lower
        opens = "open" `T.isPrefixOf` lower
        closes = "close" `T.isPrefixOf` lower
    typeLike text = case T.uncons text of
      Just (c, rest) -> isUpper c && T.all (\ch -> isAlphaNum ch || ch == '_' || ch == '\'') rest
      Nothing -> False

-- | Distributes pieces over the lines of the text, cutting a piece at each line break.
splitLines :: [Text] -> [Piece] -> [[Piece]]
splitLines ls pieces = take (length ls) (go pieces [] ++ repeat [])
  where
    go [] current = [reverse current]
    go (Piece cls text : rest) current = case T.breakOn "\n" text of
      (before, after)
        | T.null after -> go rest (Piece cls before : current)
        | otherwise -> reverse (Piece cls before : current) : go (Piece cls (T.drop 1 after) : rest) []

-- | Joins adjacent pieces of one class and drops empty ones.
merge :: [Piece] -> [Piece]
merge pieces = case filter (not . T.null . pieceText) pieces of
  [] -> []
  (p : rest) -> go p rest
  where
    go acc [] = [acc]
    go acc (q : rest)
      | pieceClass acc == pieceClass q = go acc {pieceText = pieceText acc <> pieceText q} rest
      | otherwise = acc : go q rest
