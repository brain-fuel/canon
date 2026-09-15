-- | The provisional attachment rule for languages without a dialect: a doc comment binds to the unit
-- directly below it. ref:DEC-comment-attachment
module Canon.Attach
  ( precedesImmediately
  , attachPreceding
  , attachPrecedingBruteForce
  , firstContentLine
  , topOfFileComment
  ) where

import Canon.Span (Located (..), Position (..), Span (..))
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

-- | The first non-blank line, where a file-level comment must start.
firstContentLine :: Text -> Int
firstContentLine source = case [n | (n, line) <- zip [1 ..] (T.lines source), not (T.null (T.strip line))] of
  (n : _) -> n
  [] -> 1

-- | Splits off the comment on the first content line, which binds to the file unit.
-- ref:DEC-comment-reasons
topOfFileComment :: Int -> [Located a] -> (Maybe (Located a), [Located a])
topOfFileComment line comments =
  case [c | c <- comments, spanStart (locatedSpan c) == Position line 1] of
    (c : _) -> (Just c, filter ((/= locatedSpan c) . locatedSpan) comments)
    [] -> (Nothing, comments)

-- | The adjacency rule itself: a blank line breaks the binding, because a blank line is the
-- universal sign that a comment stands alone.
precedesImmediately :: Span -> Span -> Bool
precedesImmediately comment target =
  commentEndLine + 1 == targetStartLine
    || (commentEndLine == targetStartLine && spanEnd comment <= spanStart target)
  where
    commentEndLine = positionLine (spanEnd comment)
    targetStartLine = positionLine (spanStart target)

-- | The all-pairs definition of attachment, kept as the reference the fast version is tested
-- against.
attachPrecedingBruteForce :: [Located a] -> [Located b] -> ([(Located a, Located b)], [Located a])
attachPrecedingBruteForce comments targets = go comments (sortOn locatedSpan targets)
  where
    go remaining ts = case ts of
      [] -> ([], remaining)
      (t : rest) ->
        case sortOn (Down . spanEnd . locatedSpan) [c | c <- remaining, precedesImmediately (locatedSpan c) (locatedSpan t)] of
          (best : _) ->
            let (pairs, orphans) = go (filter ((/= locatedSpan best) . locatedSpan) remaining) rest
             in ((best, t) : pairs, orphans)
          [] -> go remaining rest

-- | Attachment in one pass over both lists sorted by position.
attachPreceding :: [Located a] -> [Located b] -> ([(Located a, Located b)], [Located a])
attachPreceding comments targets = finish (foldl step (byEndLine, []) (sortOn locatedSpan targets))
  where
    byEndLine = Map.fromListWith (++) [(positionLine (spanEnd (locatedSpan c)), [c]) | c <- comments]
    step (available, pairs) t =
      let startLine = positionLine (spanStart (locatedSpan t))
          candidates =
            Map.findWithDefault [] (startLine - 1) available
              ++ filter (\c -> spanEnd (locatedSpan c) <= spanStart (locatedSpan t)) (Map.findWithDefault [] startLine available)
       in case sortOn (Down . spanEnd . locatedSpan) candidates of
            (best : _) ->
              let line = positionLine (spanEnd (locatedSpan best))
                  remaining = Map.adjust (filter ((/= locatedSpan best) . locatedSpan)) line available
               in (remaining, (best, t) : pairs)
            [] -> (available, pairs)
    finish (available, pairs) = (reverse pairs, sortOn locatedSpan (concat (Map.elems available)))
