-- | Semantic predicates belong to a parser's base class in the target language, and canon answers
-- them through a hook keyed by the parser grammar's superClass option, as lexer actions are answered.
-- ref:DEC-parser-predicates ref:DEC-csharp-grammar
module Canon.Antlr4.Predicate
  ( predicateHookFor
  , csharpPredicates
  , javaScriptPredicates
  ) where

import Canon.Antlr4.Parse (PredicateHook)
import Canon.Antlr4.Query (grammarOptions)
import Canon.Antlr4.Syntax
import Canon.Antlr4.Token (Token (..))
import Data.Char (isAlpha)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T
import qualified Data.Vector as BV

-- | The predicate hook a parser grammar's superClass selects; every predicate holds otherwise.
predicateHookFor :: Grammar ann -> PredicateHook
predicateHookFor grammar =
  case [NonEmpty.last v | Option (Name "superClass") (OptionValueName (QualifiedName v)) <- grammarOptions grammar] of
    (Name "CSharpParserBase" : _) -> csharpPredicates
    (Name "JavaScriptParserBase" : _) -> javaScriptPredicates
    (Name "TypeScriptParserBase" : _) -> javaScriptPredicates
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

-- | JavaScriptParserBase's and TypeScriptParserBase's token-text predicates: n("x") holds when the
-- next token reads x and p("x") when the one just read does, so a getter, a setter, and a static
-- member are told from a member named get, set, or static. The line-terminator predicates would need
-- the hidden tokens, which the hook is not given, so they hold. ref:DEC-javascript-dialect
javaScriptPredicates :: PredicateHook
javaScriptPredicates predicate toks _ at
  | Just word <- argumentOf "n" = textAt at == Just word
  | Just word <- argumentOf "p" = textAt (at - 1) == Just word
  | otherwise = True
  where
    argumentOf method = case T.breakOn ("." <> method <> "(\"") predicate of
      (_, rest) | not (T.null rest) -> Just (T.takeWhile (/= '"') (T.drop (T.length method + 3) rest))
      _ -> Nothing
    textAt i = tokenText <$> toks BV.!? i
