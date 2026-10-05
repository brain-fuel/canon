-- | The suite is split into unit and property groups so either can be run alone.
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
import qualified Canon.ExemptionsTest
import qualified Canon.IgnoreTest
import qualified Canon.ProjectTest
import qualified Canon.ParityTest
import qualified Canon.TangleTest
import qualified Canon.HighlightTest
import qualified Canon.Extract.GrammarTest
import qualified Canon.Extract.RustTest
import qualified Canon.Extract.CSharpTest
import qualified Canon.Extract.FSharpTest
import qualified Canon.Extract.GroovyTest
import qualified Canon.Extract.ElixirTest
import qualified Canon.Extract.GleamTest
import qualified Canon.Extract.ScalaTest
import qualified Canon.Extract.KotlinTest
import qualified Canon.Extract.ClojureTest
import qualified Canon.Extract.PrologTest
import qualified Canon.Extract.FolioTest
import qualified Canon.Extract.JavaScriptTest
import qualified Canon.Extract.TypeScriptTest
import qualified Canon.Extract.CalmTest
import qualified Canon.Extract.GoTest
import qualified Canon.Extract.PythonTest
import qualified Canon.Extract.ErlangTest
import qualified Canon.Model.CheckTest
import qualified Canon.Git.ParseTest
import qualified Canon.Model.YamlTest
import qualified Canon.RegistryTest
import qualified Canon.VettingTest
import qualified Canon.TestingTest
import qualified CanonTest
import Test.Tasty (defaultMain, testGroup)

-- | Runs the whole suite.
main :: IO ()
main =
  defaultMain
    ( testGroup
        "canon"
        [ testGroup "unit" [CanonTest.tests, Canon.Antlr4.VendoredTest.tests, Canon.Extract.GrammarTest.tests, Canon.Extract.RustTest.tests, Canon.Extract.CSharpTest.tests, Canon.Extract.FSharpTest.tests, Canon.Extract.GroovyTest.tests, Canon.Extract.ElixirTest.tests, Canon.Extract.GleamTest.tests, Canon.Extract.ErlangTest.tests, Canon.Extract.ScalaTest.tests, Canon.Extract.CalmTest.tests, Canon.Extract.KotlinTest.tests, Canon.Extract.ClojureTest.tests, Canon.Extract.PrologTest.tests, Canon.Extract.FolioTest.tests, Canon.Extract.JavaScriptTest.tests, Canon.Extract.TypeScriptTest.tests, Canon.Extract.GoTest.tests, Canon.Extract.PythonTest.tests]
        , testGroup
            "property"
            [ Canon.Antlr4.EscapeTest.tests
            , Canon.Antlr4.CommentTest.tests
            , Canon.Antlr4.RoundTripTest.tests
            , Canon.Antlr4.QueryTest.tests
            , Canon.Antlr4.RuleGraphTest.tests
            , Canon.Model.YamlTest.tests
            , Canon.ExemptionsTest.tests
            , Canon.RegistryTest.tests, Canon.VettingTest.tests, Canon.TestingTest.tests
            , Canon.Git.ParseTest.tests
            , Canon.CanonicalCommentTest.tests
            , Canon.AttachTest.tests
            , Canon.Model.CheckTest.tests
            , Canon.Antlr4.InterpretTest.tests
            , Canon.DecisionsTest.tests
            , Canon.IgnoreTest.tests
            , Canon.ProjectTest.tests
            , Canon.ParityTest.tests
            , Canon.TangleTest.tests
            , Canon.HighlightTest.tests
            ]
        ]
    )
