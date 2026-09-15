-- | Comment scanning must keep every comment with the right span, or attachment binds the wrong Why.
module Canon.Antlr4.CommentTest (tests) where

import Canon.Antlr4.Comment
import Canon.Antlr4.Gen (genActionText)
import Canon.Antlr4.Syntax
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Hedgehog (Property, assert, evalIO, forAll, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "comment"
    [ testProperty "vendored lexer grammar starts with its license block comment" vendoredLicenseComment
    , testProperty "vendored lexer grammar has line comments on the expected lines" vendoredLineComments
    , testProperty "comment markers inside actions are not comments" markersInsideActionsIgnored
    , testProperty "comment inside an options block is found" commentInsideOptionsBlock
    , testProperty "empty block comment is a block comment" emptyBlockComment
    ]

vendoredLicenseComment :: Property
vendoredLicenseComment = withTests 1 $ property $ do
  source <- evalIO (TIO.readFile "grammars/antlr4/ANTLRv4Lexer.g4")
  case scanComments source of
    (Located (Span (Position 1 1) (Position endLine _)) (Comment kind text) : _) -> do
      assert (kind /= LineComment)
      assert ("/*" `T.isPrefixOf` text)
      assert ("*/" `T.isSuffixOf` text)
      assert (endLine > 1)
    other -> fail ("unexpected first comment: " ++ show (take 1 other))

vendoredLineComments :: Property
vendoredLineComments = withTests 1 $ property $ do
  source <- evalIO (TIO.readFile "grammars/antlr4/ANTLRv4Lexer.g4")
  let lineCommentLines = [positionLine (spanStart s) | Located s (Comment LineComment _) <- scanComments source]
      sourceLines = zip [1 :: Int ..] (T.lines source)
      linesWithMarker = [n | (n, l) <- sourceLines, "//" `T.isInfixOf` l]
  assert (length lineCommentLines > 10)
  filter (`elem` linesWithMarker) lineCommentLines === lineCommentLines

markersInsideActionsIgnored :: Property
markersInsideActionsIgnored = property $ do
  ActionText body <- forAll genActionText
  let source = T.concat ["r : {", body, "// not a comment /* nor this */\n}", " ;"]
  scanComments source === []

commentInsideOptionsBlock :: Property
commentInsideOptionsBlock = withTests 1 $ property $ do
  let source = "grammar G;\noptions {\n  // inside\n  k = v;\n}\n"
  map (commentKind . locatedValue) (scanComments source) === [LineComment]

emptyBlockComment :: Property
emptyBlockComment = withTests 1 $ property $ do
  let source = "/**/ grammar G; /** doc */"
  map (commentKind . locatedValue) (scanComments source) === [BlockComment, DocComment]
