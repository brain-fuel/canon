-- | Weaving: a project's Folio pages rendered to a static site, one HTML page per document under
-- its quadrant and an index of the four, deterministic down to the byte so two renders of one
-- tree are one site. The renderer is canon's own, small and complete for what pages use:
-- headings, paragraphs, lists, quotations, tables, fenced blocks, code spans, emphasis, links,
-- and citations, which link to what they cite. ref:DEC-site-renderer ref:DEC-docs-tree
module Canon.Weave
  ( Resolve
  , Highlight
  , renderPage
  , renderIndex
  , pagePath
  , embedOf
  , escape
  , style
  ) where

import Canon.Folio (Document (..), Element (..), quadrants)
import Canon.Highlight (Piece (..))
import Canon.Model.Id (ReferenceKey (..), isReferenceKey)
import Data.Char (isDigit, isSpace)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (splitDirectories, takeFileName, (</>))

-- | What a citation resolves to: a title and a locator, from the registry or the ledger.
type Resolve = ReferenceKey -> Maybe (Text, Text)

-- | How a fenced block is highlighted: the fence's language word and the body's lines give the
-- pieces of each line, plain when the language is unknown. ref:DEC-highlight-by-lexer
type Highlight = Text -> [Text] -> [[Piece]]

-- | Where a page is published: its quadrant directory and its name, with index.html inside, so
-- the URL ends at the name. A page outside docs/<quadrant>/ is not published.
pagePath :: FilePath -> Maybe FilePath
pagePath path = case break (`elem` map snd quadrants) (splitDirectories path) of
  (_, quadrant : rest@(_ : _)) -> Just (foldr (</>) "" (quadrant : init rest ++ [takeWhile (/= '.') (last rest), "index.html"]))
  _ -> Nothing

-- | The embed address of a video locator canon knows how to embed, which today is YouTube in
-- either of its spellings; any other locator is linked, never embedded.
embedOf :: Text -> Maybe Text
embedOf locator
  | Just rest <- afterAny ["https://www.youtube.com/watch?v=", "https://youtube.com/watch?v=", "https://m.youtube.com/watch?v="] = Just (embed (T.takeWhile (/= '&') rest))
  | Just rest <- afterAny ["https://youtu.be/"] = Just (embed (T.takeWhile (`notElem` ("?&" :: String)) rest))
  | otherwise = Nothing
  where
    afterAny prefixes = case mapMaybe (`T.stripPrefix` locator) prefixes of
      (r : _) | not (T.null r) -> Just r
      _ -> Nothing
    embed i = "https://www.youtube-nocookie.com/embed/" <> i

-- | HTML escaping of text.
escape :: Text -> Text
escape = T.concatMap escapeChar

escapeChar :: Char -> Text
escapeChar c = case c of
  '&' -> "&amp;"
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  _ -> T.singleton c

-- | One page as HTML: its title, its quadrant, its video if it names one, and its elements.
renderPage :: Text -> Resolve -> Highlight -> Document -> Text
renderPage projectName resolve highlight doc =
  T.unlines
    ( [ "<!doctype html>"
      , "<html lang=\"en\">"
      , "<head>"
      , "<meta charset=\"utf-8\">"
      , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
      , "<title>" <> escape title <> "</title>"
      , "<style>" <> style <> "</style>"
      , "</head>"
      , "<body>"
      , "<header><a class=\"home\" href=\"../../index.html\">" <> escape projectName <> "</a> <span class=\"quadrant\">" <> escape kind <> "</span></header>"
      , "<main>"
      ]
        ++ video
        ++ concatMap (renderGroup resolve highlight) (groupElements (docElements doc))
        ++ ["</main>", "</body>", "</html>"]
    )
  where
    front = docFront doc
    title = fromMaybe (fromMaybe (T.pack (takeFileName (docPath doc))) (Map.lookup "id" front)) (Map.lookup "title" front)
    kind = fromMaybe "" (Map.lookup "kind" front)
    video = case Map.lookup "video" front of
      Just k | isReferenceKey k, Just (t, locator) <- resolve (ReferenceKey k) ->
        [ "<figure class=\"video\">"
        , maybe "" (\src -> "<iframe src=\"" <> escape src <> "\" title=\"" <> escape t <> "\" loading=\"lazy\" allowfullscreen></iframe>") (embedOf locator)
        , "<figcaption><a href=\"" <> escape locator <> "\">" <> escape t <> "</a></figcaption>"
        , "</figure>"
        ]
      _ -> []

-- | The index of a project's site: the four quadrants, each listing its pages by title.
renderIndex :: Text -> [(Document, FilePath)] -> Text
renderIndex projectName pages =
  T.unlines
    ( [ "<!doctype html>"
      , "<html lang=\"en\">"
      , "<head>"
      , "<meta charset=\"utf-8\">"
      , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
      , "<title>" <> escape projectName <> "</title>"
      , "<style>" <> style <> "</style>"
      , "</head>"
      , "<body>"
      , "<header><span class=\"home\">" <> escape projectName <> "</span></header>"
      , "<main>"
      ]
        ++ concat
          [ ["<h2>" <> escape (heading q) <> "</h2>", "<ul>"] ++ ["<li><a href=\"" <> escape (T.pack href) <> "\">" <> escape (titleOf d) <> "</a></li>" | (d, href) <- sortOn (titleOf . fst) mine] ++ ["</ul>"]
          | q <- map fst quadrants
          , let mine = [(d, href) | (d, href) <- pages, Map.lookup "kind" (docFront d) == Just q]
          , not (null mine)
          ]
        ++ ["</main>", "</body>", "</html>"]
    )
  where
    titleOf d = fromMaybe (fromMaybe (T.pack (docPath d)) (Map.lookup "id" (docFront d))) (Map.lookup "title" (docFront d))
    heading q = case q of
      "tutorial" -> "Tutorials"
      "how-to" -> "How-to guides"
      "reference" -> "Reference"
      "explanation" -> "Explanation"
      other -> other

-- | Consecutive prose lines grouped into one block each: a paragraph, a list, a quotation, or a
-- table, decided by how their lines begin.
data Group
  = GroupHeading Int Text
  | GroupParagraph [Text]
  | GroupList Bool [Text]
  | GroupQuote [Text]
  | GroupTable [Text]
  | GroupCode Text [Text]
  | GroupRule
  deriving (Eq, Show)

groupElements :: [Element] -> [Group]
groupElements elements = case elements of
  [] -> []
  ElementHeading _ depth title : rest -> GroupHeading depth title : groupElements rest
  ElementFence _ info body : rest -> GroupCode (T.takeWhile (not . isSpace) info) body : groupElements rest
  ElementRule _ : rest -> GroupRule : groupElements rest
  ElementBlank _ : rest -> groupElements rest
  ElementProse _ line : rest ->
    let (more, after) = span isProse rest
        ls = line : [l | ElementProse _ l <- more]
     in shape ls : groupElements after
  where
    isProse e = case e of
      ElementProse _ _ -> True
      _ -> False
    shape ls
      | all (isListItem False) ls = GroupList False ls
      | all (isListItem True) ls = GroupList True ls
      | all (">" `T.isPrefixOf`) ls = GroupQuote ls
      | all ("|" `T.isPrefixOf`) ls = GroupTable ls
      | otherwise = GroupParagraph ls
    isListItem numbered l =
      let t = T.dropWhile isSpace l
       in if numbered then not (T.null (T.takeWhile isDigit t)) && ". " `T.isPrefixOf` T.dropWhile isDigit t else any (`T.isPrefixOf` t) ["- ", "* "]

renderGroup :: Resolve -> Highlight -> Group -> [Text]
renderGroup resolve highlight g = case g of
  GroupHeading depth title -> [T.concat ["<h", level, " id=\"", slug title, "\">", inline resolve title, "</h", level, ">"]]
    where
      level = T.pack (show (min 6 depth))
  GroupParagraph ls -> ["<p>" <> inline resolve (T.unwords (map T.strip ls)) <> "</p>"]
  GroupList numbered ls -> [if numbered then "<ol>" else "<ul>"] ++ ["<li>" <> inline resolve (item l) <> "</li>" | l <- ls] ++ [if numbered then "</ol>" else "</ul>"]
    where
      item l = T.strip (T.drop 1 (T.dropWhile (\c -> c /= ' ') (T.dropWhile isSpace l)))
  GroupQuote ls -> ["<blockquote><p>" <> inline resolve (T.unwords [T.strip (T.drop 1 l) | l <- ls]) <> "</p></blockquote>"]
  GroupTable ls -> case [l | l <- ls, not (isSeparator l)] of
    [] -> []
    (h : rows) -> ["<table>", "<thead><tr>" <> T.concat ["<th>" <> inline resolve c <> "</th>" | c <- cells h] <> "</tr></thead>", "<tbody>"] ++ ["<tr>" <> T.concat ["<td>" <> inline resolve c <> "</td>" | c <- cells r] <> "</tr>" | r <- rows] ++ ["</tbody>", "</table>"]
    where
      cells l = map T.strip (dropEnds (T.splitOn "|" l))
      dropEnds xs = drop 1 (take (length xs - 1) xs)
      isSeparator l = T.all (`elem` ("|-: " :: String)) l
  GroupCode language body -> ["<pre><code class=\"language-" <> escape language <> "\">" <> T.intercalate "\n" (map (T.concat . map piece) (highlight language body)) <> "</code></pre>"]
    where
      piece (Piece cls t) = if cls == "plain" then escape t else "<span class=\"" <> cls <> "\">" <> escape t <> "</span>"
  GroupRule -> ["<hr>"]

-- | A heading's anchor: its words in lowercase joined by hyphens.
slug :: Text -> Text
slug = T.intercalate "-" . T.words . T.map (\c -> if c `elem` ("abcdefghijklmnopqrstuvwxyz0123456789" :: String) then c else ' ') . T.toLower

-- | Inline markup: code spans first, so nothing inside them is read as markup, then bold,
-- emphasis, links, and citations.
inline :: Resolve -> Text -> Text
inline resolve = T.concat . map piece . spans
  where
    spans t = case T.breakOn "`" t of
      (before, rest)
        | T.null rest -> [Left before]
        | otherwise -> case T.breakOn "`" (T.drop 1 rest) of
            (code, after)
              | T.null after -> [Left t]
              | otherwise -> Left before : Right code : spans (T.drop 1 after)
    piece p = case p of
      Right code -> "<code>" <> escape code <> "</code>"
      Left plain -> cite (links (emphasis (escape plain)))
    emphasis t = strong t
    strong t = case T.breakOn "**" t of
      (before, rest)
        | T.null rest -> italic before
        | otherwise -> case T.breakOn "**" (T.drop 2 rest) of
            (inner, after)
              | T.null after -> italic t
              | otherwise -> italic before <> "<strong>" <> italic inner <> "</strong>" <> strong (T.drop 2 after)
    italic t = case T.breakOn "*" t of
      (before, rest)
        | T.null rest -> before
        | otherwise -> case T.breakOn "*" (T.drop 1 rest) of
            (inner, after)
              | T.null after || T.null inner -> before <> "*" <> italic (T.drop 1 rest)
              | otherwise -> before <> "<em>" <> inner <> "</em>" <> italic (T.drop 1 after)
    links t = case T.breakOn "[" t of
      (before, rest)
        | T.null rest -> t
        | otherwise -> case T.breakOn "](" rest of
            (label, after)
              | T.null after -> before <> "[" <> links (T.drop 1 rest)
              | otherwise -> case T.breakOn ")" (T.drop 2 after) of
                  (href, closing)
                    | T.null closing -> t
                    | otherwise -> before <> "<a href=\"" <> href <> "\">" <> T.drop 1 label <> "</a>" <> links (T.drop 1 closing)
    cite t = T.intercalate " " (map word (T.splitOn " " t))
    word w = case T.stripPrefix "ref:" w of
      Just k ->
        let (key, punctuation) = T.span (\c -> c /= ',' && c /= '.' && c /= ';' && c /= ')') k
         in case (isReferenceKey key, resolve (ReferenceKey key)) of
              (True, Just (title, locator)) -> "<a class=\"cite\" href=\"" <> escape locator <> "\" title=\"" <> escape title <> "\">" <> escape key <> "</a>" <> punctuation
              (True, Nothing) -> "<span class=\"cite unresolved\">" <> escape key <> "</span>" <> punctuation
              _ -> w
      Nothing -> w

-- | The one stylesheet, fixed, so the site is deterministic and needs no other file.
style :: Text
style = T.intercalate " "
  [ ":root{color-scheme:light dark;--ink:#1c1a17;--paper:#faf8f3;--muted:#6b665c;--line:#e0dbcf;--accent:#8a4b1f;--kw:#cf222e;--str:#0a3069;--cmt:#6e7781;--num:#0550ae;--typ:#953800;--meta:#8250df}"
  , "@media(prefers-color-scheme:dark){:root{--ink:#e8e4da;--paper:#171614;--muted:#a09a8d;--line:#3a3733;--accent:#e0a56e;--kw:#ff7b72;--str:#a5d6ff;--cmt:#8b949e;--num:#79c0ff;--typ:#ffa657;--meta:#d2a8ff}}"
  , "pre .keyword{color:var(--kw)}pre .string{color:var(--str)}pre .comment{color:var(--cmt);font-style:italic}pre .number{color:var(--num)}pre .type{color:var(--typ)}pre .meta{color:var(--meta)}pre .name{color:var(--typ)}"
  , "body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 Georgia,'Times New Roman',serif}"
  , "header{display:flex;gap:1rem;align-items:baseline;padding:1rem 1.25rem;border-bottom:1px solid var(--line)}"
  , "header .home{font-weight:bold;color:var(--ink);text-decoration:none}header .quadrant{color:var(--muted);text-transform:uppercase;font-size:.75rem;letter-spacing:.08em}"
  , "main{max-width:46rem;margin:0 auto;padding:1.5rem 1.25rem 4rem}"
  , "h1,h2,h3,h4{line-height:1.25;font-weight:600}h1{font-size:1.9rem}h2{font-size:1.4rem;margin-top:2.2rem}h3{font-size:1.15rem}"
  , "pre{background:rgba(127,127,127,.08);border:1px solid var(--line);border-radius:6px;padding:.75rem 1rem;overflow-x:auto;font:13.5px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace}"
  , "code{font:.92em ui-monospace,SFMono-Regular,Menlo,monospace}p code{background:rgba(127,127,127,.12);padding:.05em .3em;border-radius:3px}"
  , "table{border-collapse:collapse;width:100%;font-size:.95rem}th,td{border:1px solid var(--line);padding:.35rem .6rem;vertical-align:top;text-align:left}"
  , "blockquote{margin:1rem 0;padding:.25rem 1rem;border-left:3px solid var(--accent);color:var(--muted)}"
  , "a{color:var(--accent)}a.cite{font-family:ui-monospace,Menlo,monospace;font-size:.85em;text-decoration:none;border-bottom:1px dotted var(--accent)}.cite.unresolved{color:#b3261e;font-family:ui-monospace,Menlo,monospace;font-size:.85em}"
  , "figure.video{margin:1rem 0}figure.video iframe{width:100%;aspect-ratio:16/9;border:0;border-radius:6px}figcaption{color:var(--muted);font-size:.9rem}"
  , "hr{border:0;border-top:1px solid var(--line);margin:2rem 0}"
  ]
