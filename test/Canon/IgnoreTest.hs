module Canon.IgnoreTest (tests) where

import Canon.Ignore
import Canon.Walk (findSupportedFiles)
import Control.Exception (bracket)
import Data.List (sort)
import qualified Data.Text as T
import Hedgehog (Gen, Property, assert, evalIO, forAll, property, withTests, (===))
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "ignore"
    [ testProperty "a bare name matches at any depth" bareNameAnyDepth
    , testProperty "an anchored pattern matches only from the root" anchoredFromRoot
    , testProperty "an ignored directory ignores everything beneath it" directoryCovers
    , testProperty "a later negation re-includes a file" negationReincludes
    , testProperty "glob syntax behaves like gitignore" globExamples
    , testProperty "the default patterns cover vendor directories" defaultsCoverVendors
    , testProperty "the walk visits supported files and prunes ignored directories" walkTree
    ]

genSegment :: Gen T.Text
genSegment = Gen.text (Range.linear 1 8) Gen.alphaNum

bareNameAnyDepth :: Property
bareNameAnyDepth = property $ do
  name <- forAll genSegment
  prefix <- forAll (Gen.list (Range.linear 0 4) genSegment)
  let patterns = parseIgnorePatterns [name]
  isIgnored patterns False (prefix ++ [name]) === True
  other <- forAll (Gen.filter (/= name) genSegment)
  isIgnored patterns False (prefix ++ [other]) === (name `elem` prefix)

anchoredFromRoot :: Property
anchoredFromRoot = property $ do
  name <- forAll genSegment
  inner <- forAll (Gen.filter (/= name) genSegment)
  let patterns = parseIgnorePatterns ["/" <> name]
  isIgnored patterns False [name] === True
  isIgnored patterns False [inner, name] === False

directoryCovers :: Property
directoryCovers = property $ do
  directory <- forAll genSegment
  below <- forAll (Gen.list (Range.linear 1 4) genSegment)
  let patterns = parseIgnorePatterns [directory <> "/"]
  isIgnored patterns False (directory : below) === True
  isIgnored patterns False [directory] === False

negationReincludes :: Property
negationReincludes = property $ do
  name <- forAll genSegment
  let patterns = parseIgnorePatterns ["*.g4", "!" <> name <> ".g4"]
  isIgnored patterns False [name <> ".g4"] === False
  isIgnored patterns False ["x" <> name <> ".g4"] === True

globExamples :: Property
globExamples = withTests 1 $ property $ do
  let ignored ps isDir path = isIgnored (parseIgnorePatterns ps) isDir (T.splitOn "/" path)
  ignored ["grammars/*/*.g4"] False "grammars/antlr4/ANTLRv4Lexer.g4" === True
  ignored ["grammars/*/*.g4"] False "grammars/antlr4/canonically_commented/ANTLRv4Lexer.g4" === False
  ignored ["grammars/**/*.g4"] False "grammars/antlr4/canonically_commented/ANTLRv4Lexer.g4" === True
  ignored ["**/generated/"] False "a/b/generated/x.g4" === True
  ignored ["doc?.g4"] False "docs.g4" === True
  ignored ["doc?.g4"] False "doc.g4" === False
  ignored ["[a-c]*.g4"] False "beta.g4" === True
  ignored ["[a-c]*.g4"] False "delta.g4" === False
  ignored ["build"] True "src/build" === True
  ignored ["build/"] False "src/build" === False
  assert (null (parseIgnorePatterns ["", "  ", "# comment"]))

defaultsCoverVendors :: Property
defaultsCoverVendors = withTests 1 $ property $ do
  let ignored path = isIgnored defaultIgnorePatterns False (T.splitOn "/" path)
  ignored "node_modules/x/y.g4" === True
  ignored "a/vendor/y.g4" === True
  ignored ".stack-work/dist/y.g4" === True
  ignored "grammars/antlr4/x.g4" === False

walkTree :: Property
walkTree = withTests 1 $ property $ do
  found <- evalIO $ withScratch $ \root -> do
    mapM_ (\d -> createDirectoryIfMissing True (root </> d)) ["src/deep", "node_modules/pkg", "vendor", "skipped", "build"]
    mapM_ (\f -> writeFile (root </> f) "grammar G;\n") ["a.g4", "src/b.g4", "src/deep/c.g4", "node_modules/pkg/d.g4", "vendor/e.g4", "skipped/f.g4", "build/g.g4", "src/notes.md"]
    let patterns = defaultIgnorePatterns ++ parseIgnorePatterns ["skipped/"]
    map (drop (length root + 1)) <$> findSupportedFiles patterns root
  sort found === ["a.g4", "src/b.g4", "src/deep/c.g4"]

withScratch :: (FilePath -> IO a) -> IO a
withScratch action = do
  base <- getTemporaryDirectory
  let root = base </> "canon-test-walk"
  bracket (createDirectoryIfMissing True root >> pure root) removeDirectoryRecursive action
