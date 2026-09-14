module Canon.ProjectTest (tests) where

import Canon.Antlr4.Comment (Comment (..), CommentKind (..))
import Canon.Antlr4.Interpret (loadCombinedInterpreter)
import Canon.Antlr4.Syntax (Name (..))
import Canon.CommentScan (scanCommentsWith)
import Canon.Config (defaultConfig)
import Canon.Extract.Antlr4 (Extraction (..))
import Canon.Extract.Grammar
import Canon.Git.Provider (staticGitProvider)
import Canon.Model
import Canon.Model.Gen (genProfile)
import Canon.Model.Yaml (decodeSorted, encodeSorted)
import Canon.Profile
import Canon.Project
import Canon.Span (Located (..), Position (..), Span (..))
import Canon.Walk (Walked (..))
import Control.Exception (bracket)
import Data.List (sort)
import qualified Data.Text as T
import Hedgehog (Property, annotate, evalIO, failure, forAll, property, withTests, (===))
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "project"
    [ testProperty "profile yaml round trip" profileRoundTrip
    , testProperty "comment scanning follows the profile's syntax" commentScanning
    , testProperty "a profile turns a parse tree into units and decisions" profileExtraction
    , testProperty "the walk stops at nested projects and the root is honoured" nestedProjects
    ]

profileRoundTrip :: Property
profileRoundTrip = property $ do
  p <- forAll genProfile
  decodeSorted (encodeSorted p) === Right p

commentScanning :: Property
commentScanning = withTests 1 $ property $ do
  let syntax = CommentSyntax (Just "%") (Just "/*") (Just "*/") ["\""]
      source = "%% one\n%% two\nx = \"% not\".\n/* block */ y.\n\n% alone\n"
      found = scanCommentsWith syntax source
  map (commentKind . locatedValue) found === [LineComment, BlockComment, LineComment]
  map (commentText . locatedValue) found === ["%% one\n%% two", "/* block */", "% alone"]
  map (positionLine . spanStart . locatedSpan) found === [1, 4, 6]

tinyGrammar :: T.Text
tinyGrammar =
  T.unlines
    [ "grammar Tiny;"
    , "file_ : definition* EOF ;"
    , "definition : 'def' NAME '(' ')' body ;"
    , "body : '{' definition* '}' ;"
    , "NAME : [a-z]+ ;"
    , "COMMENT : '#' ~[\\r\\n]* -> skip ;"
    , "WS : [ \\t\\r\\n]+ -> skip ;"
    ]

profileExtraction :: Property
profileExtraction = withTests 1 $ property $ do
  interpreter <- evalIO $ withScratch "profile" $ \root -> do
    writeFile (root </> "Tiny.g4") (T.unpack tinyGrammar)
    loadCombinedInterpreter (root </> "Tiny.g4")
  case interpreter of
    Left err -> annotate (show err) >> failure
    Right loaded -> do
      let profile = Profile [".tiny"] (CombinedGrammarFile "Tiny.g4") (Name "file_") [UnitRule (Name "definition") "function" (NameFromToken (Name "NAME") 1) True Nothing] (CommentSyntax (Just "#") Nothing Nothing ["\""])
          source = "# why alpha ref:REQ-1\ndef alpha() { def inner() {} }\n\ndef beta() {}\ndef beta() {}\n"
      result <- evalIO (extractWithProfileText (staticGitProvider []) defaultConfig "tiny" profile loaded "src/x.tiny" source)
      case result of
        Left err -> annotate (T.unpack (renderGrammarExtractError err)) >> failure
        Right (Extraction model findings) -> do
          findings === []
          map (renderUnitId . unitId) (modelAllUnits model) === ["tiny/src/x.tiny", "tiny/src/x.tiny/function/alpha", "tiny/src/x.tiny/function/alpha/function/inner", "tiny/src/x.tiny/function/beta", "tiny/src/x.tiny/function/beta#2"]
          [whatName (answerValue (unitWhat u)) | u <- modelAllUnits model, renderUnitId (unitId u) == "tiny/src/x.tiny/function/beta#2"] === ["beta"]
          map (renderDecisionId . decisionId) (modelDecisions model) === ["decision/tiny/src/x.tiny/function/alpha"]
          map (whyReferences . answerValue . decisionWhy) (modelDecisions model) === [[ReferenceKey "REQ-1"]]
          map (whyText . answerValue . decisionWhy) (modelDecisions model) === ["why alpha ref:REQ-1"]
          [howText u | u <- modelAllUnits model, renderUnitId (unitId u) == "tiny/src/x.tiny/function/beta"] === ["def beta() {}"]
  where
    howText u = case answerValue (unitHow u) of
      HowText t -> t
      HowAt _ -> ""

nestedProjects :: Property
nestedProjects = withTests 1 $ property $ do
  found <- evalIO $ withScratch "nested" $ \root -> do
    mapM_ (\d -> createDirectoryIfMissing True (root </> d)) ["a", "inner/src", "inner/source/deep"]
    writeFile (root </> "canon.yaml") "ignore: []\n"
    writeFile (root </> "a/x.g4") "grammar X;\n"
    writeFile (root </> "inner/canon.yaml") "root: source\n"
    writeFile (root </> "inner/src/y.g4") "grammar Y;\n"
    writeFile (root </> "inner/source/deep/z.g4") "grammar Z;\n"
    outer <- loadProject root
    innerProject <- loadProject (root </> "inner")
    case (outer, innerProject) of
      (Right o, Right i) -> do
        Walked files projects <- projectFiles o Nothing
        Walked innerFiles _ <- projectFiles i Nothing
        pure (map (drop (length root + 1)) (sort files), map (drop (length root + 1)) projects, map (drop (length root + 1)) innerFiles)
      _ -> pure ([], [], [])
  found === (["a/x.g4"], ["inner"], ["inner/source/deep/z.g4"])

withScratch :: String -> (FilePath -> IO a) -> IO a
withScratch name action = do
  base <- getTemporaryDirectory
  let root = base </> ("canon-test-" ++ name)
  bracket (createDirectoryIfMissing True root >> pure root) removeDirectoryRecursive action
