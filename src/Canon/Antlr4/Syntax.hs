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

import Data.Char (isDigit, isUpper)
import Data.List.NonEmpty (NonEmpty)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

newtype Name = Name {nameText :: Text}
  deriving (Eq, Ord, Show)

newtype QualifiedName = QualifiedName {qualifiedNameParts :: NonEmpty Name}
  deriving (Eq, Ord, Show)

newtype StringLiteral = StringLiteral {stringLiteralRaw :: Text}
  deriving (Eq, Ord, Show)

newtype CharSet = CharSet {charSetRaw :: Text}
  deriving (Eq, Ord, Show)

newtype ActionText = ActionText {actionTextRaw :: Text}
  deriving (Eq, Ord, Show)

newtype ArgumentText = ArgumentText {argumentTextRaw :: Text}
  deriving (Eq, Ord, Show)

data Position = Position
  { positionLine :: Int
  , positionColumn :: Int
  }
  deriving (Eq, Ord, Show)

data Span = Span
  { spanStart :: Position
  , spanEnd :: Position
  }
  deriving (Eq, Ord, Show)

data Located a = Located
  { locatedSpan :: Span
  , locatedValue :: a
  }
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

data Grammar ann = Grammar
  { grammarKind :: GrammarKind
  , grammarName :: Name
  , grammarPrequel :: [Prequel]
  , grammarRules :: [Rule ann]
  , grammarModes :: [Mode ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data GrammarKind = LexerGrammar | ParserGrammar | CombinedGrammar
  deriving (Eq, Ord, Show, Enum, Bounded)

data Prequel
  = PrequelOptions [Option]
  | PrequelImports (NonEmpty Import)
  | PrequelTokens [Name]
  | PrequelChannels [Name]
  | PrequelAction (Maybe Name) NamedAction
  deriving (Eq, Show)

data Option = Option
  { optionName :: Name
  , optionValue :: OptionValue
  }
  deriving (Eq, Show)

data OptionValue
  = OptionValueName QualifiedName
  | OptionValueString StringLiteral
  | OptionValueAction ActionText
  | OptionValueInt Integer
  deriving (Eq, Show)

data Import = Import
  { importLabel :: Maybe Name
  , importGrammar :: Name
  }
  deriving (Eq, Show)

data NamedAction = NamedAction
  { namedActionName :: Name
  , namedActionBody :: ActionText
  }
  deriving (Eq, Show)

data Mode ann = Mode
  { modeAnn :: ann
  , modeName :: Name
  , modeRules :: [LexerRule ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Rule ann
  = RuleParser (ParserRule ann)
  | RuleLexer (LexerRule ann)
  deriving (Eq, Show, Functor, Foldable, Traversable)

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

data RuleModifier
  = RuleModifierPublic
  | RuleModifierPrivate
  | RuleModifierProtected
  | RuleModifierFragment
  deriving (Eq, Ord, Show, Enum, Bounded)

data RulePrequel
  = RulePrequelOptions [Option]
  | RulePrequelAction NamedAction
  deriving (Eq, Show)

data ExceptionHandler = ExceptionHandler
  { handlerArgument :: ArgumentText
  , handlerBody :: ActionText
  }
  deriving (Eq, Show)

data LabeledAlternative ann = LabeledAlternative
  { labeledAlternativeBody :: Alternative ann
  , labeledAlternativeLabel :: Maybe Name
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Alternative ann = Alternative
  { alternativeAnn :: ann
  , alternativeOptions :: [ElementOption]
  , alternativeElements :: [Element ann]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Element ann
  = ElementAtom ann (Maybe Label) Atom (Maybe EbnfSuffix)
  | ElementBlock ann (Maybe Label) (Block ann) (Maybe EbnfSuffix)
  | ElementAction ann ActionForm ActionText [ElementOption]
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Label = Label
  { labelName :: Name
  , labelKind :: LabelKind
  }
  deriving (Eq, Show)

data LabelKind = LabelAssign | LabelAppend
  deriving (Eq, Ord, Show, Enum, Bounded)

data ActionForm = EmbeddedAction | SemanticPredicate
  deriving (Eq, Ord, Show, Enum, Bounded)

data Atom
  = AtomTerminal Terminal
  | AtomRuleRef Name (Maybe ArgumentText) [ElementOption]
  | AtomNotSet NotSet
  | AtomWildcard [ElementOption]
  deriving (Eq, Show)

data Block ann = Block
  { blockOptions :: [Option]
  , blockActions :: [NamedAction]
  , blockAlternatives :: NonEmpty (Alternative ann)
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data EbnfSuffix = EbnfSuffix Quantifier Greediness
  deriving (Eq, Ord, Show)

data Quantifier = Optional | ZeroOrMore | OneOrMore
  deriving (Eq, Ord, Show, Enum, Bounded)

data Greediness = Greedy | NonGreedy
  deriving (Eq, Ord, Show, Enum, Bounded)

data Terminal
  = TerminalToken Name [ElementOption]
  | TerminalLiteral StringLiteral [ElementOption]
  deriving (Eq, Show)

newtype NotSet = NotSet (NonEmpty SetElement)
  deriving (Eq, Show)

data SetElement
  = SetTerminal Terminal
  | SetRange CharRange
  | SetCharSet CharSet
  deriving (Eq, Show)

data CharRange = CharRange StringLiteral StringLiteral
  deriving (Eq, Show)

data ElementOption
  = ElementOptionFlag QualifiedName
  | ElementOptionAssign Name OptionValue
  deriving (Eq, Show)

data LexerRule ann = LexerRule
  { lexerRuleAnn :: ann
  , lexerRuleName :: Name
  , lexerRuleIsFragment :: Bool
  , lexerRuleOptions :: [Option]
  , lexerRuleAlternatives :: NonEmpty (LexerAlternative ann)
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data LexerAlternative ann = LexerAlternative
  { lexerAlternativeAnn :: ann
  , lexerAlternativeElements :: [LexerElement ann]
  , lexerAlternativeCommands :: [LexerCommand]
  }
  deriving (Eq, Show, Functor, Foldable, Traversable)

data LexerElement ann
  = LexerElementAtom ann LexerAtom (Maybe EbnfSuffix)
  | LexerElementBlock ann (NonEmpty (LexerAlternative ann)) (Maybe EbnfSuffix)
  | LexerElementAction ann ActionForm ActionText
  deriving (Eq, Show, Functor, Foldable, Traversable)

data LexerAtom
  = LexerAtomTerminal Terminal
  | LexerAtomRange CharRange
  | LexerAtomCharSet CharSet
  | LexerAtomNotSet NotSet
  | LexerAtomWildcard [ElementOption]
  deriving (Eq, Show)

data LexerCommand = LexerCommand
  { lexerCommandName :: Name
  , lexerCommandArgument :: Maybe LexerCommandArgument
  }
  deriving (Eq, Show)

data LexerCommandArgument
  = CommandArgumentName Name
  | CommandArgumentInt Integer
  deriving (Eq, Show)

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

isNameChar :: Char -> Bool
isNameChar c =
  isNameStartChar c
    || isDigit c
    || c == '\x00B7'
    || (c >= '\x0300' && c <= '\x036F')
    || (c >= '\x203F' && c <= '\x2040')

isValidName :: Text -> Bool
isValidName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) -> isNameStartChar c && T.all isNameChar rest

nameIsTokenName :: Name -> Bool
nameIsTokenName (Name t) = maybe False (isUpper . fst) (T.uncons t)

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
