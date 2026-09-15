-- | Ignore patterns follow gitignore syntax because every developer already knows it.
module Canon.Ignore
  ( IgnorePattern (..)
  , parseIgnorePattern
  , parseIgnorePatterns
  , renderIgnorePattern
  , defaultIgnorePatterns
  , isIgnored
  , matchesPattern
  , globMatches
  ) where

import Data.List (inits)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T

-- | A parsed pattern: negation, anchoring, directory-only, and segments.
data IgnorePattern = IgnorePattern
  { patternNegated :: Bool
  , patternAnchored :: Bool
  , patternDirectoryOnly :: Bool
  , patternSegments :: [Text]
  }
  deriving (Eq, Show)

-- | Parses one pattern, rejecting the empty one.
parseIgnorePattern :: Text -> Maybe IgnorePattern
parseIgnorePattern raw
  | T.null trimmed || T.isPrefixOf "#" trimmed = Nothing
  | otherwise =
      let (negated, body) = case T.stripPrefix "!" trimmed of
            Just rest -> (True, rest)
            Nothing -> (False, trimmed)
          (directoryOnly, body') = case T.stripSuffix "/" body of
            Just rest -> (True, rest)
            Nothing -> (False, body)
          (leadingSlash, body'') = case T.stripPrefix "/" body' of
            Just rest -> (True, rest)
            Nothing -> (False, body')
          segments = filter (not . T.null) (T.splitOn "/" body'')
          anchored = leadingSlash || length segments > 1
       in if null segments then Nothing else Just (IgnorePattern negated anchored directoryOnly segments)
  where
    trimmed = T.strip raw

-- | Parses a list of patterns, dropping the unparsable.
parseIgnorePatterns :: [Text] -> [IgnorePattern]
parseIgnorePatterns = mapMaybe parseIgnorePattern

-- | Renders a pattern back to text.
renderIgnorePattern :: IgnorePattern -> Text
renderIgnorePattern p =
  T.concat
    [ if patternNegated p then "!" else ""
    , if patternAnchored p && length (patternSegments p) == 1 then "/" else ""
    , T.intercalate "/" (patternSegments p)
    , if patternDirectoryOnly p then "/" else ""
    ]

-- | The directories that never hold a project's own sources.
defaultIgnorePatterns :: [IgnorePattern]
defaultIgnorePatterns =
  parseIgnorePatterns
    [ ".git/"
    , ".canon-cache/"
    , ".hg/"
    , ".svn/"
    , "node_modules/"
    , "bower_components/"
    , "vendor/"
    , "third_party/"
    , ".stack-work/"
    , "dist/"
    , "dist-newstyle/"
    , ".cabal-sandbox/"
    , "target/"
    , "build/"
    , "out/"
    , ".venv/"
    , "venv/"
    , "__pycache__/"
    , ".idea/"
    , ".vscode/"
    , ".DS_Store"
    ]

-- | Decides whether a path is ignored, with a later negation overriding an earlier match.
isIgnored :: [IgnorePattern] -> Bool -> [Text] -> Bool
isIgnored patterns isDirectory segments = any ancestorIgnored (drop 1 (inits segments))
  where
    ancestorIgnored prefix =
      let directory = isDirectory || length prefix < length segments
       in decide directory prefix
    decide directory path = case [patternNegated p | p <- patterns, matchesPattern p directory path] of
      [] -> False
      verdicts -> not (last verdicts)

-- | Matches one pattern against path segments.
matchesPattern :: IgnorePattern -> Bool -> [Text] -> Bool
matchesPattern p isDirectory segments
  | patternDirectoryOnly p && not isDirectory = False
  | patternAnchored p = segmentsMatch (patternSegments p) segments
  | otherwise = case reverse segments of
      (final : _) -> globMatches (T.concat (patternSegments p)) final
      [] -> False

segmentsMatch :: [Text] -> [Text] -> Bool
segmentsMatch pattern path = case (pattern, path) of
  ([], []) -> True
  ([], _) -> False
  ("**" : rest, _) -> any (segmentsMatch rest) (suffixes path)
  (_, []) -> False
  (p : rest, s : more) -> globMatches p s && segmentsMatch rest more
  where
    suffixes xs = case xs of
      [] -> [[]]
      (_ : more) -> xs : suffixes more

-- | Matches one glob against one segment.
globMatches :: Text -> Text -> Bool
globMatches pattern subject = go (T.unpack pattern) (T.unpack subject)
  where
    go p s = case (p, s) of
      ([], []) -> True
      ('*' : rest, _) -> any (go rest) (tails' s)
      ('?' : rest, _ : more) -> go rest more
      ('[' : rest, c : more) -> case classMatch rest c of
        Just (matched, after) -> matched && go after more
        Nothing -> False
      ('\\' : x : rest, c : more) -> x == c && go rest more
      (x : rest, c : more) -> x == c && go rest more
      _ -> False
    tails' xs = case xs of
      [] -> [[]]
      (_ : more) -> xs : tails' more
    classMatch spec c =
      let (negated, body) = case spec of
            ('!' : more) -> (True, more)
            ('^' : more) -> (True, more)
            _ -> (False, spec)
       in case break (== ']') body of
            (members, ']' : after) -> Just (negated /= memberMatch members c, after)
            _ -> Nothing
    memberMatch members c = case members of
      (lo : '-' : hi : more) | hi /= ']' -> (c >= lo && c <= hi) || memberMatch more c
      (x : more) -> x == c || memberMatch more c
      [] -> False
