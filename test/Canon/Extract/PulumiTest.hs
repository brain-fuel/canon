-- | Pulumi YAML programs are read through canon's own YAML grammar and its Pulumi dialect, which the
-- Pulumi sample's profile names, so these properties check both against what a Pulumi author
-- means by a resource, a config key, and their documentation. ref:DEC-pulumi-yaml-grammar
-- ref:REQ-pulumi-yaml-support
module Canon.Extract.PulumiTest (tests) where

import Canon.Antlr4.Interpret (InterpretError, interpretFile, interpretText, loadInterpreter, renderInterpretError)
import Canon.Antlr4.Parse (ParseTree, treeRuleNodes, treeTokens)
import Canon.Antlr4.Token (Token (..))
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
import qualified Data.List.NonEmpty as NonEmpty
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
    "pulumi"
    [ testProperty "the YAML grammars parse the Pulumi examples into their entries" prop_yamlGrammarsParseThePulumiExamplesIntoTheirEntries
    , testProperty "the Pulumi dialect makes units of resources, variables, outputs, and config keys" prop_pulumiDialectMakesUnitsOfResourcesVariablesOutputsAndConfigKeys
    , testProperty "the Pulumi profile owns Pulumi programs and stack files by name" prop_pulumiProfileOwnsPulumiProgramsAndStackFilesByName
    , testProperty "the Pulumi dialect reads quoted keys, flow interpolations, and template config" prop_pulumiDialectReadsQuotedKeysFlowInterpolationsAndTemplateConfig
    , testProperty "a Pulumi comment anywhere in a program parses and only one directly above an entry binds" prop_aPulumiCommentAnywhereInAProgramParsesAndOnlyOneDirectlyAboveAnEntryBinds
    , testProperty "the YAML grammars read anchors, tags, flow collections, complex keys, and streams" prop_yamlGrammarsReadAnchorsTagsFlowCollectionsComplexKeysAndStreams
    , testProperty "a plain scalar continues on indented lines whatever they hold" prop_aPlainScalarContinuesOnIndentedLinesWhateverTheyHold
    , testProperty "a document marker is one only at the start of its line" prop_aDocumentMarkerIsOneOnlyAtTheStartOfItsLine
    , testProperty "the plain YAML profile reads any other YAML file without units" prop_thePlainYamlProfileReadsAnyOtherYamlFileWithoutUnits
    ]

sampleDir :: FilePath
sampleDir = "lang_samples/pulumi-yaml-examples"

orFail :: Either InterpretError a -> PropertyT IO a
orFail = either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure

-- | The profile as the sample's canon.yaml declares it, with its grammar paths made relative to the
-- repository root, so the test reads the profile a Pulumi project would copy.
sampleProfile :: PropertyT IO Profile
sampleProfile = do
  loaded <- evalIO (readConfigFile (sampleDir </> "canon.yaml"))
  config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
  profile <- maybe failure pure (Map.lookup "pulumi" (configLanguages config))
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
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "pulumi" profile interpreter name name source)
  either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result

-- | Real Pulumi programs must parse whole through both the plain YAML grammar and the Pulumi
-- dialect, with block scalars, flow collections, and comments where YAML puts them, or a Pulumi
-- project's check would report parse failures instead of findings. ref:REQ-pulumi-yaml-support
-- ref:DEC-pulumi-yaml-grammar
prop_yamlGrammarsParseThePulumiExamplesIntoTheirEntries :: Property
prop_yamlGrammarsParseThePulumiExamplesIntoTheirEntries = withTests 1 $ property $ do
  plain <- evalIO (loadInterpreter "grammars/yaml/YAMLLexer.g4" "grammars/yaml/YAMLParser.g4") >>= orFail
  dialect <- evalIO (loadInterpreter "grammars/yaml/canonically_commented/YAMLLexer.g4" "grammars/yaml/canonically_commented/YAMLParser.g4") >>= orFail
  let file = (sampleDir </>)
  website <- evalIO (interpretFile plain (Name "yamlFile") (file "source/aws-yaml-static-website/Pulumi.yaml")) >>= orFail
  length (treeRuleNodes (Name "blockScalar") website) === 1
  webserver <- evalIO (interpretFile plain (Name "yamlFile") (file "source/webserver-yaml/Pulumi.yaml")) >>= orFail
  length (treeRuleNodes (Name "flowCollection") webserver) === 3
  length (treeRuleNodes (Name "blockScalar") webserver) === 1
  wordpress <- evalIO (interpretFile dialect (Name "yamlFile") (file "source/aws-yaml-ansible-wordpress/Pulumi.yaml")) >>= orFail
  length (treeRuleNodes (Name "resourceEntry") wordpress) === 17
  length (treeRuleNodes (Name "variableEntry") wordpress) === 4
  length (treeRuleNodes (Name "configEntry") wordpress) === 7
  length (treeRuleNodes (Name "outputEntry") wordpress) === 1

fixture :: Text
fixture =
  T.unlines
    [ "name: site"
    , "runtime: yaml"
    , "description: A fixture for the Pulumi profile."
    , "config:"
    , "  # The size of every instance. ref:REQ-size"
    , "  instanceType:"
    , "    type: string"
    , "    default: t3.micro"
    , "  region:"
    , "    description: |"
    , "      The region every resource lives in,"
    , "      as ref:REQ-region requires."
    , "    default: us-east-1"
    , "  undocumented:"
    , "    type: integer"
    , "  aws:profile: dev"
    , "variables:"
    , "  # Looked up once, so every instance shares one image."
    , "  ami:"
    , "    fn::invoke:"
    , "      function: aws:ec2/getAmi:getAmi"
    , "      arguments:"
    , "        mostRecent: true"
    , "        owners: [\"amazon\", self]"
    , "      return: id"
    , "resources:"
    , "  # The bucket the site is served from,"
    , "  # one per stack."
    , "  site-bucket:"
    , "    type: aws:s3:Bucket"
    , "    properties:"
    , "      tags: {Name: site, Team: \"web\"}"
    , "      policy: |"
    , "        {"
    , "          \"Version\": \"2012-10-17\""
    , "        }"
    , "  # A banner parted by a blank line."
    , ""
    , "  index.html:"
    , "    type: aws:s3:BucketObject"
    , "    properties:"
    , "      bucket: ${site-bucket}"
    , "      source:"
    , "        fn::fileAsset: ./www/index.html # a trailing note"
    , "    options:"
    , "      dependsOn:"
    , "        # A note above a sequence entry binds to nothing."
    , "        - ${site-bucket}"
    , "      ignoreChanges:"
    , "      - tags"
    , "outputs:"
    , "  # The address the site answers on."
    , "  url: ${site-bucket.websiteEndpoint}"
    , "  bucketName: ${site-bucket.bucket}"
    ]

-- | Pulumi addresses a resource, variable, output, and config key by its key, and shows a config
-- key's description as its documentation, so the dialect must make each a unit named by its key,
-- bind the comment directly above it, read a description as the Why, and require a Why on a
-- program's outputs and declared config, for the Why of a Pulumi entry to be its documentation.
-- ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar
prop_pulumiDialectMakesUnitsOfResourcesVariablesOutputsAndConfigKeys :: Property
prop_pulumiDialectMakesUnitsOfResourcesVariablesOutputsAndConfigKeys = withTests 1 $ property $ do
  Extraction model findings <- extracted "Pulumi.yaml" fixture
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whys n = [answerValue (decisionWhy d) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
      whyOf n = map whyText (whys n)
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("config", "instanceType")
        , ("config", "region")
        , ("config", "undocumented")
        , ("config", "aws:profile")
        , ("variable", "ami")
        , ("resource", "site-bucket")
        , ("resource", "index.html")
        , ("output", "url")
        , ("output", "bucketName")
        ]
  whyOf "instanceType" === ["The size of every instance. ref:REQ-size"]
  whyOf "region" === ["The region every resource lives in,\nas ref:REQ-region requires."]
  map whyReferences (whys "region") === [[ReferenceKey "REQ-region"]]
  whyOf "ami" === ["Looked up once, so every instance shares one image."]
  whyOf "site-bucket" === ["The bucket the site is served from,\none per stack."]
  whyOf "index.html" === []
  whyOf "url" === ["The address the site answers on."]
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model]
    === [ "pulumi/Pulumi.yaml/config/undocumented"
        , "pulumi/Pulumi.yaml/output/bucketName"
        ]

stackFile :: Text
stackFile =
  T.unlines
    [ "config:"
    , "  aws:region: us-west-2"
    , "  site:dbPassword:"
    , "    secure: AAABAKxAyhCqbb2Y"
    ]

-- | Pulumi reads a program from Pulumi.yaml or a Main.yaml and a stack's settings from
-- Pulumi.<stack>.yaml, and no other YAML file, so the profile must own those files by name and a
-- stack file's keys, which set values rather than declare them, must not require a Why.
-- ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar
prop_pulumiProfileOwnsPulumiProgramsAndStackFilesByName :: Property
prop_pulumiProfileOwnsPulumiProgramsAndStackFilesByName = withTests 1 $ property $ do
  profile <- sampleProfile
  let profiles = Map.fromList [("pulumi", profile)]
      owner path = fst <$> profileForPath profiles path
  map owner ["infra/Pulumi.yaml", "Pulumi.dev.yaml", "app/Main.yaml", "Pulumi.yml", "docker-compose.yaml", ".github/workflows/ci.yml"]
    === [Just "pulumi", Just "pulumi", Just "pulumi", Just "pulumi", Nothing, Nothing]
  Extraction model _ <- extracted "Pulumi.dev.yaml" stackFile
  let units = modelAllUnits model
  [whatName (answerValue (unitWhat u)) | u <- units, unitKindText (whatKind (answerValue (unitWhat u))) == "config"] === ["aws:region", "site:dbPassword"]
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === []

quotedAndFlow :: Text
quotedAndFlow =
  T.unlines
    [ "name: site"
    , "runtime: yaml"
    , "template:"
    , "  displayName: A site"
    , "  config:"
    , "    aws:region:"
    , "      description: The region to deploy into"
    , "      default: us-west-2"
    , "    siteName:"
    , "      type: string"
    , "resources:"
    , "  # The page the site serves."
    , "  \"index.html\":"
    , "    type: aws:s3:BucketObject"
    , "    properties:"
    , "      tags: {\"Name\":\"index\", \"Size\":1}"
    , "    options:"
    , "      dependsOn: [${site-bucket}, ${logs}]"
    , "  'site-bucket':"
    , "    type: aws:s3:Bucket"
    ]

-- | Pulumi addresses a resource by its key whether or not the key is quoted, writes interpolations
-- inside flow sequences, accepts JSON-style pairs, and asks for a template's config keys when it
-- makes a project, so the dialect must name a quoted key without its quotes, parse those flow
-- collections, and make each template config key a unit. ref:REQ-pulumi-yaml-support
-- ref:DEC-pulumi-yaml-grammar
prop_pulumiDialectReadsQuotedKeysFlowInterpolationsAndTemplateConfig :: Property
prop_pulumiDialectReadsQuotedKeysFlowInterpolationsAndTemplateConfig = withTests 1 $ property $ do
  Extraction model findings <- extracted "Pulumi.yaml" quotedAndFlow
  let units = modelAllUnits model
      nameOf u = whatName (answerValue (unitWhat u))
      kindOf u = unitKindText (whatKind (answerValue (unitWhat u)))
      whyOf n = [whyText (answerValue (decisionWhy d)) | u <- units, nameOf u == n, d <- decisionsFor (unitId u) model]
  [(kindOf u, nameOf u) | u <- units, kindOf u /= "file"]
    === [ ("templateConfig", "aws:region")
        , ("templateConfig", "siteName")
        , ("resource", "index.html")
        , ("resource", "site-bucket")
        ]
  whyOf "aws:region" === ["The region to deploy into"]
  whyOf "index.html" === ["The page the site serves."]
  length [() | OrphanDocComment _ _ <- findings] === 0
  [renderUnitId u | MissingCanonicalComment u _ <- checkModel emptyRegistry emptyLedger model] === ["pulumi/Pulumi.yaml/templateConfig/siteName"]

-- | Pulumi reads a comment wherever YAML allows one, so canon must read a program with comments
-- among a resource's properties, in a sequence, in a flow collection, after a block scalar, and at
-- the end of a section or of the file; only the comment directly above an entry is its Why, and the
-- others bind to nothing and are not reported, since YAML has no doc comment syntax.
-- ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar ref:DEC-stray-comments
prop_aPulumiCommentAnywhereInAProgramParsesAndOnlyOneDirectlyAboveAnEntryBinds :: Property
prop_aPulumiCommentAnywhereInAProgramParsesAndOnlyOneDirectlyAboveAnEntryBinds = withTests 1 $ property $ do
  Extraction model findings <-
    extracted
      "Pulumi.yaml"
      ( T.unlines
          [ "name: odd"
          , "runtime: yaml"
          , "resources:"
          , "  # The bucket the site is served from."
          , "  bucket:"
          , "    type: aws:s3:Bucket"
          , "    properties:"
          , "      # Among the properties."
          , "      acl: private"
          , "      tags: [a,"
          , "        # In a flow collection."
          , "        b]"
          , "      rules:"
          , "        # In a sequence."
          , "        - x"
          , "        # Between items."
          , "        - y"
          , "      policy: |"
          , "        # Text of a block scalar."
          , "      # After a block scalar."
          , "      index: 1"
          , "  # At the end of a section."
          , "outputs:"
          , "  # The name of the bucket."
          , "  name: ${bucket.id}"
          , "# At the end of the file."
          ]
      )
  [(renderUnitId u, whyText (answerValue (decisionWhy d))) | d <- modelDecisions model, u <- NonEmpty.toList (decisionUnits d)]
    === [("pulumi/Pulumi.yaml/resource/bucket", "The bucket the site is served from."), ("pulumi/Pulumi.yaml/output/name", "The name of the bucket.")]
  [() | OrphanDocComment _ _ <- findings] === []

-- | Parses a fixture with the plain YAML grammar and with the Pulumi dialect, which must read every
-- YAML file the plain grammar reads, and gives the plain grammar's tree.
parsedBoth :: Text -> PropertyT IO ParseTree
parsedBoth source = do
  plain <- evalIO (loadInterpreter "grammars/yaml/YAMLLexer.g4" "grammars/yaml/YAMLParser.g4") >>= orFail
  dialect <- evalIO (loadInterpreter "grammars/yaml/canonically_commented/YAMLLexer.g4" "grammars/yaml/canonically_commented/YAMLParser.g4") >>= orFail
  _ <- orFail (interpretText dialect (Name "yamlFile") "t.yaml" source)
  orFail (interpretText plain (Name "yamlFile") "t.yaml" source)

-- | The texts of a tree's tokens of one type.
tokensOf :: Text -> ParseTree -> [Text]
tokensOf ty tree = [tokenText t | t <- treeTokens tree, tokenType t == Name ty]

-- | YAML files beyond the block subset, such as Rails-style anchors and merge keys, CloudFormation
-- tags, a GitHub matrix written as a flow mapping over several lines, complex keys, and streams of
-- documents, are YAML 1.2, so both grammars must read them: a tag or anchor on its own line above
-- the block collection it belongs to, a verbatim tag, a block collection or block scalar as a
-- complex key, a complex key in a flow mapping, a plain scalar spanning lines in a flow
-- collection, and a document after an end marker.
-- ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar
prop_yamlGrammarsReadAnchorsTagsFlowCollectionsComplexKeysAndStreams :: Property
prop_yamlGrammarsReadAnchorsTagsFlowCollectionsComplexKeysAndStreams = withTests 1 $ property $ do
  tree <-
    parsedBoth
      ( T.unlines
          [ "%YAML 1.2"
          , "---"
          , "defaults: &defaults"
          , "  adapter: postgres"
          , "development:"
          , "  <<: *defaults"
          , "  database: dev"
          , "tags: [!!str 1, !Ref Bucket, !<tag:yaml.org,2002:int> \"2\"]"
          , "seq:"
          , "- &first"
          , "  name: one"
          , "- *first"
          , "- !!map"
          , "    name: two"
          , "matrix: {os: [ubuntu-latest,"
          , "    macos-latest],"
          , "  node: [18, 20]}"
          , "? - a"
          , "  - b"
          , ": complex"
          , "? |"
          , "  block key"
          , ": - x"
          , "flow: {? k : v}"
          , "words: [a plain scalar"
          , "  over two lines, and one]"
          , "..."
          , "second: document"
          ]
      )
  length (treeRuleNodes (Name "document") tree) === 2
  tokensOf "ANCHOR" tree === ["&defaults", "&first"]
  tokensOf "ALIAS" tree === ["*defaults", "*first"]
  tokensOf "TAG" tree === ["!!str", "!Ref", "!<tag:yaml.org,2002:int>", "!!map"]
  length (tokensOf "QUESTION" tree) === 3
  length (treeRuleNodes (Name "flowCollection") tree) === 6
  filter (T.isInfixOf "\n") (tokensOf "PLAIN" tree) === ["a plain scalar\n  over two lines"]

-- | GitHub workflows, Kubernetes manifests, and issue forms continue a plain scalar on lines that
-- hold quotes, brackets, and braces, as a shell command's `if [[ -e f ]]` or an expression's
-- closing `}}`, which YAML reads as text when the line is indented past the scalar's parent, so the
-- grammars must read each such line as a continuation and the next key at the parent's indentation
-- as an entry. ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar
prop_aPlainScalarContinuesOnIndentedLinesWhateverTheyHold :: Property
prop_aPlainScalarContinuesOnIndentedLinesWhateverTheyHold = withTests 1 $ property $ do
  tree <-
    parsedBoth
      ( T.unlines
          [ "steps:"
          , "  - name: Upload"
          , "    run: node upload.js \"${{"
          , "      github.sha }}\" \"${{ runner.temp"
          , "      }}/tarballs\""
          , "    shell: bash"
          , "args:"
          , "- while true; do"
          , "    if [[ -e /etc/labels ]]; then"
          , "      echo -en '\\n'; fi;"
          , "  done;"
          , "- next"
          , "description: You have run into problems with the"
          , "  \"flutter\" tool, or [other] issues"
          ]
      )
  tokensOf "PLAIN_CONTINUATION" tree
    === [ "github.sha }}\" \"${{ runner.temp"
        , "}}/tarballs\""
        , "if [[ -e /etc/labels ]]; then"
        , "echo -en '\\n'; fi;"
        , "done;"
        , "\"flutter\" tool, or [other] issues"
        ]
  length (treeRuleNodes (Name "mappingEntry") tree) === 6
  length (treeRuleNodes (Name "sequenceEntry") tree) === 3

-- | Three dashes or dots start or end a document only at the start of a line, so a marker followed
-- by a tag or an anchor, a value of three dashes or dots, a document after an end marker, and a
-- document indented as a whole, as Ansible playbooks are, must all read as YAML reads them.
-- ref:REQ-pulumi-yaml-support ref:DEC-pulumi-yaml-grammar
prop_aDocumentMarkerIsOneOnlyAtTheStartOfItsLine :: Property
prop_aDocumentMarkerIsOneOnlyAtTheStartOfItsLine = withTests 1 $ property $ do
  tree <-
    parsedBoth
      ( T.unlines
          [ "--- !settings"
          , "name: a"
          , "value: ---"
          , "other: ..."
          , "..."
          , "bare: document"
          , "--- &list"
          , "  - hosts: all"
          , "  - hosts: web"
          ]
      )
  length (tokensOf "DOCUMENT_START" tree) === 2
  length (tokensOf "DOCUMENT_END" tree) === 1
  length (treeRuleNodes (Name "document") tree) === 3
  filter (`elem` ["---", "..."]) (tokensOf "PLAIN" tree) === ["---", "..."]
  tokensOf "TAG" tree === ["!settings"]
  tokensOf "ANCHOR" tree === ["&list"]

-- | Most YAML files are not Pulumi programs: a Kubernetes manifest, a GitHub workflow, or any
-- settings file may have top-level config, resources, or outputs keys that the Pulumi dialect would
-- read as units. canon reads such a file through the plain YAML grammar under a profile that owns
-- .yaml and .yml with no units, while the Pulumi profile, whose file names win over any profile's
-- extensions, keeps Pulumi's programs and stack files. ref:REQ-pulumi-yaml-support
-- ref:DEC-pulumi-yaml-grammar
prop_thePlainYamlProfileReadsAnyOtherYamlFileWithoutUnits :: Property
prop_thePlainYamlProfileReadsAnyOtherYamlFileWithoutUnits = withTests 1 $ property $ do
  pulumi <- sampleProfile
  let yaml =
        pulumi
          { profileExtensions = [".yaml", ".yml"]
          , profileFiles = []
          , profileGrammar = SplitGrammarFiles "grammars/yaml/YAMLLexer.g4" "grammars/yaml/YAMLParser.g4"
          , profileUnits = []
          , profileComments = defaultCommentSyntax
          }
      profiles = Map.fromList [("pulumi", pulumi), ("yaml", yaml)]
      owner path = fst <$> profileForPath profiles path
  map owner ["Pulumi.yaml", "Pulumi.dev.yaml", "app/Main.yaml", ".github/workflows/ci.yml", "k8s/deployment.yaml"]
    === [Just "pulumi", Just "pulumi", Just "pulumi", Just "yaml", Just "yaml"]
  interpreter <- evalIO (loadProfileInterpreter yaml) >>= orFail
  let source = T.unlines ["# Settings for a service.", "config:", "  # The port it listens on.", "  port: 8080", "outputs:", "  url: http://localhost"]
  result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "yaml" yaml interpreter "settings.yaml" "settings.yaml" source)
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  [unitKindText (whatKind (answerValue (unitWhat u))) | u <- modelAllUnits model] === ["file"]
  [() | OrphanDocComment _ _ <- findings] === []
  Extraction pulumiModel _ <- extracted "Pulumi.yaml" source
  [whatName (answerValue (unitWhat u)) | u <- modelAllUnits pulumiModel, unitKindText (whatKind (answerValue (unitWhat u))) /= "file"] === ["port", "url"]
