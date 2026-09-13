module Canon.Antlr4.Gen
  ( genRuleName
  , genTokenName
  , genAnyName
  , genQualifiedName
  , genStringLiteral
  , genCharSet
  , genActionText
  , genArgumentText
  , genInteger
  ) where

import Canon.Antlr4.Syntax
import Data.Char (isAlphaNum)
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Hedgehog (Gen)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

genNameWith :: Gen Char -> Gen Name
genNameWith genFirst =
  Gen.filter (\(Name t) -> not (Set.member t reservedWords)) $
    Name <$> (T.cons <$> genFirst <*> Gen.text (Range.linear 0 8) genNameTail)
  where
    genNameTail = Gen.frequency [(10, Gen.alphaNum), (1, pure '_')]

genRuleName :: Gen Name
genRuleName = genNameWith Gen.lower

genTokenName :: Gen Name
genTokenName = genNameWith Gen.upper

genAnyName :: Gen Name
genAnyName = Gen.choice [genRuleName, genTokenName]

genQualifiedName :: Gen QualifiedName
genQualifiedName = QualifiedName . NonEmpty.fromList <$> Gen.list (Range.linear 1 3) genAnyName

genStringLiteral :: Gen StringLiteral
genStringLiteral = StringLiteral . T.concat <$> Gen.list (Range.linear 1 8) genStringLiteralPiece

genStringLiteralPiece :: Gen Text
genStringLiteralPiece =
  Gen.frequency
    [ (12, T.singleton <$> Gen.filter (\c -> c /= '\'' && c /= '\\') genPrintableAscii)
    , (2, Gen.element ["\\b", "\\t", "\\n", "\\f", "\\r", "\\\"", "\\'", "\\\\"])
    , (1, genUnicodeEscape)
    ]

genUnicodeEscape :: Gen Text
genUnicodeEscape = T.append "\\u" <$> Gen.text (Range.singleton 4) Gen.hexit

genCharSet :: Gen CharSet
genCharSet = CharSet . T.concat <$> Gen.list (Range.linear 1 6) genCharSetPiece

genCharSetPiece :: Gen Text
genCharSetPiece =
  Gen.frequency
    [ (12, T.singleton <$> genCharSetChar)
    , (3, genCharSetRange)
    , (2, Gen.element ["\\]", "\\\\", "\\-", "\\n", "\\t"])
    , (1, genUnicodeEscape)
    ]

genCharSetChar :: Gen Char
genCharSetChar = Gen.filter (\c -> c /= ']' && c /= '\\' && c /= '-') genPrintableAscii

genCharSetRange :: Gen Text
genCharSetRange = do
  lo <- genCharSetChar
  hi <- Gen.filter (>= lo) genCharSetChar
  pure (T.pack [lo, '-', hi])

genActionText :: Gen ActionText
genActionText = ActionText <$> genBalanced '{' '}'

genArgumentText :: Gen ArgumentText
genArgumentText = ArgumentText <$> genBalanced '[' ']'

genBalanced :: Char -> Char -> Gen Text
genBalanced open close =
  Gen.recursive
    Gen.choice
    [T.concat <$> Gen.list (Range.linear 0 6) genSafePiece]
    [ (\inner outer -> T.concat [outer, T.singleton open, inner, T.singleton close])
        <$> genBalanced open close
        <*> (T.concat <$> Gen.list (Range.linear 0 3) genSafePiece)
    ]
  where
    genSafePiece =
      Gen.frequency
        [ (10, T.singleton <$> Gen.filter isSafeChar genPrintableAscii)
        , (1, genQuoted '"')
        , (1, genQuoted '\'')
        ]
    isSafeChar c = isAlphaNum c || c `elem` (" ;=(),.<>:+-*&|!" :: String)
    genQuoted q =
      (\body -> T.concat [T.singleton q, body, T.singleton q])
        <$> Gen.text (Range.linear 0 5) (Gen.filter (\c -> isAlphaNum c || c == ' ') genPrintableAscii)

genPrintableAscii :: Gen Char
genPrintableAscii = Gen.enum ' ' '~'

genInteger :: Gen Integer
genInteger = Gen.integral (Range.linear 0 1000)
