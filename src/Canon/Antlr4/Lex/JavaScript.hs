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
  , typeScriptJsxHooks
  ) where

import Canon.Antlr4.Lex (HookEffect, LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Char (isAlpha, isAlphaNum, isSpace)
import Data.Text (Text)
import qualified Data.Text as T

-- | The last default-channel code token, the brace depth, the template stack or depth, and the
-- strict mode scopes, as the Java base classes keep them; whether any token but a hashbang line has
-- been read, the doc comment being held until its close, whether the last one was hidden, and the
-- brace depths of the TypeScript template expressions around the current one; whether the lexer
-- reads JSX, and the brace depths at which the JSX expression containers around the current
-- position close.
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
  , jsBracesStack :: [Int]
  , jsJsx :: Bool
  , jsJsxStack :: [Int]
  , jsLastText :: Maybe Text
  , jsAngles :: [Int]
  , jsBeforeText :: Maybe Text
  , jsTypeAlias :: Maybe Int
  , jsTypeRight :: Bool
  }
  deriving (Eq, Show)

initial :: Bool -> Bool -> JavaScriptState
initial ts jsx = JavaScriptState Nothing 0 [] 0 0 [] False ts False Nothing False [] jsx [] Nothing [] Nothing Nothing False

-- | The hooks for JavaScriptLexerBase, which reads JSX, as Babel and every JSX toolchain read it in
-- a .js or .jsx file. ref:DEC-javascript-jsx
javaScriptHooks :: LexerHooks JavaScriptState
javaScriptHooks = LexerHooks (initial False True) onAction onPredicate onEmit

-- | The hooks for TypeScriptLexerBase, which reads no JSX, as TypeScript reads a .ts file, where
-- <T>x is a type assertion.
typeScriptHooks :: LexerHooks JavaScriptState
typeScriptHooks = LexerHooks (initial True False) onAction onPredicate onEmit

-- | The hooks for TypeScriptJsxLexerBase, the TypeScript lexer of a .tsx file, which reads JSX.
-- ref:DEC-javascript-jsx
typeScriptJsxHooks :: LexerHooks JavaScriptState
typeScriptJsxHooks = LexerHooks (initial True True) onAction onPredicate onEmit

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
      | calls predicate "IsJsxPossible" = jsJsx s && jsxPossible s && not (jsTypeRight s)
      | calls predicate "IsJsxTypePossible" = jsJsx s && (jsLastToken s `elem` [Just "Colon", Just "ARROW"] || jsTypeRight s)
      | calls predicate "IsJsxExpressionClose" = take 1 (jsJsxStack s) == [jsDepth s]
      | calls predicate "IsJsxTypeArgumentsClose" = take 1 (jsAngles s) == [0]
      | calls predicate "IsJsxAttributeValue" = jsLastToken s == Just "JsxAssign"
      | otherwise = True

-- | A < starts a JSX tag where an expression may start: after no token, or after one that does not
-- end an operand, as TypeScript's scanner decides it. A JSX element, a template, and a regular
-- expression end an operand too.
-- A word ends an operand, as a name or a keyword used as one, as in z.infer<T>, unless it is one of
-- the keywords an expression follows.
jsxPossible :: JavaScriptState -> Bool
jsxPossible s =
  regexPossible s
    && jsLastToken s `notElem` map Just ["BackTick", "JsxSelfClose", "JsxCloseEnd", "RegularExpressionLiteral", "BigHexIntegerLiteral", "BigOctalIntegerLiteral", "BigBinaryIntegerLiteral", "BigDecimalIntegerLiteral", "BinaryIntegerLiteral", "OctalIntegerLiteral2"]
    && maybe True (\w -> not (isWord w) || (w `elem` expressionKeywords && jsBeforeText s `notElem` [Just ".", Just "?."])) (jsLastText s)
  where
    isWord w = maybe False (\(c, _) -> isAlpha c || c == '_' || c == '$') (T.uncons w) && T.all (\c -> isAlphaNum c || c == '_' || c == '$') w
    expressionKeywords = ["return", "typeof", "void", "delete", "await", "yield", "case", "do", "else", "in", "of", "throw", "default", "instanceof", "new"]

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
  | calls action "ProcessJsxOpenBrace" =
      let depth = jsDepth s + 1
       in (s {jsDepth = depth, jsJsxStack = depth : jsJsxStack s, jsBracesDepth = jsBracesDepth s + 1}, [])
  | calls action "ProcessJsxCloseBrace" = (s {jsDepth = jsDepth s - 1, jsJsxStack = drop 1 (jsJsxStack s), jsBracesDepth = jsBracesDepth s - 1}, [])
  | calls action "IncreaseTemplateDepth" = (s {jsTemplateDepth = jsTemplateDepth s + 1}, [])
  | calls action "DecreaseTemplateDepth" = (s {jsTemplateDepth = jsTemplateDepth s - 1}, [])
  | calls action "StartTemplateString" = (s {jsDepth = jsDepth s + 1, jsBracesDepth = 0, jsBracesStack = jsBracesDepth s : jsBracesStack s}, [])
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
    | ty == "TemplateCloseBrace" && jsTypeScript s ->
        -- A template expression's closing brace restores the brace depth of the code around it,
        -- so a template inside a block inside a template expression closes where it should.
        let (depth, outer) = case jsBracesStack s of
              (d : more) -> (d, more)
              [] -> (0, [])
         in ([token], started {jsLastToken = Just ty, jsDepth = jsDepth s - 1, jsBracesDepth = depth, jsBracesStack = outer})
    | ty `elem` ["JsxTypeParameters", "JsxFunctionTypeParameters"] ->
        let parts = splitTypeParameters token
         in (parts, started {jsLastToken = Just (nameText (tokenType (last' token parts))), jsLastText = Just (tokenText (last' token parts))})
    | ty == "JsxTypeArgumentsOpen" -> ([token], started {jsLastToken = Just ty, jsLastText = Just (tokenText token), jsAngles = 0 : jsAngles s})
    | ty == "JsxTypeArgumentsClose" -> ([token], started {jsLastToken = Just ty, jsLastText = Just (tokenText token), jsAngles = drop 1 (jsAngles s)})
    | otherwise -> ([token], started {jsLastToken = Just ty, jsLastText = Just (tokenText token), jsBeforeText = jsLastText s, jsAngles = angles, jsTypeAlias = alias, jsTypeRight = right})
  where
    -- After type Name, with its type parameters, the = at their depth opens the right side of a
    -- type alias, where a < opens a generic function type rather than a JSX tag.
    (alias, right) = case jsTypeAlias s of
      _ | ty == "TypeAlias" && jsLastText s `notElem` [Just ".", Just "?."] -> (Just 0, False)
      Just d
        | ty == "LessThan" -> (Just (d + 1), False)
        | ty == "MoreThan" -> (Just (d - 1), False)
        | ty == "Assign" && d == 0 -> (Nothing, True)
        | ty `elem` ["SemiColon", "OpenBrace", "CloseBrace", "OpenParen"] -> (Nothing, False)
        | otherwise -> (Just d, False)
      Nothing -> (Nothing, False)
    -- The < and > inside a JSX tag's type arguments, so the > that closes them returns to the tag.
    angles = case (jsAngles s, ty) of
      (d : more, "LessThan") -> d + 1 : more
      (d : more, "MoreThan") -> d - 1 : more
      (open, _) -> open
    ty = nameText (tokenType token)
    started
      | tokenChannel token == defaultChannelName && ty /= "HashBangLine" && not (isEofToken token) = s {jsStarted = True}
      | otherwise = s
    hideIf hide t = if hide && tokenChannel t == defaultChannelName then t {tokenChannel = hiddenChannelName} else t
    typeAnnotation comment = case [tokenText t | t <- drop 1 comment, tokenChannel t == defaultChannelName] of
      (word : _) -> word `elem` ["@type", "@satisfies"]
      [] -> False

-- | The tokens a type parameter list's opening holds, which the lexer matched as one so that a <
-- before them is no JSX tag: <, the name, whitespace, and the comma, extends, =, or the > and ( of a
-- generic function type. ref:DEC-javascript-jsx
splitTypeParameters :: Token -> [Token]
splitTypeParameters token = go (tokenStart token) (tokenPosition token) (T.unpack (tokenText token))
  where
    piece ty start position text channel = Token (Name ty) (T.pack text) start (start + length text) channel position
    advance (Position l c) text = foldl (\(Position l' c') ch -> if ch == '\n' then Position (l' + 1) 1 else Position l' (c' + 1)) (Position l c) text
    go _ _ [] = []
    go start position cs@(c : rest)
      | isSpace c = let (ws, more) = span isSpace cs in piece "WhiteSpaces" start position ws hiddenChannelName : go (start + length ws) (advance position ws) more
      | c `elem` ("<,=>(" :: String) = piece (punctuation c) start position [c] defaultChannelName : go (start + 1) (advance position [c]) rest
      | otherwise =
          let (word, more) = break (\ch -> isSpace ch || ch `elem` ("<,=>(" :: String)) cs
           in piece (keyword word) start position word defaultChannelName : go (start + length word) (advance position word) more
    punctuation c = case c of
      '<' -> "LessThan"
      ',' -> "Comma"
      '=' -> "Assign"
      '>' -> "MoreThan"
      _ -> "OpenParen"
    keyword w = case w of
      "extends" -> "Extends"
      "const" -> "Const"
      _ -> "Identifier"

last' :: Token -> [Token] -> Token
last' fallback ts = case [t | t <- ts, tokenChannel t == defaultChannelName] of
  [] -> fallback
  visible -> last visible
