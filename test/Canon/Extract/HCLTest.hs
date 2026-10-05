-- | HCL is read through canon's own HCL grammar and its dialect, which the HCL sample's profile
-- names, so these properties check both against what a Terraform author means by a block and its
-- documentation. ref:DEC-hcl-grammar ref:REQ-hcl-support
module Canon.Extract.HCLTest (tests) where

import Canon.Antlr4.Interpret (InterpretError, interpretFile, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Parse (treeRuleNodes)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (Config (..), defaultConfig, readConfigFile, renderConfigError)
import Canon.Decisions (emptyLedger)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Check (checkModel)
import Canon.Model.Finding
import Canon.Profile
import Canon.Registry (emptyRegistry)
import qualified Data.Map.Strict as Map
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
    "hcl"
    [ testProperty "the HCL grammars parse the key pair sample into its blocks" prop_hclGrammarsParseTheKeyPairSampleIntoItsBlocks
    , testProperty "the HCL dialect names blocks by their labels and reads descriptions as their Why" prop_hclDialectNamesBlocksByTheirLabelsAndReadsDescriptionsAsTheirWhy
    , testProperty "the HCL dialect binds a comment only to the block directly below it" prop_hclDialectBindsACommentOnlyToTheBlockDirectlyBelowIt
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/hcl-terraform-aws-key-pair"

orFail :: Either InterpretError a -> PropertyT IO a
orFail = either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Terraform project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "hcl" (configLanguages config))
  pure profile {profileGrammar = resolved (profileGrammar profile)}
  where
    resolve path = normalise (sampleDir </> path)
    resolved source = case source of
      SplitGrammarFiles lexer parser -> SplitGrammarFiles (resolve lexer) (resolve parser)
      CombinedGrammarFile path -> CombinedGrammarFile (resolve path)

-- | Extracts a fixture through the sample's profile.
extracted :: FilePath -> Text -> PropertyT IO Extraction
extracted name source = do
  profile <- sampleProfile
  interpreter <- evalIO (loadProfileInterpreter profile) >>= orFail
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "hcl" profile interpreter name name source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | A real module must parse whole through both the plain grammar and the dialect, with every block
-- found where Terraform finds it, or a Terraform project's check would report parse failures
-- instead of findings. ref:REQ-hcl-support ref:DEC-hcl-grammar
prop_hclGrammarsParseTheKeyPairSampleIntoItsBlocks :: Property
prop_hclGrammarsParseTheKeyPairSampleIntoItsBlocks = withTests 1 $ property $ do
  plain <- evalIO (loadInterpreter "grammars/hcl/HCLLexer.g4" "grammars/hcl/HCLParser.g4") >>= orFail
  dialect <- evalIO (loadInterpreter "grammars/hcl/canonically_commented/HCLLexer.g4" "grammars/hcl/canonically_commented/HCLParser.g4") >>= orFail
  let file = (sampleDir </>)
  mainTree <- evalIO (interpretFile plain (Name "configFile") (file "source/main.tf")) >>= orFail
  length (treeRuleNodes (Name "block") mainTree) === 2
  variablesTree <- evalIO (interpretFile plain (Name "configFile") (file "source/variables.tf")) >>= orFail
  length (treeRuleNodes (Name "block") variablesTree) === 10
  exampleTree <- evalIO (interpretFile plain (Name "configFile") (file "source/examples/complete/main.tf")) >>= orFail
  length (treeRuleNodes (Name "block") exampleTree) === 6
  length (treeRuleNodes (Name "templateExpr") exampleTree) === 11
  wrapperTree <- evalIO (interpretFile dialect (Name "configFile") (file "source/wrappers/main.tf")) >>= orFail
  length (treeRuleNodes (Name "topItem") wrapperTree) === 1
  length (treeRuleNodes (Name "functionCall") wrapperTree) === 10
  outputsTree <- evalIO (interpretFile dialect (Name "configFile") (file "source/outputs.tf")) >>= orFail
  length (treeRuleNodes (Name "topItem") outputsTree) === 11

fixture :: Text
fixture =
  T.unlines
    [ "terraform {"
    , "  required_version = \">= 1.5\""
    , "}"
    , ""
    , "resource \"aws_vpc\" \"main\" {"
    , "  cidr_block = \"10.0.0.0/16\""
    , "  tags = { Name = \"main-${var.region}\" }"
    , "}"
    , ""
    , "data \"aws_ami\" \"ubuntu\" {"
    , "  most_recent = true"
    , "  owners      = [for o in var.owners : lower(o) if o != \"\"]"
    , "}"
    , ""
    , "variable \"region\" {"
    , "  description = \"The region every resource lives in, as ref:REQ-region requires.\""
    , "  type        = string"
    , "  validation {"
    , "    condition     = length(var.region) > 0"
    , "    error_message = \"The region must not be empty.\""
    , "  }"
    , "}"
    , ""
    , "variable \"owners\" {"
    , "  description = <<-EOT"
    , "    The accounts whose images may be used,"
    , "    since only they are trusted."
    , "  EOT"
    , "  type = list(string)"
    , "}"
    , ""
    , "variable \"undocumented\" {"
    , "  type = number"
    , "}"
    , ""
    , "output \"vpc_id\" {"
    , "  value = aws_vpc.main.id"
    , "}"
    , ""
    , "locals {"
    , "  # Every name starts with the region, so names never collide across regions."
    , "  prefix = \"${var.region}-app\""
    , "  names  = { for k, v in var.apps : k => \"${local.prefix}-${v}\" }"
    , "}"
    , ""
    , "module \"network\" {"
    , "  source = \"./network\""
    , "}"
    , ""
    , "# The plan must succeed before anything is applied. ref:REQ-plan"
    , "run \"plan_succeeds\" {"
    , "  command = plan"
    , "}"
    , ""
    , "run \"uncommented\" {"
    , "  command = plan"
    , "}"
    , ""
    , "check \"health\" {"
    , "  assert {"
    , "    condition     = data.aws_ami.ubuntu.id != null"
    , "    error_message = \"No image.\""
    , "  }"
    , "}"
    ]

-- | Terraform addresses a block by its type and labels and shows a variable's or an output's
-- description as its documentation, so the dialect must name each block as Terraform addresses it,
-- read a description as the Why, require a Why on the module's interface, and recognise a test
-- file's run blocks as tests, for the Why of a Terraform block to be its documentation.
-- ref:REQ-hcl-support ref:DEC-hcl-grammar
prop_hclDialectNamesBlocksByTheirLabelsAndReadsDescriptionsAsTheirWhy :: Property
prop_hclDialectNamesBlocksByTheirLabelsAndReadsDescriptionsAsTheirWhy = withTests 1 $ property $ do
  Extraction model findings <- extracted "main.tf" fixture
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      byName n = [u | u <- units, nameOf u == n]
      whys n = [answerValue (decisionWhy d) | u <- byName n, d <- decisionsFor (unitId u) model]
      whyOf n = map whyText (whys n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("terraform", "terraform")
        , ("resource", "aws_vpc.main")
        , ("data", "aws_ami.ubuntu")
        , ("variable", "region")
        , ("variable", "owners")
        , ("variable", "undocumented")
        , ("output", "vpc_id")
        , ("local", "prefix")
        , ("local", "names")
        , ("module", "network")
        , ("run", "plan_succeeds")
        , ("run", "uncommented")
        , ("block", "check.health")
        ]
  whyOf "region" === ["The region every resource lives in, as ref:REQ-region requires."]
  map whyReferences (whys "region") === [[ReferenceKey "REQ-region"]]
  whyOf "owners" === ["The accounts whose images may be used,\nsince only they are trusted."]
  whyOf "prefix" === ["Every name starts with the region, so names never collide across regions."]
  whyOf "plan_succeeds" === ["The plan must succeed before anything is applied. ref:REQ-plan"]
  map (map unitTest . byName) ["plan_succeeds", "uncommented", "network"] === [[True], [True], [False]]
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "hcl/main.tf/variable/undocumented"
        , "hcl/main.tf/output/vpc_id"
        , "hcl/main.tf/run/uncommented"
        ]

attachment :: Text
attachment =
  T.unlines
    [ "################################################################################"
    , "# Key Pair"
    , "################################################################################"
    , ""
    , "resource \"aws_key_pair\" \"parted\" {"
    , "  # A note inside a body binds to nothing."
    , "  key_name = var.key_name # and neither does a trailing note"
    , "  tags = merge("
    , "    # nor a note inside brackets,"
    , "    var.tags,"
    , "    {"
    , "      # nor one inside an object."
    , "      Name = \"x\""
    , "    },"
    , "  )"
    , "}"
    , ""
    , "// The key every instance trusts,"
    , "/* rotated each quarter. */"
    , "resource \"aws_key_pair\" \"joined\" {"
    , "  key_name = \"joined\""
    , "}"
    , ""
    , "# The comment above wins over the description."
    , "output \"both\" {"
    , "  description = \"Shadowed.\""
    , "  value       = 1"
    , "}"
    , ""
    , "include \"root\" {"
    , "  path = find_in_parent_folders()"
    , "}"
    , ""
    , "# The inputs every environment shares."
    , "inputs = {"
    , "  policy = <<EOF"
    , "{\"Statement\": []}"
    , "EOF"
    , "}"
    ]

-- | HCL has no doc comment syntax, so only a comment directly above a block can be read as that
-- block's documentation: a section banner that a blank line parts from the block, and a note
-- inside a body, after code, or inside brackets, must bind to nothing and not be reported, while
-- comment lines with nothing between them are one comment. ref:REQ-hcl-support ref:DEC-hcl-grammar
prop_hclDialectBindsACommentOnlyToTheBlockDirectlyBelowIt :: Property
prop_hclDialectBindsACommentOnlyToTheBlockDirectlyBelowIt = withTests 1 $ property $ do
  Extraction model findings <- extracted "root.hcl" attachment
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("resource", "aws_key_pair.parted")
        , ("resource", "aws_key_pair.joined")
        , ("output", "both")
        , ("block", "include.root")
        , ("attribute", "inputs")
        ]
  whyOf "aws_key_pair.parted" === []
  whyOf "aws_key_pair.joined" === ["The key every instance trusts,\nrotated each quarter."]
  whyOf "both" === ["The comment above wins over the description."]
  whyOf "inputs" === ["The inputs every environment shares."]
  length [() | OrphanDocComment _ _ <- findings] === 0
