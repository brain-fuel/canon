-- | A language profile in canon.yaml is how a project declares a language: its grammar, extensions,
-- and for languages without a dialect the units and comment syntax. ref:DEC-comment-attachment
module Canon.Profile
  ( Profile (..)
  , GrammarSource (..)
  , UnitRule (..)
  , UnitName (..)
  , CommentSyntax (..)
  , defaultCommentSyntax
  , profileForPath
  ) where

import Canon.Antlr4.Syntax (Name (..))
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeExtension)

-- | A combined grammar file or a lexer and parser pair.
data GrammarSource
  = CombinedGrammarFile FilePath
  | SplitGrammarFiles FilePath FilePath
  deriving (Eq, Show)

-- | Where a unit's name comes from: a token by index or a child rule.
data UnitName
  = NameFromToken Name Int
  | NameFromRule Name
  deriving (Eq, Show)

-- | A parse-tree rule that is a unit, for languages without a dialect.
data UnitRule = UnitRule
  { unitRuleName :: Name
  , unitRuleKind :: Text
  , unitRuleNameSource :: UnitName
  , unitRuleRequired :: Bool
  , unitRuleFirstToken :: Maybe (Maybe Name, [Text])
  }
  deriving (Eq, Show)

-- | The comment and string delimiters of a language without a dialect.
data CommentSyntax = CommentSyntax
  { commentLine :: Maybe Text
  , commentBlockOpen :: Maybe Text
  , commentBlockClose :: Maybe Text
  , commentStringDelimiters :: [Text]
  }
  deriving (Eq, Show)

-- | No comments and double-quoted strings, the default for a dialect language.
defaultCommentSyntax :: CommentSyntax
defaultCommentSyntax = CommentSyntax Nothing Nothing Nothing ["\""]

-- | A language profile.
data Profile = Profile
  { profileExtensions :: [Text]
  , profileGrammar :: GrammarSource
  , profileStart :: Name
  , profileUnits :: [UnitRule]
  , profileComments :: CommentSyntax
  }
  deriving (Eq, Show)

-- | The profile that owns a file's extension.
profileForPath :: Map Text Profile -> FilePath -> Maybe (Text, Profile)
profileForPath profiles path =
  case [(lang, p) | (lang, p) <- Map.toList profiles, T.pack (takeExtension path) `elem` profileExtensions p] of
    (found : _) -> Just found
    [] -> Nothing

instance ToJSON UnitName where
  toJSON n = case n of
    NameFromToken (Name t) index -> object ["index" .= index, "token" .= t]
    NameFromRule (Name r) -> object ["rule" .= r]

instance FromJSON UnitName where
  parseJSON = withObject "UnitName" $ \o -> do
    token <- o .:? "token"
    rule <- o .:? "rule"
    index <- fromMaybe 1 <$> o .:? "index"
    case (token, rule) of
      (Just t, Nothing) -> pure (NameFromToken (Name t) index)
      (Nothing, Just r) -> pure (NameFromRule (Name r))
      _ -> fail "a unit name comes from exactly one of token or rule"

instance ToJSON UnitRule where
  toJSON (UnitRule (Name rule) kind name required firstToken) =
    object
      [ "firstToken" .= fmap (\(token, texts) -> object ["token" .= fmap nameText token, "oneOf" .= texts]) firstToken
      , "kind" .= kind
      , "name" .= name
      , "required" .= required
      , "rule" .= rule
      ]

instance FromJSON UnitRule where
  parseJSON = withObject "UnitRule" $ \o -> do
    firstToken <- o .:? "firstToken"
    constraint <- case firstToken of
      Nothing -> pure Nothing
      Just inner -> flip (withObject "firstToken") inner $ \f -> Just <$> ((,) <$> (fmap Name <$> f .:? "token") <*> f .: "oneOf")
    UnitRule
      <$> (Name <$> o .: "rule")
      <*> o .: "kind"
      <*> o .: "name"
      <*> (fromMaybe True <$> o .:? "required")
      <*> pure constraint

instance ToJSON CommentSyntax where
  toJSON (CommentSyntax line open close strings) =
    object ["blockClose" .= close, "blockOpen" .= open, "line" .= line, "strings" .= strings]

instance FromJSON CommentSyntax where
  parseJSON = withObject "CommentSyntax" $ \o ->
    CommentSyntax
      <$> o .:? "line"
      <*> o .:? "blockOpen"
      <*> o .:? "blockClose"
      <*> (fromMaybe ["\""] <$> o .:? "strings")

instance ToJSON Profile where
  toJSON p =
    object
      ( [ "comments" .= profileComments p
        , "extensions" .= profileExtensions p
        , "start" .= nameText (profileStart p)
        , "units" .= profileUnits p
        ]
          ++ case profileGrammar p of
            CombinedGrammarFile path -> ["grammar" .= path]
            SplitGrammarFiles lexer parser -> ["lexer" .= lexer, "parser" .= parser]
      )

instance FromJSON Profile where
  parseJSON = withObject "Profile" $ \o -> do
    grammar <- o .:? "grammar"
    lexer <- o .:? "lexer"
    parser <- o .:? "parser"
    source <- case (grammar, lexer, parser) of
      (Just g, Nothing, Nothing) -> pure (CombinedGrammarFile g)
      (Nothing, Just l, Just p) -> pure (SplitGrammarFiles l p)
      _ -> fail "a profile names either grammar, or both lexer and parser"
    Profile
      <$> o .: "extensions"
      <*> pure source
      <*> (Name <$> o .: "start")
      <*> (fromMaybe [] <$> o .:? "units")
      <*> (fromMaybe defaultCommentSyntax <$> o .:? "comments")
