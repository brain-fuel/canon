-- | Semantic predicates belong to a parser's base class in the target language, and canon answers
-- them through a hook keyed by the parser grammar's superClass option, as lexer actions are answered.
-- ref:DEC-parser-predicates ref:DEC-csharp-grammar
module Canon.Antlr4.Predicate
  ( predicateHookFor
  , csharpPredicates
  , javaScriptPredicates
  , goPredicates
  , pythonPredicates
  ) where

import Canon.Antlr4.Parse (PredicateHook)
import Canon.Antlr4.Predicate.Groovy (groovyPredicates)
import Canon.Antlr4.Query (grammarOptions)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token (..))
import Data.Char (isAlpha, isAlphaNum, isUpper)
import Data.Maybe (listToMaybe)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as BV

-- | The predicate hook a parser grammar's superClass selects; every predicate holds otherwise.
predicateHookFor :: Grammar ann -> PredicateHook
predicateHookFor grammar =
  case [NonEmpty.last v | Option (Name "superClass") (OptionValueName (QualifiedName v)) <- grammarOptions grammar] of
    (Name "CSharpParserBase" : _) -> csharpPredicates
    (Name "JavaScriptParserBase" : _) -> javaScriptPredicates
    (Name "TypeScriptParserBase" : _) -> javaScriptPredicates
    (Name "GoParserBase" : _) -> goPredicates
    (Name "Python3ParserBase" : _) -> pythonPredicates
    (Name "GroovyParserBase" : _) -> groovyPredicates
    _ -> \_ _ _ _ -> True

-- | CSharpParserBase's predicates. IsRightArrow, IsRightShift, and IsRightShiftAssignment hold when
-- the two tokens just read touch, so = > is no arrow and > > no shift. IsLocalVariableDeclaration
-- fails when the declaration's type is var, which allows one declarator only.
csharpPredicates :: PredicateHook
csharpPredicates predicate toks from at
  | any calls ["IsRightArrow", "IsRightShiftAssignment", "IsRightShift"] = touching (at - 2) (at - 1)
  | calls "IsLocalVariableDeclaration" = not implicitlyTyped
  | otherwise = True
  where
    calls method = method `T.isInfixOf` predicate
    touching i j = case (toks BV.!? i, toks BV.!? j) of
      (Just a, Just b) -> tokenEnd a == tokenStart b
      _ -> False
    implicitlyTyped =
      let typeAt = until (\k -> maybe True (not . isPrefixKeyword) (toks BV.!? k)) (+ 1) from
       in case (toks BV.!? typeAt, toks BV.!? (typeAt + 1)) of
            (Just t, Just next) -> tokenText t == "var" && startsName (tokenText next)
            _ -> False
    isPrefixKeyword t = tokenText t `elem` ["await", "using", "ref", "readonly", "scoped"]
    startsName t = case T.uncons t of
      Just (c, _) -> isAlpha c || c == '_' || c == '@'
      Nothing -> False

-- | JavaScriptParserBase's and TypeScriptParserBase's predicates. n("x") holds when the next token
-- reads x and p("x") when the one just read does, so a getter, a setter, and a static member are
-- told from a member named get, set, or static. lineTerminatorAhead holds when the token just read
-- and the next one are on different lines, which is where the base class finds a line terminator
-- among the hidden tokens between them, and notLineTerminator when they are on one line; closeBrace
-- holds when the next token is a closing brace, and notOpenBraceAndNotFunction, with its
-- TypeScript form that adds interface, when the next token opens no block, function, or interface.
-- propertyAhead, which only the dialects ask, holds when a name and a colon follow, as a property of
-- an object literal starts, so a doc comment before one is read as an orphan there and not taken by
-- a path that reads the braces as a block. A doc comment is not code, so these look past it to the
-- code on either side. ref:DEC-javascript-dialect ref:DEC-stray-comments
javaScriptPredicates :: PredicateHook
javaScriptPredicates predicate toks _ at
  | Just word <- argumentOf "n" = textAt at == Just word
  | Just word <- argumentOf "p" = textAt (at - 1) == Just word
  | "notLineTerminator" `T.isInfixOf` predicate = not lineBreak
  | "lineTerminatorAhead" `T.isInfixOf` predicate = lineBreak
  | "closeBrace" `T.isInfixOf` predicate = codeText == Just "}"
  | "notOpenBraceAndNotFunctionAndNotInterface" `T.isInfixOf` predicate = codeText `notElem` map Just ["{", "function", "interface"]
  | "notOpenBraceAndNotFunction" `T.isInfixOf` predicate = codeText `notElem` map Just ["{", "function"]
  | "propertyAhead" `T.isInfixOf` predicate = propertyAhead
  | otherwise = True
  where
    argumentOf method = case T.breakOn ("." <> method <> "(\"") predicate of
      (_, rest) | not (T.null rest) -> Just (T.takeWhile (/= '"') (T.drop (T.length method + 3) rest))
      _ -> Nothing
    textAt i = tokenText <$> toks BV.!? i
    isDoc t = let ty = nameText (tokenType t) in "DOC_" `T.isPrefixOf` ty || "FILE_DOC_" `T.isPrefixOf` ty
    code = until (\i -> maybe True (not . isDoc) (toks BV.!? i)) (+ 1) at
    codeText = textAt code
    previous = until (\i -> i < 0 || maybe True (not . isDoc) (toks BV.!? i)) (subtract 1) (at - 1)
    lineBreak = case (toks BV.!? previous, toks BV.!? code) of
      (Just before, Just after) -> endLine before < positionLine (tokenPosition after)
      _ -> False
    endLine t = positionLine (tokenPosition t) + T.count "\n" (tokenText t)
    propertyAhead = case (toks BV.!? code, toks BV.!? (code + 1)) of
      (Just name, Just colon) -> tokenText colon == ":" && maybe False (\(c, _) -> isAlphaNum c || c `elem` ("_$'\"" :: String)) (T.uncons (tokenText name))
      _ -> False

-- | The predicates the canonically commented Go grammar adds to GoParserBase; upstream's own, such
-- as isOperand, still hold. isExported holds when the next token is an identifier with an upper-case
-- initial, which is what makes a Go name visible outside its package, and a leading ! negates it.
-- ref:DEC-go-dialect ref:revive-exported
goPredicates :: PredicateHook
goPredicates predicate toks _ at
  | "isExported" `T.isInfixOf` predicate = negated predicate (maybe False (startsWith isUpper . tokenText) (toks BV.!? at))
  | otherwise = True

-- | The predicates the canonically commented Python grammar adds to Python3ParserBase; upstream's
-- own still hold. isPublicTopLevel holds when the next token names a definition at the top level
-- of a module, nested in no def or class body though it may stand in a module-level if, try, or
-- with block, without a leading underscore, which is what PEP 8 calls public. The nesting is
-- counted from the INDENT and DEDENT tokens before the definition: a def or class opens a body one
-- level deeper than itself, which the DEDENT back to its own level closes. isPrivateName holds when the next token starts with an underscore
-- and is not __init__, which PEP 257 asks to document like a public method. isDocString holds when
-- the next tokens are strings, one or adjacent ones that Python joins, that are a statement alone,
-- ended by its line, and none a bytes or an f-string, which Python does not take as a docstring. isOverload holds when the next tokens are
-- an @overload decorator, bare or qualified, whose stub pydocstyle asks not to document.
-- ref:DEC-python-dialect ref:pep-257
pythonPredicates :: PredicateHook
pythonPredicates predicate toks _ at
  | "isPublicTopLevel" `T.isInfixOf` predicate = negated predicate (public && topLevel)
  | "isPrivateName" `T.isInfixOf` predicate = negated predicate (not public && nameText' /= Just "__init__")
  | "isDocString" `T.isInfixOf` predicate = negated predicate docString
  | "isOverload" `T.isInfixOf` predicate = negated predicate overload
  | otherwise = True
  where
    overload = case map tokenText (takeWhile ((/= "NEWLINE") . nameText . tokenType) (drop at (BV.toList toks))) of
      ("@" : dotted) -> not (null dotted) && last dotted == "overload"
      _ -> False
    isString t = nameText (tokenType t) == "STRING"
    docString = case span isString (drop at (BV.toList toks)) of
      (strings@(_ : _), next) ->
        not (any (T.any (`elem` ("bBfF" :: String)) . T.takeWhile (`notElem` ("'\"" :: String)) . tokenText) strings)
          && maybe True ((`elem` ["NEWLINE", "EOF"]) . nameText . tokenType) (listToMaybe next)
      _ -> False
    nameText' = tokenText <$> toks BV.!? at
    public = maybe False (not . T.isPrefixOf "_") nameText'
    topLevel = null (openDefinitions (BV.toList (BV.take (at - 1) toks)))

-- | The depths of the def and class bodies open after the tokens: each def or class at a depth
-- pushes it, and a DEDENT to a depth closes every body at or below it, as does a later def or class
-- at the same depth, which ends a one-line definition that opened no indented body.
-- ref:DEC-python-dialect
openDefinitions :: [Token] -> [Int]
openDefinitions = go (0 :: Int) []
  where
    go depth open ts = case ts of
      [] -> filter (< depth) open
      (t : rest) -> case nameText (tokenType t) of
        "INDENT" -> go (depth + 1) open rest
        "DEDENT" -> go (depth - 1) (filter (< depth - 1) open) rest
        _
          | tokenText t `elem` ["def", "class"] -> go depth (depth : filter (< depth) open) rest
          | otherwise -> go depth open rest

-- | A predicate written with a leading ! asks the opposite.
negated :: Text -> Bool -> Bool
negated predicate value = if "!" `T.isInfixOf` predicate then not value else value

startsWith :: (Char -> Bool) -> Text -> Bool
startsWith p t = maybe False (p . fst) (T.uncons t)
