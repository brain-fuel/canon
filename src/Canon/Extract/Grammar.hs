-- | Extraction reads units and decisions out of a parse tree by the labels the canonically commented
-- grammar carries, so nothing about a language's comment placement is written here.
-- ref:DEC-grammar-carries-extraction-rules ref:DEC-marker-label ref:DEC-export-rule
module Canon.Extract.Grammar
  ( GrammarExtractError (..)
  , Extraction (..)
  , AlternativePlan (..)
  , loadProfileInterpreter
  , extractWithProfile
  , extractWithProfileText
  , renderGrammarExtractError
  , alternativePlans
  , exportLabelsDeclared
  , ExportEntry (..)
  , parseExportEntry
  , exportRequires
  , unitsFromTree
  ) where

import Canon.Antlr4.Comment (Comment (..))
import Canon.Antlr4.Interpret
import Canon.Antlr4.Lexical (lineTable, positionAt)
import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Syntax (Alternative (..), Block (..), EbnfSuffix (..), Element (..), Grammar (..), Label (..), LabeledAlternative (..), Name (..), ParserRule (..), Quantifier (OneOrMore), Rule (..))
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.Attach (attachPreceding, firstContentLine, topOfFileComment)
import Canon.CanonicalComment (dialectCommentBody, parseCanonicalComment, toWhy)
import Canon.CommentScan (docAttributeBody, docOpenerOf, scanCommentsWith)
import Canon.Config (Config (..))
import Canon.Git.Fill (fillGitFromBlame)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Preprocessor (inactiveLines)
import Canon.Profile
import Canon.Span (Located (..), Position (..), Span (..))
import Canon.Testing (isTestUnit)
import Data.Char (isAlphaNum, isSpace)
import Data.Foldable (toList)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing, listToMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Vector as BV
import qualified Data.Vector.Unboxed as V
import System.FilePath (splitDirectories)

-- | Extraction fails when the interpreter fails or when two units share an id.
data GrammarExtractError
  = GrammarInterpretError InterpretError
  | GrammarDuplicateUnitIds [UnitId]
  deriving (Eq, Show)

-- | A model with the findings produced while building it.
data Extraction = Extraction
  { extractionModel :: Model Evidence
  , extractionFindings :: [Finding]
  }
  deriving (Eq, Show)

-- | What a labeled alternative says about its units: the kind and whether the comment is mandatory.
data AlternativePlan = AlternativePlan
  { planKind :: Text
  , planWhyRequired :: Bool
  }
  deriving (Eq, Show)

-- | Renders an extraction error.
renderGrammarExtractError :: GrammarExtractError -> Text
renderGrammarExtractError e = case e of
  GrammarInterpretError err -> renderInterpretError err
  GrammarDuplicateUnitIds ids -> "duplicate unit ids: " <> T.intercalate ", " (map renderUnitId ids)

-- | Loads the interpreter a profile names.
loadProfileInterpreter :: Profile -> IO (Either InterpretError Interpreter)
loadProfileInterpreter profile = case profileGrammar profile of
  CombinedGrammarFile path -> loadCombinedInterpreter path
  SplitGrammarFiles lexer parser -> loadInterpreter lexer parser

-- | Extracts a file through a profile.
extractWithProfile :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> FilePath -> IO (Either GrammarExtractError Extraction)
extractWithProfile provider config language profile interpreter idPath path =
  TIO.readFile path >>= extractWithProfileText provider config language profile interpreter idPath path

-- | Extracts text through a profile, with the id path separate from the display path so ids are
-- project-relative.
extractWithProfileText :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> FilePath -> Text -> IO (Either GrammarExtractError Extraction)
extractWithProfileText provider config language profile interpreter idPath path source =
  case interpretText interpreter (profileStart profile) path source of
    Left err -> pure (Left (GrammarInterpretError err))
    Right tree -> case unitsFromTree language profile (alternativePlans (interpreterParser interpreter)) (exportLabelsDeclared (interpreterParser interpreter)) idPath path source tree of
      Left err -> pure (Left err)
      Right (root, labeled, unbound, hiddenOwn) -> do
        let comments = scanCommentsWith (profileComments profile) source
            (attached, orphans) = extractDecisionsFor (profileComments profile) path source root (Set.fromList (map decisionId labeled)) hiddenOwn comments
            tagged = Set.fromList [u | d <- attached, hasHiddenTag (profileComments profile) (whyText (answerValue (decisionWhy d))), u <- toList (decisionUnits d)]
            root' = hideTagged tagged False root
        (unitsWithGit, gitFindings) <- fillGitFromBlame provider path root'
        described <- either (const Nothing) id <$> describeVersion provider
        let model = Model language (configVersion config) described [unitsWithGit] (labeled ++ attached)
        pure (Right (Extraction model (map (OrphanDocComment path) unbound ++ [OrphanDocComment path (locatedSpan c) | c <- orphans] ++ gitFindings)))

-- | Whether a comment's prose holds one of the syntax's hidden tags as a word, as EDoc's @private.
-- ref:DEC-hidden-label
hasHiddenTag :: CommentSyntax -> Text -> Bool
hasHiddenTag syntax body = any (`elem` map (T.dropWhileEnd (not . isAlphaNum)) (T.words body)) (commentHiddenTags syntax)

-- | Marks hidden the units a hidden tag documents, and the units inside them, unless they are tests.
hideTagged :: Set.Set UnitId -> Bool -> CodeUnit ev -> CodeUnit ev
hideTagged tagged above u =
  let hidden = above || Set.member (unitId u) tagged
   in u
        { unitRequirement = if hidden && not (unitTest u) then Hidden else unitRequirement u
        , unitChildren = map (hideTagged tagged hidden) (unitChildren u)
        }

-- | Reads the unit alternatives out of the parser grammar: a labeled alternative with a why element.
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

-- | Tells whether a grammar labels export entries, which opts a language into the export rule.
-- ref:DEC-export-rule
exportLabelsDeclared :: Grammar Span -> Bool
exportLabelsDeclared grammar = any labeled (concatMap elementsOf [r | RuleParser r <- grammarRules grammar])
  where
    elementsOf r = concatMap (alternativeElements . labeledAlternativeBody) (toList (parserRuleAlternatives r))
    labeled e = case e of
      ElementAtom _ (Just (Label (Name "export") _)) _ _ -> True
      ElementBlock _ (Just (Label (Name "export") _)) _ _ -> True
      ElementBlock _ _ block _ -> any labeled (concatMap alternativeElements (toList (blockAlternatives block)))
      _ -> False

-- | The forms an export entry takes: a name, all members, some members, or a module.
data ExportEntry
  = ExportName Text
  | ExportAll Text
  | ExportSome Text [Text]
  | ExportModule Text
  deriving (Eq, Show)

-- | Parses an export entry from its text.
parseExportEntry :: Text -> ExportEntry
parseExportEntry raw
  | Just m <- T.stripPrefix "module" compact, not (T.null m) = ExportModule m
  | Just (name, rest) <- splitParen compact = if rest == ".." then ExportAll name else ExportSome name (filter (not . T.null) (T.splitOn "," rest))
  | otherwise = ExportName compact
  where
    compact = T.concat (T.words raw)
    splitParen t = case T.breakOn "(" t of
      (name, inner) | not (T.null name), not (T.null inner), Just body <- T.stripSuffix ")" (T.drop 1 inner) -> Just (name, body)
      _ -> Nothing

-- | Decides whether the export rule requires a comment on a unit. ref:DEC-export-rule
exportRequires :: Maybe [ExportEntry] -> Maybe Text -> Text -> Bool
exportRequires exports parent name = case exports of
  Nothing -> plainName name
  Just entries -> any matches entries
  where
    matches entry = case entry of
      ExportName n -> n == name
      ExportAll n -> n == name || Just n == parent
      ExportSome n members -> n == name || (Just n == parent && name `elem` members)
      ExportModule _ -> False
    plainName n = not (T.null n) && not (T.any isSpace n)

-- | Builds the unit tree, its decisions, and the orphan spans from a parse tree. A unit a profile
-- names is required when its node holds an element the grammar labels required, as the C# grammar
-- labels public and protected, or when its rule says so and its node holds no element labeled
-- optional, as the F# grammar labels private and internal. ref:DEC-csharp-grammar
-- ref:DEC-fsharp-grammar Adjacent clauses of a unit rule that merges them are one unit, unless a
-- doc comment ends on the line above a later clause, which then starts a unit of its own, as the
-- @doc of another Elixir arity does. ref:DEC-elixir-grammar In a dialect, a unit whose node holds an
-- element labeled merge merges so with the adjacent units of its rule, kind, and name, unless a later
-- one has a Why of its own. A later clause marked hidden starts a unit of its own too.
-- ref:DEC-elixir-dialect
--
-- A unit whose node holds an element labeled hidden is hidden, as Elixir's @doc false, Erlang's
-- -doc false, and Gleam's @internal mark it, and so is every unit inside it, as @moduledoc false
-- hides a module's functions; a hidden mark outside every unit hides the file. A hidden unit
-- requires no comment, whatever its rule or a required element says, unless it is a test. The ids of
-- the units marked hidden themselves come back too, so a doc comment above one is an orphan.
-- ref:DEC-hidden-label
--
-- A unit whose node holds an element labeled arity, a bracketed list of arguments, is named by its
-- name, a slash, and the number of arguments, as Erlang names a function info/2. ref:DEC-erlang-grammar
--
-- Elements labeled file, outside every unit, are the Why of the file, joined in order, as Gleam joins
-- every //// comment of a module into its documentation. ref:DEC-gleam-dialect
--
-- The first why element in a unit's node, outside the units nested in it, is the unit's Why wherever
-- the grammar puts it, as the @moduledoc of an Elixir module sits among its statements; any other why
-- element binds to nothing and is reported. ref:DEC-elixir-dialect
unitsFromTree :: Text -> Profile -> Map.Map Name [Maybe AlternativePlan] -> Bool -> FilePath -> FilePath -> Text -> ParseTree -> Either GrammarExtractError (CodeUnit Evidence, [Decision Evidence], [Span], Set.Set UnitId)
unitsFromTree language profile plans exportsDeclared idPath path source tree =
  case [i | i@(_ : _ : _) <- group (sort (map unitId (allUnits root)))] of
    [] -> Right (root, fileDecision ++ decisions, unbound, hiddenOwn)
    duplicates -> Left (GrammarDuplicateUnitIds (map NonEmpty.head (map NonEmpty.fromList duplicates)))
  where
    evidence = DerivedFromParse path
    chars = V.fromList (T.unpack source)
    table = lineTable source
    fileSegments = [T.pack d | d <- splitDirectories idPath, d /= "."]
    fileId = UnitId (language :| fileSegments)
    rulesByName = Map.fromListWith (flip (++)) [(unitRuleName r, [r]) | r <- profileUnits profile]
    syntax = profileComments profile
    docEndLines =
      Set.fromList
        [ positionLine (spanEnd (locatedSpan c))
        | c <- scanCommentsWith syntax source
        , let opener = docOpenerOf syntax (commentText (locatedValue c))
        , not (maybe False (`elem` commentInnerDoc syntax) opener)
        , null (commentOuterDoc syntax) || maybe False (`elem` commentOuterDoc syntax) opener
        ]
    mergeClauses candidates = case candidates of
      (a : b : rest)
        | Just key <- candidateMerge a
        , candidateMerge b == Just key
        , candidateName a == candidateName b
        , not (Set.member (positionLine (spanStart (treeSpan (candidateNode b))) - 1) docEndLines)
        , isNothing (candidateWhy b)
        , candidateRequirement b /= Hidden ->
            mergeClauses (a {candidateClauses = candidateClauses a ++ candidateNode b : candidateClauses b} : rest)
      (a : rest) -> a : mergeClauses rest
      [] -> []
    fileHidden = not (isUnitNode tree) && isJust (labeledSubtree "hidden" tree)
    (children, decisions, hiddenOwn) = collect fileHidden fileId [] tree
    fileWhys = labeledSubtrees "file" tree
    fileDecision = case fileWhys of
      [] -> []
      (first : _) ->
        let whySpan = treeSpan first
            whys = [whyFrom n (slice (treeSpan n)) | n <- fileWhys]
         in [ Decision
                { decisionId = decisionIdFor fileId
                , decisionUnits = fileId :| []
                , decisionWhy = Answer (Why (T.intercalate "\n\n" (map whyText whys)) (dedupe (concatMap whyReferences whys)) (dedupe (concatMap whyLicenses whys))) (Asserted (Assertion path whySpan))
                , decisionWhere = Where path whySpan [] Nothing
                , decisionVetting = Nothing
                }
            ]
    exportEntries = if exportsDeclared then Just (map (parseExportEntry . tokensText) (exportedIn tree)) else Nothing
    exportedIn node = case node of
      TokenNode _ -> []
      Labeled "export" inner -> [inner]
      Labeled _ inner -> exportedIn inner
      RuleNode _ _ ns -> concatMap exportedIn ns
    fileExports = case exportEntries of
      Just entries | not (null entries) -> Just (Just entries)
      Just _ -> Just Nothing
      Nothing -> Nothing
    unbound = map treeSpan (unboundWhys tree ++ orphansIn tree)
    orphansIn node = case node of
      TokenNode _ -> []
      Labeled "orphan" inner -> [inner]
      Labeled _ inner -> orphansIn inner
      RuleNode _ _ ns -> concatMap orphansIn ns
    unboundWhys node =
      let (whys, units) = whysAndUnits node
       in (if isNamedUnit node then drop 1 whys else whys) ++ concatMap unboundWhys units
    whysAndUnits node = case node of
      TokenNode _ -> ([], [])
      Labeled "why" inner -> ([inner], [])
      Labeled _ inner -> whysAndUnits inner
      RuleNode _ _ ns ->
        let parts = [if isNamedUnit c then ([], [c]) else whysAndUnits c | c <- ns]
         in (concatMap fst parts, concatMap snd parts)
    isNamedUnit node = isUnitNode node && isJust (labeledText "what" node)
    root =
      CodeUnit
        { unitId = fileId
        , unitWhat = Answer (What (T.pack path) (UnitKind "file")) evidence
        , unitHow = Answer (HowAt (treeSpan tree)) evidence
        , unitWhere = Answer (Where path (treeSpan tree) [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = if fileHidden then Hidden else Optional
        , unitTest = False
        , unitChildren = children
        }
    collect hiddenAbove parent chain node = collectAll hiddenAbove parent chain [node]
    collectAll hiddenAbove parent chain nodes =
      let built = map (build hiddenAbove parent chain) (uniqueNames (mergeClauses (concatMap found nodes)))
       in ([u | (u, _, _) <- built], concat [d | (_, d, _) <- built], Set.unions [h | (_, _, h) <- built])
    exported chain name = case fileExports of
      Nothing -> False
      Just entries -> exportRequires entries (parentName chain) name
    parentName chain = case reverse chain of
      (p : _) -> Just p
      [] -> Nothing
    childrenOf node = case node of
      RuleNode _ _ ns -> ns
      Labeled _ inner -> [inner]
      TokenNode _ -> []
    found node = case node of
      TokenNode _ -> []
      Labeled _ inner -> found inner
      RuleNode name alternative nodeChildren -> case planFor name alternative of
        Just plan | Just unitName <- labeledText "what" node -> [Candidate (planKind plan) (withArity node unitName) (hiddenOr node (if planWhyRequired plan || isJust (labeledSubtree "required" node) then Required else Optional)) (labeledSubtree "why" node) (labeledSubtree "how" node) node (if isJust (labeledSubtree "merge" node) then Just (nameText name <> "/" <> planKind plan) else Nothing) []]
        _ -> case [(rule, unitName) | rule <- Map.findWithDefault [] name rulesByName, accepts rule node, Just unitName <- [nameOf rule node]] of
          ((rule, unitName) : _) -> [Candidate (unitRuleKind rule) (withArity node unitName) (hiddenOr node (if (unitRuleRequired rule && not (isJust (labeledSubtree "optional" node))) || isJust (labeledSubtree "required" node) then Required else Optional)) Nothing Nothing node (if unitRuleMergeClauses rule then Just (nameText (unitRuleName rule)) else Nothing) []]
          [] -> concatMap found nodeChildren
    withArity node unitName = case labeledSubtree "arity" node of
      Just arguments -> T.concat [unitName, "/", T.pack (show (arityOf arguments))]
      Nothing -> unitName
    arityOf arguments =
      let inner = drop 1 (filter (not . isEofToken) (treeTokens arguments))
          body = take (length inner - 1) inner
          depthAt = scanl (\d t -> d + bracketDelta (tokenText t)) (0 :: Int) body
       in if null body then (0 :: Int) else 1 + length [() | (t, d) <- zip body depthAt, d == 0, tokenText t == ","]
    bracketDelta t
      | t `elem` ["(", "[", "{", "<<"] = 1
      | t `elem` [")", "]", "}", ">>"] = -1
      | otherwise = 0 :: Int
    hiddenOr node requirement = if isJust (labeledSubtree "hidden" node) then Hidden else requirement
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
    build hiddenAbove parent chain (c, segment) =
      let uid = UnitId (NonEmpty.fromList (NonEmpty.toList (unitIdSegments parent) ++ [candidateKind c, segment]))
          node = candidateNode c
          clauses = node : candidateClauses c
          sp = Span (spanStart (treeSpan node)) (spanEnd (treeSpan (last clauses)))
          howSpan = maybe sp treeSpan (candidateHow c)
          hiddenSelf = candidateRequirement c == Hidden
          hidden = hiddenSelf || hiddenAbove
          (nested, nestedDecisions, nestedHidden) = collectAll hidden uid (chain ++ [candidateName c]) (concatMap childrenOf clauses)
          markers = [T.concat (T.words (tokensText m)) | clause <- clauses, m <- labeledSubtrees "marker" clause]
          test = isTestUnit language (candidateKind c) (candidateName c) idPath markers
          required = candidateRequirement c == Required || exported chain (candidateName c)
          requirement
            | test = Required
            | hidden = Hidden
            | required = Required
            | otherwise = Optional
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
              , unitRequirement = requirement
              , unitTest = test
              , unitChildren = nested
              }
          , own ++ nestedDecisions
          , if hiddenSelf then Set.insert uid nestedHidden else nestedHidden
          )
    whyFrom whyNode raw =
      Why
        { whyText = dialectCommentBody raw
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
  , candidateMerge :: Maybe Text
  , candidateClauses :: [ParseTree]
  }

offsetFromPosition :: Text -> Position -> Int
offsetFromPosition source (Position line column) =
  let linesBefore = take (line - 1) (T.splitOn "\n" source)
   in sum (map ((+ 1) . T.length) linesBefore) + column - 1

-- | Binds comments to units. A doc comment with an inner opener belongs to the innermost unit that
-- encloses it, or to the file, and the file's first one is the file's comment ahead of a comment on
-- the first line; every other comment binds to the unit directly below it. Where the syntax names
-- outer openers, a plain comment binds to nothing and is no orphan, since it is not documentation,
-- and an outer doc comment on the first line documents the item below it rather than the file, as
-- Gleam's /// above a module's first function does. A unit is taken to start above the lines
-- directly over it that hold nothing a reader of the documentation sees: directive lines, lines of
-- an #if branch that canon does not read, and, where outer openers are named, lines held by a plain
-- comment that starts its line. So a C# #if, an F# note, or a # line between an Elixir @doc and the
-- @spec below it does not part a doc comment from its unit, as no compiler lets it. Where the
-- syntax names directives, a comment in a branch canon does not read binds to nothing and is no
-- orphan, because the code it documents is not read either. ref:DEC-rust-grammar
-- ref:DEC-comment-attachment ref:DEC-csharp-grammar ref:DEC-fsharp-grammar ref:DEC-gleam-grammar
-- ref:DEC-elixir-grammar
--
-- Documentation written as code binds as its compiler binds it: blank lines between a doc attribute
-- and the unit below it do not part them, as Elixir's @doc and Erlang's -doc bind to the next
-- definition across them. A doc comment directly above a unit marked hidden binds to nothing and is
-- an orphan, because the mark overrides it, as a later @doc false overrides an earlier @doc.
-- ref:DEC-hidden-label
extractDecisionsFor :: CommentSyntax -> FilePath -> Text -> CodeUnit Evidence -> Set.Set DecisionId -> Set.Set UnitId -> [Located Comment] -> ([Decision Evidence], [Located Comment])
extractDecisionsFor syntax path source root decided hiddenOwn scanned = (map toDecision (fileInner ++ maybe [] (\c -> [(c, rootTarget)]) header ++ pairs ++ nestedInner), orphans ++ innerOrphans)
  where
    rootTarget = Located (whereSpan (answerValue (unitWhere root))) root
    unread = if null (commentDirectives syntax) then Set.empty else inactiveLines source
    comments = [c | c <- scanned, not (Set.member (positionLine (spanStart (locatedSpan c))) unread)]
    isInner c = maybe False (`elem` commentInnerDoc syntax) (docOpenerOf syntax (commentText (locatedValue c)))
    isOuter c = null (commentOuterDoc syntax) || maybe False (`elem` commentOuterDoc syntax) (docOpenerOf syntax (commentText (locatedValue c)))
    (inner, plain) = (filter isInner comments, filter (not . isInner) comments)
    rootDecided = Set.member (decisionIdFor (unitId root)) decided
    nested = [Located (whereSpan (answerValue (unitWhere u))) u | u <- drop 1 (allUnits root)]
    enclosing c = case [t | t <- nested, spanStart (locatedSpan t) <= spanStart (locatedSpan c), spanEnd (locatedSpan c) <= spanEnd (locatedSpan t)] of
      [] -> rootTarget
      found -> last found
    innerByUnit = Map.fromListWith (flip (++)) [(unitId (locatedValue t), [(c, t)]) | (c, t) <- zip inner (map enclosing inner)]
    (fileInner, rootInnerOrphans) = case Map.lookup (unitId root) innerByUnit of
      Just ((first, t) : more) | not rootDecided -> ([(first, t)], map fst more)
      Just found -> ([], map fst found)
      Nothing -> ([], [])
    outerProper c = not (null (commentOuterDoc syntax)) && maybe False (`elem` commentOuterDoc syntax) (docOpenerOf syntax (commentText (locatedValue c)))
    (header, rest)
      | rootDecided || not (null fileInner) = (Nothing, plain)
      | otherwise =
          let (found, others) = topOfFileComment (firstContentLine source) (filter (not . outerProper) plain)
           in (found, others ++ filter outerProper plain)
    targets = [overTransparent t | t <- nested, not (Set.member (decisionIdFor (unitId (locatedValue t))) decided), not (Set.member (unitId (locatedValue t)) hiddenOwn)]
    sourceLines = BV.fromList (T.lines source)
    startsItsLine (Position line column) = maybe False (T.null . T.strip . T.take (column - 1)) (sourceLines BV.!? (line - 1))
    plainCommentLines =
      Set.fromList
        [ l
        | not (null (commentOuterDoc syntax))
        , c <- rest
        , not (outerProper c)
        , startsItsLine (spanStart (locatedSpan c))
        , l <- [positionLine (spanStart (locatedSpan c)) .. positionLine (spanEnd (locatedSpan c))]
        ]
    directiveLines = Set.fromList [n | not (null (commentDirectives syntax)), (n, line) <- zip [1 :: Int ..] (T.lines source), any (`T.isPrefixOf` T.stripStart line) (commentDirectives syntax)]
    isDocAttribute c = any (`T.isPrefixOf` T.stripStart (commentText (locatedValue c))) (commentDocAttributes syntax)
    blankLine l = maybe False (T.null . T.strip) (sourceLines BV.!? (l - 1))
    lineCount = BV.length sourceLines
    belowDocAttributes =
      Set.fromList
        [ l
        | c <- rest
        , isDocAttribute c || (commentJoinAcrossBlankLines syntax && outerProper c)
        , l <- takeWhile (\l -> l <= lineCount && (blankLine l || Set.member l baseTransparent)) [positionLine (spanEnd (locatedSpan c)) + 1 ..]
        , blankLine l
        ]
    baseTransparent = Set.unions [unread, directiveLines, plainCommentLines]
    transparentLines = Set.union baseTransparent belowDocAttributes
    overTransparent t =
      let Span start end = locatedSpan t
          firstLine = until (\l -> not (Set.member (l - 1) transparentLines)) (subtract 1) (positionLine start)
       in if firstLine == positionLine start then t else t {locatedSpan = Span (Position firstLine 1) end}
    (pairs, unattached) = attachPreceding (filter isOuter rest) targets
    orphans = unattached
    bound = Set.fromList (map (unitId . locatedValue . snd) pairs)
    (nestedInner, nestedInnerOrphans) =
      foldr
        ( \(uid, found) (keep, drop') -> case found of
            ((first, t) : more)
              | uid /= unitId root, not (Set.member uid bound), not (Set.member (decisionIdFor uid) decided) -> ((first, t) : keep, map fst more ++ drop')
            _ | uid /= unitId root -> (keep, map fst found ++ drop')
            _ -> (keep, drop')
        )
        ([], [])
        (Map.toList innerByUnit)
    innerOrphans = rootInnerOrphans ++ nestedInnerOrphans
    toDecision (comment, target) =
      let u = locatedValue target
          sp = locatedSpan comment
       in Decision
            { decisionId = decisionIdFor (unitId u)
            , decisionUnits = unitId u :| []
            , decisionWhy = Answer (toWhy (parseCanonicalComment (commentBody syntax (locatedValue comment)))) (Asserted (Assertion path sp))
            , decisionWhere = Where path sp (whereChain (answerValue (unitWhere u))) Nothing
            , decisionVetting = Nothing
            }

-- | The prose of a comment: a doc attribute's string contents, or the comment's lines without their
-- markers. ref:DEC-elixir-grammar
commentBody :: CommentSyntax -> Comment -> Text
commentBody syntax c
  | isDocAttribute = docAttributeBody syntax (commentText c)
  | otherwise = T.strip (T.unlines (map stripMarker (T.lines (commentText c))))
  where
    isDocAttribute = any (`T.isPrefixOf` T.stripStart (commentText c)) (commentDocAttributes syntax)
    stripMarker line =
      let trimmed = T.stripStart line
       in T.strip (T.dropWhile (\ch -> not (isAlphaNum ch) && ch /= '(' && ch /= '[' && ch /= '\'' && ch /= '"' && ch /= '`' && ch /= '<' && ch /= '@') trimmed)
