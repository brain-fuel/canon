-- | The grammars-v4 C# lexer leaves interpolated strings and the preprocessor to a base lexer,
-- CSharpLexerBase, and this is that base lexer ported as a hook: it tracks the braces of each
-- interpolation hole so the closing brace returns to the string, counts the dollars and quotes of an
-- interpolated raw string so its holes are parsed, and reads the branches of each conditional
-- directive that a build selects, as Canon.Preprocessor chooses them, hiding the others.
-- ref:DEC-csharp-grammar
module Canon.Antlr4.Lex.CSharp
  ( CSharpLexerState (..)
  , Hole (..)
  , csharpLexerHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, Choice, Directive (..), parseCondition, reading, stepBranchesWith)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: one entry per open interpolation hole, innermost first, holding its brace depth,
-- its parenthesis and bracket depth, and for a hole of an interpolated raw string the number of
-- braces that close it; one entry per open interpolated raw string, holding its dollars and its
-- quotes; the closing braces of a raw hole still to skip; the tokens of the directive being read;
-- one entry per open conditional directive, holding whether its current branch is read and whether
-- any branch of it has been; the symbols the file defines or undefines; and the build whose
-- branches are read.
data CSharpLexerState = CSharpLexerState
  { holes :: [Hole]
  , raws :: [(Int, Int)]
  , pendingClose :: Int
  , directive :: [Token]
  , conditions :: Branches
  , symbols :: Map.Map Text Bool
  , build :: Choice
  }
  deriving (Eq, Show)

-- | An open interpolation hole.
data Hole = Hole
  { holeBraces :: Int
  , holeParens :: Int
  , holeClosers :: Maybe Int
  }
  deriving (Eq, Show)

-- | The hooks for the C# grammar, reading the branches a build selects. ref:DEC-preprocessor-builds
csharpLexerHooks :: Choice -> LexerHooks CSharpLexerState
csharpLexerHooks choice = LexerHooks (CSharpLexerState [] [] 0 [] [] Map.empty choice) onAction onEmit

onAction :: Name -> ActionText -> Text -> CSharpLexerState -> (CSharpLexerState, [HookEffect])
onAction _ action matched s
  | calls "OnRawStringStart" =
      (s {raws = (T.length (T.takeWhile (== '$') matched), T.length (T.filter (== '"') matched)) : raws s}, [])
  | calls "OnRawOpenBraces" = case raws s of
      ((dollars, _) : _)
        | T.length matched >= dollars -> (s {holes = Hole 1 0 (Just dollars) : holes s}, [EffectSkip, EffectPushMode (Name "DEFAULT_MODE")])
      _ -> (s, [content])
  | calls "OnRawCloseBrace" =
      if pendingClose s > 0 then (s {pendingClose = pendingClose s - 1}, [EffectSkip]) else (s, [content])
  | calls "OnRawQuotes" = case raws s of
      ((_, quotes) : rest)
        | T.length matched >= quotes -> (s {raws = rest}, [EffectSetType (Name "RAW_STRING_END"), EffectPopMode])
      _ -> (s, [content])
  | calls "OpenBraceInside" = (s {holes = Hole 1 0 Nothing : holes s}, [])
  | calls "OnOpenBrace" = case holes s of
      (h : rest) -> (s {holes = h {holeBraces = holeBraces h + 1} : rest}, [])
      [] -> (s, [])
  | calls "OnCloseBraceInside" = case holes s of
      (h : rest) -> (s {holes = rest, pendingClose = closersAfter h}, [])
      [] -> (s, [])
  | calls "OnCloseBrace" = case holes s of
      (h : rest)
        | holeBraces h == 1 -> (s {holes = rest, pendingClose = closersAfter h}, [EffectSkip, EffectPopMode])
        | otherwise -> (s {holes = h {holeBraces = holeBraces h - 1} : rest}, [])
      [] -> (s, [])
  | calls "OnColon" = case holes s of
      (Hole 1 0 closers : _) -> (s, [EffectMode (Name (maybe "INTERPOLATION_FORMAT" (const "RAW_INTERPOLATION_FORMAT") closers))])
      _ -> (s, [])
  | otherwise = (s, [])
  where
    calls method = method `T.isInfixOf` actionTextRaw action
    content = EffectSetType (Name "RAW_STRING_CONTENT")
    closersAfter h = maybe 0 (subtract 1) (holeClosers h)

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
      (h : rest)
        | ty `elem` ["OPEN_PARENS", "OPEN_BRACKET"] -> st {holes = h {holeParens = holeParens h + 1} : rest}
        | ty `elem` ["CLOSE_PARENS", "CLOSE_BRACKET"] -> st {holes = h {holeParens = max 0 (holeParens h - 1)} : rest}
      _ -> st

active :: CSharpLexerState -> Bool
active = reading . conditions

-- | Applies the directive read so far, by the policy Canon.Preprocessor states.
runDirective :: CSharpLexerState -> CSharpLexerState
runDirective s = case directive s of
  [] -> s
  (first : rest) -> apply (nameText (tokenType first)) rest s {directive = []}
  where
    step d st = st {conditions = stepBranchesWith (build st) (symbols st) d (conditions st)}
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
