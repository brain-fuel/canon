module Canon.Antlr4.Lex.Adaptor
  ( AdaptorState (..)
  , antlrLexerHooks
  , hooksForGrammar
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..), SomeHooks (..), noHooks)
import Canon.Antlr4.Lex.Haskell (haskellLayoutHooks)
import Canon.Antlr4.Query (grammarOptions)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token (..))
import Data.Char (isUpper)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T

data AdaptorState
  = OutsideRule
  | InPrequel
  | InRuleOptions
  | InNamedAction
  | InLexerRule
  | InParserRule
  deriving (Eq, Show)

antlrLexerHooks :: LexerHooks AdaptorState
antlrLexerHooks = LexerHooks OutsideRule onAction onEmit
  where
    onAction rule _ _ state = case nameText rule of
      "BEGIN_ARGUMENT"
        | state == InLexerRule -> (state, [EffectPushMode (Name "LexerCharSet"), EffectMore])
        | otherwise -> (state, [EffectPushMode (Name "Argument")])
      "END_ARGUMENT" -> (state, [EffectPopMode, EffectSetTypeIfNested (Name "ARGUMENT_CONTENT")])
      _ -> (state, [])

    onEmit token state = case nameText (tokenType token) of
      ty
        | ty `elem` ["OPTIONS", "TOKENS", "CHANNELS"], state == OutsideRule -> ([token], InPrequel)
        | ty == "OPTIONS", state == InLexerRule -> ([token], InRuleOptions)
        | ty == "RBRACE", state == InPrequel -> ([token], OutsideRule)
        | ty == "RBRACE", state == InRuleOptions -> ([token], InLexerRule)
        | ty == "AT", state == OutsideRule -> ([token], InNamedAction)
        | ty == "SEMI", state == InRuleOptions -> ([token], state)
        | ty == "ACTION", state == InNamedAction -> ([token], OutsideRule)
        | ty == "ID" ->
            let retyped = if startsUpper (tokenText token) then Name "TOKEN_REF" else Name "RULE_REF"
                state' = if state == OutsideRule then (if retyped == Name "TOKEN_REF" then InLexerRule else InParserRule) else state
             in ([token {tokenType = retyped}], state')
        | ty == "SEMI" -> ([token], OutsideRule)
        | otherwise -> ([token], state)

    startsUpper t = maybe False (isUpper . fst) (T.uncons t)

hooksForGrammar :: Grammar ann -> SomeHooks
hooksForGrammar grammar =
  case [NonEmpty.last v | Option (Name "superClass") (OptionValueName (QualifiedName v)) <- grammarOptions grammar] of
    (Name "LexerAdaptor" : _) -> SomeHooks antlrLexerHooks
    (Name "HaskellBaseLexer" : _) -> SomeHooks haskellLayoutHooks
    _ -> SomeHooks noHooks
