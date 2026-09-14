module Canon.Extract.Grammar
  ( GrammarExtractError (..)
  , loadProfileInterpreter
  , extractWithProfile
  , extractWithProfileText
  , renderGrammarExtractError
  , unitsFromTree
  ) where

import Canon.Antlr4.Comment (Comment (..))
import Canon.Antlr4.Interpret
import Canon.Antlr4.Lexical (lineTable, positionAt)
import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.Attach (attachPreceding)
import Canon.CanonicalComment (parseCanonicalComment, toWhy)
import Canon.CommentScan (scanCommentsWith)
import Canon.Config (Config (..))
import Canon.Extract.Antlr4 (Extraction (..))
import Canon.Git.Derive (whenFromHistory, whoFromHistory)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Profile
import Canon.Span (Located (..), Position (..), Span (..))
import Data.Char (isAlphaNum)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Vector.Unboxed as V
import System.FilePath (splitDirectories)

data GrammarExtractError
  = GrammarInterpretError InterpretError
  | GrammarDuplicateUnitIds [UnitId]
  deriving (Eq, Show)

renderGrammarExtractError :: GrammarExtractError -> Text
renderGrammarExtractError e = case e of
  GrammarInterpretError err -> renderInterpretError err
  GrammarDuplicateUnitIds ids -> "duplicate unit ids: " <> T.intercalate ", " (map renderUnitId ids)

loadProfileInterpreter :: Profile -> IO (Either InterpretError Interpreter)
loadProfileInterpreter profile = case profileGrammar profile of
  CombinedGrammarFile path -> loadCombinedInterpreter path
  SplitGrammarFiles lexer parser -> loadInterpreter lexer parser

extractWithProfile :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> IO (Either GrammarExtractError Extraction)
extractWithProfile provider config language profile interpreter path =
  TIO.readFile path >>= extractWithProfileText provider config language profile interpreter path

extractWithProfileText :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> Text -> IO (Either GrammarExtractError Extraction)
extractWithProfileText provider config language profile interpreter path source =
  case interpretText interpreter (profileStart profile) path source of
    Left err -> pure (Left (GrammarInterpretError err))
    Right tree -> case unitsFromTree language profile path source tree of
      Left err -> pure (Left err)
      Right root -> do
        let comments = scanCommentsWith (profileComments profile) source
            (decisions, orphans) = extractDecisionsFor path root comments
        rootHistory <- historyOf provider path (whereSpan (answerValue (unitWhere root)))
        (unitsWithGit, gitFindings) <- case rootHistory of
          Left err -> pure (root, [GitUnavailable path err])
          Right _ -> (\u -> (u, [])) <$> fillGit provider path root
        described <- either (const Nothing) id <$> describeVersion provider
        let model = Model language (configVersion config) described [unitsWithGit] decisions
        pure (Right (Extraction model ([OrphanDocComment path (locatedSpan c) | c <- orphans] ++ gitFindings)))

unitsFromTree :: Text -> Profile -> FilePath -> Text -> ParseTree -> Either GrammarExtractError (CodeUnit Evidence)
unitsFromTree language profile path source tree =
  case [i | i@(_ : _ : _) <- group (sort (map unitId (allUnits root)))] of
    [] -> Right root
    duplicates -> Left (GrammarDuplicateUnitIds (map NonEmpty.head (map NonEmpty.fromList duplicates)))
  where
    evidence = DerivedFromParse path
    chars = V.fromList (T.unpack source)
    table = lineTable source
    fileSegments = map T.pack (splitDirectories path)
    fileId = UnitId (language :| fileSegments)
    rulesByName = Map.fromList [(unitRuleName r, r) | r <- profileUnits profile]
    root =
      CodeUnit
        { unitId = fileId
        , unitWhat = Answer (What (T.pack path) (UnitKind "file")) evidence
        , unitHow = Answer (HowAt (treeSpan tree)) evidence
        , unitWhere = Answer (Where path (treeSpan tree) [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Optional
        , unitChildren = collect fileId [] tree
        }
    collect parent chain node = map (build parent chain) (uniqueNames (found node))
    found node = case node of
      TokenNode _ -> []
      RuleNode name _ children -> case Map.lookup name rulesByName of
        Just rule | accepts rule node, Just unitName <- nameOf rule node -> [(rule, unitName, node)]
        _ -> concatMap found children
    uniqueNames candidates = go Map.empty candidates
      where
        go _ [] = []
        go seen ((rule, unitName, node) : rest) =
          let key = (unitRuleKind rule, unitName)
              count = Map.findWithDefault (0 :: Int) key seen
              segment = if count == 0 then unitName else T.concat [unitName, "#", T.pack (show (count + 1))]
           in (rule, unitName, segment, node) : go (Map.insert key (count + 1) seen) rest
    build parent chain (rule, unitName, segment, node) =
      let uid = UnitId (NonEmpty.fromList (NonEmpty.toList (unitIdSegments parent) ++ [unitRuleKind rule, segment]))
          sp = treeSpan node
          nested = concatMap (collect uid (chain ++ [unitName])) (childrenOf node)
       in CodeUnit
            { unitId = uid
            , unitWhat = Answer (What unitName (UnitKind (unitRuleKind rule))) evidence
            , unitHow = Answer (HowText (slice sp)) evidence
            , unitWhere = Answer (Where path sp chain Nothing) evidence
            , unitWho = Nothing
            , unitWhen = Nothing
            , unitRequirement = if unitRuleRequired rule then Required else Optional
            , unitChildren = nested
            }
    childrenOf node = case node of
      RuleNode _ _ children -> children
      TokenNode _ -> []
    accepts rule node = case unitRuleFirstToken rule of
      Nothing -> True
      Just (restriction, allowed) -> case [t | t <- treeTokens node, maybe True (== tokenType t) restriction] of
        (t : _) -> tokenText t `elem` allowed
        [] -> False
    nameOf rule node = case unitRuleNameSource rule of
      NameFromToken tokenName index -> tokenText <$> listToMaybe (drop (index - 1) [t | t <- treeTokens node, tokenType t == tokenName])
      NameFromRule ruleName -> listToMaybe (mapMaybe (ruleText ruleName) (directChildrenDeep node))
    ruleText wanted node = case node of
      RuleNode name _ _ | name == wanted -> Just (T.concat (map tokenText (treeTokens node)))
      _ -> Nothing
    directChildrenDeep node = case node of
      RuleNode _ _ children -> children ++ concatMap directChildrenDeep children
      TokenNode _ -> []
    treeSpan node = case filter (not . isEofToken) (treeTokens node) of
      [] -> Span (Position 1 1) (Position 1 1)
      toks -> Span (tokenPosition (head' toks)) (positionAt table (tokenEnd (last toks)))
    head' xs = case xs of
      (x : _) -> x
      [] -> error "empty token list"
    slice sp = T.pack (V.toList (V.slice (offsetOf (spanStart sp)) (offsetOf (spanEnd sp) - offsetOf (spanStart sp)) chars))
    offsetOf position = offsetFromPosition source position

offsetFromPosition :: Text -> Position -> Int
offsetFromPosition source (Position line column) =
  let linesBefore = take (line - 1) (T.splitOn "\n" source)
   in sum (map ((+ 1) . T.length) linesBefore) + column - 1

extractDecisionsFor :: FilePath -> CodeUnit Evidence -> [Located Comment] -> ([Decision Evidence], [Located Comment])
extractDecisionsFor path root comments = (map toDecision pairs, orphans)
  where
    targets = [Located (whereSpan (answerValue (unitWhere u))) u | u <- drop 1 (allUnits root)]
    (pairs, orphans) = attachPreceding comments targets
    toDecision (comment, target) =
      let u = locatedValue target
          sp = locatedSpan comment
       in Decision
            { decisionId = decisionIdFor (unitId u)
            , decisionUnits = unitId u :| []
            , decisionWhy = Answer (toWhy (parseCanonicalComment (commentBody (locatedValue comment)))) (Asserted (Assertion path sp))
            , decisionWhere = Where path sp (whereChain (answerValue (unitWhere u))) Nothing
            }

commentBody :: Comment -> Text
commentBody c = T.strip (T.unlines (map stripMarker (T.lines (commentText c))))
  where
    stripMarker line =
      let trimmed = T.stripStart line
       in T.strip (T.dropWhile (\ch -> not (isAlphaNum ch) && ch /= '(' && ch /= '[' && ch /= '\'' && ch /= '"' && ch /= '`' && ch /= '<') trimmed)

fillGit :: GitProvider -> FilePath -> CodeUnit Evidence -> IO (CodeUnit Evidence)
fillGit provider path unit = do
  history <- historyOf provider path (whereSpan (answerValue (unitWhere unit)))
  (who, when) <- case history of
    Right commits@(_ : _) -> do
      tags <- case whenFromHistory Nothing commits of
        Just w -> either (const []) id <$> tagsContaining provider (changeCommit (whenFirst w))
        Nothing -> pure []
      let evidence = DerivedFromGit GitLog
      pure ((`Answer` evidence) <$> whoFromHistory commits, (`Answer` evidence) <$> whenFromHistory (listToMaybe tags) commits)
    _ -> pure (Nothing, Nothing)
  children <- mapM (fillGit provider path) (unitChildren unit)
  pure unit {unitWho = who, unitWhen = when, unitChildren = children}
