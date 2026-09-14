module Main (main) where

import qualified Canon.Antlr4.CommentTest
import qualified Canon.Antlr4.EscapeTest
import qualified Canon.Antlr4.InterpretTest
import qualified Canon.Antlr4.QueryTest
import qualified Canon.Antlr4.RuleGraphTest
import qualified Canon.Antlr4.RoundTripTest
import qualified Canon.Antlr4.VendoredTest
import qualified Canon.AttachTest
import qualified Canon.CanonicalCommentTest
import qualified Canon.DecisionsTest
import qualified Canon.IgnoreTest
import qualified Canon.Extract.Antlr4Test
import qualified Canon.Model.CheckTest
import qualified Canon.Git.ParseTest
import qualified Canon.Model.YamlTest
import qualified Canon.RegistryTest
import qualified CanonTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain
    ( testGroup
        "canon"
        [ testGroup "unit" [CanonTest.tests, Canon.Antlr4.VendoredTest.tests, Canon.Extract.Antlr4Test.tests]
        , testGroup
            "property"
            [ Canon.Antlr4.EscapeTest.tests
            , Canon.Antlr4.CommentTest.tests
            , Canon.Antlr4.RoundTripTest.tests
            , Canon.Antlr4.QueryTest.tests
            , Canon.Antlr4.RuleGraphTest.tests
            , Canon.Model.YamlTest.tests
            , Canon.RegistryTest.tests
            , Canon.Git.ParseTest.tests
            , Canon.CanonicalCommentTest.tests
            , Canon.AttachTest.tests
            , Canon.Model.CheckTest.tests
            , Canon.Antlr4.InterpretTest.tests
            , Canon.DecisionsTest.tests
            , Canon.IgnoreTest.tests
            ]
        ]
    )
