module Canon.Antlr4.RuleGraphTest (tests) where

import Canon.Antlr4.Gen (genClosedGrammar)
import Canon.Antlr4.Query (allRules, ruleName, ruleNames)
import Canon.Antlr4.Read
import Canon.Antlr4.RuleGraph
import Canon.Antlr4.Syntax
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, forAll, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "rule graph"
    [ testProperty "nullable rules agree with the naive fixpoint" nullableAgrees
    , testProperty "left recursion agrees with the brute-force closure" leftRecursionAgrees
    , testProperty "direct left recursion is a subset of left recursion" directIsSubset
    , testProperty "vendored grammars have no left recursion" vendoredNotLeftRecursive
    , testProperty "vendored parser grammar is fully reachable from grammarSpec" vendoredReachable
    ]

nullableAgrees :: Property
nullableAgrees = property $ do
  g <- forAll genClosedGrammar
  nullableRules g === naiveNullable g

leftRecursionAgrees :: Property
leftRecursionAgrees = property $ do
  g <- forAll genClosedGrammar
  let corners = ruleGraphEdges (leftCornerGraph g)
      closure = transitiveClosure corners
      expected = Set.fromList [n | n <- ruleNames g, Set.member n (Map.findWithDefault Set.empty n closure)]
  leftRecursiveRules g === expected
  directlyLeftRecursiveRules g === Set.fromList [n | n <- ruleNames g, Set.member n (Map.findWithDefault Set.empty n corners)]

directIsSubset :: Property
directIsSubset = property $ do
  g <- forAll genClosedGrammar
  Set.isSubsetOf (directlyLeftRecursiveRules g) (leftRecursiveRules g) === True

naiveNullable :: Grammar ann -> Set Name
naiveNullable g = go Set.empty
  where
    go known =
      let next = Set.union known (Set.fromList [ruleName r | r <- allRules g, naiveRuleNullable known r])
       in if next == known then known else go next

naiveRuleNullable :: Set Name -> Rule ann -> Bool
naiveRuleNullable known r = case r of
  RuleParser p -> any (all elementNullable . alternativeElements . labeledAlternativeBody) (NonEmpty.toList (parserRuleAlternatives p))
  RuleLexer l -> any (all lexerElementNullable . lexerAlternativeElements) (NonEmpty.toList (lexerRuleAlternatives l))
  where
    optionalSuffix s = case s of
      Just (EbnfSuffix Optional _) -> True
      Just (EbnfSuffix ZeroOrMore _) -> True
      _ -> False
    elementNullable e = case e of
      ElementAtom _ _ (AtomRuleRef n _ _) s -> optionalSuffix s || Set.member n known
      ElementAtom _ _ _ s -> optionalSuffix s
      ElementBlock _ _ b s -> optionalSuffix s || any (all elementNullable . alternativeElements) (NonEmpty.toList (blockAlternatives b))
      ElementAction {} -> True
    lexerElementNullable e = case e of
      LexerElementAtom _ (LexerAtomTerminal (TerminalToken n _)) s -> optionalSuffix s || Set.member n known
      LexerElementAtom _ _ s -> optionalSuffix s
      LexerElementBlock _ alts s -> optionalSuffix s || any (all lexerElementNullable . lexerAlternativeElements) (NonEmpty.toList alts)
      LexerElementAction {} -> True

transitiveClosure :: Map.Map Name (Set Name) -> Map.Map Name (Set Name)
transitiveClosure edges = go edges
  where
    go current =
      let next = Map.map (\targets -> Set.unions (targets : [Map.findWithDefault Set.empty t current | t <- Set.toList targets])) current
       in if next == current then current else go next

readOrFail :: FilePath -> PropertyT IO (Grammar Span)
readOrFail path = do
  result <- evalIO (readGrammarFile path)
  case result of
    Left err -> annotate (T.unpack (renderReadError err)) >> failure
    Right r -> pure (readResultGrammar r)

vendoredNotLeftRecursive :: Property
vendoredNotLeftRecursive = withTests 1 $ property $ do
  lexer <- readOrFail "grammars/antlr4/ANTLRv4Lexer.g4"
  parser <- readOrFail "grammars/antlr4/ANTLRv4Parser.g4"
  leftRecursiveRules lexer === Set.empty
  leftRecursiveRules parser === Set.empty

vendoredReachable :: Property
vendoredReachable = withTests 1 $ property $ do
  parser <- readOrFail "grammars/antlr4/ANTLRv4Parser.g4"
  unreachableRules (Name "grammarSpec") parser === Set.empty
