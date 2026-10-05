-- | The grammars-v4 JavaScript and TypeScript lexers decide with a base class whether a slash
-- starts a regular expression, whether a closing brace ends a template expression, and whether
-- strict mode is on; this is that base class as a hook, in both its JavaScript and TypeScript
-- forms, which differ in how they count template nesting. ref:DEC-more-languages
--
-- In the canonically commented dialects the hook also hides a JSDoc or TSDoc comment that starts
-- with @type or @satisfies: it is a type cast or a type annotation, which TypeScript reads as a
-- type and no reader as documentation, so it is neither a Why nor an orphan. Every other doc comment
-- stays on the default channel, and one the grammar does not accept where it stands is reported as
-- an orphan through the parser's strayComment option. ref:DEC-javascript-dialect
-- ref:DEC-typescript-dialect ref:DEC-stray-comments
module Canon.Antlr4.Lex.JavaScript
  ( JavaScriptState (..)
  , javaScriptHooks
  , typeScriptHooks
  ) where

import Canon.Antlr4.Lex (HookEffect, LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Data.Text (Text)
import qualified Data.Text as T

-- | The last default-channel code token, the brace depth, the template stack or depth, and the
-- strict mode scopes, as the Java base classes keep them; whether any token but a hashbang line has
-- been read, the doc comment being held until its close, and whether the last one was hidden.
data JavaScriptState = JavaScriptState
  { jsLastToken :: Maybe Text
  , jsDepth :: Int
  , jsTemplateStack :: [Int]
  , jsTemplateDepth :: Int
  , jsBracesDepth :: Int
  , jsStrictScopes :: [Bool]
  , jsStrictCurrent :: Bool
  , jsTypeScript :: Bool
  , jsStarted :: Bool
  , jsHeld :: Maybe [Token]
  , jsLastHidden :: Bool
  }
  deriving (Eq, Show)

initial :: Bool -> JavaScriptState
initial ts = JavaScriptState Nothing 0 [] 0 0 [] False ts False Nothing False

-- | The hooks for JavaScriptLexerBase.
javaScriptHooks :: LexerHooks JavaScriptState
javaScriptHooks = LexerHooks (initial False) onAction onPredicate onEmit

-- | The hooks for TypeScriptLexerBase.
typeScriptHooks :: LexerHooks JavaScriptState
typeScriptHooks = LexerHooks (initial True) onAction onPredicate onEmit

calls :: ActionText -> Text -> Bool
calls action method = method `T.isInfixOf` actionTextRaw action

-- | IsStartOfFile holds until a token other than a hashbang line is read, so the first doc comment
-- below a hashbang line can still be the file's.
onPredicate :: Name -> ActionText -> Text -> Int -> JavaScriptState -> Bool
onPredicate _ predicate _ _ s = if negated then not value else value
  where
    raw = actionTextRaw predicate
    negated = "!" `T.isInfixOf` raw
    value
      | calls predicate "IsStartOfFile" = not (jsStarted s)
      | calls predicate "IsRegexPossible" = regexPossible s
      | calls predicate "IsInTemplateString" = inTemplateString s
      | calls predicate "IsStrictMode" = jsStrictCurrent s
      | otherwise = True

-- | A slash starts a regular expression unless the token before it ends an operand.
regexPossible :: JavaScriptState -> Bool
regexPossible s = case jsLastToken s of
  Nothing -> True
  Just t -> t `notElem` ["Identifier", "NullLiteral", "BooleanLiteral", "This", "CloseBracket", "CloseParen", "OctalIntegerLiteral", "DecimalLiteral", "HexIntegerLiteral", "StringLiteral", "PlusPlus", "MinusMinus"]

inTemplateString :: JavaScriptState -> Bool
inTemplateString s
  | jsTypeScript s = jsTemplateDepth s > 0 && jsBracesDepth s == 0
  | otherwise = case jsTemplateStack s of
      (d : _) -> d == jsDepth s
      [] -> False

onAction :: Name -> ActionText -> Text -> Text -> JavaScriptState -> (JavaScriptState, [HookEffect])
onAction _ action matched _ s
  | calls action "ProcessOpenBrace" =
      -- A new scope is strict if the enclosing one is; the default is never strict.
      let strict = case jsStrictScopes s of
            (b : _) -> b
            [] -> False
       in (s {jsDepth = jsDepth s + 1, jsBracesDepth = jsBracesDepth s + 1, jsStrictCurrent = strict, jsStrictScopes = strict : jsStrictScopes s}, [])
  | calls action "ProcessCloseBrace" =
      let (current, rest) = case jsStrictScopes s of
            (b : more) -> (b, more)
            [] -> (False, [])
       in (s {jsDepth = jsDepth s - 1, jsBracesDepth = jsBracesDepth s - 1, jsStrictCurrent = current, jsStrictScopes = rest}, [])
  | calls action "ProcessTemplateOpenBrace" = (s {jsDepth = jsDepth s + 1, jsTemplateStack = (jsDepth s + 1) : jsTemplateStack s}, [])
  | calls action "ProcessTemplateCloseBrace" = (s {jsDepth = jsDepth s - 1, jsTemplateStack = drop 1 (jsTemplateStack s)}, [])
  | calls action "ProcessStringLiteral" =
      let atScopeStart = jsLastToken s `elem` [Nothing, Just "OpenBrace"]
          useStrict = matched == "\"use strict\"" || matched == "\'use strict\'"
       in if atScopeStart && useStrict then (s {jsStrictCurrent = True, jsStrictScopes = True : drop 1 (jsStrictScopes s)}, []) else (s, [])
  | calls action "IncreaseTemplateDepth" = (s {jsTemplateDepth = jsTemplateDepth s + 1}, [])
  | calls action "DecreaseTemplateDepth" = (s {jsTemplateDepth = jsTemplateDepth s - 1}, [])
  | calls action "StartTemplateString" = (s {jsBracesDepth = 0}, [])
  | otherwise = (s, [])

-- | A doc comment's tokens are held until its close and then released, on the hidden channel when
-- its first word is @type or @satisfies; the blank line marked after a file's first comment follows
-- it. Doc tokens leave the last code token alone, so a slash after a doc comment is read as the
-- code before the comment says.
onEmit :: Token -> JavaScriptState -> ([Token], JavaScriptState)
onEmit token s = case jsHeld s of
  Just held
    | ty == "DOC_BLOCK_CLOSE" ->
        let comment = reverse (token : held)
            hide = typeAnnotation comment
         in (map (hideIf hide) comment, started {jsHeld = Nothing, jsLastHidden = hide})
    | isEofToken token -> (reverse held ++ [token], s {jsHeld = Nothing})
    | otherwise -> ([], started {jsHeld = Just (token : held)})
  Nothing
    | ty `elem` ["DOC_BLOCK_OPEN", "FILE_DOC_OPEN"] -> ([], started {jsHeld = Just [token]})
    | ty == "DOC_BLANK_LINE" -> ([hideIf (jsLastHidden s) token], started)
    | tokenChannel token /= defaultChannelName || isEofToken token -> ([token], s)
    | otherwise -> ([token], started {jsLastToken = Just ty})
  where
    ty = nameText (tokenType token)
    started
      | tokenChannel token == defaultChannelName && ty /= "HashBangLine" && not (isEofToken token) = s {jsStarted = True}
      | otherwise = s
    hideIf hide t = if hide && tokenChannel t == defaultChannelName then t {tokenChannel = hiddenChannelName} else t
    typeAnnotation comment = case [tokenText t | t <- drop 1 comment, tokenChannel t == defaultChannelName] of
      (word : _) -> word `elem` ["@type", "@satisfies"]
      [] -> False
