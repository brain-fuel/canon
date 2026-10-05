-- | Haskell layout is decided by a base lexer that inserts virtual braces and semicolons, and this
-- is that base lexer ported as a hook, with the doc-comment handling the dialect needs.
-- It also reads the C preprocessor's conditionals, as GHC's CPP extension runs them before the
-- lexer: a directive line is a hidden token, and the tokens of a branch the build does not read are
-- hidden from the parser and from the layout algorithm, as Canon.Preprocessor chooses the branches.
-- ref:DEC-haskell-dialect ref:DEC-haskell-grammar-fixes ref:DEC-preprocessor-builds
module Canon.Antlr4.Lex.Haskell
  ( HaskellLayout (..)
  , haskellLayoutHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Preprocessor (Branches, Choice, directiveOf, reading, stepBranchesWith)
import Canon.Span (Position (..))
import Control.Monad (when)
import Control.Monad.State.Strict (State, get, gets, modify, put, runState)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | The layout state: pending indentation, the stack of open blocks, the last layout keyword, and
-- doc tokens held back.
data HaskellLayout = HaskellLayout
  { pendingDent :: Bool
  , indentCount :: Int
  , indentStack :: [(Text, Int)]
  , initialIndent :: Maybe Token
  , lastKeyWord :: Text
  , prevWasEndl :: Bool
  , prevWasKeyWord :: Bool
  , ignoreIndent :: Bool
  , moduleStartIndent :: Bool
  , wasModuleExport :: Bool
  , inPragmas :: Bool
  , startIndent :: Int
  , nestedLevel :: Int
  , queue :: [Token]
  , heldDocs :: [Token]
  , delimiterLayouts :: [(Delimiter, Int)]
  , conditionalLayouts :: [Int]
  , guardBlock :: Maybe Int
  , openGuard :: Maybe Int
  , guardLet :: Maybe (Int, Bool)
  , lastCode :: Maybe (Int, Bool)
  , undoEquals :: Maybe (Int, (Maybe Int, Maybe Int, Maybe (Int, Bool)))
  , cppBranches :: Branches
  , cppKnown :: Map.Map Text Bool
  , cppBuild :: Choice
  , lineStart :: Int
  , quasiQuotes :: Bool
  , recursiveDo :: Bool
  }
  deriving (Eq, Show)

-- | The bracket that opened a delimited span: a parenthesis or list bracket, or the brace of a
-- record, which no layout keyword opened.
data Delimiter = Bracket | RecordBrace
  deriving (Eq, Show)

initialLayout :: Choice -> HaskellLayout
initialLayout choice = HaskellLayout True 0 [] Nothing "" False False False False False False (-1) 0 [] [] [] [] Nothing Nothing Nothing Nothing Nothing [] Map.empty choice 0 False False

-- | The hooks for the Haskell grammar, reading the conditional branches a build selects.
-- ref:DEC-preprocessor-builds
haskellLayoutHooks :: Choice -> LexerHooks HaskellLayout
haskellLayoutHooks choice = LexerHooks (initialLayout choice) onAction onPredicate onEmit

-- | The predicates the grammar asks: whether a token starts a line, as a preprocessor directive
-- must; and whether a bracket, a name, and a bar open a quasi-quotation, which they do when a pragma
-- has enabled QuasiQuotes and the name is not one of Template Haskell's own brackets.
-- ref:DEC-haskell-grammar-fixes
onPredicate :: Name -> ActionText -> Text -> Int -> HaskellLayout -> Bool
onPredicate _ predicate matched start s
  | "atLineStart" `T.isInfixOf` raw = start == lineStart s
  | "isQuasiQuote" `T.isInfixOf` raw = quasiQuotes s && quoter `notElem` ["e", "t", "d", "p"]
  | otherwise = True
  where
    raw = actionTextRaw predicate
    quoter = T.dropEnd 1 (T.drop 1 matched)

hidden :: HookEffect
hidden = EffectChannel hiddenChannelName

onAction :: Name -> ActionText -> Text -> Text -> HaskellLayout -> (HaskellLayout, [HookEffect])
onAction _ action matched _ s
  | calls "processNEWLINEToken" = (s {indentCount = 0, initialIndent = Nothing}, [hidden | pendingDent s])
  | calls "processTABToken" = (s {indentCount = if pendingDent s then indentCount s + 8 * T.length matched else indentCount s}, [hidden])
  | calls "processWSToken" = (s {indentCount = if pendingDent s then indentCount s + T.length matched else indentCount s}, [hidden])
  | calls "SetHidden" = (s, [hidden])
  | otherwise = (s, [])
  where
    calls method = method `T.isInfixOf` actionTextRaw action

type Layout = State HaskellLayout

-- | The tokens that open an implicit layout block. A declaration quotation's [d| is one, as in GHC,
-- so the declarations it holds lay out as a module's do. ref:DEC-haskell-grammar-fixes
layoutKeywords :: [Text]
layoutKeywords = ["WHERE", "LET", "DO", "MDO", "OF", "LCASE", "REC", "TopenDecQoute"]

-- | Lays out a token. A directive line updates the branches read, a token of a branch not read is
-- hidden, and a hidden token other than whitespace, such as a pragma, passes through without touching
-- the layout, as a comment does. ref:DEC-haskell-grammar-fixes
onEmit :: Token -> HaskellLayout -> ([Token], HaskellLayout)
onEmit next s0
  | ty == "CPP_DIRECTIVE" = ([next], s {cppBranches = branches', cppKnown = known'})
  | not (reading (cppBranches s)) && ty /= "EOF" = ([next {tokenChannel = hiddenChannelName}], s)
  | tokenChannel next == hiddenChannelName && ty `notElem` ["NEWLINE", "WS", "TAB"] =
      ([next], s {quasiQuotes = quasiQuotes s || enables "QuasiQuotes", recursiveDo = recursiveDo s || enables "RecursiveDo" || enables "Arrows"})
  | otherwise = runState (step next) s
  where
    ty = nameText (tokenType next)
    s = if ty == "NEWLINE" then s0 {lineStart = tokenEnd next} else s0
    enables extension = ty == "PRAGMA" && extension `T.isInfixOf` tokenText next
    branches' = case directiveOf (tokenText next) of
      Just d -> stepBranchesWith (cppBuild s) (cppKnown s) d (cppBranches s)
      Nothing -> cppBranches s
    known' = case T.words (tokenText next) of
      ("#define" : name : _) | reading (cppBranches s) -> Map.insert (T.takeWhile (/= '(') name) True (cppKnown s)
      ("#undef" : name : _) | reading (cppBranches s) -> Map.insert name False (cppKnown s)
      _ -> cppKnown s

savedIndent :: HaskellLayout -> Int
savedIndent s = case indentStack s of
  ((_, i) : _) -> i
  [] -> startIndent s

column :: Token -> Int
column t = positionColumn (tokenPosition t) - 1

enqueue :: Token -> Layout ()
enqueue t = modify (\s -> s {queue = queue s ++ [t]})

takeQueue :: Layout [Token]
takeQueue = do
  s <- get
  put s {queue = []}
  pure (queue s)

createToken :: Text -> Token -> Layout Token
createToken kind next = do
  s <- get
  pure $ case initialIndent s of
    Just first -> Token (Name kind) kind (tokenStart first) (tokenStart next) defaultChannelName (tokenPosition first)
    Nothing -> Token (Name kind) kind (tokenStart next) (tokenStart next) defaultChannelName (tokenPosition next)

closeWith :: Token -> Layout ()
closeWith next = do
  enqueue =<< createToken "SEMI" next
  enqueue =<< createToken "VCCURLY" next

closeNested :: Token -> Layout ()
closeNested next = do
  s <- get
  when (nestedLevel s > length (indentStack s)) $ do
    when (nestedLevel s > 0) $ put s {nestedLevel = nestedLevel s - 1}
    closeWith next
    closeNested next

closeToIndentInclusive :: Token -> Layout ()
closeToIndentInclusive next = do
  s <- get
  when (indentCount s <= savedIndent s && not (null (indentStack s))) $ do
    put s {indentStack = drop 1 (indentStack s), nestedLevel = max 0 (nestedLevel s - 1)}
    closeWith next
    closeToIndentInclusive next

-- | Closes a block per level of indentation lost, and only while there is a block to close: a
-- line indented less than the first token of the text, as a fragment cut from the middle of a
-- file often has, closes nothing, where looping on it would emit virtual braces without end.
closeToIndent :: Token -> Layout ()
closeToIndent next = do
  s <- get
  case indentStack s of
    (_ : rest) | indentCount s < savedIndent s -> do
      put s {indentStack = rest, nestedLevel = max 0 (nestedLevel s - 1)}
      closeWith next
      closeToIndent next
    _ -> pure ()

processIn :: Token -> Layout ()
processIn next = do
  popUntilLet
  s <- get
  case indentStack s of
    ((kw, _) : _) | kw == "let" -> do
      closeWith next
      modify (\x -> x {nestedLevel = nestedLevel x - 1, indentStack = drop 1 (indentStack x)})
    _ -> pure ()
  where
    popUntilLet = do
      s <- get
      case indentStack s of
        ((kw, _) : _) | kw /= "let" -> do
          closeWith next
          modify (\x -> x {nestedLevel = nestedLevel x - 1, indentStack = drop 1 (indentStack x)})
          popUntilLet
        _ -> pure ()

processEof :: Token -> Layout ()
processEof next = do
  modify (\s -> s {indentCount = startIndent s})
  s <- get
  when (not (pendingDent s)) $ put s {initialIndent = Just next}
  closeNested next
  closeToIndent next
  s' <- get
  when (indentCount s' == savedIndent s') $ enqueue =<< createToken "SEMI" next
  when (wasModuleExport s') $ enqueue =<< createToken "VCCURLY" next
  modify (\x -> x {startIndent = -1})

isDocToken :: Text -> Bool
isDocToken ty = "DOC_" `T.isPrefixOf` ty

takeHeld :: Layout [Token]
takeHeld = do
  s <- get
  put s {heldDocs = []}
  pure (heldDocs s)

step :: Token -> Layout [Token]
step next = do
  before <- takeQueue
  -- rec and mdo open a layout block only where RecursiveDo or Arrows makes them keywords; elsewhere
  -- rec is a name, as GHC reads it. ref:DEC-haskell-grammar-fixes
  keywords <- gets recursiveDo
  let ty0 = nameText (tokenType next)
      ty = if ty0 `elem` ["REC", "MDO"] && not keywords then "VARID" else ty0
  if isDocToken ty
    then modify (\s -> s {heldDocs = heldDocs s ++ [next]}) >> pure before
    else stepCode before ty next

stepCode :: [Token] -> Text -> Token -> Layout [Token]
stepCode before ty next = do
  when (ty == "OpenPragmaBracket") $ modify (\s -> s {inPragmas = True})
  early <- startOfFile ty
  case early of
    Just tokens -> do
      held <- takeHeld
      pure (before ++ withHeld (closeDocs held) tokens)
    Nothing -> do
      afterKeyword <- gets prevWasKeyWord
      -- An equals sign or arrow that touches another operator character is part of an operator, as
      -- the equals sign of /= or ==, and neither ends a guard nor a binding; the lexer reads such an
      -- operator as several tokens, so the hook looks at the token before and undoes what the token
      -- after shows was an operator. ref:DEC-haskell-grammar-fixes
      touchesOperator <- gets (\x -> case lastCode x of Just (end, True) -> end == tokenStart next; _ -> False)
      undo <- gets undoEquals
      case undo of
        Just (end, (g, o, l)) | end == tokenStart next && operatorToken next -> modify (\x -> x {guardBlock = g, openGuard = o, guardLet = l})
        _ -> pure ()
      when (tokenChannel next /= hiddenChannelName && ty /= "NEWLINE") $
        modify (\x -> x {undoEquals = Nothing, lastCode = Just (tokenEnd next, operatorToken next)})
      snapshot <- gets (\x -> (guardBlock x, openGuard x, guardLet x))
      let equalsSign = ty `elem` ["Arrow", "Eq"] && not touchesOperator
      when equalsSign $ modify (\x -> x {undoEquals = Just (tokenEnd next, snapshot)})
      when (ty == "ClosePragmaBracket") $ modify (\s -> s {inPragmas = False})
      when (ty == "OCURLY") $ do
        s <- get
        when (prevWasKeyWord s) $ put s {nestedLevel = nestedLevel s - 1, prevWasKeyWord = False}
        s' <- get
        when (moduleStartIndent s') $ put s' {moduleStartIndent = False, wasModuleExport = False}
        modify (\x -> x {ignoreIndent = True, prevWasEndl = False})
      s1 <- get
      when (prevWasKeyWord s1 && not (prevWasEndl s1) && not (moduleStartIndent s1) && ty `notElem` ["WS", "NEWLINE", "TAB", "OCURLY"]) $ do
        put s1 {prevWasKeyWord = False, indentStack = (lastKeyWord s1, column next) : indentStack s1}
        enqueue =<< createToken "VOCURLY" next
      s2 <- get
      when (ignoreIndent s2 && ty `elem` ("CCURLY" : layoutKeywords)) $ modify (\x -> x {ignoreIndent = False})
      s3 <- get
      when (pendingDent s3 && prevWasKeyWord s3 && not (ignoreIndent s3) && indentCount s3 <= savedIndent s3 && ty `notElem` ["NEWLINE", "WS"]) $ do
        enqueue =<< createToken "VOCURLY" next
        modify (\x -> x {prevWasKeyWord = False, prevWasEndl = True})
      s3b <- get
      -- A closing brace that starts a line closes the implicit blocks above it only when it closes
      -- an explicit layout block; a record's closing brace, written level with the statements of
      -- the do around it, closes nothing. ref:DEC-haskell-grammar-fixes
      let recordBrace = case delimiterLayouts s3b of
            (RecordBrace, _) : _ -> True
            _ -> False
      when (pendingDent s3b && prevWasEndl s3b && (ty == "WHERE" || (ty == "CCURLY" && not recordBrace)) && indentCount s3b <= savedIndent s3b && nestedLevel s3b > 0) $ do
        closeNested next
        closeToIndentInclusive next
        modify (\x -> x {prevWasEndl = False})
      -- No statement, binding, or alternative starts with a guard's bar, so a bar that starts a line
      -- level with the innermost block closes the block, as the parse-error rule of the layout
      -- algorithm does, rather than parting a statement there: a case alternative's second guard
      -- after a do in its first. ref:DEC-haskell-grammar-fixes ref:DEC-layout-parse-error-rule
      sBar <- get
      when (ty == "Pipe" && pendingDent sBar && prevWasEndl sBar && not (ignoreIndent sBar)) $ closeLevel next
      s4 <- get
      when
        ( pendingDent s4
            && prevWasEndl s4
            && not (ignoreIndent s4)
            && indentCount s4 <= savedIndent s4
            && ty `notElem` ["NEWLINE", "WS", "WHERE", "IN", "DO", "MDO", "OF", "LCASE", "REC", "CCURLY", "EOF"]
        )
        $ do
          closeNested next
          closeToIndent next
          s5 <- get
          when (indentCount s5 == savedIndent s5) $ enqueue =<< createToken "SEMI" next
          modify (\x -> x {prevWasEndl = False})
          s6 <- get
          when (indentCount s6 == startIndent s6) $ modify (\x -> x {pendingDent = False})
      s7 <- get
      when (pendingDent s7 && prevWasKeyWord s7 && not (moduleStartIndent s7) && not (ignoreIndent s7) && indentCount s7 > savedIndent s7 && ty `notElem` ["NEWLINE", "WS", "EOF"]) $ do
        modify (\x -> x {prevWasKeyWord = False})
        s8 <- get
        when (prevWasEndl s8) $ put s8 {indentStack = (lastKeyWord s8, indentCount s8) : indentStack s8, prevWasEndl = False}
        enqueue =<< createToken "VOCURLY" next
      s9 <- get
      when (pendingDent s9 && initialIndent s9 == Nothing && ty /= "NEWLINE") $ modify (\x -> x {initialIndent = Just next})
      when (ty == "NEWLINE") $ modify (\x -> x {prevWasEndl = True})
      when (ty `elem` layoutKeywords) $ do
        modify (\x -> x {nestedLevel = nestedLevel x + 1, prevWasKeyWord = True, prevWasEndl = False, lastKeyWord = tokenText next})
        -- A where cannot stand in a do block, so it closes every do block it is inside, as the
        -- parse-error rule does, and attaches to the binding around them. ref:DEC-haskell-grammar-fixes
        when (ty == "WHERE") $ closeDoBlocks next
      when (ty == "OCURLY") $ do
        -- A brace no layout keyword opened is a record's, whose fields a comma parts.
        s11 <- get
        when (not afterKeyword) $ put s11 {delimiterLayouts = (RecordBrace, length (indentStack s11)) : delimiterLayouts s11}
        modify (\x -> x {prevWasKeyWord = False})
      -- An unboxed tuple's brackets and a quotation's are brackets too. ref:DEC-haskell-grammar-fixes
      when (ty `elem` openingBrackets) $
        modify (\x -> x {delimiterLayouts = (Bracket, length (indentStack x)) : delimiterLayouts x})
      when (ty `elem` closingBrackets) $ do
        saved <- gets delimiterLayouts
        case dropWhile ((/= Bracket) . fst) saved of
          (_, depth) : rest -> do
            closeDelimited next depth
            modify (\x -> x {delimiterLayouts = rest})
          [] -> pure ()
      when (ty == "CCURLY") $ do
        saved <- gets delimiterLayouts
        case saved of
          (RecordBrace, depth) : rest -> do
            closeDelimited next depth
            modify (\x -> x {delimiterLayouts = rest})
          _ -> pure ()
      -- The parse-error rule of the layout algorithm closes an implicit block at a token the block
      -- cannot hold. Two such tokens are known here: a comma of the brackets around the block, as
      -- after a case in a tuple or a let in a comprehension, and the then or else of an if around
      -- it. A comma after a guard's bar in the block is the guard's own, until its arrow or equals
      -- sign. ref:DEC-haskell-grammar-fixes ref:DEC-layout-parse-error-rule
      when (ty == "Pipe") $ do
        s12 <- get
        case delimiterLayouts s12 of
          (_, depth) : _ | length (indentStack s12) > depth -> put s12 {guardBlock = Just (length (indentStack s12))}
          _ -> pure ()
      -- Only the guard's own arrow or equals sign ends it, not one of a let inside the guard, so a
      -- comma after the let's bindings still parts the guard. ref:DEC-haskell-grammar-fixes
      when equalsSign $ modify (\x -> if maybe True (>= length (indentStack x)) (guardBlock x) then x {guardBlock = Nothing} else x)
      when (ty == "Comma") $ do
        s13 <- get
        case delimiterLayouts s13 of
          (_, depth) : _ | guardBlock s13 /= Just (length (indentStack s13)) -> closeDelimited next depth
          _ -> pure ()
      -- A let in a guard is closed by the equals sign that ends the guard, the second one at the
      -- level of its bindings since the binding began. ref:DEC-layout-parse-error-rule
      -- A bar directly inside brackets is a comprehension's, not a guard's.
      when (ty == "Pipe") $ modify (\x -> case delimiterLayouts x of
        (_, depth) : _ | depth == length (indentStack x) -> x
        _ -> x {openGuard = Just (length (indentStack x))})
      when (ty == "LET") $ do
        s14 <- get
        when (openGuard s14 == Just (length (indentStack s14))) $ put s14 {guardLet = Just (length (indentStack s14) + 1, False)}
      when (ty `elem` ["NEWLINE", "Semi"]) $ modify (\x -> x {guardLet = fmap (\(d, _) -> (d, False)) (guardLet x)})
      when equalsSign $ do
        s15 <- get
        let n = length (indentStack s15)
            endGuard = modify (\x -> x {openGuard = if maybe False (>= n) (openGuard x) then Nothing else openGuard x, guardLet = case guardLet x of Just (d, _) | n < d -> Nothing; other -> other})
        case guardLet s15 of
          Just (d, False) | n == d, ty == "Eq" -> put s15 {guardLet = Just (d, True)}
          Just (d, True) | n == d, ty == "Eq" -> do
            closeDelimited next (d - 1)
            modify (\x -> x {guardLet = Nothing, openGuard = Nothing})
          _ -> endGuard
      when (ty == "IF") $ modify (\x -> x {conditionalLayouts = length (indentStack x) : conditionalLayouts x})
      when (ty `elem` ["THEN", "ELSE"]) $ do
        saved <- gets conditionalLayouts
        case saved of
          depth : rest -> do
            closeDelimited next depth
            when (ty == "ELSE") $ modify (\x -> x {conditionalLayouts = rest})
          [] -> pure ()
      if tokenChannel next == hiddenChannelName || ty == "NEWLINE"
        then pure (before ++ [next])
        else do
          when (ty == "IN") $ processIn next
          when (ty == "EOF") $ processEof next
          modify (\x -> x {pendingDent = True})
          queued <- takeQueue
          held <- takeHeld
          pure (before ++ queued ++ closeDocs held ++ [next])
  where
    withHeld held tokens = case reverse tokens of
      (final : virtual) -> reverse virtual ++ held ++ [final]
      [] -> held
    startOfFile kind = do
      s <- get
      if startIndent s == -1 && kind `notElem` ["NEWLINE", "WS", "TAB", "OCURLY"]
        then do
          when (kind == "MODULE") $ modify (\x -> x {moduleStartIndent = True, wasModuleExport = True})
          st <- get
          if kind /= "MODULE" && not (moduleStartIndent st) && not (inPragmas st)
            then do
              put st {startIndent = column next}
              pure Nothing
            else
              if lastKeyWord st == "where" && moduleStartIndent st
                then do
                  put st {lastKeyWord = "", prevWasKeyWord = False, nestedLevel = 0, moduleStartIndent = False, prevWasEndl = False, startIndent = column next}
                  open <- createToken "VOCURLY" next
                  -- A module whose body is empty, as module Lib where and nothing else, closes the
                  -- block it opens at the end of the file. ref:DEC-haskell-grammar-fixes
                  if kind == "EOF"
                    then do
                      close <- createToken "VCCURLY" next
                      pure (Just [open, close, next])
                    else pure (Just [open, next])
                else pure Nothing
        else pure Nothing

-- | Tells a token made of operator characters, which may be part of a longer operator.
operatorToken :: Token -> Bool
operatorToken t = not (T.null (tokenText t)) && T.all (`elem` ("!#$%&*+./<=>?@\\^|-~:" :: String)) (tokenText t)

-- | A closing parenthesis or list bracket ends only the implicit layout blocks opened
-- inside that delimiter. Enclosing let/where blocks must stay open.
closeDelimited :: Token -> Int -> Layout ()
closeDelimited next depth = do
  s <- get
  when (length (indentStack s) > depth) $ do
    closeWith next
    modify (\x -> x {indentStack = drop 1 (indentStack x), nestedLevel = max 0 (nestedLevel x - 1)})
    closeDelimited next depth

-- | Closes the implicit blocks whose indentation a line's first token is level with, keeping the
-- outermost block of the file open.
closeLevel :: Token -> Layout ()
closeLevel next = do
  s <- get
  case indentStack s of
    ((_, i) : rest) | indentCount s == i -> do
      put s {indentStack = rest, nestedLevel = max 0 (nestedLevel s - 1)}
      closeWith next
      closeLevel next
    _ -> pure ()

-- | The tokens that open and close a bracketed span, inside which a comma or the closer ends the
-- implicit blocks opened in the span.
openingBrackets, closingBrackets :: [Text]
openingBrackets = ["OpenRoundBracket", "OpenSquareBracket", "OpenBoxParen", "TopenExpQuote", "TopenExpQuoteE", "TopenTexpQuote", "TopenPatQuote", "TopenTypQoute", "TopenDecQoute"]
closingBrackets = ["CloseRoundBracket", "CloseSquareBracket", "CloseBoxParen", "TcloseQoute", "TcloseTExpQoute"]

-- | Closes the do blocks on top of the stack, before a where that cannot stand in one.
closeDoBlocks :: Token -> Layout ()
closeDoBlocks next = do
  s <- get
  case indentStack s of
    ((kw, _) : rest) | kw `elem` ["do", "mdo"] -> do
      closeWith next
      modify (\x -> x {indentStack = rest, nestedLevel = nestedLevel x - 1})
      closeDoBlocks next
    _ -> pure ()

-- | Ends each held doc comment with an empty DOC_END token, so the comment rule of the dialect has
-- one end rather than one per word, which the parser would otherwise try at every word of every
-- comment. ref:DEC-haskell-dialect
closeDocs :: [Token] -> [Token]
closeDocs toks = case toks of
  [] -> []
  (first : rest) -> first : go first rest
  where
    go previous remaining = case remaining of
      [] -> [docEnd previous]
      (t : more)
        | nameText (tokenType t) `elem` ["DOC_OPEN", "DOC_BLOCK_OPEN"] -> docEnd previous : t : go t more
        | otherwise -> t : go t more
    docEnd previous = Token (Name "DOC_END") "" (tokenEnd previous) (tokenEnd previous) defaultChannelName (tokenPosition previous)
