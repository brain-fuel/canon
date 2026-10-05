-- | Go is read through the vendored grammars-v4 Go grammar, the profile the google/uuid sample ships,
-- and the canonically commented dialect, so these properties check all three against what a Go author
-- means by a declaration and its documentation. ref:DEC-more-languages ref:DEC-go-dialect
-- ref:REQ-go-support
module Canon.Extract.GoTest (tests) where

import Canon.Antlr4.Interpret (renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Data.List (sort)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (listDirectory)
import System.FilePath (normalise, takeExtension, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "go"
    [ testProperty "the Go grammar and profile parse every file of the uuid sample into its declarations" prop_theGoGrammarAndProfileParseEveryFileOfTheUuidSampleIntoItsDeclarations
    , testProperty "the Go profile binds comments to declarations and recognises tests" prop_theGoProfileBindsCommentsToDeclarationsAndRecognisesTests
    , testProperty "the Go dialect parses every file of the uuid sample with its doc comments" prop_theGoDialectParsesEveryFileOfTheUuidSampleWithItsDocComments
    , testProperty "the Go dialect binds doc comments directly above declarations and requires them on exported names" prop_theGoDialectBindsDocCommentsDirectlyAboveDeclarationsAndRequiresThemOnExportedNames
    , testProperty "the Go dialect reads a doc comment as go/doc groups it, without its directives" prop_theGoDialectReadsADocCommentAsGoDocGroupsItWithoutItsDirectives
    , testProperty "the Go dialect requires a comment on a spec when any of its names is exported" prop_theGoDialectRequiresACommentOnASpecWhenAnyOfItsNamesIsExported
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/go-uuid"

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Go project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "go" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | The canonically commented dialect of the Go grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".go"] (SplitGrammarFiles "grammars/golang/canonically_commented/GoLexer.g4" "grammars/golang/canonically_commented/GoParser.g4") (Name "sourceFile") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | An extraction of one source text through a profile.
extractWith :: Profile -> FilePath -> Text -> PropertyT IO Extraction
extractWith profile path source = do
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "go" profile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Every Go file of the sample, each extracted through a profile, in name order.
extractSample :: Profile -> PropertyT IO [(FilePath, Extraction)]
extractSample profile = do
  names <- evalIO (sort . filter ((== ".go") . takeExtension) <$> listDirectory (sampleDir </> "source"))
  mapM (\name -> evalIO (T.pack <$> readFile (sampleDir </> "source" </> name)) >>= fmap ((,) name) . extractWith profile name) names

-- | The units of a model below its file unit.
unitsBelowFile :: Model Evidence -> [CodeUnit Evidence]
unitsBelowFile model = [u | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"]

-- | A real module must parse whole, with every function, method, and type it declares found where the
-- Go compiler finds them, or a Go project's check would report parse failures instead of findings.
-- ref:REQ-go-support ref:DEC-more-languages
prop_theGoGrammarAndProfileParseEveryFileOfTheUuidSampleIntoItsDeclarations :: Property
prop_theGoGrammarAndProfileParseEveryFileOfTheUuidSampleIntoItsDeclarations = withTests 1 $ property $ do
  profile <- sampleProfile
  extractions <- extractSample profile
  let units = concatMap (unitsBelowFile . extractionModel . snd) extractions
      kinds = [unitKindText (whatKind (answerValue (unitWhat u))) | u <- units]
  (length extractions, length units, length (filter (== "function") kinds), length (filter (== "method") kinds), length (filter (== "type") kinds), length (filter unitTest units)) === (23, 162, 114, 34, 14, 62)

-- | In Go a doc comment is the comment directly above a declaration, and a function named Test,
-- Benchmark, Example, or Fuzz in a _test.go file is a test, so the profile must bind and recognise
-- each that way for the Why of a Go declaration to be its documentation. ref:REQ-go-support
-- ref:DEC-more-languages
prop_theGoProfileBindsCommentsToDeclarationsAndRecognisesTests :: Property
prop_theGoProfileBindsCommentsToDeclarationsAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  Extraction model _ <-
    extractWith
      profile
      "shapes_test.go"
      ( T.unlines
          [ "package shapes"
          , ""
          , "// Shape is anything with an area."
          , "type Shape interface { Area() float64 }"
          , ""
          , "type circle struct{ r float64 }"
          , ""
          , "// Area is pi r squared."
          , "func (c circle) Area() float64 { return 3 * c.r * c.r }"
          , ""
          , "// Squares have the area of their side squared. ref:REQ-1"
          , "func TestSquareArea(t *testing.T) {}"
          , ""
          , "func BenchmarkArea(b *testing.B) {}"
          , ""
          , "func helper() {}"
          ]
      )
  let units = unitsBelowFile model
      nameOf u = whatName (answerValue (unitWhat u))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(unitKindText (whatKind (answerValue (unitWhat u))), nameOf u, unitTest u) | u <- units]
    === [("type", "Shape", False), ("type", "circle", False), ("method", "Area", False), ("function", "TestSquareArea", True), ("function", "BenchmarkArea", True), ("function", "helper", False)]
  whyOf "Shape" === ["Shape is anything with an area."]
  whyOf "Area" === ["Area is pi r squared."]
  whyOf "TestSquareArea" === ["Squares have the area of their side squared. ref:REQ-1"]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []

-- | Doc comments are tokens of the dialect, so real Go must still parse whole with them wherever go/doc
-- reads them, and a license header or build constraint parted from the package clause by a blank line
-- must stay a plain comment rather than an orphan. ref:REQ-go-support ref:DEC-go-dialect
prop_theGoDialectParsesEveryFileOfTheUuidSampleWithItsDocComments :: Property
prop_theGoDialectParsesEveryFileOfTheUuidSampleWithItsDocComments = withTests 1 $ property $ do
  extractions <- extractSample dialectProfile
  let models = map (extractionModel . snd) extractions
      units = concatMap unitsBelowFile models
      decisions = concatMap modelDecisions models
      kinds = [unitKindText (whatKind (answerValue (unitWhat u))) | u <- units]
      count kind = length (filter (== kind) kinds)
      fileWhys = [name | (name, Extraction model _) <- extractions, d <- modelDecisions model, NonEmpty.head (decisionUnits d) == fileUnitId name]
  (length extractions, length units, length decisions, length [() | (_, Extraction _ findings) <- extractions, OrphanDocComment _ _ <- findings], length (filter unitTest units)) === (23, 246, 86, 0, 62)
  map count ["function", "method", "type", "const", "var", "group", "field", "element"] === [114, 34, 12, 16, 33, 7, 30, 0]
  fileWhys === ["doc.go"]
  where
    fileUnitId name = UnitId ("go" NonEmpty.:| [T.pack name])

-- | In the dialect the grammar says where a doc comment binds: directly above a declaration, a spec of
-- a group, a field, or an interface method, while a comment parted from what follows by a blank line
-- or inside a function body is a plain comment, and one above an import or after the last field binds
-- to nothing and is reported. An exported name requires a comment, unless it is a method of an
-- unexported type or a spec of a documented group. ref:REQ-go-support ref:DEC-go-dialect
prop_theGoDialectBindsDocCommentsDirectlyAboveDeclarationsAndRequiresThemOnExportedNames :: Property
prop_theGoDialectBindsDocCommentsDirectlyAboveDeclarationsAndRequiresThemOnExportedNames = withTests 1 $ property $ do
  Extraction model findings <-
    extractWith
      dialectProfile
      "shapes.go"
      ( T.unlines
          [ "// Copyright notice, parted from the package clause by a blank line."
          , ""
          , "// Package shapes exercises the dialect. ref:some-key"
          , "package shapes"
          , ""
          , "// Above an import, so an orphan."
          , "import \"fmt\""
          , ""
          , "// Units of measure, documenting the group."
          , "const ("
          , "\tMetre = 1"
          , "\t// The inch has its own comment."
          , "\tInch = 0.0254"
          , ")"
          , ""
          , "var ("
          , "\t// ErrShape documents itself."
          , "\tErrShape = fmt.Errorf(\"shape\")"
          , "\tErrSize  = fmt.Errorf(\"size\")"
          , "\tcount    int"
          , ")"
          , ""
          , "// Parted from Plain by a blank line, so no documentation."
          , ""
          , "func Plain() {}"
          , ""
          , "// Point is a place on the plane."
          , "//go:generate stringer -type=Point"
          , "type Point struct {"
          , "\t// X is the abscissa."
          , "\tX, Y float64"
          , "\tlabel string // a trailing comment documents nothing"
          , "\t// After the last field, so an orphan."
          , "}"
          , ""
          , "/* Shape is anything with an area. */"
          , "type Shape interface {"
          , "\t// Area is the area of the shape."
          , "\tArea() float64"
          , "}"
          , ""
          , "func (p Point) Area() float64 {"
          , "\t// Inside a body, so a plain comment."
          , "\treturn 0"
          , "}"
          , ""
          , "type circle struct{ r float64 }"
          , ""
          , "func (c circle) Area() float64 { return 3 * c.r * c.r }"
          , ""
          , "func helper() {}"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("go/shapes.go", "Package shapes exercises the dialect. ref:some-key")
        , ("go/shapes.go/group/0", "Units of measure, documenting the group.")
        , ("go/shapes.go/group/0/const/Inch", "The inch has its own comment.")
        , ("go/shapes.go/group/1/var/ErrShape", "ErrShape documents itself.")
        , ("go/shapes.go/type/Point", "Point is a place on the plane.")
        , ("go/shapes.go/type/Point/field/X,Y", "X is the abscissa.")
        , ("go/shapes.go/type/Shape", "Shape is anything with an area.")
        , ("go/shapes.go/type/Shape/method/Area", "Area is the area of the shape.")
        ]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model, NonEmpty.head (decisionUnits d) == UnitId ("go" NonEmpty.:| ["shapes.go"])] === [[ReferenceKey "some-key"]]
  length [() | OrphanDocComment _ _ <- findings] === 2
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["go/shapes.go/group/1/var/ErrSize", "go/shapes.go/function/Plain", "go/shapes.go/method/Area"]

-- | go/doc reads the comments above a declaration with no blank line between them as one comment,
-- a block comment followed by a line comment included, and leaves directive lines such as
-- //go:generate, //nolint, and // +build out of its text, so the Why is that comment without them
-- and nothing of it is an orphan. ref:REQ-go-support ref:DEC-go-dialect
prop_theGoDialectReadsADocCommentAsGoDocGroupsItWithoutItsDirectives :: Property
prop_theGoDialectReadsADocCommentAsGoDocGroupsItWithoutItsDirectives = withTests 1 $ property $ do
  Extraction model findings <-
    extractWith
      dialectProfile
      "shapes.go"
      ( T.unlines
          [ "package shapes"
          , ""
          , "// Area is the area of a shape."
          , "//go:noinline"
          , "//nolint"
          , "// +build linux"
          , "// It is never negative. ref:area-key"
          , "func Area() float64 { return 0 }"
          , ""
          , "/* Perimeter is the length of a shape's edge. */"
          , "// It is never negative either."
          , "func Perimeter() float64 { return 0 }"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("go/shapes.go/function/Area", "Area is the area of a shape.\nIt is never negative. ref:area-key")
        , ("go/shapes.go/function/Perimeter", "Perimeter is the length of a shape's edge.\nIt is never negative either.")
        ]
  [whyReferences (answerValue (decisionWhy d)) | d <- modelDecisions model] === [[ReferenceKey "area-key"], []]
  length [() | OrphanDocComment _ _ <- findings] === 0

-- | Every name of a const or var spec is exported or not by its own initial, so a spec that exports
-- any of its names is part of the package's API and needs a comment, whichever name comes first.
-- ref:REQ-go-support ref:DEC-go-dialect ref:revive-exported
prop_theGoDialectRequiresACommentOnASpecWhenAnyOfItsNamesIsExported :: Property
prop_theGoDialectRequiresACommentOnASpecWhenAnyOfItsNamesIsExported = withTests 1 $ property $ do
  Extraction model _ <-
    extractWith
      dialectProfile
      "shapes.go"
      ( T.unlines
          [ "package shapes"
          , ""
          , "var a, B = 1, 2"
          , ""
          , "const c, d = 3, 4"
          , ""
          , "var ("
          , "\te, F int"
          , ")"
          ]
      )
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["go/shapes.go/var/a,B", "go/shapes.go/group/0/var/e,F"]
