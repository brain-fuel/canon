-- | C# and F# compile one branch of each #if, chosen by the symbols a build defines. A parse reads
-- the branches one choice selects and hides the others from the parser: by default the first branch
-- whose condition holds for some choice of the symbols the file does not define or undefine itself,
-- or under a build, the branches one assignment of the symbols selects. Extraction parses a file
-- once per build of a small set that together reads every branch some build compiles, and merges
-- what each finds, so no branch goes unread. ref:DEC-csharp-grammar ref:DEC-fsharp-grammar
-- ref:DEC-preprocessor-builds
module Canon.Preprocessor
  ( Condition (..)
  , Directive (..)
  , Branches
  , Choice
  , parseCondition
  , conditionTokens
  , satisfiable
  , stepBranches
  , stepBranchesWith
  , reading
  , directiveOf
  , inactiveLines
  , inactiveLinesWith
  , builds
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

-- | Which branches a parse reads: Nothing for the first branch whose condition holds for some choice
-- of the symbols not known, or a build's assignment of symbols, under which a symbol neither known
-- nor assigned is undefined.
type Choice = Maybe (Map.Map Text Bool)

-- | Applies a directive by the default choice.
stepBranches :: Map.Map Text Bool -> Directive -> Branches -> Branches
stepBranches = stepBranchesWith Nothing

-- | Applies a directive. A branch is read when the directives around it are read, no earlier branch
-- of its #if was, and its condition holds under the choice; symbols the file defines or undefines
-- override the build's.
stepBranchesWith :: Choice -> Map.Map Text Bool -> Directive -> Branches -> Branches
stepBranchesWith choice known directive branches = case directive of
  DirectiveIf condition ->
    let holds = reading branches && decide condition
     in (holds, holds) : branches
  DirectiveElif condition -> case branches of
    ((_, taken) : outer) ->
      let holds = not taken && reading outer && decide condition
       in (holds, taken || holds) : outer
    [] -> branches
  DirectiveElse -> case branches of
    ((_, taken) : outer) -> (not taken && reading outer, True) : outer
    [] -> branches
  DirectiveEndif -> drop 1 branches
  where
    decide condition = case choice of
      Nothing -> satisfiable known condition
      Just assignment -> evaluate (Map.union known assignment) condition

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
  | otherwise = any (\choice -> evaluate (Map.union known (Map.fromList (zip free choice))) condition) (assignments (length free))
  where
    free = nub [n | n <- symbolsOf condition, not (Map.member n known)]

-- | Every assignment of n symbols, all defined first.
assignments :: Int -> [[Bool]]
assignments n = if n == 0 then [[]] else [b : bs | b <- [True, False], bs <- assignments (n - 1)]

-- | The symbols a condition names.
symbolsOf :: Condition -> [Text]
symbolsOf c = case c of
  CondSymbol n -> [n]
  CondConstant _ -> []
  CondNot a -> symbolsOf a
  CondAnd a b -> symbolsOf a ++ symbolsOf b
  CondOr a b -> symbolsOf a ++ symbolsOf b
  CondEq a b -> symbolsOf a ++ symbolsOf b
  CondNe a b -> symbolsOf a ++ symbolsOf b

-- | A condition's value with the given symbols defined or not, and the rest undefined.
evaluate :: Map.Map Text Bool -> Condition -> Bool
evaluate env c = case c of
  CondSymbol n -> Map.findWithDefault False n env
  CondConstant b -> b
  CondNot a -> not (evaluate env a)
  CondAnd a b -> evaluate env a && evaluate env b
  CondOr a b -> evaluate env a || evaluate env b
  CondEq a b -> evaluate env a == evaluate env b
  CondNe a b -> evaluate env a /= evaluate env b

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

-- | The lines of a source that lie in a branch the default choice does not read.
inactiveLines :: Text -> Set.Set Int
inactiveLines = inactiveLinesWith Nothing

-- | The lines of a source that lie in a branch a choice does not read, by the policy the lexer hooks
-- apply, with the symbols the file defines and undefines known from the line they are set on.
inactiveLinesWith :: Choice -> Text -> Set.Set Int
inactiveLinesWith choice source = fst (walkBranches choice source)

-- | The inactive lines under a choice, and the lines of the directives that open a branch it reads.
walkBranches :: Choice -> Text -> (Set.Set Int, Set.Set Int)
walkBranches choice source = go (zip [1 ..] (T.lines source)) [] Map.empty Set.empty Set.empty
  where
    go numbered branches known acc opened = case numbered of
      [] -> (acc, opened)
      ((n, line) : rest) ->
        let acc' = if reading branches then acc else Set.insert n acc
         in case directiveOf line of
              Just d ->
                let branches' = stepBranchesWith choice known d branches
                    opens = d /= DirectiveEndif && reading branches'
                 in go rest branches' known acc' (if opens then Set.insert n opened else opened)
              Nothing -> case symbolDirective line of
                Just (name, value) | reading branches -> go rest branches (Map.insert name value known) acc' opened
                _ -> go rest branches known acc' opened
    symbolDirective line = case T.words (T.stripStart line) of
      ("#define" : name : _) -> Just (name, True)
      ("#undef" : name : _) -> Just (name, False)
      _ -> Nothing

-- | The builds a file is read under: the default choice when it has no conditional directive, and
-- otherwise a few assignments of the symbols its conditions name that together read every branch
-- some assignment reads, picked greedily by how many branches not yet read each adds. A branch no
-- assignment reads, such as #if false, is never read. Beyond twelve symbols the default choice is
-- the only build, since enumerating the assignments would not end in useful time.
builds :: Text -> [Choice]
builds source
  | null conditions = [Nothing]
  | length free > 12 = [Nothing]
  | otherwise = cover Set.empty candidates
  where
    conditions = [c | line <- T.lines source, Just d <- [directiveOf line], c <- conditionOf d]
    conditionOf d = case d of
      DirectiveIf c -> [c]
      DirectiveElif c -> [c]
      _ -> []
    free = nub (concatMap symbolsOf conditions)
    candidates = [(Just (Map.fromList (zip free bs)), snd (walkBranches (Just (Map.fromList (zip free bs))) source)) | bs <- assignments (length free)]
    cover covered remaining =
      case [(Set.size (Set.difference opened covered), choice, opened) | (choice, opened) <- remaining] of
        [] -> []
        scored ->
          let best = maximum [gain | (gain, _, _) <- scored]
           in case [(choice, opened) | (gain, choice, opened) <- scored, gain == best] of
                ((choice, opened) : _)
                  | best > 0 || Set.null covered -> choice : cover (Set.union covered opened) [r | r@(c, _) <- remaining, c /= choice]
                _ -> []
