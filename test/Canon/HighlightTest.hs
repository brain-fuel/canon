-- | The highlighter must classify a language's tokens from its grammar, tile every line with its
-- pieces, and fall back to plain when the lexer refuses the text. ref:DEC-highlight-by-lexer
module Canon.HighlightTest (tests) where

import Canon.Antlr4.Interpret (Interpreter, renderInterpretError)
import Canon.Antlr4.Syntax (Name (..))
import Canon.Extract.Grammar (loadProfileInterpreter)
import Canon.Highlight
import Canon.Profile
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Hedgehog (Property, PropertyT, annotate, assert, evalIO, failure, property, withTests, (===))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "highlight"
    [ testProperty "haskell tokens are classified from the grammar" haskellClasses
    , testProperty "the pieces of every line tile it" piecesTile
    , testProperty "a fragment starting mid-file carries no virtual token" noVirtualTokens
    , testProperty "makefile tokens follow the profile's overrides" makefileClasses
    , testProperty "a text the lexer refuses is plain" refusedIsPlain
    ]

haskellProfile :: Profile
haskellProfile = Profile [".hs"] (SplitGrammarFiles "grammars/haskell/canonically_commented/HaskellLexer.g4" "grammars/haskell/canonically_commented/HaskellParser.g4") (Name "module") [] defaultCommentSyntax Map.empty Map.empty Map.empty

makeOverrides :: Map.Map Text [Text]
makeOverrides = Map.fromList [("meta", ["IFEQ", "IFDEF", "ELSE", "INCLUDE", "DEFINE", "ENDEF"]), ("comment", ["HELP"]), ("string", ["VALUE"]), ("type", ["SPECIAL"]), ("plain", ["NAME"])]

makeProfile :: Profile
makeProfile = Profile ["Makefile"] (SplitGrammarFiles "grammars/make/canonically_commented/MakefileLexer.g4" "grammars/make/canonically_commented/MakefileParser.g4") (Name "makefile") [] defaultCommentSyntax Map.empty Map.empty makeOverrides

interpreterOrFail :: Profile -> PropertyT IO Interpreter
interpreterOrFail profile = do
  loaded <- evalIO (loadProfileInterpreter profile)
  either (\e -> annotate (T.unpack (renderInterpretError e)) >> failure) pure loaded

-- | The class of the piece holding a text, on any line.
classOf :: [[Piece]] -> Text -> [Text]
classOf ls t = [pieceClass p | l <- ls, p <- l, t `T.isInfixOf` pieceText p]

-- | The class of the piece that is exactly a text.
exactly :: [[Piece]] -> Text -> [Text]
exactly ls t = [pieceClass p | l <- ls, p <- l, pieceText p == t]

haskellClasses :: Property
haskellClasses = withTests 1 $ property $ do
  i <- interpreterOrFail haskellProfile
  let source = T.unlines ["{-# LANGUAGE OverloadedStrings #-}", "-- | The module.", "module Sample (f) where", "", "-- plain", "f :: Maybe Int -> Int", "f m = maybe 42 (+ 1) m -- tail", "s = \"text\""]
      ls = highlightLines (classifierFor Map.empty i) i source
  length ls === 8
  classOf ls "LANGUAGE" === ["meta"]
  classOf ls "{-#" === ["meta"]
  exactly ls "module" === ["keyword"]
  exactly ls "where" === ["keyword"]
  classOf ls "The module." === ["comment"]
  classOf ls "-- plain" === ["comment"]
  classOf ls "-- tail" === ["comment"]
  classOf ls "Maybe" === ["type"]
  classOf ls "42" === ["number"]
  classOf ls "\"text\"" === ["string"]
  classOf ls "::" === ["plain"]
  map (T.concat . map pieceText) ls === T.lines source

piecesTile :: Property
piecesTile = withTests 1 $ property $ do
  i <- interpreterOrFail haskellProfile
  source <- evalIO (TIO.readFile "src/Canon/Highlight.hs")
  let ls = highlightLines (classifierFor Map.empty i) i source
  length ls === length (T.lines source)
  map (T.concat . map pieceText) ls === T.lines source
  assert (all (all (not . T.null . pieceText)) ls)

noVirtualTokens :: Property
noVirtualTokens = withTests 1 $ property $ do
  i <- interpreterOrFail haskellProfile
  let source = T.unlines ["  where", "    go x = x", "    stop = 0"]
      ls = highlightLines (classifierFor Map.empty i) i source
  map (T.concat . map pieceText) ls === T.lines source
  assert (null [p | l <- ls, p <- l, pieceText p `elem` ["VOCURLY", "VCCURLY", "SEMI"]])
  classOf ls "where" === ["keyword"]

makefileClasses :: Property
makefileClasses = withTests 1 $ property $ do
  i <- interpreterOrFail makeProfile
  let source = T.unlines ["# | The port.", "PORT ?= 8080", ".PHONY: help", "help: ## what you can ask for", "\t@echo hi", "ifeq ($(OS),x)", "endif", "export PORT"]
      ls = highlightLines (classifierFor makeOverrides i) i source
  map (T.concat . map pieceText) ls === T.lines source
  classOf ls "The port." === ["comment"]
  classOf ls "8080" === ["string"]
  classOf ls ".PHONY" === ["type"]
  classOf ls "## what" === ["comment"]
  classOf ls "ifeq" === ["meta"]
  exactly ls "endif" === ["keyword"]
  exactly ls "export" === ["keyword"]
  assert (all (== "plain") (classOf ls "help"))

refusedIsPlain :: Property
refusedIsPlain = withTests 1 $ property $ do
  i <- interpreterOrFail haskellProfile
  let source = "module M where\nx = \"unterminated\n"
      ls = highlightLines (classifierFor Map.empty i) i source
  ls === plainLines source
  plainLines "" === []
  plainLines "a\n" === [[Piece "plain" "a"]]
