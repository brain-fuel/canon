module Canon.Antlr4.RuleGraph
  ( RuleGraph (..)
  , referenceGraph
  , nullableRules
  , leftCornerGraph
  , directlyLeftRecursiveRules
  , leftRecursiveRules
  , unreachableRules
  , stronglyConnectedRuleGroups
  ) where

import Canon.Antlr4.Query (allRules, ruleName, ruleNames, ruleReferences)
import Canon.Antlr4.Syntax
import Data.Graph (SCC (..), graphFromEdges, reachable, stronglyConnComp)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set

data RuleGraph = RuleGraph
  { ruleGraphNodes :: [Name]
  , ruleGraphEdges :: Map Name (Set Name)
  }
  deriving (Eq, Show)

referenceGraph :: Grammar ann -> RuleGraph
referenceGraph g =
  RuleGraph (ruleNames g) (Map.fromListWith Set.union [(ruleName r, ruleReferences r) | r <- allRules g])

nullableRules :: Grammar ann -> Set Name
nullableRules g = fixpoint Set.empty
  where
    rules = allRules g
    fixpoint known =
      let next = Set.fromList [ruleName r | r <- rules, ruleNullable known r]
       in if next == known then known else fixpoint next

ruleNullable :: Set Name -> Rule ann -> Bool
ruleNullable known r = case r of
  RuleParser p -> any (alternativeNullable known . labeledAlternativeBody) (NonEmpty.toList (parserRuleAlternatives p))
  RuleLexer l -> any (lexerAlternativeNullable known) (NonEmpty.toList (lexerRuleAlternatives l))

alternativeNullable :: Set Name -> Alternative ann -> Bool
alternativeNullable known = all (elementNullable known) . alternativeElements

elementNullable :: Set Name -> Element ann -> Bool
elementNullable known e = case e of
  ElementAtom _ _ a suffix -> suffixNullable suffix || atomNullable a
  ElementBlock _ _ b suffix -> suffixNullable suffix || any (alternativeNullable known) (NonEmpty.toList (blockAlternatives b))
  ElementAction {} -> True
  where
    atomNullable a = case a of
      AtomRuleRef n _ _ -> Set.member n known
      _ -> False

lexerAlternativeNullable :: Set Name -> LexerAlternative ann -> Bool
lexerAlternativeNullable known = all (lexerElementNullable known) . lexerAlternativeElements

lexerElementNullable :: Set Name -> LexerElement ann -> Bool
lexerElementNullable known e = case e of
  LexerElementAtom _ a suffix -> suffixNullable suffix || lexerAtomNullable a
  LexerElementBlock _ alts suffix -> suffixNullable suffix || any (lexerAlternativeNullable known) (NonEmpty.toList alts)
  LexerElementAction {} -> True
  where
    lexerAtomNullable a = case a of
      LexerAtomTerminal (TerminalToken n _) -> Set.member n known
      _ -> False

suffixNullable :: Maybe EbnfSuffix -> Bool
suffixNullable suffix = case suffix of
  Just (EbnfSuffix Optional _) -> True
  Just (EbnfSuffix ZeroOrMore _) -> True
  _ -> False

leftCornerGraph :: Grammar ann -> RuleGraph
leftCornerGraph g = RuleGraph (ruleNames g) (Map.fromListWith Set.union [(ruleName r, leftCorners r) | r <- allRules g])
  where
    nullable = nullableRules g
    leftCorners r = case r of
      RuleParser p -> Set.unions (map (alternativeLeftCorners . labeledAlternativeBody) (NonEmpty.toList (parserRuleAlternatives p)))
      RuleLexer l -> Set.unions (map lexerAlternativeLeftCorners (NonEmpty.toList (lexerRuleAlternatives l)))
    alternativeLeftCorners = go . alternativeElements
      where
        go elements = case elements of
          [] -> Set.empty
          (e : rest) -> Set.union (elementLeftCorners e) (if elementNullable nullable e then go rest else Set.empty)
    elementLeftCorners e = case e of
      ElementAtom _ _ (AtomRuleRef n _ _) _ -> Set.singleton n
      ElementBlock _ _ b _ -> Set.unions (map alternativeLeftCorners (NonEmpty.toList (blockAlternatives b)))
      _ -> Set.empty
    lexerAlternativeLeftCorners = go . lexerAlternativeElements
      where
        go elements = case elements of
          [] -> Set.empty
          (e : rest) -> Set.union (lexerElementLeftCorners e) (if lexerElementNullable nullable e then go rest else Set.empty)
    lexerElementLeftCorners e = case e of
      LexerElementAtom _ (LexerAtomTerminal (TerminalToken n _)) _ -> Set.singleton n
      LexerElementBlock _ alts _ -> Set.unions (map lexerAlternativeLeftCorners (NonEmpty.toList alts))
      _ -> Set.empty

directlyLeftRecursiveRules :: Grammar ann -> Set Name
directlyLeftRecursiveRules g = Set.fromList [n | (n, targets) <- Map.toList (ruleGraphEdges (leftCornerGraph g)), Set.member n targets]

leftRecursiveRules :: Grammar ann -> Set Name
leftRecursiveRules g = Set.fromList (concatMap NonEmpty.toList (stronglyConnectedRuleGroups (leftCornerGraph g)))

stronglyConnectedRuleGroups :: RuleGraph -> [NonEmpty Name]
stronglyConnectedRuleGroups graph = mapMaybe cyclic (stronglyConnComp (adjacency graph))
  where
    cyclic scc = case scc of
      CyclicSCC members -> NonEmpty.nonEmpty members
      AcyclicSCC _ -> Nothing

adjacency :: RuleGraph -> [(Name, Name, [Name])]
adjacency (RuleGraph nodes edges) =
  [(n, n, filter (`Set.member` defined) (Set.toList (Map.findWithDefault Set.empty n edges))) | n <- nodes]
  where
    defined = Set.fromList nodes

unreachableRules :: Name -> Grammar ann -> Set Name
unreachableRules start g = case vertexOf start of
  Nothing -> Set.fromList (ruleGraphNodes graph)
  Just v ->
    let reached = Set.fromList [n | vertex <- reachable adjacencyGraph v, let (n, _, _) = nodeOf vertex]
     in Set.difference (Set.fromList (ruleGraphNodes graph)) reached
  where
    graph = referenceGraph g
    (adjacencyGraph, nodeOf, vertexOf) = graphFromEdges (adjacency graph)
