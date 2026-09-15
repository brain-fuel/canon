-- | The questions ANTLR's Grammar object answers about a grammar, answered over the value the reader
-- produces, so tools need no Java to ask them. ref:DEC-parser-foundation
module Canon.Antlr4.Query
  ( ruleName
  , ruleAnn
  , allRules
  , ruleNames
  , lookupRule
  , ruleIndex
  , parserRules
  , lexerRules
  , fragmentRules
  , duplicateRuleNames
  , grammarOptions
  , grammarImports
  , namedActions
  , declaredTokens
  , channelNames
  , tokenNames
  , tokenTypes
  , literals
  , literalTokenTypes
  , implicitLiteralTokens
  , defaultModeName
  , modeNames
  , rulesInMode
  , modeOfLexerRule
  , KnownLexerCommand (..)
  , knownLexerCommand
  , semanticPredicates
  , embeddedActions
  , labeledAlternatives
  , elementLabels
  , parserRuleElements
  , lexerRuleElements
  , ruleReferences
  , tokenReferences
  , referencesByRule
  , undefinedRuleReferences
  , undefinedTokenReferences
  , tokenReferencesUndefinedIn
  , WellFormednessIssue (..)
  , wellFormed
  ) where

import Canon.Antlr4.Syntax
import Data.List (elemIndex, nub)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set

-- | The name of a rule of either kind.
ruleName :: Rule ann -> Name
ruleName r = case r of
  RuleParser p -> parserRuleName p
  RuleLexer l -> lexerRuleName l

-- | The annotation of a rule of either kind.
ruleAnn :: Rule ann -> ann
ruleAnn r = case r of
  RuleParser p -> parserRuleAnn p
  RuleLexer l -> lexerRuleAnn l

-- | Every rule including those inside modes, in file order, because ids and indices follow file
-- order.
allRules :: Grammar ann -> [Rule ann]
allRules g = grammarRules g ++ concatMap (map RuleLexer . modeRules) (grammarModes g)

-- | The names in file order.
ruleNames :: Grammar ann -> [Name]
ruleNames = map ruleName . allRules

-- | Finds a rule by name.
lookupRule :: Name -> Grammar ann -> Maybe (Rule ann)
lookupRule name g = case filter ((== name) . ruleName) (allRules g) of
  (r : _) -> Just r
  [] -> Nothing

-- | The position of a rule in file order.
ruleIndex :: Name -> Grammar ann -> Maybe Int
ruleIndex name g = elemIndex name (ruleNames g)

-- | The parser rules.
parserRules :: Grammar ann -> [ParserRule ann]
parserRules g = [p | RuleParser p <- allRules g]

-- | The non-fragment lexer rules, which are the token vocabulary.
lexerRules :: Grammar ann -> [LexerRule ann]
lexerRules g = [l | RuleLexer l <- allRules g]

-- | The fragment rules, which produce no tokens.
fragmentRules :: Grammar ann -> [LexerRule ann]
fragmentRules = filter lexerRuleIsFragment . lexerRules

-- | Names defined more than once, which ANTLR rejects.
duplicateRuleNames :: Grammar ann -> [Name]
duplicateRuleNames g = nub [n | (n, i) <- zip names [0 :: Int ..], n `elem` take i names]
  where
    names = ruleNames g

-- | The options of the grammar header.
grammarOptions :: Grammar ann -> [Option]
grammarOptions g = concat [o | PrequelOptions o <- grammarPrequel g]

-- | The imported grammars.
grammarImports :: Grammar ann -> [Import]
grammarImports g = concat [NonEmpty.toList i | PrequelImports i <- grammarPrequel g]

-- | The named actions such as header and members.
namedActions :: Grammar ann -> [(Maybe Name, NamedAction)]
namedActions g = [(scope, a) | PrequelAction scope a <- grammarPrequel g]

-- | The tokens block.
declaredTokens :: Grammar ann -> [Name]
declaredTokens g = concat [t | PrequelTokens t <- grammarPrequel g]

-- | The channels block plus the built-in channels.
channelNames :: Grammar ann -> [Name]
channelNames g = concat [c | PrequelChannels c <- grammarPrequel g]

-- | Every token name, declared or defined by a rule.
tokenNames :: Grammar ann -> [Name]
tokenNames g = nub (declaredTokens g ++ [lexerRuleName l | l <- lexerRules g, not (lexerRuleIsFragment l)])

-- | Token names with their numbering.
tokenTypes :: Grammar ann -> Map Name Int
tokenTypes g = Map.fromList (zip (tokenNames g) [1 ..])

-- | Every literal that appears in the grammar.
literals :: Grammar ann -> Set StringLiteral
literals g = Set.fromList (concatMap ruleLiterals (allRules g))

ruleLiterals :: Rule ann -> [StringLiteral]
ruleLiterals r = case r of
  RuleParser p -> concatMap elementLiterals (parserRuleElements p)
  RuleLexer l -> concatMap lexerElementLiterals (lexerRuleElements l)
  where
    elementLiterals e = case e of
      ElementAtom _ _ a _ -> atomLiterals a
      _ -> []
    atomLiterals a = case a of
      AtomTerminal t -> terminalLiterals t
      AtomNotSet s -> notSetLiterals s
      _ -> []
    lexerElementLiterals e = case e of
      LexerElementAtom _ a _ -> lexerAtomLiterals a
      _ -> []
    lexerAtomLiterals a = case a of
      LexerAtomTerminal t -> terminalLiterals t
      LexerAtomNotSet s -> notSetLiterals s
      _ -> []
    notSetLiterals (NotSet elements) = concat [terminalLiterals t | SetTerminal t <- NonEmpty.toList elements]
    terminalLiterals t = case t of
      TerminalLiteral s _ -> [s]
      _ -> []

-- | The literal-to-token map ANTLR builds, so a parser literal finds its lexer rule.
literalTokenTypes :: Grammar ann -> Map StringLiteral Name
literalTokenTypes g = Map.fromList (mapMaybe aliasOf (reverse (lexerRules g)))
  where
    aliasOf l
      | lexerRuleIsFragment l = Nothing
      | otherwise = case NonEmpty.toList (lexerRuleAlternatives l) of
          [LexerAlternative _ [LexerElementAtom _ (LexerAtomTerminal (TerminalLiteral s _)) Nothing] _] ->
            Just (s, lexerRuleName l)
          _ -> Nothing

-- | The literals a combined grammar defines implicitly as T__ tokens.
implicitLiteralTokens :: Grammar ann -> [StringLiteral]
implicitLiteralTokens g =
  nub [s | RuleParser p <- allRules g, s <- ruleLiterals (RuleParser p), not (Map.member s aliases)]
  where
    aliases = literalTokenTypes g

-- | The name of the default lexer mode.
defaultModeName :: Name
defaultModeName = Name "DEFAULT_MODE"

-- | The mode names.
modeNames :: Grammar ann -> [Name]
modeNames g = defaultModeName : map modeName (grammarModes g)

-- | The rules of a mode.
rulesInMode :: Name -> Grammar ann -> [LexerRule ann]
rulesInMode name g
  | name == defaultModeName = [l | RuleLexer l <- grammarRules g]
  | otherwise = concat [modeRules m | m <- grammarModes g, modeName m == name]

-- | The mode a lexer rule belongs to.
modeOfLexerRule :: Name -> Grammar ann -> Maybe Name
modeOfLexerRule name g = case [m | m <- modeNames g, any ((== name) . lexerRuleName) (rulesInMode m g)] of
  (m : _) -> Just m
  [] -> Nothing

-- | The lexer commands ANTLR defines, as a type so unknown commands are reported.
data KnownLexerCommand
  = LexerSkip
  | LexerMore
  | LexerPopMode
  | LexerType Name
  | LexerChannel Name
  | LexerMode Name
  | LexerPushMode Name
  deriving (Eq, Show)

-- | Classifies a lexer command.
knownLexerCommand :: LexerCommand -> Maybe KnownLexerCommand
knownLexerCommand (LexerCommand (Name n) arg) = case (n, arg) of
  ("skip", Nothing) -> Just LexerSkip
  ("more", Nothing) -> Just LexerMore
  ("popMode", Nothing) -> Just LexerPopMode
  ("type", Just (CommandArgumentName t)) -> Just (LexerType t)
  ("channel", Just (CommandArgumentName c)) -> Just (LexerChannel c)
  ("mode", Just (CommandArgumentName m)) -> Just (LexerMode m)
  ("pushMode", Just (CommandArgumentName m)) -> Just (LexerPushMode m)
  _ -> Nothing

-- | The predicates in the grammar, which the interpreter assumes true.
semanticPredicates :: Grammar ann -> [(Name, ActionText)]
semanticPredicates = actionsOfForm SemanticPredicate

-- | The embedded actions in the grammar.
embeddedActions :: Grammar ann -> [(Name, ActionText)]
embeddedActions = actionsOfForm EmbeddedAction

actionsOfForm :: ActionForm -> Grammar ann -> [(Name, ActionText)]
actionsOfForm wanted g = concatMap ruleActions (allRules g)
  where
    ruleActions r = case r of
      RuleParser p -> [(parserRuleName p, t) | ElementAction _ form t _ <- parserRuleElements p, form == wanted]
      RuleLexer l -> [(lexerRuleName l, t) | LexerElementAction _ form t <- lexerRuleElements l, form == wanted]

-- | The alternatives with a hash label, which are the unit alternatives of a dialect.
-- ref:DEC-grammar-carries-extraction-rules
labeledAlternatives :: ParserRule ann -> [(Name, Alternative ann)]
labeledAlternatives p = [(l, a) | LabeledAlternative a (Just l) <- NonEmpty.toList (parserRuleAlternatives p)]

-- | The element labels, which are the extraction labels of a dialect.
elementLabels :: ParserRule ann -> [Label]
elementLabels p = concatMap labelOf (parserRuleElements p)
  where
    labelOf e = case e of
      ElementAtom _ (Just l) _ _ -> [l]
      ElementBlock _ (Just l) _ _ -> [l]
      _ -> []

-- | Every element of a parser rule, flattened.
parserRuleElements :: ParserRule ann -> [Element ann]
parserRuleElements p = concatMap (alternativeElementsDeep . labeledAlternativeBody) (NonEmpty.toList (parserRuleAlternatives p))

alternativeElementsDeep :: Alternative ann -> [Element ann]
alternativeElementsDeep = concatMap elementDeep . alternativeElements
  where
    elementDeep e = e : case e of
      ElementBlock _ _ b _ -> concatMap alternativeElementsDeep (NonEmpty.toList (blockAlternatives b))
      _ -> []

-- | Every element of a lexer rule, flattened.
lexerRuleElements :: LexerRule ann -> [LexerElement ann]
lexerRuleElements l = concatMap lexerAlternativeElementsDeep (NonEmpty.toList (lexerRuleAlternatives l))

lexerAlternativeElementsDeep :: LexerAlternative ann -> [LexerElement ann]
lexerAlternativeElementsDeep = concatMap elementDeep . lexerAlternativeElements
  where
    elementDeep e = e : case e of
      LexerElementBlock _ alts _ -> concatMap lexerAlternativeElementsDeep (NonEmpty.toList alts)
      _ -> []

-- | The rules a rule references.
ruleReferences :: Rule ann -> Set Name
ruleReferences r = case r of
  RuleParser p -> Set.fromList [n | ElementAtom _ _ (AtomRuleRef n _ _) _ <- parserRuleElements p]
  RuleLexer l -> Set.delete (Name "EOF") (lexerTokenReferences l)

-- | The tokens a rule references.
tokenReferences :: Rule ann -> Set Name
tokenReferences r = case r of
  RuleParser p -> Set.fromList (concatMap atomTokens [a | ElementAtom _ _ a _ <- parserRuleElements p])
  RuleLexer l -> lexerTokenReferences l
  where
    atomTokens a = case a of
      AtomTerminal t -> terminalTokens t
      AtomNotSet s -> notSetTokens s
      _ -> []

lexerTokenReferences :: LexerRule ann -> Set Name
lexerTokenReferences l = Set.fromList (concatMap lexerAtomTokens [a | LexerElementAtom _ a _ <- lexerRuleElements l])
  where
    lexerAtomTokens a = case a of
      LexerAtomTerminal t -> terminalTokens t
      LexerAtomNotSet s -> notSetTokens s
      _ -> []

terminalTokens :: Terminal -> [Name]
terminalTokens t = case t of
  TerminalToken n _ -> [n]
  _ -> []

notSetTokens :: NotSet -> [Name]
notSetTokens (NotSet elements) = concat [terminalTokens t | SetTerminal t <- NonEmpty.toList elements]

-- | References of every rule, for graph building.
referencesByRule :: Grammar ann -> Map Name (Set Name)
referencesByRule g = Map.fromListWith Set.union [(ruleName r, ruleReferences r) | r <- allRules g]

-- | References to rules that do not exist.
undefinedRuleReferences :: Grammar ann -> [(Name, Name)]
undefinedRuleReferences g =
  [(ruleName r, n) | r <- allRules g, n <- Set.toList (ruleReferences r), not (Set.member n defined)]
  where
    defined = Set.fromList (ruleNames g)

-- | References to tokens that do not exist.
undefinedTokenReferences :: Grammar ann -> [(Name, Name)]
undefinedTokenReferences g = tokenReferencesUndefinedIn g g

-- | Token references undefined against a given vocabulary, for split grammars.
tokenReferencesUndefinedIn :: Grammar a -> Grammar b -> [(Name, Name)]
tokenReferencesUndefinedIn parserGrammar lexerGrammar =
  [ (parserRuleName p, n)
  | p <- parserRules parserGrammar
  , n <- Set.toList (tokenReferences (RuleParser p))
  , n /= Name "EOF"
  , not (Set.member n defined)
  ]
  where
    defined = Set.fromList (tokenNames lexerGrammar ++ declaredTokens parserGrammar)

-- | The ways a grammar can be ill-formed short of failing to read.
data WellFormednessIssue
  = ActionValuedOptionOutsidePredicate Name
  | OptionsOnEmptyAlternative Name
  | CharSetInParserRule Name
  deriving (Eq, Show)

-- | Every issue of a grammar.
wellFormed :: Grammar ann -> [WellFormednessIssue]
wellFormed g = concatMap issuesOf (parserRules g)
  where
    issuesOf p =
      [ActionValuedOptionOutsidePredicate (parserRuleName p) | any actionValued (nonPredicateOptions p)]
        ++ [OptionsOnEmptyAlternative (parserRuleName p) | any emptyWithOptions (alternativesDeep p)]
        ++ [CharSetInParserRule (parserRuleName p) | any hasCharSet (parserRuleElements p)]
    alternativesDeep p = concatMap (alternativeDeep . labeledAlternativeBody) (NonEmpty.toList (parserRuleAlternatives p))
    alternativeDeep a = a : concat [concatMap alternativeDeep (NonEmpty.toList (blockAlternatives b)) | ElementBlock _ _ b _ <- alternativeElements a]
    emptyWithOptions a = not (null (alternativeOptions a)) && null (alternativeElements a)
    nonPredicateOptions p =
      concatMap alternativeOptions (alternativesDeep p)
        ++ concat [atomOptions a | ElementAtom _ _ a _ <- parserRuleElements p]
    atomOptions a = case a of
      AtomTerminal t -> terminalOptions t
      AtomRuleRef _ _ o -> o
      AtomNotSet (NotSet elements) -> concat [terminalOptions t | SetTerminal t <- NonEmpty.toList elements]
      AtomWildcard o -> o
    terminalOptions t = case t of
      TerminalToken _ o -> o
      TerminalLiteral _ o -> o
    actionValued o = case o of
      ElementOptionAssign _ (OptionValueAction _) -> True
      _ -> False
    hasCharSet e = case e of
      ElementAtom _ _ (AtomNotSet (NotSet elements)) _ -> any isCharSet (NonEmpty.toList elements)
      _ -> False
    isCharSet s = case s of
      SetCharSet _ -> True
      _ -> False
