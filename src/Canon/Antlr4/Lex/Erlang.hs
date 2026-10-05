-- | Erlang's preprocessor replaces each macro call with the body of its -define before the parser
-- sees it, and this hook does the same for the macros a file defines itself, so a macro that stands
-- for part of a form, such as an element followed by a comma, parses as its expansion does. A macro
-- the file does not define, such as ?MODULE or one from an included header, is left to the grammar,
-- which reads a macro call where an expression, a pattern, a type, a form, or a clause may be. The
-- -define itself is passed on unchanged, so the grammar still reads it as an attribute.
-- ref:DEC-erlang-grammar
module Canon.Antlr4.Lex.Erlang
  ( ErlangPreprocessorState (..)
  , Macro (..)
  , erlangPreprocessorHooks
  , expandMacros
  ) where

import Canon.Antlr4.Lex (LexerHooks (..))
import Canon.Antlr4.Token (Token (..), isEofToken)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

-- | A macro a file defines: its parameters, if it takes any, and the tokens of its body.
data Macro = Macro
  { macroParameters :: Maybe [Text]
  , macroBody :: [Token]
  }
  deriving (Eq, Show)

-- | The hook state: the macros defined so far, by name, one per arity, as Erlang allows, the last two tokens passed on, the tokens of a
-- -define being read, with its bracket depth, and the tokens of a macro call held back until it is
-- complete.
data ErlangPreprocessorState = ErlangPreprocessorState
  { macros :: Map.Map Text [Macro]
  , recent :: [Text]
  , defining :: Maybe ([Token], Int)
  , pending :: [Token]
  }
  deriving (Eq, Show)

-- | The hooks for the Erlang grammars.
erlangPreprocessorHooks :: LexerHooks ErlangPreprocessorState
erlangPreprocessorHooks = LexerHooks (ErlangPreprocessorState Map.empty [] Nothing []) (\_ _ _ _ s -> (s, [])) (\_ _ _ _ _ -> True) onEmit

onEmit :: Token -> ErlangPreprocessorState -> ([Token], ErlangPreprocessorState)
onEmit token s
  | isEofToken token = (pending s ++ [token], s {pending = []})
  | Just (collected, depth) <- defining s = passOn (record collected depth)
  | not (null (pending s)) = continueCall (pending s ++ [token])
  | text == "?" = ([], s {pending = [token]})
  | text == "define", take 2 (recent s) `elem` [["-", "."], ["-"]] = passOn s {defining = Just ([], 0)}
  | otherwise = passOn s
  where
    text = tokenText token
    passOn st = ([token], st {recent = take 2 (text : recent st)})
    record collected depth =
      let depth' = depth + bracketChange text
          collected' = collected ++ [token]
       in if depth' == 0 && depth > 0
            then s {defining = Nothing, macros = maybe (macros s) (\(name, m) -> Map.insertWith replaceArity name [m] (macros s)) (parseDefine collected')}
            else s {defining = Just (collected', depth')}
    continueCall held = case held of
      [_, name] | tokenText name == "?" -> (held, s {pending = [], recent = take 2 ("?" : recent s)})
      (_ : name : rest)
        | Just defined <- Map.lookup (tokenText name) (macros s) ->
            if all ((== Nothing) . macroParameters) defined
              then finish (expandMacros (macros s) (take 2 held)) (drop 2 held)
              else case rest of
                [] -> ([], s {pending = held})
                (open : _) | tokenText open /= "(" -> finish (expandMacros (macros s) (take 2 held)) rest
                _ -> case closingIndex rest of
                  Just n -> finish (expandMacros (macros s) (take (2 + n) held)) (drop (2 + n) held)
                  Nothing -> ([], s {pending = held})
      _ -> finish held []
    finish emitted rest =
      let (more, s') = foldl (\(acc, st) t -> let (out, st') = onEmit t st in (acc ++ out, st')) ([], s {pending = []}) rest
       in (emitted ++ more, s' {recent = take 2 (map tokenText (reverse emitted) ++ recent s')})

-- | Adds a definition, replacing an earlier one of the same arity.
replaceArity :: [Macro] -> [Macro] -> [Macro]
replaceArity new old = new ++ [m | m <- old, fmap length (macroParameters m) `notElem` map (fmap length . macroParameters) new]

-- | The definition a call uses: the one whose parameters match its arguments, or the one without
-- parameters.
chooseMacro :: [Macro] -> Maybe Int -> Maybe Macro
chooseMacro defined arguments = case [m | Just n <- [arguments], m <- defined, fmap length (macroParameters m) == Just n] of
  (m : _) -> Just m
  [] -> case [m | m <- defined, macroParameters m == Nothing] of
    (m : _) -> Just m
    [] -> Nothing

-- | The number of tokens up to and including the parenthesis that closes the first one.
closingIndex :: [Token] -> Maybe Int
closingIndex = go 0 0
  where
    go :: Int -> Int -> [Token] -> Maybe Int
    go n depth toks = case toks of
      [] -> Nothing
      (t : rest) ->
        let depth' = depth + bracketChange (tokenText t)
         in if depth' == 0 then Just (n + 1) else go (n + 1) depth' rest

bracketChange :: Text -> Int
bracketChange t
  | t `elem` ["(", "[", "{", "<<"] = 1
  | t `elem` [")", "]", "}", ">>"] = -1
  | otherwise = 0

-- | Reads a -define from the tokens after its keyword: the name, the parameters, and the body up to the
-- closing parenthesis.
parseDefine :: [Token] -> Maybe (Text, Macro)
parseDefine toks = case toks of
  (open : name : rest) | tokenText open == "(" -> case rest of
    (paren : more) | tokenText paren == "(" -> do
      n <- closingIndex (paren : more)
      let params = [tokenText t | t <- take (n - 2) more, tokenText t /= ","]
      comma : body <- Just (drop (n - 1) more)
      if tokenText comma == "," then Just (tokenText name, Macro (Just params) (dropClose body)) else Nothing
    (comma : body) | tokenText comma == "," -> Just (tokenText name, Macro Nothing (dropClose body))
    _ -> Nothing
  _ -> Nothing
  where
    dropClose body = take (length body - 1) body

-- | Expands the macro calls in a run of tokens whose macros are known, replacing each call with the
-- body of its macro, its parameters replaced by the arguments, every token placed at the call so spans
-- stay in order. A call of an unknown macro is kept, and expansion stops after a fixed depth, so a
-- macro that refers to itself ends.
expandMacros :: Map.Map Text [Macro] -> [Token] -> [Token]
expandMacros = expand (16 :: Int)
  where
    expand depth known toks = case toks of
      (q : name : rest)
        | depth > 0
        , tokenText q == "?"
        , Just defined <- Map.lookup (tokenText name) known ->
            let called = case rest of
                  (open : _) | tokenText open == "(", Just n <- closingIndex rest -> Just (n, splitArguments (take (n - 2) (drop 1 rest)))
                  _ -> Nothing
             in case (called, chooseMacro defined (length . snd <$> called)) of
                  (Just (n, args), Just macro@(Macro (Just params) _)) ->
                    let bound = Map.fromList (zip params args)
                        body = concatMap (\t -> Map.findWithDefault [t] (tokenText t) bound) (macroBody macro)
                     in placed q (lastOf name rest n) (expand (depth - 1) known body) ++ expand depth known (drop n rest)
                  (_, Just (Macro Nothing body)) -> placed q name (expand (depth - 1) known body) ++ expand depth known rest
                  _ -> q : expand depth known (name : rest)
      (t : rest) -> t : expand depth known rest
      [] -> []
    lastOf name rest n = if n == 0 then name else last (name : take n rest)
    placed first final = map (\t -> t {tokenStart = tokenStart first, tokenEnd = tokenEnd final, tokenPosition = tokenPosition first})

-- | Splits macro arguments at the commas outside brackets.
splitArguments :: [Token] -> [[Token]]
splitArguments toks = if null toks then [] else go 0 [] toks
  where
    go :: Int -> [Token] -> [Token] -> [[Token]]
    go depth current remaining = case remaining of
      [] -> [reverse current]
      (t : rest)
        | depth == 0 && tokenText t == "," -> reverse current : go depth [] rest
        | otherwise -> go (depth + bracketChange (tokenText t) + keywordChange (tokenText t)) (t : current) rest
    keywordChange t
      | t `elem` ["begin", "case", "if", "receive", "try", "maybe"] = 1
      | t == "end" = -1
      | otherwise = 0
