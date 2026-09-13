module Main (main) where

import qualified Canon.Antlr4.CommentTest
import qualified Canon.Antlr4.EscapeTest
import qualified CanonTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain
    ( testGroup
        "canon"
        [ CanonTest.tests
        , testGroup "property" [Canon.Antlr4.EscapeTest.tests, Canon.Antlr4.CommentTest.tests]
        ]
    )
