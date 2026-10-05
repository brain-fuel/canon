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

-- | Where a unit's name comes from: a token by index, a child rule, or the unit's position among the
-- units of its rule in its parent, counted from zero, for a unit without a name of its own, such as
-- a field of a Rust tuple struct. ref:DEC-rust-visibility
data UnitName
  = NameFromToken Name Int
  | NameFromRule Name
  | NameFromOrdinal
  deriving (Eq, Show)

-- | A parse-tree rule that is a unit, for languages without a dialect. Several unit rules may name
-- one parse-tree rule, told apart by their first token, as ExUnit's test and describe calls are.
-- With clauses merged, adjacent matches of the rule with one name are one unit, as the clauses of an
-- Elixir function are one function, unless a doc comment directly above a later clause starts a new
-- unit, as the @doc of another arity does. ref:DEC-elixir-grammar
data UnitRule = UnitRule
  { unitRuleName :: Name
  , unitRuleKind :: Text
  , unitRuleNameSource :: UnitName
  , unitRuleRequired :: Bool
  , unitRuleFirstToken :: Maybe (Maybe Name, [Text])
  , unitRuleMergeClauses :: Bool
  }
  deriving (Eq, Show)

-- | The comment and string delimiters of a language without a dialect, and the openers of its doc
-- comments where the language tells them from plain comments, as Rust's /// and //! are told from
-- //. When outer openers are given, only a comment that starts with one binds to the unit below it;
-- a comment that starts with an inner opener belongs to the unit that encloses it, or to the file.
-- ref:DEC-rust-grammar
--
-- Doc attributes are the openers of documentation written as code rather than as a comment, as
-- Elixir's @doc and @moduledoc are: an attribute followed by a string, or by a sigil and a string,
-- is scanned as a comment whose text runs from the attribute to the end of the string, and its
-- body is the string's contents. A string delimiter of three or more characters, such as a
-- heredoc's, may span lines. ref:DEC-elixir-grammar
--
-- A line that starts with one of the directive openers, as C#'s #if and #pragma do, stands between
-- a doc comment and its unit without separating them. ref:DEC-csharp-grammar
data CommentSyntax = CommentSyntax
  { commentLine :: Maybe Text
  , commentBlockOpen :: Maybe Text
  , commentBlockClose :: Maybe Text
  , commentStringDelimiters :: [Text]
  , commentOuterDoc :: [Text]
  , commentInnerDoc :: [Text]
  , commentDocAttributes :: [Text]
  , commentDirectives :: [Text]
  }
  deriving (Eq, Show)

-- | No comments and double-quoted strings, the default for a dialect language.
defaultCommentSyntax :: CommentSyntax
defaultCommentSyntax = CommentSyntax Nothing Nothing Nothing ["\""] [] [] [] []

-- | A language profile. Its signatures map the extension of a signature file to the extension of
-- the implementation it declares, as F#'s .fsi declares a .fs: where both files of a name are
-- checked, the signature carries the comments and the implementation needs none.
-- ref:DEC-fsharp-signatures
data Profile = Profile
  { profileExtensions :: [Text]
  , profileGrammar :: GrammarSource
  , profileStart :: Name
  , profileUnits :: [UnitRule]
  , profileComments :: CommentSyntax
  , profileSignatures :: Map Text Text
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
    NameFromOrdinal -> object ["ordinal" .= True]

instance FromJSON UnitName where
  parseJSON = withObject "UnitName" $ \o -> do
    token <- o .:? "token"
    rule <- o .:? "rule"
    ordinal <- fromMaybe False <$> o .:? "ordinal"
    index <- fromMaybe 1 <$> o .:? "index"
    case (token, rule, ordinal) of
      (Just t, Nothing, False) -> pure (NameFromToken (Name t) index)
      (Nothing, Just r, False) -> pure (NameFromRule (Name r))
      (Nothing, Nothing, True) -> pure NameFromOrdinal
      _ -> fail "a unit name comes from exactly one of token, rule, or ordinal"

instance ToJSON UnitRule where
  toJSON (UnitRule (Name rule) kind name required firstToken merge) =
    object
      ( [ "firstToken" .= fmap (\(token, texts) -> object ["token" .= fmap nameText token, "oneOf" .= texts]) firstToken
        , "kind" .= kind
        , "name" .= name
        , "required" .= required
        , "rule" .= rule
        ]
          ++ ["mergeClauses" .= True | merge]
      )

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
      <*> (fromMaybe False <$> o .:? "mergeClauses")

instance ToJSON CommentSyntax where
  toJSON (CommentSyntax line open close strings outer inner attributes directives) =
    object
      ( ["blockClose" .= close, "blockOpen" .= open, "line" .= line, "strings" .= strings]
          ++ ["outerDoc" .= outer | not (null outer)]
          ++ ["innerDoc" .= inner | not (null inner)]
          ++ ["docAttributes" .= attributes | not (null attributes)]
          ++ ["directives" .= directives | not (null directives)]
      )

instance FromJSON CommentSyntax where
  parseJSON = withObject "CommentSyntax" $ \o ->
    CommentSyntax
      <$> o .:? "line"
      <*> o .:? "blockOpen"
      <*> o .:? "blockClose"
      <*> (fromMaybe ["\""] <$> o .:? "strings")
      <*> (fromMaybe [] <$> o .:? "outerDoc")
      <*> (fromMaybe [] <$> o .:? "innerDoc")
      <*> (fromMaybe [] <$> o .:? "docAttributes")
      <*> (fromMaybe [] <$> o .:? "directives")

instance ToJSON Profile where
  toJSON p =
    object
      ( [ "comments" .= profileComments p
        , "extensions" .= profileExtensions p
        , "start" .= nameText (profileStart p)
        , "units" .= profileUnits p
        ]
          ++ ["signatures" .= profileSignatures p | not (Map.null (profileSignatures p))]
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
      <*> (fromMaybe Map.empty <$> o .:? "signatures")
