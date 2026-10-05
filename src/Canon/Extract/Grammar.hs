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

import Canon.Extract.Calm (calmUnits)
import Canon.Antlr4.Comment (Comment (..))
import Canon.Antlr4.Interpret
import Canon.Antlr4.Lexical (lineTable, positionAt)
import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Syntax (Alternative (..), Block (..), EbnfSuffix (..), Element (..), Grammar (..), Label (..), LabeledAlternative (..), Name (..), ParserRule (..), Quantifier (OneOrMore), Rule (..), nameText)
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.Attach (attachPreceding, firstContentLine, topOfFileComment)
import Canon.CanonicalComment (docCommentBody, parseCanonicalComment, toWhy)
import Canon.CommentScan (docAttributeBody, docOpenerOf, scanCommentsWith)
import Canon.Config (Config (..))
import Canon.Git.Fill (fillGitFromBlame)
import Canon.Git.Provider
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Preprocessor (builds, inactiveLinesWith)
import Canon.Profile
import Canon.Span (Located (..), Position (..), Span (..))
import Canon.Testing (isTestUnit)
import Data.Char (isAlphaNum, isDigit, isSpace, isUpper)
import Data.Foldable (toList)
import Data.List (group, sort, sortOn)
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
  | GrammarArchitectureError Text
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
  GrammarArchitectureError message -> message
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
-- project-relative. A file whose lexer reads #if directives is read once per build of the few that
-- together read every branch, and the units and decisions each read finds are merged by id, the
-- first build's winning; a doc comment is an orphan only when every build that reads it leaves it
-- unbound. ref:DEC-preprocessor-builds
extractWithProfileText :: GitProvider -> Config -> Text -> Profile -> Interpreter -> FilePath -> FilePath -> Text -> IO (Either GrammarExtractError Extraction)
extractWithProfileText provider config language profile interpreter idPath path source =
  case mapM readBuild choices of
    Left err -> pure (Left err)
    Right readings -> do
      let root = foldl1 mergeUnits [r | (_, r, _, _) <- readings]
          decisions = firstById (concat [ds | (_, _, ds, _) <- readings])
          orphaned = [sp | sp <- uniqueSpans (concat [spans | (_, _, _, spans) <- readings]), all (orphanIn sp) readings]
      (unitsWithGit, gitFindings) <- fillGitFromBlame provider path root
      described <- either (const Nothing) id <$> describeVersion provider
      let model = Model language (configVersion config) described [unitsWithGit] decisions
      pure (Right (Extraction model (map (OrphanDocComment path) orphaned ++ gitFindings)))
  where
    preprocessed = interpreterPreprocesses interpreter
    choices = if preprocessed then builds source else [Nothing]
    comments = scanCommentsWith (profileComments profile) source
    readBuild choice = do
      tree <- either (Left . GrammarInterpretError) Right (interpretTextWith choice interpreter (profileStart profile) path source)
      (root, labeled, unbound) <- unitsFromTree language profile (alternativePlans (interpreterParser interpreter)) (exportLabelsDeclared (interpreterParser interpreter)) idPath path source tree
      let unread = if preprocessed then inactiveLinesWith choice source else Set.empty
          (attached, orphans) = extractDecisionsFor (profileComments profile) unread path source root (Set.fromList (map decisionId labeled)) comments
      Right (unread, root, labeled ++ attached, unbound ++ map locatedSpan orphans)
    orphanIn sp (unread, _, _, spans) = Set.member (positionLine (spanStart sp)) unread || sp `elem` spans
    uniqueSpans = foldr (\sp acc -> sp : filter (/= sp) acc) []
    firstById = go Set.empty
      where
        go _ [] = []
        go seen (d : rest)
          | Set.member (decisionId d) seen = go seen rest
          | otherwise = d : go (Set.insert (decisionId d) seen) rest

-- | Merges the units two builds of one file found: a unit both found is the first's, with the
-- children of both merged, and the children are kept in source order. ref:DEC-preprocessor-builds
mergeUnits :: CodeUnit Evidence -> CodeUnit Evidence -> CodeUnit Evidence
mergeUnits a b = a {unitChildren = sortOnStart (foldl insert (unitChildren a) (unitChildren b))}
  where
    insert children child = case break ((== unitId child) . unitId) children of
      (before, found : after) -> before ++ mergeUnits found child : after
      (_, []) -> children ++ [child]
    sortOnStart = sortOn (spanStart . whereSpan . answerValue . unitWhere)

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

-- | Parses an export entry from its text. A module export is the word module before a module name,
-- which starts with a capital, so a name that merely starts with module, as Prolog's module_path/1
-- does, is a name. ref:DEC-prolog-dialect
parseExportEntry :: Text -> ExportEntry
parseExportEntry raw
  | Just m <- T.stripPrefix "module" compact, Just (initial, _) <- T.uncons m, isUpper initial = ExportModule m
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

-- | Builds the unit tree, its decisions, and the orphan spans from a parse tree. A unit is required
-- when its node holds an element the grammar labels required, as the C# grammar labels public and
-- protected, or when a profile's rule says so, unless its node holds an element labeled optional,
-- as the F# grammar labels private and internal; a unit whose why element is mandatory is required
-- whatever it holds. ref:DEC-csharp-grammar
-- ref:DEC-fsharp-grammar A unit found under an element labeled inherited needs a comment when the
-- unit enclosing it does, unless its node holds an element labeled optional, as the items of a
-- public Rust trait and the members of a public C# interface do. ref:DEC-inherited-label A unit
-- rule named by ordinal numbers its units from zero in their parent. ref:DEC-rust-visibility
-- Adjacent clauses of a unit rule that merges them are one unit, unless a
-- doc comment ends on the line above a later clause, which then starts a unit of its own, as the
-- @doc of another Elixir arity does. ref:DEC-elixir-grammar Adjacent units of a labeled alternative
-- named with an arity merge in the same way when they share a kind and a name, as the clauses of a
-- Prolog predicate are one predicate, and a later clause with a Why of its own starts a unit.
-- ref:DEC-prolog-dialect
unitsFromTree :: Text -> Profile -> Map.Map Name [Maybe AlternativePlan] -> Bool -> FilePath -> FilePath -> Text -> ParseTree -> Either GrammarExtractError (CodeUnit Evidence, [Decision Evidence], [Span])
unitsFromTree language profile plans exportsDeclared idPath path source tree
  | language == "calm" = either (Left . GrammarArchitectureError) Right (calmUnits idPath path source tree)
  | otherwise =
  case [i | i@(_ : _ : _) <- group (sort (map unitId (allUnits root)))] of
    [] -> Right (root, fileDecisions ++ decisions, unbound)
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
        , isNothing (candidateWhy b)
        , not (Set.member (positionLine (spanStart (treeSpan (candidateNode b))) - 1) docEndLines) ->
            mergeClauses (a {candidateClauses = candidateClauses a ++ candidateNode b : candidateClauses b} : rest)
      (a : rest) -> a : mergeClauses rest
      [] -> []
    (children, unitDecisions) = collect fileId [] False tree
    -- A Python module's docstring is the file's Why through the profile, unless the grammar labels
    -- it a why element of the start rule, as the Python dialect does. ref:DEC-python-dialect
    decisions = unitDecisions ++ case pythonDoc tree of
      Just doc | language == "python", null rootWhys ->
        let sp = treeSpan doc
         in [Decision (decisionIdFor fileId) (fileId :| []) (Answer (whyFrom doc (slice sp)) (Asserted (Assertion path sp))) (Where path sp [] Nothing) Nothing]
      _ -> []
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
    unbound = map treeSpan (drop 1 rootWhys ++ unboundBelowRoot ++ orphansIn tree)
    -- A why element of the start rule outside every unit is the file's Why, as Rust's //! at the top
    -- of a file is; of several, the first binds and the others are orphans. ref:DEC-rust-dialect
    rootWhys = case tree of
      RuleNode _ _ ns | not (isUnitNode tree) -> [inner | Labeled "why" inner <- ns]
      _ -> []
    unboundBelowRoot = case tree of
      RuleNode _ _ ns | not (isUnitNode tree) -> concatMap unboundWhys ns
      _ -> unboundWhys tree
    fileDecisions = case rootWhys of
      (whyNode : _) ->
        let whySpan = treeSpan whyNode
         in [ Decision
                { decisionId = decisionIdFor fileId
                , decisionUnits = fileId :| []
                , decisionWhy = Answer (whyFrom whyNode (slice whySpan)) (Asserted (Assertion path whySpan))
                , decisionWhere = Where path whySpan [] Nothing
                , decisionVetting = Nothing
                }
            ]
      [] -> []
    orphansIn node = case node of
      TokenNode _ -> []
      Labeled "orphan" inner -> [inner]
      Labeled _ inner -> orphansIn inner
      RuleNode _ _ ns -> concatMap orphansIn ns
    unboundWhys node = case node of
      TokenNode _ -> []
      Labeled _ inner -> unboundWhys inner
      RuleNode _ _ ns
        | isUnitNode node && isJust (planName node) -> concatMap unboundWhys (filter (not . isWhy) ns)
        | otherwise -> [inner | Labeled "why" inner <- ns] ++ concatMap unboundWhys ns
    isWhy node = case node of
      Labeled "why" _ -> True
      _ -> False
    root =
      CodeUnit
        { unitId = fileId
        , unitWhat = Answer (What (T.pack path) (UnitKind "file") Nothing) evidence
        , unitHow = Answer (HowAt (treeSpan tree)) evidence
        , unitWhere = Answer (Where path (treeSpan tree) [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Optional
        , unitTest = False
        , unitChildren = children
        }
    collect parent chain parentRequired node = collectAll parent chain parentRequired [node]
    collectAll parent chain parentRequired nodes =
      let built = map (build parent chain parentRequired) (uniqueNames (numberOrdinals (mergeClauses (attachBindings (concatMap found nodes)))))
       in (map fst built, concatMap snd built)
    numberOrdinals candidates = go Map.empty candidates
      where
        go _ [] = []
        go counts (c : rest)
          | candidateOrdinal c =
              let k = Map.findWithDefault (0 :: Int) (candidateKind c) counts
               in c {candidateName = T.pack (show k)} : go (Map.insert (candidateKind c) (k + 1) counts) rest
          | otherwise = c : go counts rest
    -- A labeled binding belongs to the nearest unit before it, at the same level, with its name;
    -- a binding that matches no unit is not a unit, as before. ref:DEC-binding-label
    attachBindings = go []
      where
        go acc [] = reverse acc
        go acc (FoundUnit c : rest) = go (c : acc) rest
        go acc (FoundBinding b : rest) = case bindingHead b of
          Just name | (before, c : after) <- break ((== name) . candidateName) acc -> go (before ++ c {candidateBindings = candidateBindings c ++ [b]} : after) rest
          _ -> go acc rest
    -- The name a binding defines: the first word, the operator run between the first word and
    -- the equals sign (an operator lexes as adjacent single symbols), or the word in backticks.
    bindingHead b = case takeWhile ((`notElem` ["=", "|"]) . tokenText) [t | t <- treeTokens b, not (isEofToken t), not (isVirtual t)] of
      [] -> Nothing
      lhs@(first : rest)
        | tokenText first == "(" -> Just (T.concat (map tokenText (takeWhile ((/= ")") . tokenText) lhs) ++ [")"]))
        | (run : _) <- operatorRuns rest -> Just (T.concat ["(", run, ")"])
        | (name : _) <- [tokenText n | (tick, n) <- zip lhs rest, tokenText tick == "`"] -> Just name
        | otherwise -> Just (tokenText first)
    operatorRuns toks = case dropWhile (not . isOperator . tokenText) toks of
      [] -> []
      (t : more) ->
        let (adjacent, rest) = spanAdjacent t more
         in T.concat (map tokenText (t : adjacent)) : operatorRuns rest
    spanAdjacent prev toks = case toks of
      (t : more) | isOperator (tokenText t), tokenStart t == tokenEnd prev -> let (a, r) = spanAdjacent t more in (t : a, r)
      _ -> ([], toks)
    -- A layout hook's virtual token carries its own kind as its text.
    isVirtual t = tokenText t == nameText (tokenType t) && nameText (tokenType t) `elem` ["VOCURLY", "VCCURLY", "SEMI"]
    isOperator t = not (T.null t) && T.all (`elem` ("!#$%&*+./<=>?@\\^|-~:" :: String)) t
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
      Labeled "inherited" inner -> [inherit f | f <- found inner]
      Labeled "binding" inner -> [FoundBinding inner]
      Labeled _ inner -> found inner
      RuleNode name alternative nodeChildren -> case planFor name alternative of
        Just plan | Just (unitName, ordinal) <- planName node -> [FoundUnit (Candidate (planKind plan) unitName (if planWhyRequired plan || (isJust (labeledSubtree "required" node) && not optional) then Required else Optional) optional False ordinal (labeledSubtree "why" node) (labeledSubtree "how" node) (labeledSubtree "signature" node) [] node (if isJust (labeledSubtree "arity" node) then Just (planKind plan) else Nothing) [])]
        _ -> case [(rule, unitName) | rule <- Map.findWithDefault [] name rulesByName, accepts rule node, Just unitName <- [nameOf rule node]] of
          ((rule, unitName) : _) -> [FoundUnit (Candidate (unitRuleKind rule) unitName (if (unitRuleRequired rule || isJust (labeledSubtree "required" node)) && not optional then Required else Optional) optional False (unitRuleNameSource rule == NameFromOrdinal) (pythonDoc node) Nothing Nothing [] node (if unitRuleMergeClauses rule then Just (nameText (unitRuleName rule)) else Nothing) [])]
          [] -> concatMap found nodeChildren
        where
          optional = isJust (labeledSubtree "optional" node)
    inherit f = case f of
      FoundUnit c -> FoundUnit c {candidateInherits = True}
      FoundBinding b -> FoundBinding b
    -- A docstring is a string expression in the first statement of this declaration's suite.
    pythonDoc node
      | language /= "python" = Nothing
      | otherwise = do
          block <- case node of
            RuleNode (Name "file_input") _ _ -> Just node
            _ -> listToMaybe [b | b@(RuleNode (Name "block") _ _) <- childrenOf node]
          statement <- firstStatement block
          case filter (\t -> nameText (tokenType t) `notElem` ["NEWLINE", "INDENT", "DEDENT"] && not (isEofToken t)) (treeTokens statement) of
            [t] | nameText (tokenType t) == "STRING", isJust (pythonString (tokenText t)) -> Just (TokenNode t)
            _ -> Nothing
    firstStatement node = case node of
      RuleNode (Name "simple_stmt") _ _ -> Just node
      RuleNode (Name "stmt") _ ns -> listToMaybe ns >>= firstStatement
      RuleNode (Name "simple_stmts") _ ns -> listToMaybe ns >>= firstStatement
      RuleNode (Name "block") _ ns -> listToMaybe [n | n@RuleNode {} <- ns] >>= firstStatement
      RuleNode (Name "file_input") _ ns -> listToMaybe [n | n@RuleNode {} <- ns] >>= firstStatement
      _ -> Nothing
    pythonString raw =
      let plain = if "r" `T.isPrefixOf` T.toLower raw || "u" `T.isPrefixOf` T.toLower raw then T.drop 1 raw else raw
       in listToMaybe [body | delimiter <- ["\"\"\"", "'''", "\"", "'"], Just middle <- [T.stripPrefix delimiter plain], Just body <- [T.stripSuffix delimiter middle]]
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
    labeledName wanted node = nameFromTokens <$> labeledSubtree wanted node
    -- A unit alternative is named by its what element, or by its position when it has an element
    -- labeled ordinal instead, as a field of a Rust tuple struct is. ref:DEC-rust-dialect
    planName node = case labeledName "what" node of
      Just unitName -> Just (maybe unitName (\a -> T.concat [unitName, "/", T.pack (show (arityOf a))]) (labeledSubtree "arity" node), False)
      Nothing -> if isJust (labeledSubtree "ordinal" node) then Just ("", True) else Nothing
    -- A unit with an element labeled arity is named name/arity, as a Prolog predicate is: the
    -- arity is the number the element holds, as in the declaration dynamic foo/1, or else the
    -- number of rules among its children, as the arguments of a clause's head are; a head without
    -- arguments labels an empty rule. ref:DEC-prolog-dialect
    arityOf a = case T.unpack (tokensText a) of
      digits@(_ : _) | all isDigit digits -> read digits :: Int
      _ -> length [() | RuleNode {} <- map unlabel (childrenOf a)]
    unlabel n = case n of
      Labeled _ inner -> unlabel inner
      _ -> n
    tokensText n = T.concat (map tokenText (filter (not . isEofToken) (treeTokens n)))
    -- A name is its tokens run together, with a hyphen where the source spaces a word from what
    -- follows it, so the Rust impl Deref for Guard<T, U> is named Deref-for-Guard<T,U> and a unit id
    -- holds no space. ref:DEC-rust-visibility
    nameFromTokens n = joinWords (filter (not . isEofToken) (treeTokens n))
    joinWords toks = T.concat (zipWith glue (Nothing : map Just toks) toks)
    glue previous t = case previous of
      Just p
        | tokenEnd p < tokenStart t
        , Just (_, lastChar) <- T.unsnoc (tokenText p)
        , wordChar lastChar ->
            "-" <> tokenText t
      _ -> tokenText t
    wordChar ch = isAlphaNum ch || ch == '_' || ch == '\''
    uniqueNames candidates = go Map.empty candidates
      where
        go _ [] = []
        go seen (c : rest) =
          let key = (candidateKind c, candidateName c)
              count = Map.findWithDefault (0 :: Int) key seen
              segment = if count == 0 then candidateName c else T.concat [candidateName c, "#", T.pack (show (count + 1))]
           in (c, segment) : go (Map.insert key (count + 1) seen) rest
    build parent chain parentRequired (c, segment) =
      let uid = UnitId (NonEmpty.fromList (NonEmpty.toList (unitIdSegments parent) ++ [candidateKind c, segment]))
          node = candidateNode c
          clauses = node : candidateClauses c
          ownSpan = Span (spanStart (treeSpan node)) (spanEnd (treeSpan (last clauses)))
          -- A binding's span ends at its last real token, not at the virtual brace the layout
          -- hook places on the next line.
          bindingSpans = [Span (spanStart (treeSpan b)) (maybe (spanEnd (treeSpan b)) (spanEnd . treeSpan . TokenNode) (lastReal b)) | b <- candidateBindings c]
          lastReal b = case reverse [t | t <- treeTokens b, not (isEofToken t), not (isVirtual t)] of
            (t : _) -> Just t
            [] -> Nothing
          sp = case bindingSpans of
            [] -> ownSpan
            _ -> Span (spanStart ownSpan) (maximum (spanEnd ownSpan : map spanEnd bindingSpans))
          -- The How is the bindings when there are any, else the labeled how, else the unit's own
          -- text after its comment, so a How never contains the Why.
          howSpan = case (bindingSpans, candidateHow c) of
            (b : bs, _) -> Span (spanStart b) (maximum (map spanEnd (b : bs)))
            ([], Just h) -> treeSpan h
            ([], Nothing) -> maybe ownSpan (\w -> Span (spanEnd (treeSpan w)) (spanEnd ownSpan)) (candidateWhy c)
          (nested, nestedDecisions) = collectAll uid (chain ++ [candidateName c]) required (concatMap childrenOf clauses)
          markers = [T.concat (T.words (tokensText m)) | clause <- clauses, m <- labeledSubtrees "marker" clause]
          test = isTestUnit language (candidateKind c) (candidateName c) idPath markers
          inherits = candidateInherits c && parentRequired && not (candidateOptional c)
          required = test || candidateRequirement c == Required || inherits || exported chain (candidateName c)
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
              , unitWhat = Answer (What (candidateName c) (UnitKind (candidateKind c)) (T.strip . slice . treeSpan <$> candidateSignature c)) evidence
              , unitHow = Answer (HowText (T.strip (case candidateWhy c of
                    Just why | language == "python" -> slice (Span (spanStart ownSpan) (spanStart (treeSpan why))) <> slice (Span (spanEnd (treeSpan why)) (spanEnd ownSpan))
                    _ -> slice howSpan))) evidence
              , unitWhere = Answer (Where path sp chain Nothing) evidence
              , unitWho = Nothing
              , unitWhen = Nothing
              , unitRequirement = if required then Required else Optional
              , unitTest = test
              , unitChildren = nested
              }
          , own ++ nestedDecisions
          )
    whyFrom _ raw | language == "python", Just body <- pythonString raw = toWhy (parseCanonicalComment body)
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
      NameFromDirectToken tokenName index -> tokenText <$> listToMaybe (drop (index - 1) [t | t <- directTokens node, tokenType t == tokenName])
      NameFromRule ruleName -> listToMaybe (mapMaybe (ruleText ruleName) (directChildrenDeep node))
      NameFromOrdinal -> Just ""
    ruleText wanted node = case node of
      RuleNode name _ _ | name == wanted -> Just (nameFromTokens node)
      _ -> Nothing
    directTokens node = case node of
      RuleNode _ _ ns -> concatMap ownToken ns
      _ -> []
    ownToken node = case node of
      TokenNode t -> [t]
      Labeled _ inner -> ownToken inner
      RuleNode {} -> []
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
  , candidateOptional :: Bool
  , candidateInherits :: Bool
  , candidateOrdinal :: Bool
  , candidateWhy :: Maybe ParseTree
  , candidateHow :: Maybe ParseTree
  , candidateSignature :: Maybe ParseTree
  , candidateBindings :: [ParseTree]
  , candidateNode :: ParseTree
  , candidateMerge :: Maybe Text
  , candidateClauses :: [ParseTree]
  }

-- | What a walk of the tree finds: a unit, or a labeled binding that belongs to one.
data Found = FoundUnit Candidate | FoundBinding ParseTree

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
extractDecisionsFor :: CommentSyntax -> Set.Set Int -> FilePath -> Text -> CodeUnit Evidence -> Set.Set DecisionId -> [Located Comment] -> ([Decision Evidence], [Located Comment])
extractDecisionsFor syntax unread path source root decided scanned = (map toDecision (fileInner ++ maybe [] (\c -> [(c, rootTarget)]) header ++ pairs ++ nestedInner), orphans ++ innerOrphans)
  where
    rootTarget = Located (whereSpan (answerValue (unitWhere root))) root
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
    targets = [overTransparent t | t <- nested, not (Set.member (decisionIdFor (unitId (locatedValue t))) decided)]
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
    transparentLines = Set.unions [unread, directiveLines, plainCommentLines]
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
       in T.strip (T.dropWhile (\ch -> not (isAlphaNum ch) && ch /= '(' && ch /= '[' && ch /= '\'' && ch /= '"' && ch /= '`' && ch /= '<') trimmed)
