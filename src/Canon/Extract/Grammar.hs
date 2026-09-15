module Canon.Extract.Grammar
  ( GrammarExtractError (..)
  , Extraction (..)
  , AlternativePlan (..)
  , loadProfileInterpreter
  , extractWithProfile
  , extractWithProfileText
  , renderGrammarExtractError
  , alternativePlans
  , unitsFromTree
  ) where

import Canon.Antlr4.Comment (Comment (..))
import Canon.Antlr4.Interpret
import Canon.Antlr4.Lexical (lineTable, positionAt)
import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Syntax (Alternative (..), Block (..), EbnfSuffix (..), Element (..), Grammar (..), Label (..), LabeledAlternative (..), Name (..), ParserRule (..), Quantifier (OneOrMore), Rule (..))
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.Attach (attachPreceding, firstContentLine, topOfFileComment)
import Canon.CanonicalComment (docCommentBody, parseCanonicalComment, toWhy)
import Canon.CommentScan (scanCommentsWith)
import Canon.Config (Config (..))
import Canon.Git.Fill (fillGitFromBlame)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Profile
import Canon.Span (Located (..), Position (..), Span (..))
import Canon.Testing (isTestUnit)
import Data.Char (isAlphaNum)
import Data.Foldable (toList)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, listToMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Vector.Unboxed as V
import System.FilePath (splitDirectories)

data GrammarExtractError
  = GrammarInterpretError InterpretError
  | GrammarDuplicateUnitIds [UnitId]
  deriving (Eq, Show)

data Extraction = Extraction
  { extractionModel :: Model Evidence
  , extractionFindings :: [Finding]
  }
  deriving (Eq, Show)

data AlternativePlan = AlternativePlan
  { planKind :: Text
  , planWhyRequired :: Bool
  }
  deriving (Eq, Show)

renderGrammarExtractError :: GrammarExtractError -> Text
renderGrammarExtractError e = case e of
  GrammarInterpretError err -> renderInterpretError err
  GrammarDuplicateUnitIds ids -> "duplicate unit ids: " <> T.intercalate ", " (map renderUnitId ids)

loadProfileInterpreter :: Profile -> IO (Either InterpretError Interpreter)
loadProfileInterpreter profile = case profileGrammar profile of
  CombinedGrammarFile path -> loadCombinedInterpreter path
  SplitGrammarFiles lexer parser -> loadInterpreter lexer parser

extractWithProfile :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> FilePath -> IO (Either GrammarExtractError Extraction)
extractWithProfile provider config language profile interpreter idPath path =
  TIO.readFile path >>= extractWithProfileText provider config language profile interpreter idPath path

extractWithProfileText :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> FilePath -> Text -> IO (Either GrammarExtractError Extraction)
extractWithProfileText provider config language profile interpreter idPath path source =
  case interpretText interpreter (profileStart profile) path source of
    Left err -> pure (Left (GrammarInterpretError err))
    Right tree -> case unitsFromTree language profile (alternativePlans (interpreterParser interpreter)) idPath path source tree of
      Left err -> pure (Left err)
      Right (root, labeled, unbound) -> do
        let comments = scanCommentsWith (profileComments profile) source
            (attached, orphans) = extractDecisionsFor path source root (Set.fromList (map decisionId labeled)) comments
        (unitsWithGit, gitFindings) <- fillGitFromBlame provider path root
        described <- either (const Nothing) id <$> describeVersion provider
        let model = Model language (configVersion config) described [unitsWithGit] (labeled ++ attached)
        pure (Right (Extraction model (map (OrphanDocComment path) unbound ++ [OrphanDocComment path (locatedSpan c) | c <- orphans] ++ gitFindings)))

alternativePlans :: Grammar Span -> Map.Map Name [Maybe AlternativePlan]
alternativePlans grammar = Map.fromList [(parserRuleName r, map plan (toList (parserRuleAlternatives r))) | RuleParser r <- grammarRules grammar]
  where
    plan la = case labeledAlternativeLabel la of
      Just (Name kind) | whys@(_ : _) <- concatMap whyElements (alternativeElements (labeledAlternativeBody la)) -> Just (AlternativePlan kind (and whys))
      _ -> Nothing
    whyElements e = case e of
      ElementAtom _ (Just (Label (Name "why") _)) _ suffix -> [mandatory suffix]
      ElementBlock _ (Just (Label (Name "why") _)) _ suffix -> [mandatory suffix]
      ElementBlock _ _ block _ -> concatMap (concatMap whyElements . alternativeElements) (toList (blockAlternatives block))
      _ -> []
    mandatory suffix = case suffix of
      Nothing -> True
      Just (EbnfSuffix OneOrMore _) -> True
      Just _ -> False

unitsFromTree :: Text -> Profile -> Map.Map Name [Maybe AlternativePlan] -> FilePath -> FilePath -> Text -> ParseTree -> Either GrammarExtractError (CodeUnit Evidence, [Decision Evidence], [Span])
unitsFromTree language profile plans idPath path source tree =
  case [i | i@(_ : _ : _) <- group (sort (map unitId (allUnits root)))] of
    [] -> Right (root, decisions, unbound)
    duplicates -> Left (GrammarDuplicateUnitIds (map NonEmpty.head (map NonEmpty.fromList duplicates)))
  where
    evidence = DerivedFromParse path
    chars = V.fromList (T.unpack source)
    table = lineTable source
    fileSegments = [T.pack d | d <- splitDirectories idPath, d /= "."]
    fileId = UnitId (language :| fileSegments)
    rulesByName = Map.fromList [(unitRuleName r, r) | r <- profileUnits profile]
    (children, decisions) = collect fileId [] tree
    unbound = map treeSpan (unboundWhys tree ++ orphansIn tree)
    orphansIn node = case node of
      TokenNode _ -> []
      Labeled "orphan" inner -> [inner]
      Labeled _ inner -> orphansIn inner
      RuleNode _ _ ns -> concatMap orphansIn ns
    unboundWhys node = case node of
      TokenNode _ -> []
      Labeled _ inner -> unboundWhys inner
      RuleNode _ _ ns
        | isUnitNode node && isJust (labeledText "what" node) -> concatMap unboundWhys (filter (not . isWhy) ns)
        | otherwise -> [inner | Labeled "why" inner <- ns] ++ concatMap unboundWhys ns
    isWhy node = case node of
      Labeled "why" _ -> True
      _ -> False
    root =
      CodeUnit
        { unitId = fileId
        , unitWhat = Answer (What (T.pack path) (UnitKind "file")) evidence
        , unitHow = Answer (HowAt (treeSpan tree)) evidence
        , unitWhere = Answer (Where path (treeSpan tree) [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Optional
        , unitTest = False
        , unitChildren = children
        }
    collect parent chain node = collectAll parent chain [node]
    collectAll parent chain nodes =
      let built = map (build parent chain) (uniqueNames (concatMap found nodes))
       in (map fst built, concatMap snd built)
    childrenOf node = case node of
      RuleNode _ _ ns -> ns
      Labeled _ inner -> [inner]
      TokenNode _ -> []
    found node = case node of
      TokenNode _ -> []
      Labeled _ inner -> found inner
      RuleNode name alternative nodeChildren -> case planFor name alternative of
        Just plan | Just unitName <- labeledText "what" node -> [Candidate (planKind plan) unitName (if planWhyRequired plan || isJust (labeledSubtree "required" node) then Required else Optional) (labeledSubtree "why" node) (labeledSubtree "how" node) node]
        _ -> case Map.lookup name rulesByName of
          Just rule | accepts rule node, Just unitName <- nameOf rule node -> [Candidate (unitRuleKind rule) unitName (if unitRuleRequired rule then Required else Optional) Nothing Nothing node]
          _ -> concatMap found nodeChildren
    planFor name alternative = Map.lookup name plans >>= \alts -> listToMaybe (drop alternative alts) >>= id
    isUnitNode node = case node of
      RuleNode name alternative _ -> isJust (planFor name alternative) || Map.member name rulesByName
      _ -> False
    labeledSubtree wanted node = listToMaybe (labeledSubtrees wanted node)
    labeledSubtrees wanted node = labeledIn node
      where
        labeledIn n = case n of
          Labeled l inner | l == wanted -> [inner]
          Labeled _ inner -> labeledIn inner
          TokenNode _ -> []
          RuleNode _ _ ns -> concatMap (\c -> if isUnitNode c then [] else labeledIn c) ns
    labeledText wanted node = tokensText <$> labeledSubtree wanted node
    tokensText n = T.concat (map tokenText (filter (not . isEofToken) (treeTokens n)))
    uniqueNames candidates = go Map.empty candidates
      where
        go _ [] = []
        go seen (c : rest) =
          let key = (candidateKind c, candidateName c)
              count = Map.findWithDefault (0 :: Int) key seen
              segment = if count == 0 then candidateName c else T.concat [candidateName c, "#", T.pack (show (count + 1))]
           in (c, segment) : go (Map.insert key (count + 1) seen) rest
    build parent chain (c, segment) =
      let uid = UnitId (NonEmpty.fromList (NonEmpty.toList (unitIdSegments parent) ++ [candidateKind c, segment]))
          node = candidateNode c
          sp = treeSpan node
          howSpan = maybe sp treeSpan (candidateHow c)
          (nested, nestedDecisions) = collectAll uid (chain ++ [candidateName c]) (childrenOf node)
          markers = [T.concat (T.words (tokensText m)) | m <- labeledSubtrees "marker" node]
          test = isTestUnit language (candidateKind c) (candidateName c) idPath markers
          own = case candidateWhy c of
            Nothing -> []
            Just whyNode ->
              let whySpan = treeSpan whyNode
               in [ Decision
                      { decisionId = decisionIdFor uid
                      , decisionUnits = uid :| []
                      , decisionWhy = Answer (whyFrom whyNode (slice whySpan)) (Asserted (Assertion path whySpan))
                      , decisionWhere = Where path whySpan chain Nothing
                      , decisionVetting = Nothing
                      }
                  ]
       in ( CodeUnit
              { unitId = uid
              , unitWhat = Answer (What (candidateName c) (UnitKind (candidateKind c))) evidence
              , unitHow = Answer (HowText (slice howSpan)) evidence
              , unitWhere = Answer (Where path sp chain Nothing) evidence
              , unitWho = Nothing
              , unitWhen = Nothing
              , unitRequirement = if test then Required else candidateRequirement c
              , unitTest = test
              , unitChildren = nested
              }
          , own ++ nestedDecisions
          )
    whyFrom whyNode raw =
      Why
        { whyText = docCommentBody raw
        , whyReferences = keys "ref" "ref:" whyNode
        , whyLicenses = keys "license" "license:" whyNode
        }
    keys label prefix n = dedupe [ReferenceKey (maybe t id (T.stripPrefix prefix t)) | t <- labeledTokens label n]
    dedupe = foldr (\k acc -> k : filter (/= k) acc) []
    labeledTokens wanted n = case n of
      Labeled l inner | l == wanted -> [tokensText inner]
      Labeled _ inner -> labeledTokens wanted inner
      TokenNode _ -> []
      RuleNode _ _ ns -> concatMap (labeledTokens wanted) ns
    accepts rule node = case unitRuleFirstToken rule of
      Nothing -> True
      Just (restriction, allowed) -> case [t | t <- treeTokens node, maybe True (== tokenType t) restriction] of
        (t : _) -> tokenText t `elem` allowed
        [] -> False
    nameOf rule node = case unitRuleNameSource rule of
      NameFromToken tokenName index -> tokenText <$> listToMaybe (drop (index - 1) [t | t <- treeTokens node, tokenType t == tokenName])
      NameFromRule ruleName -> listToMaybe (mapMaybe (ruleText ruleName) (directChildrenDeep node))
    ruleText wanted node = case node of
      RuleNode name _ _ | name == wanted -> Just (tokensText node)
      _ -> Nothing
    directChildrenDeep node = case node of
      RuleNode _ _ ns -> ns ++ concatMap directChildrenDeep ns
      Labeled _ inner -> directChildrenDeep inner
      TokenNode _ -> []
    treeSpan node = case filter (not . isEofToken) (treeTokens node) of
      [] -> Span (Position 1 1) (Position 1 1)
      toks -> Span (tokenPosition (head' toks)) (positionAt table (tokenEnd (last toks)))
    head' xs = case xs of
      (x : _) -> x
      [] -> error "empty token list"
    slice sp = T.pack (V.toList (V.slice (offsetOf (spanStart sp)) (offsetOf (spanEnd sp) - offsetOf (spanStart sp)) chars))
    offsetOf position = offsetFromPosition source position

data Candidate = Candidate
  { candidateKind :: Text
  , candidateName :: Text
  , candidateRequirement :: CommentRequirement
  , candidateWhy :: Maybe ParseTree
  , candidateHow :: Maybe ParseTree
  , candidateNode :: ParseTree
  }

offsetFromPosition :: Text -> Position -> Int
offsetFromPosition source (Position line column) =
  let linesBefore = take (line - 1) (T.splitOn "\n" source)
   in sum (map ((+ 1) . T.length) linesBefore) + column - 1

extractDecisionsFor :: FilePath -> Text -> CodeUnit Evidence -> Set.Set DecisionId -> [Located Comment] -> ([Decision Evidence], [Located Comment])
extractDecisionsFor path source root decided comments = (maybe [] (\c -> [toDecision (c, Located (whereSpan (answerValue (unitWhere root))) root)]) header ++ map toDecision pairs, orphans)
  where
    targets = [Located (whereSpan (answerValue (unitWhere u))) u | u <- drop 1 (allUnits root), not (Set.member (decisionIdFor (unitId u)) decided)]
    (header, rest) = if Set.member (decisionIdFor (unitId root)) decided then (Nothing, comments) else topOfFileComment (firstContentLine source) comments
    (pairs, orphans) = attachPreceding rest targets
    toDecision (comment, target) =
      let u = locatedValue target
          sp = locatedSpan comment
       in Decision
            { decisionId = decisionIdFor (unitId u)
            , decisionUnits = unitId u :| []
            , decisionWhy = Answer (toWhy (parseCanonicalComment (commentBody (locatedValue comment)))) (Asserted (Assertion path sp))
            , decisionWhere = Where path sp (whereChain (answerValue (unitWhere u))) Nothing
            , decisionVetting = Nothing
            }

commentBody :: Comment -> Text
commentBody c = T.strip (T.unlines (map stripMarker (T.lines (commentText c))))
  where
    stripMarker line =
      let trimmed = T.stripStart line
       in T.strip (T.dropWhile (\ch -> not (isAlphaNum ch) && ch /= '(' && ch /= '[' && ch /= '\'' && ch /= '"' && ch /= '`' && ch /= '<') trimmed)
