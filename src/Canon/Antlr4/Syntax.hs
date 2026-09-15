-- | The representation of an ANTLR grammar, annotated at every node, so that reading, printing,
-- querying, and interpreting all share one value. ref:DEC-parser-foundation
module Canon.Antlr4.Syntax
  ( Name (..)
  , QualifiedName (..)
  , StringLiteral (..)
  , CharSet (..)
  , ActionText (..)
  , ArgumentText (..)
  , Position (..)
  , Span (..)
  , Located (..)
  , Grammar (..)
  , GrammarKind (..)
  , Prequel (..)
  , Option (..)
  , OptionValue (..)
  , Import (..)
  , NamedAction (..)
  , Mode (..)
  , Rule (..)
  , ParserRule (..)
  , RuleModifier (..)
  , RulePrequel (..)
  , ExceptionHandler (..)
  , LabeledAlternative (..)
  , Alternative (..)
  , Element (..)
  , Label (..)
  , LabelKind (..)
  , ActionForm (..)
  , Atom (..)
  , Block (..)
  , EbnfSuffix (..)
  , Quantifier (..)
  , Greediness (..)
  , Terminal (..)
  , NotSet (..)
  , SetElement (..)
  , CharRange (..)
  , ElementOption (..)
  , LexerRule (..)
  , LexerAlternative (..)
  , LexerElement (..)
  , LexerAtom (..)
  , LexerCommand (..)
  , LexerCommandArgument (..)
  , isValidName
  , isNameStartChar
  , isNameChar
  , nameIsTokenName
  , reservedWords
  ) where

import Canon.Span (Located (..), Position (..), Span (..))
import Data.Char (isDigit, isUpper)
import Data.List.NonEmpty (NonEmpty)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

-- | A rule, token, or option name.
newtype Name = Name {nameText :: Text}
  deriving (Eq, Ord, Show)

-- | A dotted name, as superClass options use.
newtype QualifiedName = QualifiedName {qualifiedNameParts :: NonEmpty Name}
  deriving (Eq, Ord, Show)

-- | A literal kept raw, decoded only when needed.
newtype StringLiteral = StringLiteral {stringLiteralRaw :: Text}
  deriving (Eq, Ord, Show)

-- | A character set kept raw, decoded only when compiled.
newtype CharSet = CharSet {charSetRaw :: Text}
  deriving (Eq, Ord, Show)

-- | The raw text of an action, whose meaning belongs to a target language.
newtype ActionText = ActionText {actionTextRaw :: Text}
  deriving (Eq, Ord, Show)

-- | The raw text of an argument block.
newtype ArgumentText = ArgumentText {argumentTextRaw :: Text}
  deriving (Eq, Ord, Show)

-- | A grammar: kind, name, prequel, rules, and modes.
data Grammar ann = Grammar
  { grammarKind :: GrammarKind
  , grammarName :: Name
  , grammarPrequel :: [Prequel]
  , grammarRules :: [Rule ann]
  , grammarModes :: [Mode ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | Lexer, parser, or combined, which decides which rules are allowed.
data GrammarKind = LexerGrammar | ParserGrammar | CombinedGrammar
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The header constructs before the rules.
data Prequel
  = PrequelOptions [Option]
  | PrequelImports (NonEmpty Import)
  | PrequelTokens [Name]
  | PrequelChannels [Name]
  | PrequelAction (Maybe Name) NamedAction
  deriving (Eq, Show)

-- | One option with its value.
data Option = Option
  { optionName :: Name
  , optionValue :: OptionValue
  }
  deriving (Eq, Show)

-- | The forms an option value takes.
data OptionValue
  = OptionValueName QualifiedName
  | OptionValueString StringLiteral
  | OptionValueAction ActionText
  | OptionValueInt Integer
  deriving (Eq, Show)

-- | An import of another grammar.
data Import = Import
  { importLabel :: Maybe Name
  , importGrammar :: Name
  }
  deriving (Eq, Show)

-- | A named action with its scope.
data NamedAction = NamedAction
  { namedActionName :: Name
  , namedActionBody :: ActionText
  }
  deriving (Eq, Show)

-- | A lexer mode with its rules.
data Mode ann = Mode
  { modeAnn :: ann
  , modeName :: Name
  , modeRules :: [LexerRule ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A rule of either kind.
data Rule ann
  = RuleParser (ParserRule ann)
  | RuleLexer (LexerRule ann)
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A parser rule with all its optional parts.
data ParserRule ann = ParserRule
  { parserRuleAnn :: ann
  , parserRuleName :: Name
  , parserRuleModifiers :: [RuleModifier]
  , parserRuleArguments :: Maybe ArgumentText
  , parserRuleReturns :: Maybe ArgumentText
  , parserRuleThrows :: [QualifiedName]
  , parserRuleLocals :: Maybe ArgumentText
  , parserRulePrequel :: [RulePrequel]
  , parserRuleAlternatives :: NonEmpty (LabeledAlternative ann)
  , parserRuleHandlers :: [ExceptionHandler]
  , parserRuleFinally :: Maybe ActionText
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | The modifiers a rule may carry.
data RuleModifier
  = RuleModifierPublic
  | RuleModifierPrivate
  | RuleModifierProtected
  | RuleModifierFragment
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Options and actions before a rule body.
data RulePrequel
  = RulePrequelOptions [Option]
  | RulePrequelAction NamedAction
  deriving (Eq, Show)

-- | A catch clause on a rule.
data ExceptionHandler = ExceptionHandler
  { handlerArgument :: ArgumentText
  , handlerBody :: ActionText
  }
  deriving (Eq, Show)

-- | An alternative with its optional hash label.
data LabeledAlternative ann = LabeledAlternative
  { labeledAlternativeBody :: Alternative ann
  , labeledAlternativeLabel :: Maybe Name
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | One alternative with its options and elements.
data Alternative ann = Alternative
  { alternativeAnn :: ann
  , alternativeOptions :: [ElementOption]
  , alternativeElements :: [Element ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | An atom, a block, or an action, with its label and suffix.
data Element ann
  = ElementAtom ann (Maybe Label) Atom (Maybe EbnfSuffix)
  | ElementBlock ann (Maybe Label) (Block ann) (Maybe EbnfSuffix)
  | ElementAction ann ActionForm ActionText [ElementOption]
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | An element label with its kind.
data Label = Label
  { labelName :: Name
  , labelKind :: LabelKind
  }
  deriving (Eq, Show)

-- | Assignment or append.
data LabelKind = LabelAssign | LabelAppend
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | An action or a predicate.
data ActionForm = EmbeddedAction | SemanticPredicate
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | A terminal, rule reference, not-set, or wildcard.
data Atom
  = AtomTerminal Terminal
  | AtomRuleRef Name (Maybe ArgumentText) [ElementOption]
  | AtomNotSet NotSet
  | AtomWildcard [ElementOption]
  deriving (Eq, Show)

-- | A parenthesised group of alternatives.
data Block ann = Block
  { blockOptions :: [Option]
  , blockActions :: [NamedAction]
  , blockAlternatives :: NonEmpty (Alternative ann)
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A quantifier with its greediness.
data EbnfSuffix = EbnfSuffix Quantifier Greediness
  deriving (Eq, Ord, Show)

-- | Optional, zero or more, or one or more.
data Quantifier = Optional | ZeroOrMore | OneOrMore
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Greedy or non-greedy.
data Greediness = Greedy | NonGreedy
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | A token reference or a literal.
data Terminal
  = TerminalToken Name [ElementOption]
  | TerminalLiteral StringLiteral [ElementOption]
  deriving (Eq, Show)

-- | A negated set.
newtype NotSet = NotSet (NonEmpty SetElement)
  deriving (Eq, Show)

-- | One element of a set.
data SetElement
  = SetTerminal Terminal
  | SetRange CharRange
  | SetCharSet CharSet
  deriving (Eq, Show)

-- | A character range.
data CharRange = CharRange StringLiteral StringLiteral
  deriving (Eq, Show)

-- | An option on an element, such as assoc.
data ElementOption
  = ElementOptionFlag QualifiedName
  | ElementOptionAssign Name OptionValue
  deriving (Eq, Show)

-- | A lexer rule with its alternatives and options.
data LexerRule ann = LexerRule
  { lexerRuleAnn :: ann
  , lexerRuleName :: Name
  , lexerRuleIsFragment :: Bool
  , lexerRuleOptions :: [Option]
  , lexerRuleAlternatives :: NonEmpty (LexerAlternative ann)
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A lexer alternative with its commands.
data LexerAlternative ann = LexerAlternative
  { lexerAlternativeAnn :: ann
  , lexerAlternativeElements :: [LexerElement ann]
  , lexerAlternativeCommands :: [LexerCommand]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A lexer atom, block, or action with its suffix.
data LexerElement ann
  = LexerElementAtom ann LexerAtom (Maybe EbnfSuffix)
  | LexerElementBlock ann (NonEmpty (LexerAlternative ann)) (Maybe EbnfSuffix)
  | LexerElementAction ann ActionForm ActionText
  deriving (Eq, Show, Functor, Foldable, Traversable)

-- | A lexer atom: character set, terminal, not-set, or wildcard.
data LexerAtom
  = LexerAtomTerminal Terminal
  | LexerAtomRange CharRange
  | LexerAtomCharSet CharSet
  | LexerAtomNotSet NotSet
  | LexerAtomWildcard [ElementOption]
  deriving (Eq, Show)

-- | A lexer command with its optional argument.
data LexerCommand = LexerCommand
  { lexerCommandName :: Name
  , lexerCommandArgument :: Maybe LexerCommandArgument
  }
  deriving (Eq, Show)

-- | A command argument: a name or an integer.
data LexerCommandArgument
  = CommandArgumentName Name
  | CommandArgumentInt Integer
  deriving (Eq, Show)

-- | The characters that may start a name.
isNameStartChar :: Char -> Bool
isNameStartChar c =
  within 'A' 'Z'
    || within 'a' 'z'
    || c == '_'
    || within '\x00C0' '\x00D6'
    || within '\x00D8' '\x00F6'
    || within '\x00F8' '\x02FF'
    || within '\x0370' '\x037D'
    || within '\x037F' '\x1FFF'
    || within '\x200C' '\x200D'
    || within '\x2070' '\x218F'
    || within '\x2C00' '\x2FEF'
    || within '\x3001' '\xD7FF'
    || within '\xF900' '\xFDCF'
    || within '\xFDF0' '\xFFFD'
  where
    within lo hi = c >= lo && c <= hi

-- | The characters a name may contain.
isNameChar :: Char -> Bool
isNameChar c =
  isNameStartChar c
    || isDigit c
    || c == '\x00B7'
    || (c >= '\x0300' && c <= '\x036F')
    || (c >= '\x203F' && c <= '\x2040')

-- | Whether text is a valid name.
isValidName :: Text -> Bool
isValidName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) -> isNameStartChar c && T.all isNameChar rest

-- | Whether a name is a token name by its first letter, which is how ANTLR tells the two apart.
nameIsTokenName :: Name -> Bool
nameIsTokenName (Name t) = maybe False (isUpper . fst) (T.uncons t)

-- | The words ANTLR reserves.
reservedWords :: Set Text
reservedWords =
  Set.fromList
    [ "import"
    , "fragment"
    , "lexer"
    , "parser"
    , "grammar"
    , "protected"
    , "public"
    , "private"
    , "returns"
    , "locals"
    , "throws"
    , "catch"
    , "finally"
    , "mode"
    ]
