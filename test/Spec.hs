module Main (main) where

import qualified Canon.Antlr4.CommentTest
import qualified Canon.Antlr4.EscapeTest
import qualified Canon.Antlr4.QueryTest
import qualified Canon.Antlr4.RuleGraphTest
import qualified Canon.Antlr4.RoundTripTest
import qualified Canon.Antlr4.VendoredTest
import qualified CanonTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain
    ( testGroup
        "canon"
        [ testGroup "unit" [CanonTest.tests, Canon.Antlr4.VendoredTest.tests]
        , testGroup
            "property"
            [ Canon.Antlr4.EscapeTest.tests
            , Canon.Antlr4.CommentTest.tests
            , Canon.Antlr4.RoundTripTest.tests
            , Canon.Antlr4.QueryTest.tests
            , Canon.Antlr4.RuleGraphTest.tests
            ]
        ]
    )
