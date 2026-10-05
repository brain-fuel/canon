-- | Rice's Tax reads CALM architecture descriptions through canon with a JSON grammar of its own,
-- so these properties read one through the same kind of grammar and check what canon makes of it.
-- ref:DEC-calm-ingestion ref:REQ-calm-ingestion
module Canon.Extract.CalmTest (tests) where

import Canon.Antlr4.Interpret (Interpreter, loadCombinedInterpreter, renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Config (defaultConfig)
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Profile
import Control.Exception (bracket)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "calm"
    [ testProperty "a CALM description yields its nodes, relationships, and flows with their descriptions as Whys" prop_aCalmDescriptionYieldsItsNodesRelationshipsAndFlowsWithTheirDescriptionsAsWhys
    , testProperty "a CALM description with a dangling reference or a repeated id is refused" prop_aCalmDescriptionWithADanglingReferenceOrARepeatedIdIsRefused
    ]

-- | A JSON grammar of the shape Rice's Tax ships for CALM.
jsonGrammar :: Text
jsonGrammar =
  T.unlines
    [ "grammar Calm;"
    , "json: value EOF;"
    , "value: object | array | STRING | NUMBER | 'true' | 'false' | 'null';"
    , "object: '{' (pair (',' pair)*)? '}';"
    , "pair: STRING ':' value;"
    , "array: '[' (value (',' value)*)? ']';"
    , "STRING: '\"' (ESC | ~[\"\\\\\\u0000-\\u001F])* '\"';"
    , "fragment ESC: '\\\\' ([\"\\\\/bfnrt] | 'u' HEX HEX HEX HEX);"
    , "fragment HEX: [0-9a-fA-F];"
    , "NUMBER: '-'? ('0' | [1-9] [0-9]*) ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?;"
    , "WS: [ \\t\\r\\n]+ -> skip;"
    ]

-- | The CALM profile: no units of its own, since the extractor reads the description's structure.
calmProfile :: Profile
calmProfile = Profile [".calm.json"] (CombinedGrammarFile "Calm.g4") (Name "json") [] defaultCommentSyntax Map.empty Map.empty Map.empty

-- | Loads the grammar from a scratch directory of its own name, since properties run at once.
calmInterpreter :: String -> PropertyT IO Interpreter
calmInterpreter name = do
  loaded <- evalIO $ do
    base <- getTemporaryDirectory
    let root = base </> ("canon-test-calm-" ++ name)
    bracket (createDirectoryIfMissing True root >> pure root) removeDirectoryRecursive $ \dir -> do
      writeFile (dir </> "Calm.g4") (T.unpack jsonGrammar)
      loadCombinedInterpreter (dir </> "Calm.g4")
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | Extracts a description.
extractCalm :: String -> Text -> PropertyT IO (Either GrammarExtractError Extraction)
extractCalm name source = do
  interpreter <- calmInterpreter name
  evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "calm" calmProfile interpreter "arch.calm.json" "arch.calm.json" source)

-- | A two-node description with one relationship and one flow.
description :: Text -> Text -> Text
description destination secondId =
  T.unlines
    [ "{"
    , "  \"$schema\": \"https://calm.finos.org/release/1.2/meta/calm.json\","
    , "  \"nodes\": ["
    , "    {\"unique-id\": \"gateway\", \"node-type\": \"service\", \"name\": \"API Gateway\", \"description\": \"Routes public requests. ref:REQ-routing\"},"
    , "    {\"unique-id\": \"" <> secondId <> "\", \"node-type\": \"database\", \"name\": \"Orders\", \"description\": \"Holds orders.\"}"
    , "  ],"
    , "  \"relationships\": ["
    , "    {\"unique-id\": \"gateway-orders\", \"description\": \"The gateway writes orders.\", \"relationship-type\": {\"connects\": {\"source\": {\"node\": \"gateway\"}, \"destination\": {\"node\": \"" <> destination <> "\"}}}}"
    , "  ],"
    , "  \"flows\": ["
    , "    {\"unique-id\": \"place-order\", \"name\": \"Place order\", \"description\": \"A customer places an order.\", \"transitions\": [{\"relationship-unique-id\": \"gateway-orders\"}]}"
    , "  ]"
    , "}"
    ]

-- | An architecture element is a unit whose Why is its description, so an architecture is
-- documented and vetted like code, each element required to say why it exists.
-- ref:REQ-calm-ingestion ref:DEC-calm-ingestion
prop_aCalmDescriptionYieldsItsNodesRelationshipsAndFlowsWithTheirDescriptionsAsWhys :: Property
prop_aCalmDescriptionYieldsItsNodesRelationshipsAndFlowsWithTheirDescriptionsAsWhys = withTests 1 $ property $ do
  result <- extractCalm "units" (description "orders" "orders")
  Extraction model findings <- either (\e -> annotate (T.unpack (renderGrammarExtractError e)) >> failure) pure result
  findings === []
  [(renderUnitId (unitId u), unitRequirement u) | u <- modelAllUnits model]
    === [ ("calm/arch.calm.json", Optional)
        , ("calm/arch.calm.json/node/gateway", Required)
        , ("calm/arch.calm.json/node/orders", Required)
        , ("calm/arch.calm.json/relationship/gateway-orders", Required)
        , ("calm/arch.calm.json/flow/place-order", Required)
        ]
  [(renderDecisionId (decisionId d), whyReferences (answerValue (decisionWhy d))) | d <- modelDecisions model]
    === [ ("decision/calm/arch.calm.json/node/gateway", [ReferenceKey "REQ-routing"])
        , ("decision/calm/arch.calm.json/node/orders", [])
        , ("decision/calm/arch.calm.json/relationship/gateway-orders", [])
        , ("decision/calm/arch.calm.json/flow/place-order", [])
        ]

-- | A relationship to a node that does not exist, or two nodes with one id, describes no
-- architecture, so the description is refused rather than read in part. ref:REQ-calm-ingestion
-- ref:DEC-calm-ingestion
prop_aCalmDescriptionWithADanglingReferenceOrARepeatedIdIsRefused :: Property
prop_aCalmDescriptionWithADanglingReferenceOrARepeatedIdIsRefused = withTests 1 $ property $ do
  dangling <- extractCalm "dangling" (description "payments" "orders")
  either renderGrammarExtractError (const "") dangling === "CALM refers to unknown node: payments"
  repeated <- extractCalm "repeated" (description "gateway" "gateway")
  either renderGrammarExtractError (const "") repeated === "duplicate CALM node ids: gateway"
