-- | C# and F# compile one branch of each #if, chosen by symbols a build defines, and canon reads one
-- too: the first branch whose condition holds for some choice of the symbols the file does not
-- define or undefine itself. The lexer hooks of both languages hide the other branches from the
-- parser, and extraction leaves the comments in them unbound and unreported, so one policy decides
-- both what code canon sees and what documentation it expects to bind. ref:DEC-csharp-grammar
-- ref:DEC-fsharp-grammar
module Canon.Preprocessor
  ( Condition (..)
  , Directive (..)
  , Branches
  , parseCondition
  , conditionTokens
  , satisfiable
  , stepBranches
  , reading
  , directiveOf
  , inactiveLines
  ) where

import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..), defaultChannelName)
import Canon.Span (Position (..))
import Data.Char (isAlphaNum, isSpace)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

-- | A preprocessor condition.
data Condition
  = CondSymbol Text
  | CondConstant Bool
  | CondNot Condition
  | CondAnd Condition Condition
  | CondOr Condition Condition
  | CondEq Condition Condition
  | CondNe Condition Condition
  deriving (Eq, Show)

-- | A conditional directive.
data Directive
  = DirectiveIf Condition
  | DirectiveElif Condition
  | DirectiveElse
  | DirectiveEndif
  deriving (Eq, Show)

-- | One entry per open #if, innermost first: whether its current branch is read, and whether any
-- branch of it has been.
type Branches = [(Bool, Bool)]

-- | Whether the code at this point is read: every open #if is in its read branch.
reading :: Branches -> Bool
reading = all fst

-- | Applies a directive. A branch is read when the directives around it are read, no earlier branch
-- of its #if was, and its condition holds for some choice of the symbols not known.
stepBranches :: Map.Map Text Bool -> Directive -> Branches -> Branches
stepBranches known directive branches = case directive of
  DirectiveIf condition ->
    let holds = reading branches && satisfiable known condition
     in (holds, holds) : branches
  DirectiveElif condition -> case branches of
    ((_, taken) : outer) ->
      let holds = not taken && reading outer && satisfiable known condition
       in (holds, taken || holds) : outer
    [] -> branches
  DirectiveElse -> case branches of
    ((_, taken) : outer) -> (not taken && reading outer, True) : outer
    [] -> branches
  DirectiveEndif -> drop 1 branches

-- | Parses the tokens of a condition by C#'s precedence: !, then == and !=, then &&, then ||. A
-- condition that does not parse reads as true, so its branch is kept.
parseCondition :: [Token] -> Condition
parseCondition toks = case orExpr (map simplify (filter significant toks)) of
  Just (c, []) -> c
  _ -> CondConstant True
  where
    significant t = tokenType t `notElem` [Name "DIRECTIVE_NEW_LINE", Name "SINGLE_LINE_COMMENT"]
    simplify t = (nameText (tokenType t), tokenText t)
    binary next ops build ts = do
      (left, rest) <- next ts
      loop left rest
      where
        loop left rest = case rest of
          ((ty, _) : more) | ty `elem` ops -> do
            (right, rest') <- next more
            loop (build ty left right) rest'
          _ -> Just (left, rest)
    orExpr = binary andExpr ["OP_OR"] (\_ a b -> CondOr a b)
    andExpr = binary eqExpr ["OP_AND"] (\_ a b -> CondAnd a b)
    eqExpr = binary unary ["OP_EQ", "OP_NE"] (\ty a b -> if ty == "OP_EQ" then CondEq a b else CondNe a b)
    unary ts = case ts of
      (("BANG", _) : rest) -> fmap (\(c, r) -> (CondNot c, r)) (unary rest)
      (("OPEN_PARENS", _) : rest) -> case orExpr rest of
        Just (c, ("CLOSE_PARENS", _) : more) -> Just (c, more)
        _ -> Nothing
      (("TRUE", _) : rest) -> Just (CondConstant True, rest)
      (("FALSE", _) : rest) -> Just (CondConstant False, rest)
      (("CONDITIONAL_SYMBOL", name) : rest) -> Just (CondSymbol name, rest)
      _ -> Nothing

-- | The tokens of a condition written as text, named as the C# lexer names them so one parser reads
-- conditions from either language.
conditionTokens :: Text -> [Token]
conditionTokens text = go (T.stripStart text)
  where
    go t
      | T.null t = []
      | "//" `T.isPrefixOf` t = []
      | Just rest <- T.stripPrefix "&&" t = tok "OP_AND" "&&" rest
      | Just rest <- T.stripPrefix "||" t = tok "OP_OR" "||" rest
      | Just rest <- T.stripPrefix "==" t = tok "OP_EQ" "==" rest
      | Just rest <- T.stripPrefix "!=" t = tok "OP_NE" "!=" rest
      | Just rest <- T.stripPrefix "!" t = tok "BANG" "!" rest
      | Just rest <- T.stripPrefix "(" t = tok "OPEN_PARENS" "(" rest
      | Just rest <- T.stripPrefix ")" t = tok "CLOSE_PARENS" ")" rest
      | otherwise =
          let (word, rest) = T.span (\c -> isAlphaNum c || c == '_' || c == '.') t
           in if T.null word
                then go (T.stripStart (T.drop 1 t))
                else case word of
                  "true" -> tok "TRUE" word rest
                  "false" -> tok "FALSE" word rest
                  _ -> tok "CONDITIONAL_SYMBOL" word rest
    tok kind text' rest = Token (Name kind) text' 0 0 defaultChannelName (Position 1 1) : go (T.dropWhile isSpace rest)

-- | Whether a condition holds for some choice of its free symbols, with the known symbols fixed.
-- Beyond twelve free symbols it is taken to hold rather than enumerated.
satisfiable :: Map.Map Text Bool -> Condition -> Bool
satisfiable known condition
  | length free > 12 = True
  | otherwise = any (\choice -> eval (Map.union known (Map.fromList (zip free choice))) condition) (choices (length free))
  where
    free = nub [n | n <- symbolsOf condition, not (Map.member n known)]
    choices n = if n == 0 then [[]] else [b : bs | b <- [True, False], bs <- choices (n - 1)]
    symbolsOf c = case c of
      CondSymbol n -> [n]
      CondConstant _ -> []
      CondNot a -> symbolsOf a
      CondAnd a b -> symbolsOf a ++ symbolsOf b
      CondOr a b -> symbolsOf a ++ symbolsOf b
      CondEq a b -> symbolsOf a ++ symbolsOf b
      CondNe a b -> symbolsOf a ++ symbolsOf b
    eval env c = case c of
      CondSymbol n -> Map.findWithDefault False n env
      CondConstant b -> b
      CondNot a -> not (eval env a)
      CondAnd a b -> eval env a && eval env b
      CondOr a b -> eval env a || eval env b
      CondEq a b -> eval env a == eval env b
      CondNe a b -> eval env a /= eval env b

-- | The conditional directive a line holds, if any.
directiveOf :: Text -> Maybe Directive
directiveOf line = case T.stripPrefix "#" (T.stripStart line) of
  Just rest
    | Just c <- keyword "if" rest -> Just (DirectiveIf (parseCondition (conditionTokens c)))
    | Just c <- keyword "elif" rest -> Just (DirectiveElif (parseCondition (conditionTokens c)))
    | Just _ <- keyword "else" rest -> Just DirectiveElse
    | Just _ <- keyword "endif" rest -> Just DirectiveEndif
  _ -> Nothing
  where
    keyword word rest = case T.stripPrefix word (T.stripStart rest) of
      Just after | T.null after || not (isAlphaNum (T.head after) || T.head after == '_') -> Just after
      _ -> Nothing

-- | The lines of a source that lie in a branch canon does not read, by the policy the lexer hooks
-- apply, with the symbols the file defines and undefines known from the line they are set on.
inactiveLines :: Text -> Set.Set Int
inactiveLines source = go (zip [1 ..] (T.lines source)) [] Map.empty Set.empty
  where
    go numbered branches known acc = case numbered of
      [] -> acc
      ((n, line) : rest) ->
        let acc' = if reading branches then acc else Set.insert n acc
         in case directiveOf line of
              Just d -> go rest (stepBranches known d branches) known acc'
              Nothing -> case symbolDirective line of
                Just (name, value) | reading branches -> go rest branches (Map.insert name value known) acc'
                _ -> go rest branches known acc'
    symbolDirective line = case T.words (T.stripStart line) of
      ("#define" : name : _) -> Just (name, True)
      ("#undef" : name : _) -> Just (name, False)
      _ -> Nothing
