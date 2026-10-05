-- | Scala 3 lets indentation stand for braces, and canon's Scala grammar reads it as tokens: this
-- hook, selected by the grammar's ScalaLexerBase superClass, inserts INDENT, OUTDENT, and NEWLINE
-- where the Scala 3 compiler's scanner does (dotty.tools.dotc.parsing.Scanners, its handleNewLine,
-- regions, and token sets), answers whether a < starts an XML literal, and in the canonically
-- commented dialect places each Scaladoc comment right before the code token it precedes.
-- ref:DEC-scala-indentation ref:scala3-indentation ref:scala3-compiler-scanners
module Canon.Antlr4.Lex.Scala
  ( ScalaLayout (..)
  , Region (..)
  , Bracket (..)
  , scalaLexerHooks
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | What a parenthesis or bracket encloses: the condition of an old-style if, while, or for, after
-- whose closing parenthesis an indented region may start; the parameters of an extension, after
-- which its methods may be indented; or anything else.
data Bracket = PlainBracket | ConditionBracket | ExtensionBracket
  deriving (Eq, Show)

-- | A region, as the compiler's scanner keeps them: an indented region with its width and the token
-- that opened it, the file's own region being the outermost; braces and brackets, with the width
-- their lines are measured against once known; an XML literal, by the depth of its open elements;
-- and an interpolated string, as the compiler's InString; line breaks inside the last two mean
-- nothing.
data Region
  = Indented Int Text
  | InBraces (Maybe Int)
  | InParens Bracket (Maybe Int)
  | InXml Int
  | InString
  deriving (Eq, Show)

-- | The hook state: the open regions, innermost first and the file's region last (Nothing until the
-- first code token sets its width); the end offset and position of the last code token, its type,
-- and the type before it; whether the last code token may open an indented region; whether the
-- tokens since an extension keyword are its parameters; whether a blank line has passed since the
-- last code token; the end offset and last character of the last token of any channel, for the XML
-- predicate; an operator held at the start of a line until the next token shows whether whitespace
-- follows it; and the Scaladoc tokens held until the next code token.
data ScalaLayout = ScalaLayout
  { regions :: [Region]
  , fileWidth :: Maybe Int
  , lastEnd :: Maybe (Int, Position)
  , lastType :: Text
  , previousType :: Text
  , lastOpens :: Bool
  , extensionHeader :: Bool
  , pastBlank :: Bool
  , lastChar :: Char
  , heldOperator :: Maybe Token
  , docs :: [Token]
  }
  deriving (Eq, Show)

-- | The hooks for the Scala grammar. ref:DEC-scala-indentation
scalaLexerHooks :: LexerHooks ScalaLayout
scalaLexerHooks = LexerHooks (ScalaLayout [] Nothing Nothing "" "" False False False ' ' Nothing []) (\_ _ _ _ s -> (s, [])) onPredicate onEmit

-- | A < starts an XML literal when the character before it is whitespace or one of { ( >, as the
-- compiler's scanner decides; the lexer rule checks the name after it.
onPredicate :: Name -> ActionText -> Text -> Int -> ScalaLayout -> Bool
onPredicate _ (ActionText action) _ _ s
  | "xmlStart" `T.isInfixOf` action = lastChar s `elem` (" \t\r\n{(>" :: String)
  | otherwise = True

-- | The tokens of a Scaladoc comment in the canonically commented dialect. The hook holds them until
-- the next code token has produced its layout tokens, and emits them just before it, so a line
-- holding only a comment is blank to the layout, as it is to the compiler. ref:DEC-scala-dialect
docTypes :: [Text]
docTypes = ["DOC_OPEN", "DOC_WORD", "DOC_PUNCT", "DOC_REF", "DOC_LICENSE", "DOC_CLOSE"]

-- | The compiler's canStartIndentTokens: the tokens after which an indented region may start. A colon
-- is one only after a name, a closing bracket, this, super, or new, as the compiler's COLONeol is.
startsIndent :: Text -> Text -> Bool
startsIndent previous ty
  | ty == "COLON" = previous `elem` colonPredecessors
  | otherwise = ty `elem` (statementContinuations ++ ["WITH", "EQUALS", "FAT_ARROW", "CONTEXT_ARROW", "LEFT_ARROW", "WHILE", "TRY", "FOR", "IF", "THROW", "RETURN"])

colonPredecessors :: [Text]
colonPredecessors = ["ID", "BACKQUOTED_ID", "RPAREN", "RBRACK", "THIS", "SUPER", "NEW"] ++ softKeywords

-- | The tokens an end marker may name besides a name, which the compiler reads as a name after end.
endTags :: [Text]
endTags = ["ID", "BACKQUOTED_ID", "OP", "IF", "WHILE", "FOR", "MATCH", "TRY", "NEW", "THROW", "GIVEN", "VAL", "THIS", "EXTENSION"]

-- | The compiler's statCtdTokens: tokens that continue the statement before them.
statementContinuations :: [Text]
statementContinuations = ["THEN", "ELSE", "DO", "CATCH", "FINALLY", "YIELD", "MATCH"]

softKeywords :: [Text]
softKeywords = ["AS", "DERIVES", "END", "EXTENSION", "INFIX", "INLINE", "OPAQUE", "OPEN", "TRANSPARENT", "USING"]

-- | The compiler's canEndStatTokens: names and operators, literals, this, super, return, type,
-- given, closing brackets, and an OUTDENT; the tag of an end marker ends a statement, as the
-- compiler turns it into a name.
ends :: Text -> Bool
ends ty =
  ty
    `elem` [ "ID", "BACKQUOTED_ID", "NUMBER", "STRING", "MULTILINE_STRING", "INTERPOLATION_END", "DEDENTED_STRING"
           , "CHARACTER", "SYMBOL", "THIS", "SUPER", "RETURN", "TYPE", "GIVEN"
           , "RPAREN", "RBRACK", "RBRACE", "OUTDENT", "XML_END_TAG", "XML_EMPTY_END", "XML_SPECIAL", "OP"
           ]
      ++ softKeywords

-- | The tokens that cannot start a statement, the complement of the compiler's canStartStatTokens
-- among canon's tokens; derives is kept here, though a soft keyword, since a line starting with it
-- continues a class header.
cannotStart :: [Text]
cannotStart =
  statementContinuations
    ++ [ "WITH", "EXTENDS", "DERIVES", "DOT", "COMMA", "COLON", "EQUALS", "FAT_ARROW", "CONTEXT_ARROW", "LEFT_ARROW"
       , "SUBTYPE", "SUPERTYPE", "HASH", "RPAREN", "RBRACK", "RBRACE", "SEMI", "AS"
       ]

-- | The token a closing token may follow on its own line to close an indented region opened by it:
-- else closes a then, then an if, do a while or for, yield a for, catch and finally a try, and
-- finally a catch, as the compiler's parser asks the scanner for an OUTDENT where it expects them.
closes :: Text -> [Text]
closes ty = case ty of
  "ELSE" -> ["THEN", "ELSE_CONDITION"]
  "THEN" -> ["IF"]
  "DO" -> ["WHILE", "FOR"]
  "YIELD" -> ["FOR"]
  "CATCH" -> ["TRY"]
  "FINALLY" -> ["TRY", "CATCH"]
  _ -> []

onEmit :: Token -> ScalaLayout -> ([Token], ScalaLayout)
onEmit token s0 = case heldOperator s0 of
  Just op ->
    let leadingInfix = tokenChannel token /= defaultChannelName && tokenStart token == tokenEnd op && T.any (`elem` (" \t\r\n" :: String)) (T.take 1 (tokenText token))
        (out1, s1) = step (Just leadingInfix) op s0 {heldOperator = Nothing}
        (out2, s2) = onEmit token s1
     in (out1 ++ out2, s2)
  Nothing -> step Nothing token s0

-- | Handles one token; an operator that starts a line is held until the token after it shows
-- whether it is a leading infix operator, followed by whitespace, as the compiler's
-- isLeadingInfixOperator asks.
step :: Maybe Bool -> Token -> ScalaLayout -> ([Token], ScalaLayout)
step infixKnown token s
  | isEofToken token = (replicate (length [() | Indented _ _ <- regions s]) (virtual s "OUTDENT") ++ docs s ++ [token], s {docs = []})
  | tokenChannel token /= defaultChannelName =
      ( [token]
      , s
          { lastChar = maybe (lastChar s) snd (T.unsnoc (tokenText token))
          , pastBlank = pastBlank s || (ty == "WHITESPACE" && T.count "\n" (tokenText token) >= 2)
          }
      )
  | ty `elem` docTypes = ([], s {docs = docs s ++ [token], lastChar = maybe (lastChar s) snd (T.unsnoc (tokenText token))})
  | newLine && ty == "OP" && infixKnown == Nothing && not inXml = ([], s {heldOperator = Just token})
  | otherwise =
      let leadingInfix = infixKnown == Just True && not (pastBlank s)
          (layout, s1) = if newLine && not inXml then atLineStart ty leadingInfix column s else ([], s)
          (closing, s2, opensAfterBracket) = brackets ty (if newLine then s1 else midLine s1)
          opens
            | lastType s == "END" = False
            | ty `elem` ["RPAREN", "RBRACK"] = opensAfterBracket
            | otherwise = startsIndent (lastType s) ty
          header = case regions s2 of
            (InParens _ _ : _) -> extensionHeader s2
            _
              | ty == "EXTENSION" -> True
              | ty `elem` ["LPAREN", "LBRACK", "RPAREN", "RBRACK"] -> extensionHeader s2
              | otherwise -> False
          midClose = if newLine then [] else midLineOutdents s1
       in ( layout ++ midClose ++ closing ++ docs s ++ [token]
          , s2
              { lastEnd = Just (tokenEnd token, endPosition token)
              , lastType = if lastType s == "END" && ty `elem` endTags then "ID" else ty
              , previousType = lastType s
              , lastOpens = opens
              , extensionHeader = header
              , pastBlank = False
              , lastChar = maybe (lastChar s) snd (T.unsnoc (tokenText token))
              , docs = []
              }
          )
  where
    ty = nameText (tokenType token)
    Position line column = tokenPosition token
    newLine = case lastEnd s of
      Nothing -> True
      Just (_, Position previousLine _) -> line > previousLine
    inXml = case regions s of
      (InXml _ : _) -> True
      (InString : _) -> True
      _ -> False
    -- Before a token that closes an indented region in the middle of a line, or a comma inside
    -- parentheses, the OUTDENTs the compiler's observeOutdented inserts.
    midLine st = st {regions = drop (length (midLineOutdents st)) (regions st)}
    midLineOutdents st = case regions st of
      (Indented _ prefix : _)
        | prefix `elem` closes ty -> [virtual st "OUTDENT"]
      rs
        | ty == "COMMA"
        , (indented, InParens _ _ : _) <- span isIndented rs
        , not (null indented) ->
            map (const (virtual st "OUTDENT")) indented
      _ -> []
    isIndented r = case r of
      Indented _ _ -> True
      _ -> False

-- | Opens and closes the regions of brackets, braces, and XML literals. A closing bracket or brace
-- closes the indented regions opened inside it with OUTDENTs, as the compiler's closeIndented does,
-- and a closing parenthesis says whether it ends an old-style condition or an extension's
-- parameters, after which an indented region may start.
brackets :: Text -> ScalaLayout -> ([Token], ScalaLayout, Bool)
brackets ty s = case ty of
  "LPAREN" -> open (InParens (bracketKind True) Nothing)
  "LBRACK" -> open (InParens (bracketKind False) Nothing)
  "LBRACE" -> open (InBraces Nothing)
  "RPAREN" -> close isParens
  "RBRACK" -> close isParens
  "RBRACE" -> close isBraces
  "INTERPOLATION_START" -> open InString
  "INTERPOLATION_END" -> close isString
  "XML_OPEN" -> case regions s of
    (InXml d : rest) -> ([], s {regions = InXml (d + 1) : rest}, False)
    rs -> ([], s {regions = InXml 1 : rs}, False)
  _
    | ty `elem` ["XML_END_TAG", "XML_EMPTY_END"] -> case regions s of
        (InXml d : rest) -> ([], s {regions = if d <= 1 then rest else InXml (d - 1) : rest}, False)
        _ -> ([], s, False)
    | otherwise -> ([], s, False)
  where
    open region = ([], s {regions = region : regions s}, False)
    bracketKind paren
      | paren && lastType s `elem` ["IF", "WHILE", "FOR"] = ConditionBracket
      | extensionHeader s = ExtensionBracket
      | otherwise = PlainBracket
    close matches =
      let (inner, rest) = break matches (regions s)
       in case rest of
            (region : outer) ->
              ( [virtual s "OUTDENT" | Indented _ _ <- inner]
              , s {regions = outer}
              , case region of
                  InParens kind _ -> kind /= PlainBracket
                  _ -> False
              )
            [] -> ([], s, False)
    isParens r = case r of
      InParens _ _ -> True
      _ -> False
    isBraces r = case r of
      InBraces _ -> True
      _ -> False
    isString r = case r of
      InString -> True
      _ -> False

-- | The layout tokens before the first code token of a line, by the compiler's handleNewLine. In an
-- indented region or the file's region the width is the region's; in braces it is the width of the
-- first line inside them; in parentheses and brackets it is the width of the line after the opening
-- bracket when that ends its line and the enclosing region's otherwise. NEWLINE separates two
-- statements where the region separates them (the file's region, braces, and an indented region
-- the line is not left of), the last token can end a statement, the next can start one and is no
-- leading infix operator, and the line does not continue the last as an indented line starting
-- with a bracket or after return does. Otherwise an OUTDENT closes an indented region the line is
-- left of, or level with when the region holds the cases of a match or catch and the line starts
-- with anything but case, and the rules apply again to the same line; and INDENT opens a region
-- when the line is right of the width, or level with a match or catch and starting with case, and
-- the last token may start one.
atLineStart :: Text -> Bool -> Int -> ScalaLayout -> ([Token], ScalaLayout)
atLineStart ty leadingInfix column s0 =
  let s = case fileWidth s0 of
        Nothing -> s0 {fileWidth = Just column}
        Just _ -> s0
   in go s
  where
    go s =
      let (width, separating, prefix, s') = measure s
          outermost = null (regions s)
          continuing = column > width && (ty `elem` ["LPAREN", "LBRACK", "LBRACE"] || lastType s == "RETURN") && not (pastBlank s)
          canStart = ty `notElem` cannotStart && not leadingInfix
          closesCases = column == width && prefix `elem` ["MATCH", "CATCH"] && ty /= "CASE"
          afterParameters = lastType s `elem` ["RPAREN", "RBRACK"] && opening s && column > width
          emptyBody = lastType s == "COLON" && opening s && ty == "END" && column <= width
       in if emptyBody
            then ([virtual s "NEWLINE"], s')
            else if afterParameters
            then ([virtual s "INDENT"], s' {regions = Indented column (indentPrefix s) : regions s'})
            else if separating && not closesCases && ends (lastType s) && canStart && not continuing
            then ([virtual s "NEWLINE"], s')
            else
              if column < width || (column == width && prefix `elem` ["MATCH", "CATCH"] && ty /= "CASE")
                then
                  if outermost
                    then ([], if column < width then s' {fileWidth = Just column} else s')
                    else case regions s' of
                      (Indented _ _ : outer)
                        | lastType s /= "INDENT" && not leadingInfix && lastType s `notElem` statementContinuations ->
                            let (more, s'') = go s' {regions = outer, lastType = "OUTDENT", previousType = lastType s, lastOpens = False}
                             in (virtual s "OUTDENT" : more, s'')
                      _ -> ([], s')
                else
                  if (column > width || (column == width && lastType s `elem` ["MATCH", "CATCH"] && ty == "CASE")) && opening s
                    then ([virtual s "INDENT"], s' {regions = Indented column (indentPrefix s) : regions s'})
                    else ([], s')
    opening s = lastOpens s && lastType s /= "INDENT"
    indentPrefix s
      | lastType s == "RPAREN" = "ELSE_CONDITION"
      | otherwise = lastType s
    -- The width a line is measured against, whether a line break separates statements there, the
    -- token that opened the region, and the state with the region's width recorded once known.
    measure s = case regions s of
      [] -> let w = maybe column id (fileWidth s) in (w, True, "", s)
      (Indented w prefix : _) -> (w, w <= column, prefix, s)
      (InBraces known : rest) ->
        let w = maybe column id known in (w, True, "", s {regions = InBraces (Just w) : rest})
      (InParens kind known : rest) ->
        let w = maybe (if lastType s `elem` ["LPAREN", "LBRACK"] then column else outerWidth rest) id known
         in (w, False, "", s {regions = InParens kind (Just w) : rest})
      (InXml _ : _) -> (column, False, "", s)
      (InString : _) -> (column, False, "", s)
    outerWidth rs = case rs of
      [] -> maybe 1 id (fileWidth s0)
      (Indented w _ : _) -> w
      (InBraces (Just w) : _) -> w
      (InParens _ (Just w) : _) -> w
      (_ : rest) -> outerWidth rest

-- | A layout token, empty and placed where the last code token ends, so it widens no span.
virtual :: ScalaLayout -> Text -> Token
virtual s kind = case lastEnd s of
  Just (offset, position) -> Token (Name kind) "" offset offset defaultChannelName position
  Nothing -> Token (Name kind) "" 0 0 defaultChannelName (Position 1 1)

endPosition :: Token -> Position
endPosition token =
  let Position line column = tokenPosition token
      parts = T.splitOn "\n" (tokenText token)
   in case parts of
        [single] -> Position line (column + T.length single)
        _ -> Position (line + length parts - 1) (T.length (last parts) + 1)
