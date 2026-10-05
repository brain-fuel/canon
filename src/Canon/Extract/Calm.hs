-- | CALM descriptions are assertions about architecture, not evidence of deployed behaviour, so
-- canon reads one as units with stable node, relationship, and flow identities and exact source
-- spans, each element's description its Why, for Rice's Tax to vet like code.
-- ref:DEC-calm-ingestion
module Canon.Extract.Calm (calmUnits) where

import qualified Canon.Antlr4.Syntax
import Canon.Antlr4.Parse (ParseTree (..), treeTokens)
import Canon.Antlr4.Token (Token (..), isEofToken)
import Canon.CanonicalComment (parseCanonicalComment, toWhy)
import Canon.Model
import Canon.Span (Span (..), Position (..))
import Data.Aeson (Value (..), eitherDecodeStrict', encode)
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.FilePath (splitDirectories)

-- | Validates the ingestion boundary and builds review units. It is not full CALM JSON Schema
-- validation: interfaces, controls, decorators, and external references remain in the body.
-- ref:DEC-calm-ingestion
calmUnits :: FilePath -> FilePath -> Text -> ParseTree -> Either Text (CodeUnit Evidence, [Decision Evidence], [Span])
calmUnits idPath path _ tree = do
  rejectDuplicateKeys tree
  value <- treeValue tree
  object <- asObject value
  case KM.lookup "$schema" object of
    Just (String "https://calm.finos.org/release/1.2/meta/calm.json") -> pure ()
    _ -> Left "CALM ingestion requires $schema https://calm.finos.org/release/1.2/meta/calm.json"
  nodes <- arrayField "nodes" object
  relationships <- arrayField "relationships" object
  flows <- optionalArray "flows" object
  nodeIds <- mapM (fieldText "unique-id") nodes
  relationshipIds <- mapM (fieldText "unique-id") relationships
  flowIds <- mapM (fieldText "unique-id") flows
  unique "node" nodeIds
  unique "relationship" relationshipIds
  unique "flow" flowIds
  mapM_ validateNode nodes
  mapM_ (validateRelationship nodeIds) relationships
  mapM_ (validateFlow relationshipIds) flows
  let entries = [("node", "nodes", nodes), ("relationship", "relationships", relationships), ("flow", "flows", flows)]
  built <- fmap concat $ mapM (buildGroup tree) entries
  let root = unit fileId (T.pack idPath) "file" tree Optional [] (map fst built) value
  pure (root, concatMap snd built, [])
  where
    evidence = DerivedFromParse path
    fileId = UnitId ("calm" :| map T.pack (filter (/= ".") (splitDirectories idPath)))
    unit uid name kind node required chain nested value = CodeUnit
      uid (Answer (What name (UnitKind kind) Nothing) evidence)
      (Answer (HowText (TE.decodeUtf8 (LBS.toStrict (encode value)))) evidence)
      (Answer (Where path (nodeSpan node) chain Nothing) evidence)
      Nothing Nothing required False nested
    buildGroup root (kind, key, values) = do
      let objects = maybe [] arrayValues (fieldTree key root)
      if length objects /= length values then Left ("CALM source mapping failed for " <> key) else mapM (build kind) (zip objects values)
    build kind (node, value) = do
      ident <- fieldText "unique-id" value
      if isIdSegment ident then pure () else Left ("CALM unique-id must be a nonempty path segment: " <> ident)
      object <- asObject value
      let uid = UnitId (NE.fromList (NE.toList (unitIdSegments fileId) ++ [kind, ident]))
          display = case KM.lookup "name" object of Just (String n) -> n; _ -> ident
          description = case KM.lookup "description" object of Just (String d) -> d; _ -> ""
          body = Object (KM.delete "description" object)
          whyNode = maybe node id (fieldTree "description" node)
          sp = nodeSpan whyNode
          decisions = [Decision (decisionIdFor uid) (uid :| []) (Answer (toWhy (parseCanonicalComment description)) (Asserted (Assertion path sp))) (Where path sp [] Nothing) Nothing | not (T.null (T.strip description))]
      pure (unit uid display kind node Required [] [] body, decisions)

asObject :: Value -> Either Text (KM.KeyMap Value)
asObject (Object o) = Right o
asObject _ = Left "CALM element must be an object"

fieldText :: Text -> Value -> Either Text Text
fieldText key value = do
  object <- asObject value
  case KM.lookup (K.fromText key) object of
    Just (String t) | not (T.null (T.strip t)) -> Right t
    _ -> Left ("CALM element requires nonempty string " <> key)

arrayField :: Text -> KM.KeyMap Value -> Either Text [Value]
arrayField key object = case KM.lookup (K.fromText key) object of
  Just (Array a) -> Right (toList a)
  _ -> Left ("CALM requires array " <> key)

optionalArray :: Text -> KM.KeyMap Value -> Either Text [Value]
optionalArray key object = if KM.member (K.fromText key) object then arrayField key object else Right []

unique :: Text -> [Text] -> Either Text ()
unique kind ids = case [x | x : _ : _ <- group (sort ids)] of
  [] -> Right ()
  duplicates -> Left ("duplicate CALM " <> kind <> " ids: " <> T.intercalate ", " duplicates)

validateNode :: Value -> Either Text ()
validateNode v = do
  _ <- fieldText "name" v
  _ <- fieldText "description" v
  kind <- fieldText "node-type" v
  if kind `elem` ["actor", "ecosystem", "system", "service", "database", "network", "ldap", "webclient", "data-asset"] then Right () else Left ("unsupported CALM node-type: " <> kind)

validateRelationship :: [Text] -> Value -> Either Text ()
validateRelationship ids v = do
  o <- asObject v
  t <- maybe (Left "CALM relationship requires relationship-type") asObject (KM.lookup "relationship-type" o)
  refs <- case KM.toList t of
    [("connects", endpoints)] -> do
      e <- asObject endpoints
      mapM (\key -> maybe (Left ("CALM connects requires " <> key)) (fieldText "node") (KM.lookup (K.fromText key) e)) ["source", "destination"]
    [(kind, endpoints)] | kind `elem` ["interacts", "composed-of", "deployed-in"] -> do
      e <- asObject endpoints
      parent <- fieldText (if kind == "interacts" then "actor" else "container") endpoints
      members <- arrayField "nodes" e >>= mapM textValue
      pure (parent : members)
    _ -> Left "CALM relationship-type must contain one supported relationship variant"
  mapM_ (known "node" ids) refs

validateFlow :: [Text] -> Value -> Either Text ()
validateFlow ids v = do
  o <- asObject v
  _ <- fieldText "name" v
  _ <- fieldText "description" v
  transitions <- arrayField "transitions" o
  mapM_ (\t -> fieldText "relationship-unique-id" t >>= known "relationship" ids) transitions

known :: Text -> [Text] -> Text -> Either Text ()
known kind ids value = if value `elem` ids then Right () else Left ("CALM refers to unknown " <> kind <> ": " <> value)

textValue :: Value -> Either Text Text
textValue (String t) = Right t
textValue _ = Left "CALM reference must be a string"

-- The JSON grammar retains token spans; object order must not affect identity or attachment.
treeValue :: ParseTree -> Either Text Value
treeValue = either (Left . T.pack) Right . eitherDecodeStrict' . TE.encodeUtf8 . T.concat . map tokenText . filter (not . isEofToken) . treeTokens

nodeSpan :: ParseTree -> Span
nodeSpan tree = case filter (not . isEofToken) (treeTokens tree) of
  ts@(first : _) -> Span (tokenPosition first) (tokenEndPosition (last ts))
  [] -> error "CALM grammar produced an empty value"

children :: ParseTree -> [ParseTree]
children (RuleNode _ _ ns) = ns
children (Labeled _ n) = [n]
children _ = []

firstRule :: Text -> ParseTree -> Maybe ParseTree
firstRule name n@(RuleNode rule _ _) | showRule rule == name = Just n
firstRule name n = case mapMaybe (firstRule name) (children n) of
  x : _ -> Just x
  [] -> Nothing

showRule :: Canon.Antlr4.Syntax.Name -> Text
showRule = Canon.Antlr4.Syntax.nameText

fieldTree :: Text -> ParseTree -> Maybe ParseTree
fieldTree key n = do
  object <- firstRule "object" n
  Map.lookup key (Map.fromList (mapMaybe pair (children object)))
  where
    pair (RuleNode rule _ ns) | showRule rule == "pair" = case ns of
      TokenNode token : _ -> case eitherDecodeStrict' (TE.encodeUtf8 (tokenText token)) of
        Right (String k) -> (,) k <$> firstValue ns
        _ -> Nothing
      _ -> Nothing
    pair _ = Nothing
    firstValue ns = case [v | v@(RuleNode r _ _) <- ns, showRule r == "value"] of
      v : _ -> Just v
      [] -> Nothing

arrayValues :: ParseTree -> [ParseTree]
arrayValues n = case firstRule "array" n of
  Just a -> [v | v@(RuleNode r _ _) <- children a, showRule r == "value"]
  Nothing -> []

-- Reject duplicate keys before JSON decoding can collapse ambiguous architecture.
rejectDuplicateKeys :: ParseTree -> Either Text ()
rejectDuplicateKeys n = do
  case n of
    RuleNode r _ ns | showRule r == "object" ->
      unique "object key" [key | RuleNode p _ (TokenNode t : _) <- ns, showRule p == "pair", Right (String key) <- [treeValue (TokenNode t)]]
    _ -> pure ()
  mapM_ rejectDuplicateKeys (children n)

tokenEndPosition :: Token -> Position
tokenEndPosition token =
  let Position line column = tokenPosition token
      ls = T.splitOn "\n" (tokenText token)
   in case ls of
        [one] -> Position line (column + T.length one)
        _ -> Position (line + length ls - 1) (T.length (last ls) + 1)
