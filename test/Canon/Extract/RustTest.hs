-- | Rust is read through the vendored grammars-v4 Rust grammar and the profile the Rust sample ships,
-- so these properties check both against what a Rust author means by an item and its documentation.
-- ref:DEC-rust-grammar ref:REQ-rust-support
module Canon.Extract.RustTest (tests) where

import Canon.Antlr4.Interpret (Interpreter (..), interpretFile, interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Lex (renderLexError)
import Canon.Antlr4.Parse (treeRuleNodes, treeTokens)
import Canon.Antlr4.Syntax (Name (..), nameText)
import Canon.Antlr4.Token (Token (..), hiddenChannelName, isEofToken)
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel, checkTests)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (Reference (..), ReferenceKind (..), Registry (..), emptyRegistry)
import Canon.Span (Position (..), Span (..))
import Canon.Decisions (emptyLedger)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.FilePath (normalise, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "rust"
    [ testProperty "the Rust grammar parses the scopeguard sample into its items" prop_rustGrammarParsesTheScopeguardSampleIntoItsItems
    , testProperty "the Rust lexer tells ranges, method calls, tuple indices, and escaped backslashes apart" prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart
    , testProperty "the Rust profile binds doc comments across attributes and recognises tests" prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests
    , testProperty "an empty Rust line comment ends at its line and hides no code" prop_anEmptyRustLineCommentEndsAtItsLineAndHidesNoCode
    , testProperty "the Rust profile requires comments on what is visible outside the crate" prop_rustProfileRequiresCommentsOnWhatIsVisibleOutsideTheCrate
    , testProperty "a Rust trait impl is named by its trait and its self type" prop_aRustTraitImplIsNamedByItsTraitAndItsSelfType
    , testProperty "the Rust dialect parses the scopeguard sample with its doc comments" prop_theRustDialectParsesTheScopeguardSampleWithItsDocComments
    , testProperty "the Rust dialect binds outer and inner doc comments and reports misplaced ones" prop_theRustDialectBindsOuterAndInnerDocCommentsAndReportsMisplacedOnes
    , testProperty "a Rust doc comment anywhere in a file parses and one that documents nothing is an orphan" prop_aRustDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan
    , testProperty "async, try, and dyn are names in a 2015 edition crate and keywords in later ones" prop_asyncTryAndDynAreNamesInA2015EditionCrateAndKeywordsInLaterOnes
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/rust-scopeguard"

interpreterOrFail :: PropertyT IO Interpreter
interpreterOrFail = do
  loaded <- evalIO (loadInterpreter "grammars/rust/RustLexer.g4" "grammars/rust/RustParser.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Rust project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "rust" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | A real crate must parse whole, with every function, impl, and macro it defines found where
-- rustc finds them, or a Rust project's check would report parse failures instead of findings.
-- ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustGrammarParsesTheScopeguardSampleIntoItsItems :: Property
prop_rustGrammarParsesTheScopeguardSampleIntoItsItems = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  result <- evalIO (interpretFile interpreter (Name "crate") (sampleDir </> "source/src/lib.rs"))
  tree <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure result
  length (treeRuleNodes (Name "function_") tree) === 21
  length (treeRuleNodes (Name "traitImpl") tree) === 8
  length (treeRuleNodes (Name "inherentImpl") tree) === 1
  length (treeRuleNodes (Name "macroRulesDefinition") tree) === 3
  length (treeRuleNodes (Name "enumeration") tree) === 3

-- | The upstream lexer told these apart with base-class predicates that canon cannot run; the
-- grammar's replacements must keep 1..2 a range, 1.max(2) a call, x.0.1 two tuple indices, and a
-- string ending in an escaped backslash a single string. ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart :: Property
prop_rustLexerTellsRangesMethodCallsTupleIndicesAndEscapesApart = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let typesOf source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, not (isEofToken t), tokenChannel t /= hiddenChannelName]
  typesOf "1..2" === Right [("INTEGER_LITERAL", "1"), ("DOTDOT", ".."), ("INTEGER_LITERAL", "2")]
  typesOf "1.max(2)" === Right [("INTEGER_LITERAL", "1"), ("DOT", "."), ("NON_KEYWORD_IDENTIFIER", "max"), ("LPAREN", "("), ("INTEGER_LITERAL", "2"), ("RPAREN", ")")]
  typesOf "1.5e3" === Right [("FLOAT_LITERAL", "1.5e3")]
  typesOf "\"a\\\\\" \"b\"" === Right [("STRING_LITERAL", "\"a\\\\\""), ("STRING_LITERAL", "\"b\"")]
  typesOf "#![no_std]" === Right [("POUND", "#"), ("NOT", "!"), ("LSQUAREBRACKET", "["), ("NON_KEYWORD_IDENTIFIER", "no_std"), ("RSQUAREBRACKET", "]")]
  case interpretText interpreter (Name "crate") "f.rs" "fn f() { let t = x.0.1; let u = a.union(b); _ = &&t; }" of
    Left err -> annotate (T.unpack (renderInterpretError err)) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "letStatement") tree) === 2
      [tokenText t | node <- treeRuleNodes (Name "tupleIndex") tree, t <- treeTokens node] === ["0.1"]

fixture :: Text
fixture =
  T.unlines
    [ "#![no_std]"
    , "//! The crate exists to exercise the Rust profile. ref:some-key"
    , ""
    , "use core::fmt;"
    , ""
    , "// A plain comment is not documentation."
    , "fn helper() {}"
    , ""
    , "/// A shape is a circle or a square."
    , "#[derive(Debug, Clone)]"
    , "pub enum Shape {"
    , "    Circle(f64),"
    , "    Square(f64),"
    , "}"
    , ""
    , "/// Areas are what shapes are for."
    , "pub trait Area {"
    , "    /// The area of the shape."
    , "    fn area(&self) -> f64;"
    , "}"
    , ""
    , "impl Area for Shape {"
    , "    fn area(&self) -> f64 {"
    , "        match self {"
    , "            Shape::Circle(r) => 3.0 * r * r,"
    , "            Shape::Square(w) => w * w,"
    , "        }"
    , "    }"
    , "}"
    , ""
    , "pub mod nested {"
    , "    //! The nested module's own documentation."
    , ""
    , "    /// Limits keep the range small."
    , "    pub const LIMIT: u32 = 10;"
    , "}"
    , ""
    , "/// Orphaned by the blank line below."
    , ""
    , "pub struct Point(pub f64, pub f64);"
    , ""
    , "macro_rules! twice { ($e:expr) => { $e + $e }; }"
    , ""
    , "#[cfg(test)]"
    , "mod tests {"
    , "    /// Squares have the area of their side squared. ref:REQ-1"
    , "    #[test]"
    , "    fn square_area_is_side_squared() {}"
    , ""
    , "    #[test]"
    , "    fn uncommented_test() {}"
    , "}"
    ]

-- | In Rust a doc comment sits above an item's attributes, //! documents the module or file around
-- it, a plain // comment documents nothing, and #[test] makes a function a test, so the profile must
-- bind and recognise each that way for the Why of a Rust item to be its documentation.
-- ref:REQ-rust-support ref:DEC-rust-grammar
prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests :: Property
prop_rustProfileBindsDocCommentsAcrossAttributesAndRecognisesTests = withTests 1 $ property $ do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "rust" profile interpreter "lib.rs" "lib.rs" fixture)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- byName n, d <- decisionsFor (unitId u) model]
      testsOf n = map unitTest (byName n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("function", "helper")
        , ("enum", "Shape")
        , ("variant", "Circle")
        , ("field", "0")
        , ("variant", "Square")
        , ("field", "0")
        , ("trait", "Area")
        , ("function", "area")
        , ("impl", "Area-for-Shape")
        , ("function", "area")
        , ("module", "nested")
        , ("const", "LIMIT")
        , ("struct", "Point")
        , ("field", "0")
        , ("field", "1")
        , ("macro", "twice")
        , ("module", "tests")
        , ("function", "square_area_is_side_squared")
        , ("function", "uncommented_test")
        ]
  whyOf "lib.rs" === ["The crate exists to exercise the Rust profile. ref:some-key"]
  whyOf "helper" === []
  whyOf "Shape" === ["A shape is a circle or a square."]
  whyOf "Area" === ["Areas are what shapes are for."]
  whyOf "area" === ["The area of the shape."]
  whyOf "nested" === ["The nested module's own documentation."]
  whyOf "LIMIT" === ["Limits keep the range small."]
  whyOf "Point" === []
  length [() | OrphanDocComment _ _ <- findings] === 1
  map testsOf ["square_area_is_side_squared", "uncommented_test", "helper"] === [[True], [True], [False]]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "rust/lib.rs/enum/Shape/variant/Circle"
        , "rust/lib.rs/enum/Shape/variant/Square"
        , "rust/lib.rs/struct/Point"
        , "rust/lib.rs/struct/Point/field/0"
        , "rust/lib.rs/struct/Point/field/1"
        , "rust/lib.rs/module/tests/function/uncommented_test"
        ]
  [renderUnitId u | TestWithoutRequirement u _ <- checkTests (Registry (Map.singleton (ReferenceKey "REQ-1") (Reference Requirement "squares" "here"))) model] === []

-- | A profile-path extraction of a Rust fixture through the sample's profile.
extractFixture :: Text -> PropertyT IO (Model Evidence)
extractFixture source = do
  profile <- sampleProfile
  loaded <- evalIO (loadProfileInterpreter profile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "rust" profile interpreter "lib.rs" "lib.rs" source)
  Extraction model _ <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  pure model

-- | Upstream's comment rules let the character after // or /// be a line break, so an empty comment
-- ran on through the next line and the code there vanished from the parse; //// is a plain comment
-- and no documentation. ref:REQ-rust-support ref:DEC-rust-visibility
prop_anEmptyRustLineCommentEndsAtItsLineAndHidesNoCode :: Property
prop_anEmptyRustLineCommentEndsAtItsLineAndHidesNoCode = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let visible source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [tokenText t | t <- toks, not (isEofToken t), tokenChannel t /= hiddenChannelName]
      hidden source = case interpreterTokenize interpreter source of
        Left err -> Left (renderLexError err)
        Right toks -> Right [(nameText (tokenType t), tokenText t) | t <- toks, tokenChannel t == hiddenChannelName, nameText (tokenType t) /= "WHITESPACE", nameText (tokenType t) /= "NEWLINE"]
  visible "//\nfn a() {}\n///\nfn b() {}\n" === Right ["fn", "a", "(", ")", "{", "}", "fn", "b", "(", ")", "{", "}"]
  hidden "//\n///\n////x\n/// doc\n" === Right [("LINE_COMMENT", "//"), ("OUTER_LINE_DOC", "///"), ("LINE_COMMENT", "////x"), ("OUTER_LINE_DOC", "/// doc")]
  model <- extractFixture (T.unlines ["//// Commented-out documentation.", "pub fn f() {}", "///", "/// Documented after an empty line of documentation.", "pub fn g() {}"])
  let whyOf n = [whyText (answerValue (decisionWhy d)) | u <- modelAllUnits model, whatName (answerValue (unitWhat u)) == n, d <- decisionsFor (unitId u) model]
  whyOf "f" === []
  whyOf "g" === ["Documented after an empty line of documentation."]

-- | rustc's missing_docs lint asks for documentation on what a crate exports: items marked pub without
-- a restriction, the items of a public trait and the variants of a public enum, which have no pub of
-- their own, and macros marked #[macro_export]; a private item, a pub(crate) item, and the methods of
-- a trait impl, which the trait documents, need none. ref:REQ-rust-support ref:DEC-rust-visibility
prop_rustProfileRequiresCommentsOnWhatIsVisibleOutsideTheCrate :: Property
prop_rustProfileRequiresCommentsOnWhatIsVisibleOutsideTheCrate = withTests 1 $ property $ do
  model <-
    extractFixture
      ( T.unlines
          [ "pub fn exported() {}"
          , "pub(crate) fn crate_only() {}"
          , "fn private() {}"
          , "pub trait Public { fn item(&self); type Out; }"
          , "trait Private { fn hidden(&self); }"
          , "pub enum Choice { Yes, No(u8) }"
          , "enum Inner { A }"
          , "pub struct Record { pub open: u8, closed: u8 }"
          , "pub struct Pair(pub u8, u8);"
          , "impl Public for Record { fn item(&self) {} type Out = u8; }"
          , "impl Record { pub fn new() -> Self { todo!() } fn helper(&self) {} }"
          , "#[macro_export]"
          , "macro_rules! exported_macro { () => {} }"
          , "macro_rules! local_macro { () => {} }"
          , "pub(super) const LIMIT: u8 = 1;"
          , "pub static NAME: &str = \"x\";"
          ]
      )
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitRequirement u == Required]
    === [ "rust/lib.rs/function/exported"
        , "rust/lib.rs/trait/Public"
        , "rust/lib.rs/trait/Public/function/item"
        , "rust/lib.rs/trait/Public/type/Out"
        , "rust/lib.rs/enum/Choice"
        , "rust/lib.rs/enum/Choice/variant/Yes"
        , "rust/lib.rs/enum/Choice/variant/No"
        , "rust/lib.rs/struct/Record"
        , "rust/lib.rs/struct/Record/field/open"
        , "rust/lib.rs/struct/Pair"
        , "rust/lib.rs/struct/Pair/field/0"
        , "rust/lib.rs/impl/Record/function/new"
        , "rust/lib.rs/macro/exported_macro"
        , "rust/lib.rs/static/NAME"
        ]

-- | A type has one inherent impl in rustdoc but an impl block per trait, and a trait impl is known by
-- its trait, so a unit id must say which trait an impl is for rather than number the impls of a type.
-- ref:REQ-rust-support ref:DEC-rust-visibility
prop_aRustTraitImplIsNamedByItsTraitAndItsSelfType :: Property
prop_aRustTraitImplIsNamedByItsTraitAndItsSelfType = withTests 1 $ property $ do
  model <-
    extractFixture
      ( T.unlines
          [ "struct Guard<T>(T);"
          , "impl<T> Guard<T> { fn a(&self) {} }"
          , "impl<T> Guard<T> { fn b(&self) {} }"
          , "impl<T> core::ops::Deref for Guard<T> { type Target = T; fn deref(&self) -> &T { &self.0 } }"
          , "impl<T: fmt::Debug> fmt::Debug for Guard<T> { fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { Ok(()) } }"
          , "unsafe impl<T: Sync> Sync for Guard<T> {}"
          , "impl<T> !Send for &'static mut Guard<T> {}"
          ]
      )
  [renderUnitId (unitId u) | u <- modelAllUnits model, unitKindText (whatKind (answerValue (unitWhat u))) `elem` ["impl", "function"]]
    === [ "rust/lib.rs/impl/Guard<T>"
        , "rust/lib.rs/impl/Guard<T>/function/a"
        , "rust/lib.rs/impl/Guard<T>#2"
        , "rust/lib.rs/impl/Guard<T>#2/function/b"
        , "rust/lib.rs/impl/core::ops::Deref-for-Guard<T>"
        , "rust/lib.rs/impl/core::ops::Deref-for-Guard<T>/function/deref"
        , "rust/lib.rs/impl/fmt::Debug-for-Guard<T>"
        , "rust/lib.rs/impl/fmt::Debug-for-Guard<T>/function/fmt"
        , "rust/lib.rs/impl/Sync-for-Guard<T>"
        , "rust/lib.rs/impl/!Send-for-&'static-mut-Guard<T>"
        ]

-- | The canonically commented dialect of the Rust grammar, with no units of a profile, so every unit
-- comes from the grammar's labels.
dialectProfile :: Profile
dialectProfile = Profile [".rs"] (SplitGrammarFiles "grammars/rust/canonically_commented/RustLexer.g4" "grammars/rust/canonically_commented/RustParser.g4") (Name "crate") [] defaultCommentSyntax Map.empty Map.empty Map.empty []

-- | An extraction through the Rust dialect.
extractDialect :: FilePath -> Text -> PropertyT IO Extraction
extractDialect path source = do
  loaded <- evalIO (loadProfileInterpreter dialectProfile)
  interpreter <- either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "rust" dialectProfile interpreter path path source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Doc comments are tokens of the dialect, so real Rust must still parse whole with them in every
-- place rustc allows, among them a macro's input and a test module. ref:REQ-rust-support
-- ref:DEC-rust-dialect
prop_theRustDialectParsesTheScopeguardSampleWithItsDocComments :: Property
prop_theRustDialectParsesTheScopeguardSampleWithItsDocComments = withTests 1 $ property $ do
  source <- evalIO (T.pack <$> readFile (sampleDir </> "source/src/lib.rs"))
  Extraction model findings <- extractDialect "lib.rs" source
  let names = [whatName (answerValue (unitWhat u)) | u <- modelAllUnits model]
  length (filter (== "should_run") names) === 4
  length [() | OrphanDocComment _ _ <- findings] === 0
  length (modelDecisions model) === 15
  null [whyText (answerValue (decisionWhy d)) | d <- modelDecisions model, decisionId d == decisionIdFor (UnitId ("rust" NonEmpty.:| ["lib.rs"]))] === False

-- | In the dialect the grammar says where a doc comment binds: /// above an item's attributes, //!
-- inside the module or file it documents, and a doc comment where no item follows, as above a
-- statement or after an attribute, is an orphan; //// is no documentation. ref:REQ-rust-support
-- ref:DEC-rust-dialect
prop_theRustDialectBindsOuterAndInnerDocCommentsAndReportsMisplacedOnes :: Property
prop_theRustDialectBindsOuterAndInnerDocCommentsAndReportsMisplacedOnes = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "lib.rs"
      ( T.unlines
          [ "//! The crate exercises the dialect. ref:some-key"
          , "//! It has two lines."
          , ""
          , "/// A pair of numbers."
          , "#[derive(Debug)]"
          , "pub struct Pair("
          , "    /// The first."
          , "    pub u8,"
          , "    u8,"
          , ");"
          , ""
          , "//// Commented-out documentation."
          , "pub fn plain() {}"
          , ""
          , "#[inline]"
          , "/// After the attribute, so an orphan."
          , "pub fn late() {"
          , "    /// On a statement, so an orphan."
          , "    let x = 1;"
          , "}"
          , ""
          , "pub mod inner {"
          , "    //! The inner module documents itself."
          , "    /** A block doc comment. */"
          , "    pub enum Choice { /// The first choice."
          , "        Yes, No }"
          , "}"
          , ""
          , "macro_rules! made { () => { /// Documentation in a macro's input."
          , "    struct Made; } }"
          ]
      )
  let whys = [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
  whys
    === [ ("rust/lib.rs", "The crate exercises the dialect. ref:some-key\nIt has two lines.")
        , ("rust/lib.rs/struct/Pair", "A pair of numbers.")
        , ("rust/lib.rs/struct/Pair/field/0", "The first.")
        , ("rust/lib.rs/module/inner", "The inner module documents itself.")
        , ("rust/lib.rs/module/inner/enum/Choice", "A block doc comment.")
        , ("rust/lib.rs/module/inner/enum/Choice/variant/Yes", "The first choice.")
        ]
  mapMaybe (\d -> if decisionId d == decisionIdFor (UnitId ("rust" NonEmpty.:| ["lib.rs"])) then Just (whyReferences (answerValue (decisionWhy d))) else Nothing) (modelDecisions model) === [[ReferenceKey "some-key"]]
  length [() | OrphanDocComment _ _ <- findings] === 2
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === ["rust/lib.rs/function/plain", "rust/lib.rs/function/late", "rust/lib.rs/module/inner/enum/Choice/variant/No"]

-- | rustc reads a doc comment wherever an attribute may stand and warns of one that documents
-- nothing, so a crate with one inside an expression, before a closing bracket, or at the end of a
-- block still compiles; canon must read it whole, keep the Whys of its items, and report each such
-- comment as an orphan. ref:REQ-rust-support ref:DEC-rust-dialect ref:DEC-stray-comments
prop_aRustDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan :: Property
prop_aRustDocCommentAnywhereInAFileParsesAndOneThatDocumentsNothingIsAnOrphan = withTests 1 $ property $ do
  Extraction model findings <-
    extractDialect
      "lib.rs"
      ( T.unlines
          [ "/// A function."
          , "#[inline]"
          , "/// After an attribute."
          , "pub fn f(a: u8) -> u8 {"
          , "    let x = g(1, 2,"
          , "        /// After the last argument."
          , "    );"
          , "    let y = x"
          , "        /// Inside an expression."
          , "        + 1;"
          , "    let z = y"
          , "        /// Before a method call."
          , "        .max(a);"
          , "    match z {"
          , "        1 => 2,"
          , "        /// After the last arm."
          , "    }"
          , "    /// At the end of a block."
          , "}"
          , ""
          , "/// A pair."
          , "pub struct P {"
          , "    /// A field."
          , "    pub a: u8,"
          , "    /// After the last field."
          , "}"
          , "/// At the end of the file."
          ]
      )
  [renderUnitId u | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
    === ["rust/lib.rs/function/f", "rust/lib.rs/struct/P", "rust/lib.rs/struct/P/field/a"]
  sort [positionLine (spanStart sp) | OrphanDocComment _ sp <- findings] === [3, 6, 9, 12, 16, 18, 25, 27]

-- | canon reads a crate without knowing its edition, and in the 2015 edition async, try, and dyn are
-- ordinary names, so a 2015 crate must parse with them as names while a later crate's async blocks
-- and dyn types still parse as such. ref:REQ-rust-support ref:DEC-rust-grammar
prop_asyncTryAndDynAreNamesInA2015EditionCrateAndKeywordsInLaterOnes :: Property
prop_asyncTryAndDynAreNamesInA2015EditionCrateAndKeywordsInLaterOnes = withTests 1 $ property $ do
  interpreter <- interpreterOrFail
  let parsed source = either (Left . renderInterpretError) Right (interpretText interpreter (Name "crate") "lib.rs" source)
  case parsed "trait T { fn f(&self, u8); }\nfn g(x: Box<T>) { let async = 1; let try = async; let dyn = try; }" of
    Left err -> annotate (T.unpack err) >> failure
    Right tree -> length (treeRuleNodes (Name "letStatement") tree) === 3
  case parsed "async fn f(x: &dyn Fn()) { let y = async move { 1 }.await; }" of
    Left err -> annotate (T.unpack err) >> failure
    Right tree -> do
      length (treeRuleNodes (Name "asyncBlockExpression") tree) === 1
      [nameText (tokenType t) | node <- treeRuleNodes (Name "traitObjectTypeOneBound") tree, t <- take 1 (treeTokens node)] === ["KW_DYN"]
