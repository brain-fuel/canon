-- | Haskell layout is decided by a base lexer that inserts virtual braces and semicolons, and this
-- is that base lexer ported as a hook, with the doc-comment handling the dialect needs.
-- ref:DEC-haskell-dialect ref:DEC-haskell-grammar-fixes
module Canon.Antlr4.Lex.Haskell
  ( HaskellLayout (..)
  , haskellLayoutHooks
  ) where

import Canon.Antlr4.Lex (HookEffect (..), LexerHooks (..))
import Canon.Antlr4.Syntax (ActionText (..), Name (..))
import Canon.Antlr4.Token
import Canon.Span (Position (..))
import Control.Monad (when)
import Control.Monad.State.Strict (State, get, gets, modify, put, runState)
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
  }
  deriving (Eq, Show)

-- | The bracket that opened a delimited span: a parenthesis or list bracket, or the brace of a
-- record, which no layout keyword opened.
data Delimiter = Bracket | RecordBrace
  deriving (Eq, Show)

initialLayout :: HaskellLayout
initialLayout = HaskellLayout True 0 [] Nothing "" False False False False False False (-1) 0 [] [] [] [] Nothing Nothing Nothing Nothing Nothing

-- | The hooks for the Haskell grammar.
haskellLayoutHooks :: LexerHooks HaskellLayout
haskellLayoutHooks = LexerHooks initialLayout onAction (\_ _ _ _ _ -> True) onEmit

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

layoutKeywords :: [Text]
layoutKeywords = ["WHERE", "LET", "DO", "MDO", "OF", "LCASE", "REC"]

onEmit :: Token -> HaskellLayout -> ([Token], HaskellLayout)
onEmit next s0 = runState (step next) s0

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
  let ty = nameText (tokenType next)
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
      pure (before ++ withHeld held tokens)
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
      when (pendingDent s3b && prevWasEndl s3b && ty `elem` ["WHERE", "CCURLY"] && indentCount s3b <= savedIndent s3b && nestedLevel s3b > 0) $ do
        closeNested next
        closeToIndentInclusive next
        modify (\x -> x {prevWasEndl = False})
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
        when (ty == "WHERE") $ do
          s10 <- get
          case indentStack s10 of
            ((kw, _) : rest) | kw `elem` ["do", "mdo"] -> do
              closeWith next
              modify (\x -> x {indentStack = rest, nestedLevel = nestedLevel x - 1})
            _ -> pure ()
      when (ty == "OCURLY") $ do
        -- A brace no layout keyword opened is a record's, whose fields a comma parts.
        s11 <- get
        when (not afterKeyword) $ put s11 {delimiterLayouts = (RecordBrace, length (indentStack s11)) : delimiterLayouts s11}
        modify (\x -> x {prevWasKeyWord = False})
      when (ty `elem` ["OpenRoundBracket", "OpenSquareBracket"]) $
        modify (\x -> x {delimiterLayouts = (Bracket, length (indentStack x)) : delimiterLayouts x})
      when (ty `elem` ["CloseRoundBracket", "CloseSquareBracket"]) $ do
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
      when equalsSign $ modify (\x -> x {guardBlock = Nothing})
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
          pure (before ++ queued ++ held ++ [next])
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
                  pure (Just [open, next])
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
