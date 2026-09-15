-- | A token is the unit the lexer produces and the parser consumes, with its channel and position,
-- because ANTLR routes tokens by channel.
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

-- | A token with its type, text, offsets, channel, and position.
data Token = Token
  { tokenType :: Name
  , tokenText :: Text
  , tokenStart :: Int
  , tokenEnd :: Int
  , tokenChannel :: Name
  , tokenPosition :: Position
  }
  deriving (Eq, Ord, Show)

-- | The name of the end-of-input token, which grammars reference as EOF.
eofTokenName :: Name
eofTokenName = Name "EOF"

-- | The name of the channel parsers read.
defaultChannelName :: Name
defaultChannelName = Name "DEFAULT_TOKEN_CHANNEL"

-- | The name of the channel ANTLR calls HIDDEN.
hiddenChannelName :: Name
hiddenChannelName = Name "HIDDEN"

-- | Tells the end-of-input token, which spans and slices must exclude.
isEofToken :: Token -> Bool
isEofToken = (== eofTokenName) . tokenType

-- | Renders a token for messages and trees.
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
