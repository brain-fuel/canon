module Canon.Antlr4.Read
  ( ReadResult (..)
  , ReadError (..)
  , readGrammar
  , readGrammarFile
  , renderReadError
  ) where

import Canon.Antlr4.Comment (Comment, scanComments)
import Canon.Antlr4.Grammar (ParseError (..), parseGrammarText)
import Canon.Antlr4.Syntax (Grammar, Located, Position (..), Span)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

data ReadResult = ReadResult
  { readResultGrammar :: Grammar Span
  , readResultComments :: [Located Comment]
  }
  deriving (Eq, Show)

data ReadError = ReadParseError FilePath ParseError
  deriving (Eq, Show)

readGrammar :: FilePath -> Text -> Either ReadError ReadResult
readGrammar path source = case parseGrammarText source of
  Left err -> Left (ReadParseError path err)
  Right grammar -> Right (ReadResult grammar (scanComments source))

readGrammarFile :: FilePath -> IO (Either ReadError ReadResult)
readGrammarFile path = readGrammar path <$> TIO.readFile path

renderReadError :: ReadError -> Text
renderReadError (ReadParseError path err) =
  T.concat
    [ T.pack path
    , ":"
    , T.pack (show (positionLine (parseErrorPosition err)))
    , ":"
    , T.pack (show (positionColumn (parseErrorPosition err)))
    , ": "
    , parseErrorMessage err
    ]
