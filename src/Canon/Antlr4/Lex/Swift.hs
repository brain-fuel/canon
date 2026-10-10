-- | Swift ends a statement at a line break unless the tokens around it continue it, and compiles one
-- branch of each #if; neither is lexical, and this hook, selected by the Swift grammar's
-- SwiftLexerBase superClass, supplies both. It emits a NEWLINE token where a line break separates
-- two statements, as the Swift compiler's parser decides from the tokens on each side of it, hides
-- the branches of each #if a build does not read, as Canon.Preprocessor chooses them, answers
-- whether a slash starts a regex literal, and in the canonically commented dialect places each doc
-- comment right before the code token it precedes. ref:DEC-swift-grammar ref:swift-lexical-structure
module Canon.Antlr4.Lex.Swift
  ( SwiftLexerState (..)
  , swiftLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, Choice, reading, stepBranchesWith, swiftDirectiveOf)
import Canon.Span (Position (..))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The hook state: the open brackets, innermost first, an attribute's argument clause marked as
-- such; the type and text of the last code token and the type of the one before it, whether the
-- last may end a statement and whether a regex literal may follow it, and where it ends; whether
-- the last token of any channel was whitespace or a comment; an operator that starts a line, held
-- until the token after it shows whether whitespace follows it; the doc comment tokens held until
-- the next code token, and whether a /// comment is open; one entry per open #if; and the build
-- whose branches are read.
data SwiftLexerState = SwiftLexerState
  { brackets :: [Text]
  , lastType :: Text
  , lastText :: Text
  , previousType :: Text
  , lastEnds :: Bool
  , lastAllowsRegex :: Bool
  , lastEnd :: Maybe (Int, Position)
  , spaceBefore :: Bool
  , held :: Maybe Token
  , docs :: [Token]
  , docOpen :: Bool
  , conditions :: Branches
  , build :: Choice
  }
  deriving (Eq, Show)

-- | The hooks for the Swift grammar, reading the branches a build selects. ref:DEC-swift-grammar
-- ref:DEC-preprocessor-builds
swiftLexerHooks :: Choice -> LexerHooks SwiftLexerState
swiftLexerHooks choice =
  LexerHooks (SwiftLexerState [] "" "" "" False True Nothing True Nothing [] False [] choice) (\_ _ _ _ s -> (s, [])) onPredicate onEmit

-- | A slash starts a bare regex literal where an expression may start: at the start of the file,
-- after an opening bracket, a comma, a colon, or a semicolon, after an operator with whitespace
-- before it, and after a keyword that an expression follows, as the compiler's lexer decides from
-- the token before it; the lexer rule checks that no space follows the slash. ref:swift-regex-literals
onPredicate :: Name -> ActionText -> Text -> Int -> SwiftLexerState -> Bool
onPredicate _ (ActionText action) _ _ s
  | "regexStart" `T.isInfixOf` action = lastAllowsRegex s
  | otherwise = True

-- | The keywords after which an expression starts, so a slash after one starts a regex literal.
regexKeywords :: [Text]
regexKeywords = ["return", "case", "in", "if", "where", "try", "await", "throw", "guard", "while", "switch", "repeat", "yield", "else", "do", "catch"]

-- | The keywords that cannot end a statement: a declaration's introducer, which a name follows, and
-- the keywords of statements and expressions that something must follow. A keyword read as a member
-- name after a dot is a name, and ends one.
cannotEndWords :: [Text]
cannotEndWords =
  [ "func", "var", "let", "class", "struct", "enum", "protocol", "extension", "import", "typealias", "associatedtype"
  , "case", "operator", "precedencegroup", "if", "guard", "while", "for", "switch", "repeat", "else", "in", "where"
  , "is", "as", "try", "await", "throw", "defer", "do", "catch", "inout"
  ]

-- | The keywords that cannot start a statement, so a line starting with one continues the line
-- before it: else after an if's block, catch after a do's, where before a generic where clause, in
-- after a closure's parameters, is and as, which take an operand on each side, and the effects of a
-- signature whose parameters end the line before.
cannotStartWords :: [Text]
cannotStartWords = ["else", "catch", "where", "in", "is", "as", "throws", "rethrows", "async"]

-- | The keyword token types that introduce a declaration, which a name follows, so none ends a
-- statement and the word after one is a name that may, as in case await.
introducers :: [Text]
introducers = ["FUNC", "VAR", "LET", "CLASS", "STRUCT", "ENUM", "PROTOCOL", "EXTENSION", "IMPORT", "TYPEALIAS", "ASSOCIATEDTYPE", "CASE", "OPERATOR", "PRECEDENCEGROUP"]

-- | The token types that cannot end a statement: opening brackets and the punctuation that something
-- must follow.
cannotEndTypes :: [Text]
cannotEndTypes = ["LPAREN", "LBRACK", "LBRACE", "COMMA", "COLON", "SEMI", "DOT", "AT", "HASH", "BACKSLASH"]

-- | The token types that cannot start a statement: closing brackets, an opening brace, which after a
-- line break begins a body or a trailing closure of the line before, and the punctuation that
-- continues an expression or a declaration.
cannotStartTypes :: [Text]
cannotStartTypes = ["RPAREN", "RBRACK", "RBRACE", "LBRACE", "COMMA", "COLON", "DOT", "SEMI"]

-- | The keyword token types that are names after a dot, as in .init, .default, and Foo.self.
keywordTypes :: [Text]
keywordTypes =
  [ "ASSOCIATEDTYPE", "CASE", "CLASS", "DEINIT", "ENUM", "EXTENSION", "FILEPRIVATE", "FUNC", "IMPORT", "INIT", "INTERNAL"
  , "LET", "OPERATOR", "PRECEDENCEGROUP", "PRIVATE", "PROTOCOL", "PUBLIC", "STATIC", "STRUCT", "SUBSCRIPT", "TYPEALIAS", "VAR"
  , "ACTOR", "BORROWING", "CONSUMING", "CONVENIENCE", "DISTRIBUTED", "DYNAMIC", "FINAL", "INDIRECT", "INFIX", "LAZY", "MACRO"
  , "MUTATING", "NONISOLATED", "NONMUTATING", "OPEN", "OPTIONAL", "OVERRIDE", "PACKAGE", "POSTFIX", "PREFIX", "REQUIRED"
  , "SPI", "UNOWNED", "WEAK"
  ]

-- | The token types of a doc comment in the canonically commented dialect, which the hook holds until
-- the next code token. ref:DEC-swift-dialect
docTypes :: [Text]
docTypes = ["DOC_OPEN", "DOC_BLOCK_OPEN", "DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE", "DOC_BLOCK_CLOSE"]

-- | Handles one token: a directive steps the #if branches; a token in a branch not read is hidden; a
-- token of a doc comment is held; an operator starting a line is held until the next token; and a
-- code token gets a NEWLINE before it where a line break separates it from the last statement.
onEmit :: Token -> SwiftLexerState -> ([Token], SwiftLexerState)
onEmit token s
  | ty == "DIRECTIVE" = ([token], directive s)
  | not (reading (conditions s)) && not (isEofToken token) = ([token {tokenChannel = hiddenChannelName}], s)
  | otherwise = case held s of
      Just op ->
        let spaced = tokenChannel token /= defaultChannelName || ty `elem` docTypes || tokenStart token > tokenEnd op
            (out1, s1) = code (Just spaced) op s {held = Nothing}
            (out2, s2) = onEmit token s1
         in (out1 ++ out2, s2)
      Nothing -> step token s
  where
    ty = nameText (tokenType token)
    directive st = case swiftDirectiveOf (tokenText token) of
      Just d -> st {conditions = stepBranchesWith (build st) Map.empty d (conditions st)}
      Nothing -> st

-- | Handles a token with no operator held.
step :: Token -> SwiftLexerState -> ([Token], SwiftLexerState)
step token s
  | isEofToken token = (docs (closeDoc token s) ++ [token], s {docs = [], docOpen = False})
  | ty `elem` ["DOC_CLOSE", "DOC_PLAIN_AFTER"] = ([token], (closeDoc token s) {spaceBefore = True})
  | ty `elem` docTypes = ([], s {docs = docs s ++ [token], docOpen = docOpen s || ty == "DOC_OPEN", spaceBefore = True})
  | tokenChannel token /= defaultChannelName = ([token], s {spaceBefore = True})
  | otherwise = code Nothing token s
  where
    ty = nameText (tokenType token)

-- | Ends an open /// doc comment with an empty DOC_END token where its line ends, so the comment rule
-- ends there rather than after any of its words. ref:DEC-swift-dialect
closeDoc :: Token -> SwiftLexerState -> SwiftLexerState
closeDoc token s
  | docOpen s = s {docs = docs s ++ [Token (Name "DOC_END") "" (tokenStart token) (tokenStart token) defaultChannelName (tokenPosition token)], docOpen = False}
  | otherwise = s

-- | Handles a code token. An operator at the start of a line is held until the next token shows
-- whether whitespace follows it: with whitespace on both sides it is binary and continues the line
-- before, and otherwise it is a prefix operator that may start a statement. Given whether
-- whitespace follows a held operator, the token is emitted after the NEWLINE the line break before
-- it needs, if any, and the doc comment held before it.
code :: Maybe Bool -> Token -> SwiftLexerState -> ([Token], SwiftLexerState)
code spacedAfter token0 s
  | newLine && isOperator ty && spacedAfter == Nothing && tokenText token `notElem` ["=", "->"] = ([], s {held = Just token, lastAllowsRegex = True, spaceBefore = False})
  | otherwise =
      ( [virtual s | separates] ++ docs s ++ [token]
      , s
          { brackets = bracketsAfter
          , lastType = ty
          , lastText = text
          , previousType = lastType s
          , lastEnds = ends
          , lastAllowsRegex = allowsRegex
          , lastEnd = Just (tokenEnd token, endPosition token)
          , spaceBefore = False
          , docs = []
          }
      )
  where
    afterDot = lastType s == "DOT" && not newLine
    token = if afterDot && nameText (tokenType token0) `elem` keywordTypes then token0 {tokenType = Name "ID"} else token0
    ty = nameText (tokenType token)
    text = tokenText token
    Position line _ = tokenPosition token0
    newLine = case lastEnd s of
      Nothing -> False
      Just (_, Position previous _) -> line > previous
    inBraces = case brackets s of
      [] -> True
      (b : _) -> b == "{"
    startsStatement
      | ty `elem` cannotStartTypes = False
      | ty == "LPAREN" = not (signatureContinues s)
      | isOperator ty = spacedAfter /= Just True && text `notElem` ["=", "->"] && not (">" `T.isPrefixOf` text)
      | ty == "ID" = text `notElem` cannotStartWords
      | otherwise = True
    separates = newLine && inBraces && lastEnds s && startsStatement
    ends
      | afterDot || lastType s `elem` introducers = True
      | ty `elem` cannotEndTypes = False
      | ty == "RPAREN" = take 1 (brackets s) /= ["@("]
      | isOperator ty = ">" `T.isPrefixOf` text || (not (spaceBefore s) && not newLine && text `notElem` ["=", "->", "<"])
      | ty == "ID" = text `notElem` cannotEndWords
      | otherwise = ty `notElem` introducers
    allowsRegex
      | ty `elem` ["LPAREN", "LBRACK", "LBRACE", "COMMA", "COLON", "SEMI"] = True
      | isOperator ty = spaceBefore s || newLine
      | ty == "ID" = not afterDot && text `elem` regexKeywords
      | otherwise = ty == "CASE" && not afterDot
    -- An attribute's argument clause, opened right after @ and its name, is marked so its closing
    -- parenthesis ends no statement: the declaration or type it applies to may follow on the next
    -- line, as @convention(thin) and a function type do.
    bracketsAfter = case ty of
      "LPAREN"
        | previousType s == "AT" && lastType s /= "AT" && not newLine -> "@(" : brackets s
        | otherwise -> "(" : brackets s
      "LBRACK" -> "[" : brackets s
      "LBRACE" -> "{" : brackets s
      _ | ty `elem` ["RPAREN", "RBRACK", "RBRACE"] -> drop 1 (brackets s)
      _ -> brackets s

-- | Whether a parameter clause on the next line continues a signature: after a generic parameter
-- clause's closing >, after init, or after a function's name, as a function declared over several
-- lines has it.
signatureContinues :: SwiftLexerState -> Bool
signatureContinues s =
  (isOperator (lastType s) && ">" `T.isPrefixOf` lastText s) || lastType s == "INIT" || previousType s == "FUNC"

-- | Whether a token type is an operator: OP, or a lone < or >.
isOperator :: Text -> Bool
isOperator ty = ty `elem` ["OP", "LT", "GT"]

-- | A NEWLINE token, empty and placed where the last code token ends, so it widens no span.
virtual :: SwiftLexerState -> Token
virtual s = case lastEnd s of
  Just (offset, position) -> Token (Name "NEWLINE") "" offset offset defaultChannelName position
  Nothing -> Token (Name "NEWLINE") "" 0 0 defaultChannelName (Position 1 1)

-- | Where a token ends, as a line and column, for a token such as a multi-line string that spans
-- lines.
endPosition :: Token -> Position
endPosition token =
  let Position line column = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position line (column + T.length single)
        _ -> Position (line + length parts - 1) (T.length (last parts) + 1)
