-- | Apache Groovy's parser grammar asks its Java superclass, AbstractParser, and the
-- SemanticPredicates class whether a line is a method declaration or a call, a local variable
-- declaration or a command expression, and whether a command expression may take arguments after a
-- call; this is that superclass as a predicate hook, with the one predicate canon adds,
-- isConstructorName, which tells a constructor from a method as upstream's AST builder did.
-- ref:DEC-parser-predicates ref:DEC-groovy-grammar
module Canon.Antlr4.Predicate.Groovy
  ( groovyPredicates
  ) where

import Canon.Antlr4.Parse (PredicateHook)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Antlr4.Token (Token (..))
import Data.Char (isAlpha, isUpper)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as BV

-- | The predicates of GroovyParser, read with _input.LT(1) as the token the parse has reached. A
-- predicate written with a leading ! holds when the call it negates fails. The counters of switch
-- expressions and async closures, and the annotation-type argument, are not tracked, so those
-- predicates hold, which admits a yield or defer statement where upstream reads a call. In the
-- canonically commented dialect a Groovydoc comment may start the declaration a predicate looks at,
-- and the predicates that read the next tokens look past it, as upstream's parser never saw it.
-- ref:DEC-groovy-dialect
groovyPredicates :: PredicateHook
groovyPredicates predicate toks from at
  | calls "isInvalidMethodDeclaration" = negated (typeAt 1 `elem` ["Identifier", "CapitalizedIdentifier", "StringLiteral", "YIELD"] && typeAt 2 == "LPAREN")
  | calls "isIdentifierAssign" = negated (startsWord (textAt 1) && typeAt 2 == "ASSIGN")
  | calls "isInvalidLocalVariableDeclaration" = negated (invalidLocalVariableDeclaration toks next)
  | calls "isFollowingArgumentsOrClosure" = negated (followingArgumentsOrClosure toks from at)
  | calls "LT(2).getType() == DOT" = typeAt 2 == "DOT"
  | calls "isConstructorName" = constructorName toks from at
  | otherwise = True
  where
    calls method = method `T.isInfixOf` predicate
    negated value = if "!" `T.isPrefixOf` T.strip predicate then not value else value
    next = pastDocComments toks at
    typeAt k = tokenTypeAt toks (next + k - 1)
    textAt k = maybe "" tokenText (toks BV.!? (next + k - 1))

-- | The index of the first token at or after i that is not part of a Groovydoc comment or one of the
-- newlines after it.
pastDocComments :: BV.Vector Token -> Int -> Int
pastDocComments toks i
  | tokenTypeAt toks i == "DOC_BLOCK_OPEN" = pastDocComments toks (afterNewlines (afterClose i))
  | otherwise = i
  where
    afterClose k
      | k >= BV.length toks = k
      | tokenTypeAt toks k == "DOC_BLOCK_CLOSE" = k + 1
      | otherwise = afterClose (k + 1)
    afterNewlines k = if tokenTypeAt toks k == "NL" then afterNewlines (k + 1) else k

tokenTypeAt :: BV.Vector Token -> Int -> Text
tokenTypeAt toks i = maybe "EOF" (nameText . tokenType) (toks BV.!? i)

startsWord :: Text -> Bool
startsWord t = case T.uncons t of
  Just (c, _) -> isAlpha c || c == '_' || c == '$'
  Nothing -> False

-- | SemanticPredicates.isInvalidLocalVariableDeclaration: a statement such as a b is a command
-- expression, not a declaration of b, unless its first word is a primitive type, a modifier, or
-- capitalized, or an assignment, type arguments, or brackets follow; an annotation starts a
-- declaration unless a loop follows it.
invalidLocalVariableDeclaration :: BV.Vector Token -> Int -> Bool
invalidLocalVariableDeclaration toks at
  | dottedGeneric = False
  | otherwise =
      ( not (firstType == "BuiltInPrimitiveType" || firstType `elem` modifierTypes)
          && not (isUpper next)
          && next /= '@'
          && not (typeAt (index + 2) == "ASSIGN" || type2 `elem` ["LT", "LBRACK"])
      )
        || (next == '@' && annotatedLoopStatement toks at)
  where
    typeAt k = tokenTypeAt toks (at + k - 1)
    afterDots k = if typeAt k == "DOT" then afterDots (k + 2) else k
    (index, type2, dottedGeneric) =
      if typeAt 2 == "DOT"
        then
          let n = afterDots 4
           in (n - 1, typeAt n, typeAt n `elem` ["LT", "LBRACK"])
        else (1, typeAt 2, False)
    firstType = typeAt index
    next = maybe ' ' fst (T.uncons (maybe "" tokenText (toks BV.!? (at + index - 1))))
    modifierTypes = ["ABSTRACT", "FINAL", "NATIVE", "PRIVATE", "PROTECTED", "PUBLIC", "STATIC", "STRICTFP", "SYNCHRONIZED", "TRANSIENT", "VOLATILE", "DEF", "VAR", "VAL", "DEFAULT", "SEALED", "NON_SEALED"]

-- | SemanticPredicates.isAnnotatedLoopStatement: annotations followed by for, while, or do.
annotatedLoopStatement :: BV.Vector Token -> Int -> Bool
annotatedLoopStatement toks at = tokenTypeAt toks (skipAnnotations at) `elem` ["FOR", "WHILE", "DO"]
  where
    skipAnnotations i
      | tokenTypeAt toks i == "AT" = skipAnnotations (skipArguments (skipDots (i + 2)))
      | otherwise = i
    skipDots i = if tokenTypeAt toks i == "DOT" then skipDots (i + 2) else i
    skipArguments i
      | tokenTypeAt toks i == "LPAREN" = closeFrom (i + 1) (1 :: Int)
      | otherwise = i
    closeFrom i depth
      | depth == 0 || i >= BV.length toks = i
      | otherwise = case tokenTypeAt toks i of
          "LPAREN" -> closeFrom (i + 1) (depth + 1)
          "RPAREN" -> closeFrom (i + 1) (depth - 1)
          _ -> closeFrom (i + 1) depth

-- | SemanticPredicates.isFollowingArgumentsOrClosure, which asks whether the expression before a
-- command's arguments is a path ending in arguments or a closure, read from its tokens: an
-- expression with an operator outside brackets is not a path, and a path ends in arguments or a
-- closure when its last bracket group is a parenthesis or a brace opened after its first token. A
-- new expression's own arguments and body are its creator, not a path element.
followingArgumentsOrClosure :: BV.Vector Token -> Int -> Int -> Bool
followingArgumentsOrClosure toks from at
  | at <= from = False
  | any (`elem` operators) depthZero = False
  | otherwise = case tokenTypeAt toks (at - 1) of
      "RPAREN" -> closesPath "LPAREN" "RPAREN"
      "RBRACE" -> closesPath "LBRACE" "RBRACE"
      _ -> False
  where
    depthZero = [tokenTypeAt toks i | (i, 0) <- zip [from .. at - 1] (depths from (0 :: Int))]
    depths i d
      | i >= at = []
      | otherwise =
          let t = tokenTypeAt toks i
              d' = if t `elem` openers then d + 1 else if t `elem` closers then max 0 (d - 1) else d
           in (if t `elem` closers then d' else d) : depths (i + 1) d'
    closesPath open close =
      let o = fromMaybe from (opener open close (at - 1))
       in o > from && not (tokenTypeAt toks from == "NEW" && not (any (`elem` pathOperators) [tokenTypeAt toks i | i <- [from .. o - 1]]))
    opener open close i = go (i - 1) (0 :: Int)
      where
        go k depth
          | k < from = Nothing
          | tokenTypeAt toks k == close = go (k - 1) (depth + 1)
          | tokenTypeAt toks k == open = if depth == 0 then Just k else go (k - 1) (depth - 1)
          | otherwise = go (k - 1) depth
    openers = ["LPAREN", "LBRACK", "SAFE_INDEX", "LBRACE"]
    closers = ["RPAREN", "RBRACK", "RBRACE"]
    pathOperators = ["DOT", "SAFE_DOT", "SPREAD_DOT", "SAFE_CHAIN_DOT", "METHOD_POINTER", "METHOD_REFERENCE"]
    operators =
      [ "ASSIGN", "ADD_ASSIGN", "SUB_ASSIGN", "MUL_ASSIGN", "DIV_ASSIGN", "AND_ASSIGN", "OR_ASSIGN", "XOR_ASSIGN", "MOD_ASSIGN"
      , "LSHIFT_ASSIGN", "RSHIFT_ASSIGN", "URSHIFT_ASSIGN", "POWER_ASSIGN", "ELVIS_ASSIGN"
      , "ADD", "SUB", "MUL", "DIV", "MOD", "POWER", "AND", "OR", "BITAND", "BITOR", "XOR", "LT", "GT", "LE", "GE"
      , "EQUAL", "NOTEQUAL", "IDENTICAL", "NOT_IDENTICAL", "SPACESHIP", "REGEX_FIND", "REGEX_MATCH", "IMPLIES"
      , "QUESTION", "ELVIS", "COLON", "INSTANCEOF", "NOT_INSTANCEOF", "AS", "IN", "NOT_IN"
      , "RANGE_INCLUSIVE", "RANGE_EXCLUSIVE_LEFT", "RANGE_EXCLUSIVE_RIGHT", "RANGE_EXCLUSIVE_FULL"
      , "NOT", "BITNOT", "INC", "DEC", "ARROW"
      ]

-- | Whether the name the parse has reached, followed by a parenthesis, is the name of the class,
-- enum, record, or trait whose body holds it: the nearest unclosed brace before the member, and the
-- type keyword before that brace with no brace or semicolon between.
constructorName :: BV.Vector Token -> Int -> Int -> Bool
constructorName toks from at =
  tokenTypeAt toks (at + 1) == "LPAREN"
    && maybe False (\name -> fmap tokenText (toks BV.!? at) == Just name) (enclosingBrace (from - 1) (0 :: Int) >>= typeName)
  where
    enclosingBrace k depth
      | k < 0 = Nothing
      | otherwise = case tokenTypeAt toks k of
          "RBRACE" -> enclosingBrace (k - 1) (depth + 1)
          "LBRACE" -> if depth == 0 then Just k else enclosingBrace (k - 1) (depth - 1)
          _ -> enclosingBrace (k - 1) depth
    typeName brace = keyword (brace - 1)
    keyword k
      | k < 0 = Nothing
      | otherwise = case tokenTypeAt toks k of
          t
            | t `elem` ["CLASS", "ENUM", "RECORD", "TRAIT"] -> tokenText <$> toks BV.!? (k + 1)
            | t `elem` ["LBRACE", "RBRACE", "SEMI"] -> Nothing
            | otherwise -> keyword (k - 1)
