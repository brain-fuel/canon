-- | The grammars-v4 JavaScript and TypeScript lexers decide with a base class whether a slash
-- starts a regular expression, whether a closing brace ends a template expression, and whether
-- strict mode is on; this is that base class as a hook, in both its JavaScript and TypeScript
-- forms, which differ in how they count template nesting. ref:DEC-more-languages
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

-- | The last default-channel token, the brace depth, the template stack or depth, and the strict
-- mode scopes, as the Java base classes keep them.
data JavaScriptState = JavaScriptState
  { jsLastToken :: Maybe Text
  , jsDepth :: Int
  , jsTemplateStack :: [Int]
  , jsTemplateDepth :: Int
  , jsBracesDepth :: Int
  , jsStrictScopes :: [Bool]
  , jsStrictCurrent :: Bool
  , jsTypeScript :: Bool
  }
  deriving (Eq, Show)

initial :: Bool -> JavaScriptState
initial ts = JavaScriptState Nothing 0 [] 0 0 [] False ts

-- | The hooks for JavaScriptLexerBase.
javaScriptHooks :: LexerHooks JavaScriptState
javaScriptHooks = LexerHooks (initial False) onAction onPredicate onEmit

-- | The hooks for TypeScriptLexerBase.
typeScriptHooks :: LexerHooks JavaScriptState
typeScriptHooks = LexerHooks (initial True) onAction onPredicate onEmit

calls :: ActionText -> Text -> Bool
calls action method = method `T.isInfixOf` actionTextRaw action

onPredicate :: Name -> ActionText -> Text -> Int -> JavaScriptState -> Bool
onPredicate _ predicate _ _ s = if negated then not value else value
  where
    raw = actionTextRaw predicate
    negated = "!" `T.isInfixOf` raw
    value
      | calls predicate "IsStartOfFile" = jsLastToken s == Nothing
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

onEmit :: Token -> JavaScriptState -> ([Token], JavaScriptState)
onEmit token s = ([token], if tokenChannel token == defaultChannelName then s {jsLastToken = Just (nameText (tokenType token))} else s)
