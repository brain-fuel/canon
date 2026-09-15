-- | Reading a grammar file yields both its grammar and its comments, because the comments carry the
-- Why and ANTLR would throw them away. ref:DEC-comment-reasons
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

-- | The grammar and its comments together, since both come from one read.
data ReadResult = ReadResult
  { readResultGrammar :: Grammar Span
  , readResultComments :: [Located Comment]
  }
  deriving (Eq, Show)

-- | A read fails at a position, which is what a user needs to fix the file.
data ReadError = ReadParseError FilePath ParseError
  deriving (Eq, Show)

-- | Reads grammar text, with the path kept for messages.
readGrammar :: FilePath -> Text -> Either ReadError ReadResult
readGrammar path source = case parseGrammarText source of
  Left err -> Left (ReadParseError path err)
  Right grammar -> Right (ReadResult grammar (scanComments source))

-- | Reads a grammar file from disk.
readGrammarFile :: FilePath -> IO (Either ReadError ReadResult)
readGrammarFile path = readGrammar path <$> TIO.readFile path

-- | Renders a read failure as path, line, and column.
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
