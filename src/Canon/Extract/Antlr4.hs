module Canon.Extract.Antlr4
  ( ExtractError (..)
  , Extraction (..)
  , extractGrammarModel
  , extractGrammarText
  , extractGrammarUnits
  , extractDecisions
  , ruleUnitId
  , modeUnitId
  , grammarUnitId
  , renderExtractError
  ) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Pretty (prettyPrequel, prettyRule)
import Canon.Antlr4.Query (allRules, ruleAnn, ruleName)
import Canon.Antlr4.Read (ReadError, ReadResult (..), readGrammar, renderReadError)
import Canon.Antlr4.Syntax hiding (Optional)
import Canon.Attach (attachPreceding)
import Canon.CanonicalComment (parseCanonicalComment, toWhy)
import Canon.Config (Config (..))
import Canon.Git.Derive (whenFromHistory, whoFromHistory)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Span (spanHull)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

data ExtractError
  = ExtractReadError ReadError
  | ExtractDuplicateUnitIds [UnitId]
  deriving (Eq, Show)

data Extraction = Extraction
  { extractionModel :: Model Evidence
  , extractionFindings :: [Finding]
  }
  deriving (Eq, Show)

languageName :: Text
languageName = "antlr4"

grammarUnitId :: Name -> UnitId
grammarUnitId (Name g) = UnitId ("grammar" :| [g])

modeUnitId :: Name -> Name -> UnitId
modeUnitId (Name g) (Name m) = UnitId ("grammar" :| [g, "mode", m])

ruleUnitId :: Name -> Maybe Name -> Name -> UnitId
ruleUnitId (Name g) mode (Name r) =
  UnitId ("grammar" :| ([g] ++ maybe [] (\(Name m) -> ["mode", m]) mode ++ ["rule", r]))

data Target = Target
  { targetUnitId :: UnitId
  , targetChain :: [Text]
  }

extractGrammarModel :: GitProvider -> Config -> FilePath -> IO (Either ExtractError Extraction)
extractGrammarModel provider config path = TIO.readFile path >>= extractGrammarText provider config path

extractGrammarText :: GitProvider -> Config -> FilePath -> Text -> IO (Either ExtractError Extraction)
extractGrammarText provider config path source =
  case readGrammar path source of
    Left err -> pure (Left (ExtractReadError err))
    Right (ReadResult grammar comments) -> case extractGrammarUnits path grammar of
      Left err -> pure (Left err)
      Right root -> do
        let (decisions, orphans) = extractDecisions path grammar comments
        rootHistory <- historyOf provider path (whereSpan (answerValue (unitWhere root)))
        (unitsWithGit, gitFindings) <- case rootHistory of
          Left err -> pure (root, [GitUnavailable path err])
          Right _ -> (\u -> (u, [])) <$> fillGit provider path root
        described <- either (const Nothing) id <$> describeVersion provider
        let model = Model languageName (configVersion config) described [unitsWithGit] decisions
            findings = [OrphanDocComment path (locatedSpan c) | c <- orphans] ++ gitFindings
        pure (Right (Extraction model findings))

extractGrammarUnits :: FilePath -> Grammar Span -> Either ExtractError (CodeUnit Evidence)
extractGrammarUnits path grammar =
  case [i | i@(_ : _ : _) <- group (sort (map unitId (allUnits root)))] of
    [] -> Right root
    duplicates -> Left (ExtractDuplicateUnitIds (map NonEmpty.head (map NonEmpty.fromList duplicates)))
  where
    g = grammarName grammar
    evidence = DerivedFromParse path
    indexed = zip [0 ..] (allRules grammar)
    indexOf r = listToMaybe [i | (i, r') <- indexed, ruleAnn r' == ruleAnn r, ruleName r' == ruleName r]
    root =
      CodeUnit
        { unitId = grammarUnitId g
        , unitWhat = Answer (What (nameText g) (UnitKind "grammar")) evidence
        , unitHow = Answer (HowText (T.intercalate "\n\n" (map prettyPrequel (grammarPrequel grammar)))) evidence
        , unitWhere = Answer (Where path rootSpan [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Optional
        , unitChildren = map (ruleUnit Nothing) (grammarRules grammar) ++ map modeUnit (grammarModes grammar)
        }
    rootSpan = case NonEmpty.nonEmpty (map ruleAnn (grammarRules grammar) ++ map modeAnn (grammarModes grammar)) of
      Just spans -> spanHull spans
      Nothing -> Span (Position 1 1) (Position 1 1)
    modeUnit m =
      CodeUnit
        { unitId = modeUnitId g (modeName m)
        , unitWhat = Answer (What (nameText (modeName m)) (UnitKind "mode")) evidence
        , unitHow = Answer (HowAt (modeAnn m)) evidence
        , unitWhere = Answer (Where path (modeAnn m) [nameText g] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Optional
        , unitChildren = map (ruleUnit (Just (modeName m)) . RuleLexer) (modeRules m)
        }
    ruleUnit mode r =
      CodeUnit
        { unitId = ruleUnitId g mode (ruleName r)
        , unitWhat = Answer (What (nameText (ruleName r)) (ruleKind r)) evidence
        , unitHow = Answer (HowText (prettyRule r)) evidence
        , unitWhere = Answer (Where path (ruleAnn r) (nameText g : maybe [] (\m -> [nameText m]) mode) (indexOf r)) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = ruleRequirement r
        , unitChildren = []
        }
    ruleKind r = UnitKind $ case r of
      RuleParser _ -> "parserRule"
      RuleLexer l | lexerRuleIsFragment l -> "fragmentRule"
      RuleLexer _ -> "lexerRule"
    ruleRequirement r = case r of
      RuleLexer l | lexerRuleIsFragment l -> Optional
      _ -> Required

extractDecisions :: FilePath -> Grammar Span -> [Located Comment] -> ([Decision Evidence], [Located Comment])
extractDecisions path grammar comments = (map toDecision pairs, orphans)
  where
    g = grammarName grammar
    docComments = [c | c <- comments, commentKind (locatedValue c) == DocComment]
    targets =
      [Located (ruleAnn r) (Target (ruleUnitId g Nothing (ruleName r)) [nameText g]) | r <- grammarRules grammar]
        ++ [ Located (lexerRuleAnn l) (Target (ruleUnitId g (Just (modeName m)) (lexerRuleName l)) [nameText g, nameText (modeName m)])
           | m <- grammarModes grammar
           , l <- modeRules m
           ]
    (pairs, orphans) = attachPreceding docComments targets
    toDecision (comment, target) =
      let uid = targetUnitId (locatedValue target)
          sp = locatedSpan comment
       in Decision
            { decisionId = decisionIdFor uid
            , decisionUnits = uid :| []
            , decisionWhy = Answer (toWhy (parseCanonicalComment (commentText (locatedValue comment)))) (Asserted (Assertion path sp))
            , decisionWhere = Where path sp (targetChain (locatedValue target)) Nothing
            }

fillGit :: GitProvider -> FilePath -> CodeUnit Evidence -> IO (CodeUnit Evidence)
fillGit provider path unit = do
  history <- historyOf provider path (whereSpan (answerValue (unitWhere unit)))
  (who, when) <- case history of
    Right commits@(_ : _) -> do
      tags <- case whenFromHistory Nothing commits of
        Just w -> either (const []) id <$> tagsContaining provider (changeCommit (whenFirst w))
        Nothing -> pure []
      let evidence = DerivedFromGit GitLog
      pure
        ( (`Answer` evidence) <$> whoFromHistory commits
        , (`Answer` evidence) <$> whenFromHistory (listToMaybe tags) commits
        )
    _ -> pure (Nothing, Nothing)
  children <- mapM (fillGit provider path) (unitChildren unit)
  pure unit {unitWho = who, unitWhen = when, unitChildren = children}

renderExtractError :: ExtractError -> Text
renderExtractError e = case e of
  ExtractReadError err -> renderReadError err
  ExtractDuplicateUnitIds ids -> "duplicate unit ids: " <> T.intercalate ", " (map renderUnitId ids)
