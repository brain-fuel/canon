module Canon.Antlr4.Token
  ( Token (..)
  , eofTokenName
  , defaultChannelName
  , hiddenChannelName
  , isEofToken
  , renderToken
  ) where

import Canon.Antlr4.Syntax (Name (..))
import Canon.Span (Position (..))
import Data.Text (Text)
import qualified Data.Text as T

data Token = Token
  { tokenType :: Name
  , tokenText :: Text
  , tokenStart :: Int
  , tokenEnd :: Int
  , tokenChannel :: Name
  , tokenPosition :: Position
  }
  deriving (Eq, Ord, Show)

eofTokenName :: Name
eofTokenName = Name "EOF"

defaultChannelName :: Name
defaultChannelName = Name "DEFAULT_TOKEN_CHANNEL"

hiddenChannelName :: Name
hiddenChannelName = Name "HIDDEN"

isEofToken :: Token -> Bool
isEofToken = (== eofTokenName) . tokenType

renderToken :: Token -> Text
renderToken t =
  T.concat
    [ nameText (tokenType t)
    , "@"
    , T.pack (show (positionLine (tokenPosition t)))
    , ":"
    , T.pack (show (positionColumn (tokenPosition t)))
    , " "
    , T.pack (show (tokenText t))
    ]
