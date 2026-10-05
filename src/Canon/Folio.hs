-- | A Folio page as canon reads it: the front matter, the prose, and the fenced blocks with the
-- section and the prose that belong to each, scanned from the parse tree of the Folio grammar.
-- The rules of what a block's prose is follow wavelet's tangler, which this replaces: prose
-- accumulates from the last heading, blank lines are kept once prose has started, and a tangled
-- block clears it so two blocks under one heading do not both claim the same paragraphs.
-- ref:DEC-folio-language ref:DEC-section-prose-is-why
module Canon.Folio
  ( Document (..)
  , Block (..)
  , Element (..)
  , scanDocument
  , elementsOf
  , attributes
  , frontMatterOf
  , quadrants
  ) where

import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Syntax (Name (..), nameText)
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.Span (Position (..))
import Data.Char (isSpace)

import Data.Map.Strict (Map)
import Data.Maybe (mapMaybe)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | A fenced block that tangles: where it is, the file and name it declares, whether it is
-- scaffolding, the headings above it with their depths, the prose since the last heading with
-- line numbers, and its body.
data Block = Block
  { blockSource :: FilePath
  , blockLine :: Int
  , blockLanguage :: Text
  , blockFile :: FilePath
  , blockName :: Text
  , blockIsPart :: Bool
  , blockDeclared :: Bool
  , blockSection :: [(Int, Text)]
  , blockProse :: [(Int, Text)]
  , blockBody :: [Text]
  }
  deriving (Eq, Show)

-- | A page: its path, its front-matter fields with the lines they span, every prose line with
-- its number, and its tangled blocks in order.
data Document = Document
  { docPath :: FilePath
  , docFront :: Map Text Text
  , docFrontSpan :: Maybe (Int, Int)
  , docProse :: [(Int, Text)]
  , docBlocks :: [Block]
  , docElements :: [Element]
  }
  deriving (Eq, Show)

-- | One element of a page, read from the parse tree with the line it starts on.
data Element
  = ElementHeading Int Int Text
  | ElementFence Int Text [Text]
  | ElementProse Int Text
  | ElementRule Int
  | ElementBlank Int
  deriving (Eq, Show)

-- | The four Diátaxis quadrants a page's kind may name, and the directory each lives in.
quadrants :: [(Text, FilePath)]
quadrants = [("tutorial", "tutorials"), ("how-to", "how-to"), ("reference", "reference"), ("explanation", "explanation")]

-- | The elements of a page's parse tree, in order.
elementsOf :: ParseTree -> (Maybe ((Int, Int), [Text]), [Element])
elementsOf tree = (front, concatMap element (children tree))
  where
    children node = case node of
      RuleNode _ _ ns -> ns
      Labeled _ inner -> [inner]
      TokenNode _ -> []
    front = case [n | n@(RuleNode (Name "frontMatter") _ _) <- children tree] of
      (n : _) ->
        let toks = real n
            fields = [tokenText t | t <- toks, nameText (tokenType t) == "PROSE"]
         in case (toks, reverse toks) of
              (first : _, final : _) -> Just ((lineOf first, lineOf final), fields)
              _ -> Nothing
      [] -> Nothing
    element node = case node of
      RuleNode (Name "element") _ ns -> concatMap element ns
      RuleNode (Name "heading") _ _ -> case real node of
        (t : _) -> let (hashes, rest) = T.span (== '#') (tokenText t) in [ElementHeading (lineOf t) (T.length hashes) (T.strip rest)]
        [] -> []
      RuleNode (Name "codeBlock") _ ns -> case real node of
        (t : _) ->
          let info = T.strip (T.dropWhile (== '`') (tokenText t))
              body = [lineText n | n@(RuleNode (Name "codeLine") _ _) <- ns]
           in [ElementFence (lineOf t) info body]
        [] -> []
      RuleNode (Name "prose") _ _ -> [ElementProse (lineOf t) (tokenText t) | t <- take 1 (real node)]
      RuleNode (Name "rule") _ _ -> [ElementRule (lineOf t) | t <- take 1 (real node)]
      RuleNode (Name "blank") _ _ -> [ElementBlank (lineOf t) | t <- take 1 (real node)]
      _ -> []
    lineText n = case [tokenText t | t <- real n, nameText (tokenType t) == "CODE_LINE"] of
      (l : _) -> l
      [] -> ""
    real n = [t | t <- treeTokens n, not (isEofToken t)]
    lineOf t = positionLine (tokenPosition t)

-- | The key and value pairs of an info string: words of the form key=value, in order.
attributes :: Text -> [(Text, Text)]
attributes info = mapMaybe attribute (T.words info)
  where
    attribute w = case T.breakOn "=" w of
      (k, v) | not (T.null k), T.length v > 1 -> Just (k, T.drop 1 v)
      _ -> Nothing

-- | Front-matter fields as key and value, one per line, the value trimmed.
frontMatterOf :: [Text] -> Map Text Text
frontMatterOf fields = Map.fromList (mapMaybe field fields)
  where
    field f = case T.breakOn ":" f of
      (k, v) | not (T.null k), not (T.null v) -> Just (T.strip k, T.strip (T.drop 1 v))
      _ -> Nothing

-- | Scans a page: headings keep a trail by depth, prose gathers from the last heading and is
-- cleared by a tangled block, and a block without file= is an illustration that is never
-- tangled and leaves the prose in place. Front-matter fields are not prose.
scanDocument :: FilePath -> ParseTree -> Document
scanDocument path tree = go [] [] [] [] elements
  where
    (front, elements) = elementsOf tree
    frontFields = maybe Map.empty (frontMatterOf . snd) front
    go trail prose blocks allProse es = case es of
      [] -> Document path frontFields (fst <$> front) (reverse allProse) (reverse blocks) elements
      ElementHeading n depth title : rest -> go (filter ((< depth) . fst) trail ++ [(depth, title)]) [] blocks ((n, T.replicate depth "#" <> " " <> title) : allProse) rest
      ElementFence n info body : rest ->
        let attrs = attributes info
            language = T.takeWhile (not . isSpace) info
         in case lookup "file" attrs of
              Nothing -> go trail prose blocks allProse rest
              Just file ->
                let name = lookup "def" attrs
                    part = lookup "part" attrs
                    block =
                      Block
                        { blockSource = path
                        , blockLine = n
                        , blockLanguage = language
                        , blockFile = T.unpack file
                        , blockName = maybe (maybe "?" id part) id name
                        , blockIsPart = part /= Nothing
                        , blockDeclared = name /= Nothing || part /= Nothing
                        , blockSection = trail
                        , blockProse = reverse prose
                        , blockBody = body
                        }
                 in go trail [] (block : blocks) allProse rest
      ElementProse n line : rest -> go trail ((n, line) : prose) blocks ((n, line) : allProse) rest
      ElementRule _ : rest -> go trail prose blocks allProse rest
      ElementBlank n : rest
        | null prose -> go trail prose blocks allProse rest
        | otherwise -> go trail ((n, "") : prose) blocks ((n, "") : allProse) rest

