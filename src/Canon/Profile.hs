-- | A language profile in canon.yaml is how a project declares a language: its grammar, extensions,
-- and for languages without a dialect the units and comment syntax. ref:DEC-comment-attachment
module Canon.Profile
  ( Profile (..)
  , GrammarSource (..)
  , UnitRule (..)
  , UnitName (..)
  , CommentSyntax (..)
  , Embedding (..)
  , DocStyle (..)
  , defaultCommentSyntax
  , profileForPath
  , profileOwns
  ) where

import Canon.Antlr4.Syntax (Name (..))
import Canon.Ignore (globMatches)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeFileName)

-- | A combined grammar file or a lexer and parser pair.
data GrammarSource
  = CombinedGrammarFile FilePath
  | SplitGrammarFiles FilePath FilePath
  deriving (Eq, Show)

-- | Where a unit's name comes from: a token by index anywhere under the rule, a token by index
-- among the rule's own tokens (so Go's method name is found past its receiver), a child rule, or
-- the unit's position among the units of its rule in its parent, counted from zero, for a unit
-- without a name of its own, such as a field of a Rust tuple struct. ref:DEC-rust-visibility
-- ref:DEC-more-languages
data UnitName
  = NameFromToken Name Int
  | NameFromDirectToken Name Int
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
--
-- An interpolation opener and closer, such as Elixir's #{ and }, mark code inside a string, which
-- may hold strings and braces of its own, so a quote inside it does not end the string around it.
-- ref:DEC-elixir-grammar
--
-- Where doc comments join across blank lines, as Gleam's /// lines do, doc comments that open alike
-- and stand apart only by blank lines are one comment, and blank lines below one do not part it from
-- its unit. A hidden tag, such as EDoc's @private, in a doc comment hides the unit it documents.
-- ref:DEC-gleam-grammar ref:DEC-hidden-label
data CommentSyntax = CommentSyntax
  { commentLine :: Maybe Text
  , commentBlockOpen :: Maybe Text
  , commentBlockClose :: Maybe Text
  , commentStringDelimiters :: [Text]
  , commentOuterDoc :: [Text]
  , commentInnerDoc :: [Text]
  , commentDocAttributes :: [Text]
  , commentDirectives :: [Text]
  , commentInterpolation :: Maybe (Text, Text)
  , commentJoinAcrossBlankLines :: Bool
  , commentHiddenTags :: [Text]
  }
  deriving (Eq, Show)

-- | No comments and double-quoted strings, the default for a dialect language.
defaultCommentSyntax :: CommentSyntax
defaultCommentSyntax = CommentSyntax Nothing Nothing Nothing ["\""] [] [] [] [] Nothing False []

-- | How a Folio page's fenced blocks of one language are read and tangled: the profile that parses
-- them, the comment syntax that must not appear in a block, the width a tangled line may have,
-- and how a generated documentation comment and banner are written. ref:DEC-folio-language
data Embedding = Embedding
  { embeddingLanguage :: Text
  , embeddingComments :: CommentSyntax
  , embeddingWidth :: Int
  , embeddingDoc :: DocStyle
  }
  deriving (Eq, Show)

-- | The spelling of a generated documentation comment: its opener, the prefix of every later
-- line, the text of a blank line, the prefix of a banner line, and the markup the comment is
-- converted to, haddock or plain. ref:DEC-tangle-output-format
data DocStyle = DocStyle
  { docOpen :: Text
  , docContinue :: Text
  , docBlank :: Text
  , docBanner :: Text
  , docMarkup :: Text
  }
  deriving (Eq, Show)

-- | A language profile. Its signatures map the extension of a signature file to the extension of
-- the implementation it declares, as F#'s .fsi declares a .fs: where both files of a name are
-- checked, the signature carries the comments and the implementation needs none. The highlight
-- map names, per class of the highlighter, the token names the grammar's own shape does not
-- classify, such as a directive that carries the rest of its line. ref:DEC-fsharp-signatures
-- ref:DEC-highlight-by-lexer Besides extensions, a profile may own files by name patterns, as
-- Pulumi owns Pulumi.yaml and Main.yaml but not every YAML file. ref:DEC-pulumi-yaml-grammar
data Profile = Profile
  { profileExtensions :: [Text]
  , profileGrammar :: GrammarSource
  , profileStart :: Name
  , profileUnits :: [UnitRule]
  , profileComments :: CommentSyntax
  , profileSignatures :: Map Text Text
  , profileEmbeds :: Map Text Embedding
  , profileHighlight :: Map Text [Text]
  , profileFiles :: [Text]
  }
  deriving (Eq, Show)

-- | The profile that owns a file: the first whose file name patterns match its name, or else the
-- first that owns its extension, so a profile for Pulumi.yaml is chosen over one for every YAML
-- file. ref:DEC-pulumi-yaml-grammar
profileForPath :: Map Text Profile -> FilePath -> Maybe (Text, Profile)
profileForPath profiles path =
  case [(lang, p) | (lang, p) <- Map.toList profiles, ownsByName p] ++ [(lang, p) | (lang, p) <- Map.toList profiles, ownsByExtension p] of
    (found : _) -> Just found
    [] -> Nothing
  where
    ownsByName p = any (`globMatches` T.pack (takeFileName path)) (profileFiles p)
    ownsByExtension p = any (`T.isSuffixOf` T.pack (takeFileName path)) (profileExtensions p)

-- | Whether a profile owns a file, by its name patterns or its extension, which is what the walk
-- asks of every file it finds.
profileOwns :: Profile -> FilePath -> Bool
profileOwns p path = any (`T.isSuffixOf` T.pack (takeFileName path)) (profileExtensions p) || any (`globMatches` T.pack (takeFileName path)) (profileFiles p)

instance ToJSON UnitName where
  toJSON n = case n of
    NameFromToken (Name t) index -> object ["index" .= index, "token" .= t]
    NameFromDirectToken (Name t) index -> object ["index" .= index, "token" .= t, "direct" .= True]
    NameFromRule (Name r) -> object ["rule" .= r]
    NameFromOrdinal -> object ["ordinal" .= True]

instance FromJSON UnitName where
  parseJSON = withObject "UnitName" $ \o -> do
    token <- o .:? "token"
    rule <- o .:? "rule"
    ordinal <- fromMaybe False <$> o .:? "ordinal"
    index <- fromMaybe 1 <$> o .:? "index"
    direct <- fromMaybe False <$> o .:? "direct"
    case (token, rule, ordinal) of
      (Just t, Nothing, False) -> pure ((if direct then NameFromDirectToken else NameFromToken) (Name t) index)
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
  toJSON (CommentSyntax line open close strings outer inner attributes directives interpolation joins hiddenTags) =
    object
      ( ["blockClose" .= close, "blockOpen" .= open, "line" .= line, "strings" .= strings]
          ++ ["outerDoc" .= outer | not (null outer)]
          ++ ["innerDoc" .= inner | not (null inner)]
          ++ ["docAttributes" .= attributes | not (null attributes)]
          ++ ["directives" .= directives | not (null directives)]
          ++ ["interpolation" .= [o, c] | Just (o, c) <- [interpolation]]
          ++ ["joinAcrossBlankLines" .= True | joins]
          ++ ["hiddenTags" .= hiddenTags | not (null hiddenTags)]
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
      <*> (o .:? "interpolation" >>= traverse pair)
      <*> (fromMaybe False <$> o .:? "joinAcrossBlankLines")
      <*> (fromMaybe [] <$> o .:? "hiddenTags")
    where
      pair xs = case xs of
        [open, close] -> pure (open, close)
        _ -> fail "an interpolation is an opener and a closer"

instance ToJSON DocStyle where
  toJSON (DocStyle open continue blank banner markup) = object ["banner" .= banner, "blank" .= blank, "continue" .= continue, "markup" .= markup, "open" .= open]

instance FromJSON DocStyle where
  parseJSON = withObject "DocStyle" $ \o ->
    DocStyle <$> o .: "open" <*> o .: "continue" <*> o .: "blank" <*> o .: "banner" <*> (fromMaybe "plain" <$> o .:? "markup")

instance ToJSON Embedding where
  toJSON (Embedding language comments width doc) = object ["comments" .= comments, "doc" .= doc, "language" .= language, "width" .= width]

instance FromJSON Embedding where
  parseJSON = withObject "Embedding" $ \o ->
    Embedding <$> o .: "language" <*> (fromMaybe defaultCommentSyntax <$> o .:? "comments") <*> (fromMaybe 98 <$> o .:? "width") <*> o .: "doc"

instance ToJSON Profile where
  toJSON p =
    object
      ( [ "comments" .= profileComments p
        , "extensions" .= profileExtensions p
        , "start" .= nameText (profileStart p)
        , "units" .= profileUnits p
        ]
          ++ ["signatures" .= profileSignatures p | not (Map.null (profileSignatures p))]
          ++ (if Map.null (profileEmbeds p) then [] else ["embeds" .= profileEmbeds p])
          ++ (if Map.null (profileHighlight p) then [] else ["highlight" .= profileHighlight p])
          ++ ["files" .= profileFiles p | not (null (profileFiles p))]
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
      <$> (fromMaybe [] <$> o .:? "extensions")
      <*> pure source
      <*> (Name <$> o .: "start")
      <*> (fromMaybe [] <$> o .:? "units")
      <*> (fromMaybe defaultCommentSyntax <$> o .:? "comments")
      <*> (fromMaybe Map.empty <$> o .:? "signatures")
      <*> (fromMaybe Map.empty <$> o .:? "embeds")
      <*> (fromMaybe Map.empty <$> o .:? "highlight")
      <*> (fromMaybe [] <$> o .:? "files")
