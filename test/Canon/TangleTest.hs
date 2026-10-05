-- | The tangler must find what a page's blocks declare, carry each section's address, write the
-- prose as a documentation comment within the width, keep the pages' order, and map every tangled
-- line back to its page; and the Folio grammar must decide its line-level ties as the lexer's
-- rule order says. ref:DEC-tangle-in-canon ref:DEC-folio-language
module Canon.TangleTest (tests) where

import Canon.Antlr4.Interpret (Interpreter, interpretText, renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Extract.Grammar (loadProfileInterpreter)
import Canon.Folio
import Canon.Profile
import Canon.Tangle
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "tangle"
    [ testProperty "a page's blocks are found with their names, parts, and illustrations left out" findsBlocks
    , testProperty "the generated comment opens as a doc comment and ends with the section's address" carriesAddress
    , testProperty "every generated line fits the width unless one word cannot" fitsWidth
    , testProperty "blocks reach a file in page order and the line map returns each body line" preservesOrder
    , testProperty "a header's comment follows its pragmas" pragmasFirst
    , testProperty "the grammar breaks its ties by rule order" grammarTies
    ]

folioProfile :: Profile
folioProfile = Profile [".md"] (SplitGrammarFiles "grammars/folio/FolioLexer.g4" "grammars/folio/FolioParser.g4") (Name "document") [] defaultCommentSyntax Map.empty Map.empty Map.empty

haskellEmbedding :: Embedding
haskellEmbedding = Embedding "haskell" (CommentSyntax (Just "--") (Just "{-") (Just "-}") ["\""] [] [] [] []) 98 (DocStyle "-- | " "-- " "--" "-- " "haddock")

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadProfileInterpreter folioProfile)
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

scanOrFail :: Interpreter -> FilePath -> Text -> PropertyT IO Document
scanOrFail interpreter path source = case interpretText interpreter (Name "document") path source of
  Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
  Right tree -> pure (scanDocument path tree)

page :: Text
page =
  T.unlines
    [ "---"
    , "id: sample.page"
    , "kind: reference"
    , "---"
    , "# 1. A sample"
    , ""
    , "## 1.1 Header"
    , ""
    , "```haskell file=src/Sample.hs part=header"
    , "{-# LANGUAGE LambdaCase #-}"
    , ""
    , "module Sample (double) where"
    , "```"
    , ""
    , "## 1.2 Doubling"
    , ""
    , "Doubling is `adding` a number to **itself**, which is the whole of it."
    , ""
    , "A second paragraph."
    , ""
    , "```haskell file=src/Sample.hs def=double"
    , "double :: Int -> Int"
    , "double x = x + x"
    , "```"
    , ""
    , "```text"
    , "an illustration, never tangled"
    , "```"
    , ""
    , "```haskell file=src/Sample.hs"
    , "undeclared = 1"
    , "```"
    ]

findsBlocks :: Property
findsBlocks = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  doc <- scanOrFail interpreter "docs/reference/sample.md" page
  Map.lookup "id" (docFront doc) === Just "sample.page"
  docFrontSpan doc === Just (1, 4)
  map blockName (docBlocks doc) === ["header", "double", "?"]
  map blockIsPart (docBlocks doc) === [True, False, False]
  map blockDeclared (docBlocks doc) === [True, True, False]
  map blockLine (docBlocks doc) === [9, 21, 30]
  map (map snd . blockProse) (docBlocks doc) === [[], ["Doubling is `adding` a number to **itself**, which is the whole of it.", "", "A second paragraph.", ""], []]
  map (map snd . blockSection) (docBlocks doc) === [["1. A sample", "1.1 Header"], ["1. A sample", "1.2 Doubling"], ["1. A sample", "1.2 Doubling"]]

carriesAddress :: Property
carriesAddress = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  doc <- scanOrFail interpreter "docs/reference/sample.md" page
  let comment = docComment haskellEmbedding (docBlocks doc !! 1)
  comment === ["-- | Doubling is @adding@ a number to __itself__, which is the whole of it.", "--", "-- A second paragraph.", "--", "-- Specified by sample S1.2."]

fitsWidth :: Property
fitsWidth = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let long = T.unlines ["## 2. Long", "", T.unwords (replicate 40 "word"), "", "aVeryLongWordThatCannotBeWrappedBecauseItHasNoSpacesAnywhereInsideItAtAllWhateverTheWidthAsksFor", "", "```haskell file=src/L.hs def=l", "l = 1", "```"]
  doc <- scanOrFail interpreter "l.md" long
  comment <- case docBlocks doc of
    (b : _) -> pure (docComment haskellEmbedding b)
    [] -> failure
  assert (all (\l -> T.length l <= 98 || length (T.words l) == 2) comment)
  assert (length comment > 3)

preservesOrder :: Property
preservesOrder = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  first <- scanOrFail interpreter "a.md" (T.unlines ["# 1. A", "", "One.", "", "```haskell file=src/M.hs def=one", "one = 1", "```"])
  second <- scanOrFail interpreter "b.md" (T.unlines ["# 1. B", "", "Two.", "", "```haskell file=src/M.hs def=two", "two = 2", "```"])
  t <- one (assemble haskellEmbedding (docBlocks first ++ docBlocks second))
  tangledPath t === "src/M.hs"
  T.lines (tangledText t) === ["-- Tangled from a.md, b.md.", "-- Edit the specification, not this file.", "-- Every comment below is generated from the prose there.", "", "-- | One.", "--", "-- Specified by a S1.", "one = 1", "", "-- | Two.", "--", "-- Specified by b S1.", "two = 2"]
  [(doc, n, l) | (l, OriginBody doc n) <- zip (T.lines (tangledText t)) (tangledOrigins t)] === [("a.md", 6, "one = 1"), ("b.md", 6, "two = 2")]
  tangledRanges t === [(5, 8), (10, 13)]

pragmasFirst :: Property
pragmasFirst = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  doc <- scanOrFail interpreter "h.md" (T.unlines ["# 1. H", "", "The module.", "", "```haskell file=src/H.hs part=header", "{-# LANGUAGE LambdaCase #-}", "", "module H where", "```"])
  t <- one (assemble haskellEmbedding (docBlocks doc))
  drop 4 (T.lines (tangledText t)) === ["{-# LANGUAGE LambdaCase #-}", "", "-- | The module.", "--", "-- Specified by h S1.", "module H where"]

one :: [Tangled] -> PropertyT IO Tangled
one ts = case ts of
  [t] -> pure t
  _ -> annotate (show (length ts) ++ " tangled files") >> failure

grammarTies :: Property
grammarTies = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  doc <- scanOrFail interpreter "t.md" (T.unlines ["# Title", "#hashtag is prose", "---", "````haskell file=f.hs def=x", "```", "inner", "```", "x = 1", "````", "--- not a rule"])
  docFrontSpan doc === Nothing
  map snd (docProse doc) === ["# Title", "#hashtag is prose", "--- not a rule"]
  map blockBody (docBlocks doc) === [["```", "inner", "```", "x = 1"]]
