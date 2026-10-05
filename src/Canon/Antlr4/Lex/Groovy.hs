-- | Apache Groovy's lexer grammar leaves to its Java superclass, AbstractLexer and the members of
-- GroovyLexer, which the vendored grammar names GroovyLexerBase so the name selects this hook alone, whether a slash starts a slashy string, which brackets make newlines insignificant,
-- and which characters may start an identifier; this is that superclass as a hook. The predicates
-- that looked ahead in the character stream are written as characters in the vendored grammar,
-- since canon's lexer predicates see what has been matched, and NOT_IN, which upstream gated on the
-- character after it, is split here when letters follow. ref:DEC-groovy-grammar
module Canon.Antlr4.Lex.Groovy
  ( GroovyLexerState (..)
  , groovyLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Char (GeneralCategory (..), generalCategory, isUpper)
import Data.Text (Text)
import qualified Data.Text as T

-- | The type of the last token on the default channel, which decides whether a slash starts a
-- slashy string, and the open brackets, innermost first, each with the type of the token before
-- it, since a parenthesis after try opens resources, inside which newlines still count.
data GroovyLexerState = GroovyLexerState
  { groovyLastType :: Maybe Text
  , groovyParens :: [(Text, Maybe Text)]
  }
  deriving (Eq, Show)

-- | The hooks for the superclass of GroovyLexer, upstream's AbstractLexer, named GroovyLexerBase in
-- the vendored grammar. ref:DEC-groovy-grammar
groovyLexerHooks :: LexerHooks GroovyLexerState
groovyLexerHooks = LexerHooks (GroovyLexerState Nothing []) onAction onPredicate onEmit

calls :: ActionText -> Text -> Bool
calls action method = method `T.isInfixOf` actionTextRaw action

-- | enterParen and exitParen keep the bracket stack, and a newline inside parentheses or square
-- brackets, but not braces, goes to the hidden channel, as ignoreTokenInsideParens does.
onAction :: Name -> ActionText -> Text -> Text -> GroovyLexerState -> (GroovyLexerState, [HookEffect])
onAction _ action matched _ s
  | calls action "enterParen" = (s {groovyParens = (matched, groovyLastType s) : groovyParens s}, [])
  | calls action "exitParen" = (s {groovyParens = drop 1 (groovyParens s)}, [])
  | calls action "ignoreTokenInsideParens" = (s, [EffectChannel hiddenChannelName | insideParens s])
  | otherwise = (s, [])

insideParens :: GroovyLexerState -> Bool
insideParens s = case groovyParens s of
  ((text, before) : _) -> (text == "(" && before /= Just "TRY") || text == "[" || text == "?["
  [] -> False

-- | The predicates of GroovyLexer's members, decided on the text matched so far, whose last
-- character is _input.LA(-1). canon reads code points, so the alternatives for UTF-16 surrogate
-- pairs never apply.
onPredicate :: Name -> ActionText -> Text -> Int -> GroovyLexerState -> Bool
onPredicate _ predicate matched _ s
  | calls predicate "isRegexAllowed" = regexAllowed s
  | calls predicate "isValEnabled" = True
  | calls predicate "isSupplementary" || calls predicate "toCodePoint" = False
  | calls predicate "LA(-4) != '$'" = T.length matched < 4 || T.index matched (T.length matched - 4) /= '$'
  | calls predicate "isJavaIdentifierStartAndNotIdentifierIgnorable" = lastChar (\c -> javaIdentifierStart c && not (ignorable c) && casing c)
  | calls predicate "isJavaIdentifierPartAndNotIdentifierIgnorable" = lastChar (\c -> javaIdentifierPart c && not (ignorable c))
  | calls predicate "LA(-1) != '$'" = lastChar (/= '$')
  | calls predicate "isJavaLetterInGString" = negatedIf (lastChar javaLetterInGString)
  | otherwise = True
  where
    raw = actionTextRaw predicate
    lastChar test = maybe False (test . snd) (T.unsnoc matched)
    negatedIf value = if "!this.isJavaLetterInGString" `T.isInfixOf` raw then not value else value
    casing c
      | "!Character.isUpperCase" `T.isInfixOf` raw = not (isUpper c)
      | "Character.isUpperCase" `T.isInfixOf` raw = isUpper c
      | otherwise = True

-- | After an operand a slash divides, so it starts a slashy string only after anything else, as
-- REGEX_CHECK_SET says.
regexAllowed :: GroovyLexerState -> Bool
regexAllowed s = case groovyLastType s of
  Nothing -> True
  Just t ->
    t
      `notElem` [ "DEC"
                , "INC"
                , "THIS"
                , "RBRACE"
                , "RBRACK"
                , "RPAREN"
                , "GStringEnd"
                , "NullLiteral"
                , "StringLiteral"
                , "BooleanLiteral"
                , "IntegerLiteral"
                , "FloatingPointLiteral"
                , "Identifier"
                , "CapitalizedIdentifier"
                ]

-- | isFollowedByJavaLetterInGString, asked of the character after a dollar: an ASCII letter, an
-- underscore, or a brace, or a character beyond ASCII that may start a Java identifier, which upstream
-- read from the code point, so a supplementary letter counts.
javaLetterInGString :: Char -> Bool
javaLetterInGString c
  | c < '\x80' = c == '_' || c == '{' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  | otherwise = javaIdentifierStart c

-- | Character.isJavaIdentifierStart: a letter, a letter number, a currency symbol, or a connector.
javaIdentifierStart :: Char -> Bool
javaIdentifierStart c =
  generalCategory c `elem` [UppercaseLetter, LowercaseLetter, TitlecaseLetter, ModifierLetter, OtherLetter, LetterNumber, CurrencySymbol, ConnectorPunctuation]

-- | Character.isJavaIdentifierPart: a start character, a digit, or a combining mark, or an ignorable
-- character, which the grammar excludes separately.
javaIdentifierPart :: Char -> Bool
javaIdentifierPart c =
  javaIdentifierStart c || generalCategory c `elem` [DecimalNumber, SpacingCombiningMark, NonSpacingMark] || ignorable c

-- | Character.isIdentifierIgnorable: format characters and the control characters Java ignores in
-- identifiers.
ignorable :: Char -> Bool
ignorable c = generalCategory c == Format || (c <= '\x08') || (c >= '\x0E' && c <= '\x1B') || (c >= '\x7F' && c <= '\x9F')

-- | Records the type of each default-channel token, as GroovyLexer's emit does, and splits a NOT_IN
-- that took letters after !in into ! and the word, which upstream's isFollowedBy predicate left to
-- the identifier rules.
onEmit :: Token -> GroovyLexerState -> ([Token], GroovyLexerState)
onEmit token s
  | tokenType token == Name "NOT_IN" && tokenText token /= "!in" =
      let Position line column = tokenPosition token
          bang = token {tokenType = Name "NOT", tokenText = "!", tokenEnd = tokenStart token + 1}
          word = T.drop 1 (tokenText token)
          rest = token {tokenType = Name (wordType word), tokenText = word, tokenStart = tokenStart token + 1, tokenPosition = Position line (column + 1)}
       in ([bang, rest], s {groovyLastType = Just (wordType word)})
  | tokenChannel token == defaultChannelName = ([token], s {groovyLastType = Just (nameText (tokenType token))})
  | otherwise = ([token], s)
  where
    wordType word = case word of
      "int" -> "BuiltInPrimitiveType"
      "interface" -> "INTERFACE"
      "instanceof" -> "INSTANCEOF"
      _ -> "Identifier"
