-- | The body of a canonical comment and its citations, normalised the same way whatever language it
-- came from. ref:DEC-comment-reasons
module Canon.CanonicalComment
  ( CanonicalComment (..)
  , docCommentBody
  , dialectCommentBody
  , docStringBody
  , referenceTokens
  , licenseTokens
  , mentionsLicense
  , parseCanonicalComment
  , toWhy
  ) where

import Canon.Model.Answer (Why (..))
import Canon.Model.Id (ReferenceKey (..), isReferenceKey)
import Data.Char (isAlpha, isAsciiLower, isDigit)
import Data.List (nub)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T

-- | The three things a comment can carry: prose, references, and licenses.
data CanonicalComment = CanonicalComment
  { canonicalWhy :: Text
  , canonicalReferences :: [ReferenceKey]
  , canonicalLicenses :: [ReferenceKey]
  }
  deriving (Eq, Show)

-- | Strips the delimiters and line markers of every supported comment form, so the Why is prose
-- alone. The /// and //! of Rust, C#, and F# doc lines are line markers, and so is the plain // of
-- a Go doc comment, whose block form opens with a plain /*. ref:DEC-rust-dialect ref:DEC-go-dialect
-- The %, %%, and %! of PlDoc lines are line markers too. ref:DEC-prolog-dialect A comment opened
-- with a hash, two slashes, or a slash and one star, as HCL and YAML write them, may be several
-- comment lines joined, and each line loses its own markers, with the ! of an inner Rust doc line
-- and the | of a Make or Haddock-style line.
-- ref:DEC-hcl-grammar ref:DEC-pulumi-yaml-grammar
docCommentBody :: Text -> Text
docCommentBody raw
  | plainOpener (T.stripStart raw) = T.strip (T.intercalate "\n" (map stripPlainLine (filter (not . isDirective) (T.lines raw))))
  | otherwise = T.strip (T.intercalate "\n" (map stripLineMarker (T.lines (stripDelimiters raw))))
  where
    stripDelimiters t = foldr dropSuffix (foldr dropPrefix (T.strip t) ["/*", "/**", "/*!", "{-|", "--|", "-- |", "#|", "# |"]) ["*/", "-}"]
    dropPrefix p t = maybe t id (T.stripPrefix p t)
    dropSuffix s t = maybe t id (T.stripSuffix s t)
    stripLineMarker line = T.strip (withoutMarker (T.stripStart line))
    withoutMarker trimmed
      | Just rest <- T.stripPrefix "///" trimmed = rest
      | Just rest <- T.stripPrefix "//!" trimmed = rest
      | Just rest <- T.stripPrefix "//" trimmed = rest
      | Just rest <- T.stripPrefix "--" trimmed = maybe rest id (T.stripPrefix "|" (T.stripStart rest))
      | Just rest <- T.stripPrefix "#" trimmed = maybe rest id (T.stripPrefix "|" (T.stripStart rest))
      | Just rest <- T.stripPrefix "%" trimmed = T.dropWhile (`elem` ("%!" :: String)) rest
      | otherwise = maybe trimmed id (T.stripPrefix "*" trimmed)
    -- A tool directive among // lines, such as //go:generate, //nolint, or // +build, is no prose,
    -- as go/doc leaves it out of a doc comment. ref:DEC-go-dialect ref:go-doc-comments
    isDirective line = case T.stripPrefix "//" (T.stripStart line) of
      Just rest ->
        let (word, after) = T.span (\c -> isAsciiLower c || isDigit c) rest
         in any (`T.isPrefixOf` rest) ["line ", "extern ", "export ", "nolint", " +build"]
              || (not (T.null word) && maybe False (\(c, more) -> c == ':' && maybe False (\(d, _) -> isAsciiLower d || isDigit d) (T.uncons more)) (T.uncons after))
      Nothing -> False
    plainOpener t = "#" `T.isPrefixOf` t || "//" `T.isPrefixOf` t || ("/*" `T.isPrefixOf` t && not ("/**" `T.isPrefixOf` t))
    stripPlainLine line =
      let trimmed = T.strip line
          unclosed = T.strip (maybe trimmed id (T.stripSuffix "*/" trimmed))
          unopened
            | "/*" `T.isPrefixOf` unclosed = T.drop 2 unclosed
            | "//" `T.isPrefixOf` unclosed = T.dropWhile (== '/') unclosed
            | "#" `T.isPrefixOf` unclosed = T.dropWhile (== '#') unclosed
            | "*" `T.isPrefixOf` unclosed = T.drop 1 unclosed
            | otherwise = unclosed
          marked = unopened /= unclosed
       in T.strip (case T.uncons (T.stripStart unopened) of
            Just (c, rest) | marked, c `elem` ("!|" :: String) -> rest
            _ -> unopened)

-- | The prose of a canonical comment a dialect grammar matched, which is the comment's own text, so
-- its form is known from how it opens. Documentation written as an attribute, as Elixir's @doc and
-- Erlang's -doc are, is the contents of its string, dedented; line comments opened with slashes, as
-- Gleam's /// and ////, lose those marks on every line; every other form, among them Erlang's
-- %% @doc and Prolog's %!, is read as docCommentBody reads it, line by line.
-- ref:DEC-elixir-dialect ref:DEC-gleam-dialect
-- ref:DEC-erlang-dialect
dialectCommentBody :: Text -> Text
dialectCommentBody raw
  | Just body <- attributeBody stripped = body
  | "///" `T.isPrefixOf` stripped = withoutLeading '/'
  | otherwise = docCommentBody raw
  where
    stripped = T.strip raw
    withoutLeading c = dedent [T.dropWhile (== c) (T.stripStart line) | line <- T.lines raw]

-- | The string of a documentation attribute, such as @doc """...""" or -doc("...")., without the
-- attribute, a sigil, the delimiters, or what follows the string.
attributeBody :: Text -> Maybe Text
attributeBody t = do
  name <- case [n | n <- ["@moduledoc", "@typedoc", "@doc", "-moduledoc", "-doc"], n `T.isPrefixOf` t] of
    (n : _) -> Just n
    [] -> Nothing
  let afterName = T.stripStart (T.drop (T.length name) t)
      afterParen = T.stripStart (maybe afterName id (T.stripPrefix "(" afterName))
      afterSigil = case T.uncons afterParen of
        Just ('~', rest) -> T.dropWhile isAlpha rest
        _ -> afterParen
  delimiter <- case [d | d <- ["\"\"\"\"", "\"\"\"", "'''", "\""], d `T.isPrefixOf` afterSigil] of
    (d : _) -> Just d
    [] -> Nothing
  let inside = T.drop (T.length delimiter) afterSigil
      (body, _) = T.breakOnEnd delimiter inside
  pure (dedent (T.lines (maybe body id (T.stripSuffix delimiter body))))

-- | Lines with their common indentation removed and the whole stripped, as a heredoc's contents are
-- read.
dedent :: [Text] -> Text
dedent ls =
  let indents = [T.length (T.takeWhile (== ' ') l) | l <- ls, not (T.null (T.strip l))]
      margin = if null indents then 0 else minimum indents
   in T.strip (T.intercalate "\n" [T.stripEnd (T.drop margin l) | l <- ls])

-- | The prose of documentation written as data rather than as a comment: a quoted string, a
-- heredoc, or a YAML block or plain scalar, as an HCL description or a Pulumi config description
-- is, without its quotes, header, or indentation. ref:DEC-hcl-grammar ref:DEC-pulumi-yaml-grammar
docStringBody :: Text -> Text
docStringBody raw = case T.uncons stripped of
  Just ('"', rest) | Just inner <- T.stripSuffix "\"" rest -> T.strip (unescape inner)
  Just ('\'', rest) | Just inner <- T.stripSuffix "'" rest -> T.strip (T.replace "''" "'" inner)
  Just ('<', _) | "<<" `T.isPrefixOf` stripped -> heredoc
  Just (c, _) | c `elem` ("|>" :: String) -> blockScalar c
  _ -> T.unwords (filter (not . T.null) (map T.strip (T.lines stripped)))
  where
    stripped = T.strip raw
    bodyLines = drop 1 (T.lines stripped)
    heredoc =
      let word = T.strip (T.dropWhile (`elem` ("<-" :: String)) (T.takeWhile (/= '\n') stripped))
          content = case reverse bodyLines of
            (lastLine : before) | T.strip lastLine == word -> reverse before
            _ -> bodyLines
       in T.strip (T.intercalate "\n" (dedentLines content))
    blockScalar indicator =
      let content = dedentLines bodyLines
       in T.strip (if indicator == '>' then T.unwords (filter (not . T.null) (map T.strip content)) else T.intercalate "\n" content)
    dedentLines ls =
      let indents = [T.length (T.takeWhile (== ' ') l) | l <- ls, not (T.null (T.strip l))]
          common = if null indents then 0 else minimum indents
       in map (T.stripEnd . T.drop common) ls
    unescape t = case T.breakOn "\\" t of
      (before, after) -> case T.unpack (T.take 2 after) of
        ['\\', c] -> before <> T.singleton (escaped c) <> unescape (T.drop 2 after)
        _ -> before <> after
    escaped c = case c of
      'n' -> '\n'
      't' -> '\t'
      other -> other

referencePrefix :: Text
referencePrefix = "ref:"

licensePrefix :: Text
licensePrefix = "license:"

keyedTokens :: Text -> Text -> [ReferenceKey]
keyedTokens prefix = nub . mapMaybe keyOf . T.words
  where
    keyOf token = do
      rest <- T.stripPrefix prefix token
      let key = T.dropWhileEnd (`elem` (".,;:)!?" :: String)) (T.takeWhile (/= '<') rest)
      if isReferenceKey key then Just (ReferenceKey key) else Nothing

-- | The ref keys cited in a body, in order and without repeats. A key ends where markup starts, so a
-- key closed by an XML tag in a C# or F# doc comment is cited without the tag. ref:DEC-csharp-grammar
referenceTokens :: Text -> [ReferenceKey]
referenceTokens = keyedTokens referencePrefix

-- | The license keys cited in a body.
licenseTokens :: Text -> [ReferenceKey]
licenseTokens = keyedTokens licensePrefix

-- | Parses a raw comment into its body and citations, for languages without a dialect.
parseCanonicalComment :: Text -> CanonicalComment
parseCanonicalComment raw =
  let body = docCommentBody raw
   in CanonicalComment body (referenceTokens body) (licenseTokens body)

-- | Converts a parsed comment into the model's Why.
toWhy :: CanonicalComment -> Why
toWhy (CanonicalComment body references licenses) = Why body references licenses

-- | Detects text that reads like a license notice, so a notice without a license key is reported.
mentionsLicense :: Text -> Bool
mentionsLicense body =
  any (`T.isInfixOf` T.toLower body) ["copyright", "all rights reserved", "licensed under", "spdx-license-identifier", "the \"bsd license\"", "mit license", "apache license", "gnu general public license"]
