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
import Control.Monad.State.Strict (State, get, modify, put, runState)
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
  }
  deriving (Eq, Show)

initialLayout :: HaskellLayout
initialLayout = HaskellLayout True 0 [] Nothing "" False False False False False False (-1) 0 [] []

-- | The hooks for the Haskell grammar.
haskellLayoutHooks :: LexerHooks HaskellLayout
haskellLayoutHooks = LexerHooks initialLayout onAction onEmit

hidden :: HookEffect
hidden = EffectChannel hiddenChannelName

onAction :: Name -> ActionText -> Text -> HaskellLayout -> (HaskellLayout, [HookEffect])
onAction _ action matched s
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

closeToIndent :: Token -> Layout ()
closeToIndent next = do
  s <- get
  when (indentCount s < savedIndent s) $ do
    when (not (null (indentStack s)) && nestedLevel s > 0) $
      put s {indentStack = drop 1 (indentStack s), nestedLevel = nestedLevel s - 1}
    closeWith next
    closeToIndent next

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
      when (ty == "OCURLY") $ modify (\x -> x {prevWasKeyWord = False})
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
