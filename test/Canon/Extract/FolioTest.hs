-- | The Folio's canonically commented dialect reads a page as units by the grammar's labels: the page
-- with its front matter as its Why and its id as its What, and each section with its prose as its
-- Why, so these properties check it against canon's own pages. ref:DEC-folio-dialect
-- ref:REQ-folio-support
module Canon.Extract.FolioTest (tests) where

import Canon.Antlr4.Interpret (renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Extract.Folio (pageUnitId)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Finding
import Canon.Profile
import Canon.Span (Position (..), Span (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "folio"
    [ testProperty "the Folio dialect reads canon's pages into a doc unit and its sections" prop_theFolioDialectReadsCanonsPagesIntoADocUnitAndItsSections
    , testProperty "the Folio dialect binds front matter to the page and reports misplaced front matter" prop_theFolioDialectBindsFrontMatterToThePageAndReportsMisplacedFrontMatter
    ]

-- | The canonically commented dialect of the Folio grammar, with no units of a profile and no
-- comment syntax, so every unit and every Why comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".md"] (SplitGrammarFiles "grammars/folio/canonically_commented/FolioLexer.g4" "grammars/folio/canonically_commented/FolioParser.g4") (Name "document") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | An extraction of one page through the dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "folio" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | The Why of each decision with the unit it binds to.
whysOf :: Model Evidence -> [(Text, Text)]
whysOf model = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]

-- | A page must parse whole through the dialect and yield the unit canon's own page extraction
-- makes, kind doc under the same id, with the front matter as its Why and a unit for each section
-- with prose; the root profile still reads docs/ with the plain grammar, whose rule names the page
-- extraction and the tangler read, so the dialect changes nothing the root check reports.
-- ref:REQ-folio-support ref:DEC-folio-dialect ref:DEC-doc-kind ref:DEC-section-prose-is-why
prop_theFolioDialectReadsCanonsPagesIntoADocUnitAndItsSections :: Property
prop_theFolioDialectReadsCanonsPagesIntoADocUnitAndItsSections = withTests 1 $ property $ do
  loaded <- evalIO (readConfigFile "canon.yaml")
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  fmap profileGrammar (Map.lookup "folio" (configLanguages config)) === Just (SplitGrammarFiles "grammars/folio/FolioLexer.g4" "grammars/folio/FolioParser.g4")
  let explanation = "docs/explanation/folio.md"
  folio <- evalIO (T.pack <$> readFile explanation)
  Extraction model findings <- extractDialect explanation folio
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitRequirement u == Required]
    === [ renderUnitId (pageUnitId explanation "canon.folio")
        , "folio/docs/explanation/folio.md/doc/canon.folio/section/The-Folio"
        , "folio/docs/explanation/folio.md/doc/canon.folio/section/The-section-is-the-Why"
        , "folio/docs/explanation/folio.md/doc/canon.folio/section/The-units-keep-the-tangled-path"
        , "folio/docs/explanation/folio.md/doc/canon.folio/section/The-four-quadrants"
        ]
  take 1 (whysOf model) === [("folio/docs/explanation/folio.md/doc/canon.folio", "id: canon.folio\nkind: explanation\ntitle: The Folio, or why a page can be the source of its code")]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model]
    === [[], [ReferenceKey "DEC-folio-language"], [ReferenceKey "DEC-section-prose-is-why"], [ReferenceKey "DEC-units-by-tangled-path"], map ReferenceKey ["DEC-docs-tree", "DEC-doc-kind", "DEC-video-reference", "diataxis"]]
  let howTo = "docs/how-to/tangle.md"
  tangle <- evalIO (T.pack <$> readFile howTo)
  Extraction tangleModel tangleFindings <- extractDialect howTo tangle
  length [() | OrphanDocComment _ _ <- tangleFindings] === 0
  map fst (whysOf tangleModel)
    === [ renderUnitId (pageUnitId howTo "canon.how-to.tangle")
        , "folio/docs/how-to/tangle.md/doc/canon.how-to.tangle/section/Tangle-a-project's-pages-into-its-sources"
        ]

-- | Front matter documents the page only at its top: a second --- block binds to nothing and is an
-- orphan, a section whose heading is followed by a block rather than prose is no unit, a citation in
-- backticks is an example rather than a citation, and the video a page names is cited like a
-- reference. ref:REQ-folio-support ref:DEC-folio-dialect
prop_theFolioDialectBindsFrontMatterToThePageAndReportsMisplacedFrontMatter :: Property
prop_theFolioDialectBindsFrontMatterToThePageAndReportsMisplacedFrontMatter = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "docs/how-to/draw.md"
      ( T.unlines
          [ "---"
          , "id: shapes.how-to.draw"
          , "kind: how-to"
          , "title: Draw a shape"
          , "video: draw-video"
          , "---"
          , "A page about shapes."
          , ""
          , "# Draw"
          , ""
          , "Drawing needs a canvas. ref:DEC-canvas"
          , "Write `ref:not-a-citation` to cite."
          , ""
          , "```haskell file=src/Draw.hs def=draw"
          , "draw = undefined"
          , "```"
          , ""
          , "Prose after the block."
          , ""
          , "---"
          , "id: misplaced"
          , "---"
          , ""
          , "## Only code"
          , ""
          , "```"
          , "canon tangle"
          , "```"
          ]
      )
  whysOf model
    === [ ("folio/docs/how-to/draw.md/doc/shapes.how-to.draw", "id: shapes.how-to.draw\nkind: how-to\ntitle: Draw a shape\nvideo: draw-video")
        , ("folio/docs/how-to/draw.md/doc/shapes.how-to.draw/section/Draw", "Drawing needs a canvas. ref:DEC-canvas\nWrite `ref:not-a-citation` to cite.")
        ]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model] === [[ReferenceKey "draw-video"], [ReferenceKey "DEC-canvas"]]
  [howText (answerValue (unitHow u)) | u <- modelAllUnits model, whatName (answerValue (unitWhat u)) == "Draw"]
    === ["```haskell file=src/Draw.hs def=draw\ndraw = undefined\n```\n\nProse after the block.\n\n---\nid: misplaced\n---"]
  [spanStart sp | OrphanDocComment _ sp <- findings] === [Position 20 1]
  where
    howText h = case h of
      HowText t -> t
      _ -> ""
