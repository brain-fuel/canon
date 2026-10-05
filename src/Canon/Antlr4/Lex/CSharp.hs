-- | The grammars-v4 C# lexer leaves interpolated strings and the preprocessor to a base lexer,
-- CSharpLexerBase, and this is that base lexer ported as a hook: it tracks the braces of each
-- interpolation hole so the closing brace returns to the string, and it reads one branch of each
-- conditional directive, as Canon.Preprocessor chooses it, hiding the others.
-- ref:DEC-csharp-grammar
module Canon.Antlr4.Lex.CSharp
  ( CSharpLexerState (..)
  , csharpLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, Directive (..), parseCondition, reading, stepBranches)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: one entry per open interpolation hole, innermost first, holding its brace depth
-- and its parenthesis and bracket depth; the tokens of the directive being read; one entry per open
-- conditional directive, holding whether its current branch is read and whether any branch of it
-- has been; and the symbols the file defines or undefines.
data CSharpLexerState = CSharpLexerState
  { holes :: [(Int, Int)]
  , directive :: [Token]
  , conditions :: Branches
  , symbols :: Map.Map Text Bool
  }
  deriving (Eq, Show)

-- | The hooks for the C# grammar.
csharpLexerHooks :: LexerHooks CSharpLexerState
csharpLexerHooks = LexerHooks (CSharpLexerState [] [] [] Map.empty) onAction onEmit

onAction :: Name -> ActionText -> Text -> CSharpLexerState -> (CSharpLexerState, [HookEffect])
onAction _ action _ s
  | calls "OpenBraceInside" = (s {holes = (1, 0) : holes s}, [])
  | calls "OnOpenBrace" = case holes s of
      ((braces, parens) : rest) -> (s {holes = (braces + 1, parens) : rest}, [])
      [] -> (s, [])
  | calls "OnCloseBraceInside" = (s {holes = drop 1 (holes s)}, [])
  | calls "OnCloseBrace" = case holes s of
      ((1, _) : rest) -> (s {holes = rest}, [EffectSkip, EffectPopMode])
      ((braces, parens) : rest) -> (s {holes = (braces - 1, parens) : rest}, [])
      [] -> (s, [])
  | calls "OnColon" = case holes s of
      ((1, 0) : _) -> (s, [EffectMode (Name "INTERPOLATION_FORMAT")])
      _ -> (s, [])
  | otherwise = (s, [])
  where
    calls method = method `T.isInfixOf` actionTextRaw action

onEmit :: Token -> CSharpLexerState -> ([Token], CSharpLexerState)
onEmit token s
  | tokenChannel token == Name "DIRECTIVE" =
      if ty == "DIRECTIVE_NEW_LINE"
        then ([token], runDirective s)
        else ([token], s {directive = directive s ++ [token]})
  | isEofToken token = ([token], runDirective s)
  | not (active s) = ([token {tokenChannel = hiddenChannelName}], s)
  | otherwise = ([token], trackHole s)
  where
    ty = nameText (tokenType token)
    trackHole st = case holes st of
      ((braces, parens) : rest)
        | ty `elem` ["OPEN_PARENS", "OPEN_BRACKET"] -> st {holes = (braces, parens + 1) : rest}
        | ty `elem` ["CLOSE_PARENS", "CLOSE_BRACKET"] -> st {holes = (braces, max 0 (parens - 1)) : rest}
      _ -> st

active :: CSharpLexerState -> Bool
active = reading . conditions

-- | Applies the directive read so far, by the policy Canon.Preprocessor states.
runDirective :: CSharpLexerState -> CSharpLexerState
runDirective s = case directive s of
  [] -> s
  (first : rest) -> apply (nameText (tokenType first)) rest s {directive = []}
  where
    step d st = st {conditions = stepBranches (symbols st) d (conditions st)}
    apply kind rest st = case kind of
      "IF" -> step (DirectiveIf (parseCondition rest)) st
      "ELIF" -> step (DirectiveElif (parseCondition rest)) st
      "ELSE" -> step DirectiveElse st
      "ENDIF" -> step DirectiveEndif st
      "DEFINE" | active st, Just name <- symbolOf rest -> st {symbols = Map.insert name True (symbols st)}
      "UNDEF" | active st, Just name <- symbolOf rest -> st {symbols = Map.insert name False (symbols st)}
      _ -> st
    symbolOf toks = case [tokenText t | t <- toks, tokenType t == Name "CONDITIONAL_SYMBOL"] of
      (name : _) -> Just name
      [] -> Nothing
