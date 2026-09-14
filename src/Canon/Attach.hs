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

firstContentLine :: Text -> Int
firstContentLine source = case [n | (n, line) <- zip [1 ..] (T.lines source), not (T.null (T.strip line))] of
  (n : _) -> n
  [] -> 1

topOfFileComment :: Int -> [Located a] -> (Maybe (Located a), [Located a])
topOfFileComment line comments =
  case [c | c <- comments, spanStart (locatedSpan c) == Position line 1] of
    (c : _) -> (Just c, filter ((/= locatedSpan c) . locatedSpan) comments)
    [] -> (Nothing, comments)

precedesImmediately :: Span -> Span -> Bool
precedesImmediately comment target =
  commentEndLine + 1 == targetStartLine
    || (commentEndLine == targetStartLine && spanEnd comment <= spanStart target)
  where
    commentEndLine = positionLine (spanEnd comment)
    targetStartLine = positionLine (spanStart target)

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
