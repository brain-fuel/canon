-- | Tangling: the fenced blocks of Folio pages assembled into the source files they name, with a
-- banner and a documentation comment generated from each block's prose, byte for byte as
-- wavelet's tangler wrote them, so the first regeneration of an existing tree changes nothing.
-- A line map records where every tangled line came from, so a unit found in the tangled text is
-- reported in the page. ref:DEC-tangle-in-canon ref:DEC-tangle-output-format
module Canon.Tangle
  ( Origin (..)
  , Tangled (..)
  , assemble
  , docComment
  , sectionRef
  , wrapTo
  , toHaddock
  , originOf
  ) where

import Canon.Folio (Block (..))
import Canon.Profile (DocStyle (..), Embedding (..))
import Data.Char (isDigit, isSpace)
import Data.List (dropWhileEnd, nub)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeFileName)

-- | Where a tangled line came from: the banner, a generated comment of a block, a body line of a
-- block at a line of its page, or the blank line after a block.
data Origin
  = OriginBanner
  | OriginDoc FilePath Int
  | OriginBody FilePath Int
  | OriginBlank
  deriving (Eq, Show)

-- | One tangled file: its path, its text, the origin of each line, and the blocks it came from.
data Tangled = Tangled
  { tangledPath :: FilePath
  , tangledText :: Text
  , tangledOrigins :: [Origin]
  , tangledBlocks :: [Block]
  , tangledRanges :: [(Int, Int)]
  }
  deriving (Eq, Show)

-- | Assembles every file the blocks name, in the order the blocks were scanned: a banner naming
-- the pages, then each block's generated comment, its body, and a blank line, with trailing
-- blank lines trimmed.
assemble :: Embedding -> [Block] -> [Tangled]
assemble embedding blocks = [render file | file <- nub (map blockFile blocks)]
  where
    style = embeddingDoc embedding
    render file =
      let mine = [b | b <- blocks, blockFile b == file]
          sources = nub (map (takeFileName . blockSource) mine)
          banner =
            [ (docBanner style <> l, OriginBanner)
            | l <- ["Tangled from " <> T.intercalate ", " (map T.pack sources) <> ".", "Edit the specification, not this file.", "Every comment below is generated from the prose there."]
            , docMarkup style /= "none"
            ]
          -- A generated comment goes after the pragmas a block begins with, since a module's
          -- comment must follow its LANGUAGE pragmas and precede its module line.
          chunk b =
            let numbered = zip [1 ..] (blockBody b)
                (pragmas, rest) = span (\(_, l) -> "{-#" `T.isPrefixOf` l || T.null (T.strip l)) numbered
                (leading, following) = if any (\(_, l) -> "{-#" `T.isPrefixOf` l) pragmas then (pragmas, rest) else ([], numbered)
             in [(l, OriginBody (blockSource b) (blockLine b + i)) | (i, l) <- leading]
                  ++ [(l, OriginDoc (blockSource b) (blockLine b)) | l <- docComment embedding b]
                  ++ [(l, OriginBody (blockSource b) (blockLine b + i)) | (i, l) <- following]
                  ++ [("", OriginBlank)]
          chunks = map chunk mine
          body = dropWhileEnd (T.null . fst) (concat chunks)
          ls = banner ++ [("", OriginBlank)] ++ body
          starts = scanl (+) (length banner + 2) (map length chunks)
          ranges = [(from, from + length c - 2) | (from, c) <- zip starts chunks]
       in Tangled file (T.unlines (map fst ls)) (map snd ls) mine ranges

-- | The generated documentation comment of a block: its prose converted for the comment's markup,
-- wrapped to the width less the opener, a blank line, and the address of its section. Scaffolding
-- gets one only when its section carries prose, so a module header documented in its page has a
-- comment too. ref:DEC-header-blocks-documented
docComment :: Embedding -> Block -> [Text]
docComment embedding block
  | docMarkup style == "none" = []
  | null body = []
  | otherwise = case concatMap (wrapTo (embeddingWidth embedding - T.length (docOpen style))) (body ++ ["", sectionRef block]) of
      [] -> []
      first : rest -> ((docOpen style <> first) : map continuation rest) ++ [" */" | docMarkup style == "javadoc"]
  where
    style = embeddingDoc embedding
    convert = if docMarkup style == "haddock" then toHaddock else id
    body = dropWhileEnd T.null (map (convert . snd) (blockProse block))
    continuation l = if T.null l then docBlank style else docContinue style <> l

-- | Wraps one line at word boundaries to the width, a word longer than the width standing alone.
wrapTo :: Int -> Text -> [Text]
wrapTo n line
  | T.length line <= n = [line]
  | otherwise = fold (T.words line)
  where
    fold [] = []
    fold ws = let (taken, rest) = fill "" ws in taken : fold rest
    fill acc [] = (acc, [])
    fill acc (w : ws)
      | T.null acc = fill w ws
      | T.length acc + 1 + T.length w <= n = fill (acc <> " " <> w) ws
      | otherwise = (acc, w : ws)

-- | Markdown converted only where Haddock would render it wrongly: inline code and bold.
toHaddock :: Text -> Text
toHaddock = T.pack . go . T.unpack
  where
    go s = case s of
      '`' : rest -> case break (== '`') rest of
        (code, '`' : more) -> "@" ++ code ++ "@" ++ go more
        _ -> '`' : go rest
      '*' : '*' : rest -> case breakOn "**" rest of
        Just (strong, more) -> "__" ++ strong ++ "__" ++ go more
        Nothing -> '*' : '*' : go rest
      c : rest -> c : go rest
      [] -> []
    breakOn needle = search ""
      where
        search _ [] = Nothing
        search seen remainder@(c : more)
          | take (length needle) remainder == needle = Just (reverse seen, drop (length needle) remainder)
          | otherwise = search (c : seen) more

-- | The address a reader follows back: the page's name and the last numbered section above the
-- block, with S for the section sign so the repository holds only characters a person can type.
sectionRef :: Block -> Text
sectionRef block = "Specified by " <> spec <> section <> "."
  where
    spec = T.takeWhile (/= '.') (T.pack (takeFileName (blockSource block)))
    numbers = filter (not . T.null) (map (numberOf . snd) (blockSection block))
    numberOf title = T.dropWhileEnd (== '.') (T.takeWhile (\c -> isDigit c || c == '.') (T.dropWhile isSpace title))
    section = case numbers of
      [] -> ""
      ns -> " S" <> last ns

-- | The origin of a tangled line by number, for relocating a span.
originOf :: Tangled -> Int -> Maybe Origin
originOf t n
  | n >= 1, n <= length (tangledOrigins t) = Just (tangledOrigins t !! (n - 1))
  | otherwise = Nothing
