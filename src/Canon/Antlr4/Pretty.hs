-- | Printing a grammar back to text is what makes the reader testable: reading what was printed must
-- give the same value.
module Canon.Antlr4.Pretty
  ( prettyGrammar
  , prettyPrequel
  , prettyRule
  , prettyParserRule
  , prettyLexerRule
  , prettyAlternative
  , prettyLexerAlternative
  , prettyElement
  , prettyLexerElement
  , prettyAtom
  , prettyLexerAtom
  , prettyOption
  , prettyOptionValue
  , prettyElementOptions
  , prettyStringLiteral
  ) where

import Canon.Antlr4.Syntax
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T

-- | Prints a whole grammar in the layout antlr-format produces, so vendored files print back
-- unchanged.
prettyGrammar :: Grammar ann -> Text
prettyGrammar g =
  T.concat $
    [prettyGrammarKind (grammarKind g), " ", nameText (grammarName g), ";\n\n"]
      ++ map (\p -> prettyPrequel p <> "\n\n") (grammarPrequel g)
      ++ map (\r -> prettyRule r <> "\n\n") (grammarRules g)
      ++ map prettyMode (grammarModes g)

prettyGrammarKind :: GrammarKind -> Text
prettyGrammarKind kind = case kind of
  LexerGrammar -> "lexer grammar"
  ParserGrammar -> "parser grammar"
  CombinedGrammar -> "grammar"

prettyMode :: Mode ann -> Text
prettyMode m =
  T.concat $ ["mode ", nameText (modeName m), ";\n\n"] ++ map (\r -> prettyLexerRule r <> "\n\n") (modeRules m)

-- | Prints one prequel construct.
prettyPrequel :: Prequel -> Text
prettyPrequel p = case p of
  PrequelOptions opts -> prettyOptionsBlock "" opts
  PrequelImports imports -> T.concat ["import ", T.intercalate ", " (map prettyImport (NonEmpty.toList imports)), ";"]
  PrequelTokens names -> prettyNameBlock "tokens" names
  PrequelChannels names -> prettyNameBlock "channels" names
  PrequelAction scope action ->
    T.concat ["@", maybe "" (\s -> nameText s <> "::") scope, prettyNamedActionBody action]

prettyImport :: Import -> Text
prettyImport (Import label g) = maybe "" (\l -> nameText l <> " = ") label <> nameText g

prettyNameBlock :: Text -> [Name] -> Text
prettyNameBlock keyword names =
  T.concat [keyword, " {\n", T.intercalate ",\n" (map (\n -> "    " <> nameText n) names), if null names then "" else "\n", "}"]

prettyOptionsBlock :: Text -> [Option] -> Text
prettyOptionsBlock indent opts =
  T.concat $
    [indent, "options {\n"]
      ++ map (\o -> T.concat [indent, "    ", prettyOption o, ";\n"]) opts
      ++ [indent, "}"]

-- | Prints one option.
prettyOption :: Option -> Text
prettyOption (Option name value) = T.concat [nameText name, " = ", prettyOptionValue value]

-- | Prints one option value.
prettyOptionValue :: OptionValue -> Text
prettyOptionValue v = case v of
  OptionValueName q -> prettyQualifiedName q
  OptionValueString s -> prettyStringLiteral s
  OptionValueAction a -> prettyAction a
  OptionValueInt n -> T.pack (show n)

prettyQualifiedName :: QualifiedName -> Text
prettyQualifiedName (QualifiedName parts) = T.intercalate "." (map nameText (NonEmpty.toList parts))

prettyNamedActionBody :: NamedAction -> Text
prettyNamedActionBody (NamedAction name body) = T.concat [nameText name, " ", prettyAction body]

prettyAction :: ActionText -> Text
prettyAction (ActionText body) = T.concat ["{", body, "}"]

prettyArgument :: ArgumentText -> Text
prettyArgument (ArgumentText body) = T.concat ["[", body, "]"]

-- | Prints a literal with its escapes encoded.
prettyStringLiteral :: StringLiteral -> Text
prettyStringLiteral (StringLiteral raw) = T.concat ["'", raw, "'"]

prettyCharSet :: CharSet -> Text
prettyCharSet (CharSet raw) = T.concat ["[", raw, "]"]

-- | Prints one rule of either kind.
prettyRule :: Rule ann -> Text
prettyRule r = case r of
  RuleParser p -> prettyParserRule p
  RuleLexer l -> prettyLexerRule l

-- | Prints a parser rule with its alternatives on their own lines.
prettyParserRule :: ParserRule ann -> Text
prettyParserRule r =
  T.intercalate "\n" $
    [ T.unwords $
        map prettyRuleModifier (parserRuleModifiers r)
          ++ [nameText (parserRuleName r)]
          ++ maybe [] (\a -> [prettyArgument a]) (parserRuleArguments r)
          ++ maybe [] (\a -> ["returns", prettyArgument a]) (parserRuleReturns r)
          ++ (if null (parserRuleThrows r) then [] else ["throws", T.intercalate ", " (map prettyQualifiedName (parserRuleThrows r))])
          ++ maybe [] (\a -> ["locals", prettyArgument a]) (parserRuleLocals r)
    ]
      ++ map prettyRulePrequel (parserRulePrequel r)
      ++ zipWith prettyLabeledAlternative (":" : repeat "|") (NonEmpty.toList (parserRuleAlternatives r))
      ++ ["    ;"]
      ++ map prettyExceptionHandler (parserRuleHandlers r)
      ++ maybe [] (\a -> ["    finally " <> prettyAction a]) (parserRuleFinally r)

prettyRuleModifier :: RuleModifier -> Text
prettyRuleModifier m = case m of
  RuleModifierPublic -> "public"
  RuleModifierPrivate -> "private"
  RuleModifierProtected -> "protected"
  RuleModifierFragment -> "fragment"

prettyRulePrequel :: RulePrequel -> Text
prettyRulePrequel p = case p of
  RulePrequelOptions opts -> prettyOptionsBlock "    " opts
  RulePrequelAction action -> "    @" <> prettyNamedActionBody action

prettyExceptionHandler :: ExceptionHandler -> Text
prettyExceptionHandler (ExceptionHandler arg body) = T.concat ["    catch ", prettyArgument arg, " ", prettyAction body]

prettyLabeledAlternative :: Text -> LabeledAlternative ann -> Text
prettyLabeledAlternative lead (LabeledAlternative alt label) =
  T.unwords $ ["    " <> lead] ++ alternativeWords alt ++ maybe [] (\l -> ["#", nameText l]) label

-- | Prints one alternative.
prettyAlternative :: Alternative ann -> Text
prettyAlternative = T.unwords . alternativeWords

alternativeWords :: Alternative ann -> [Text]
alternativeWords (Alternative _ opts elements) =
  (if null opts then [] else [prettyElementOptions opts]) ++ map prettyElement elements

-- | Prints one element with its label and suffix.
prettyElement :: Element ann -> Text
prettyElement e = case e of
  ElementAtom _ label a suffix -> T.concat [prettyLabel label, prettyAtom a, prettySuffix suffix]
  ElementBlock _ label b suffix -> T.concat [prettyLabel label, prettyBlock b, prettySuffix suffix]
  ElementAction _ form body opts -> T.concat [prettyAction body, prettyActionForm form, prettyElementOptions opts]

prettyLabel :: Maybe Label -> Text
prettyLabel = maybe "" (\(Label n k) -> nameText n <> (if k == LabelAssign then "=" else "+="))

prettyActionForm :: ActionForm -> Text
prettyActionForm form = case form of
  EmbeddedAction -> ""
  SemanticPredicate -> "?"

prettySuffix :: Maybe EbnfSuffix -> Text
prettySuffix = maybe "" prettyEbnfSuffix

prettyEbnfSuffix :: EbnfSuffix -> Text
prettyEbnfSuffix (EbnfSuffix q g) = quantifier <> greediness
  where
    quantifier = case q of
      Optional -> "?"
      ZeroOrMore -> "*"
      OneOrMore -> "+"
    greediness = case g of
      Greedy -> ""
      NonGreedy -> "?"

prettyBlock :: Block ann -> Text
prettyBlock (Block opts actions alts) =
  T.concat
    [ "("
    , if null opts && null actions
        then ""
        else T.unwords (optionsInline opts ++ map (\a -> "@" <> prettyNamedActionBody a) actions ++ [":"]) <> " "
    , T.intercalate " | " (map prettyAlternative (NonEmpty.toList alts))
    , ")"
    ]
  where
    optionsInline os = if null os then [] else [T.concat ["options { ", T.concat (map (\o -> prettyOption o <> "; ") os), "}"]]

-- | Prints one atom.
prettyAtom :: Atom -> Text
prettyAtom a = case a of
  AtomTerminal t -> prettyTerminal t
  AtomRuleRef n args opts -> T.concat [nameText n, maybe "" prettyArgument args, prettyElementOptions opts]
  AtomNotSet s -> prettyNotSet s
  AtomWildcard opts -> "." <> prettyElementOptions opts

prettyTerminal :: Terminal -> Text
prettyTerminal t = case t of
  TerminalToken n opts -> nameText n <> prettyElementOptions opts
  TerminalLiteral s opts -> prettyStringLiteral s <> prettyElementOptions opts

prettyNotSet :: NotSet -> Text
prettyNotSet (NotSet elements) = case NonEmpty.toList elements of
  [single] -> "~" <> prettySetElement single
  many -> T.concat ["~(", T.intercalate " | " (map prettySetElement many), ")"]

prettySetElement :: SetElement -> Text
prettySetElement s = case s of
  SetTerminal t -> prettyTerminal t
  SetRange r -> prettyCharRange r
  SetCharSet cs -> prettyCharSet cs

prettyCharRange :: CharRange -> Text
prettyCharRange (CharRange lo hi) = T.concat [prettyStringLiteral lo, " .. ", prettyStringLiteral hi]

-- | Prints element options in angle brackets.
prettyElementOptions :: [ElementOption] -> Text
prettyElementOptions opts
  | null opts = ""
  | otherwise = T.concat ["<", T.intercalate ", " (map prettyElementOption opts), ">"]

prettyElementOption :: ElementOption -> Text
prettyElementOption o = case o of
  ElementOptionFlag q -> prettyQualifiedName q
  ElementOptionAssign n v -> T.concat [nameText n, " = ", prettyOptionValue v]

-- | Prints a lexer rule with its commands.
prettyLexerRule :: LexerRule ann -> Text
prettyLexerRule r =
  T.intercalate "\n" $
    [(if lexerRuleIsFragment r then "fragment " else "") <> nameText (lexerRuleName r)]
      ++ (if null (lexerRuleOptions r) then [] else [prettyOptionsBlock "    " (lexerRuleOptions r)])
      ++ zipWith (\lead alt -> T.unwords ("    " <> lead : lexerAlternativeWords alt)) (":" : repeat "|") (NonEmpty.toList (lexerRuleAlternatives r))
      ++ ["    ;"]

-- | Prints one lexer alternative.
prettyLexerAlternative :: LexerAlternative ann -> Text
prettyLexerAlternative = T.unwords . lexerAlternativeWords

lexerAlternativeWords :: LexerAlternative ann -> [Text]
lexerAlternativeWords (LexerAlternative _ elements commands) =
  map prettyLexerElement elements
    ++ (if null commands then [] else ["->", T.intercalate ", " (map prettyLexerCommand commands)])

prettyLexerCommand :: LexerCommand -> Text
prettyLexerCommand (LexerCommand n arg) = nameText n <> maybe "" (\a -> T.concat ["(", prettyCommandArgument a, ")"]) arg

prettyCommandArgument :: LexerCommandArgument -> Text
prettyCommandArgument a = case a of
  CommandArgumentName n -> nameText n
  CommandArgumentInt n -> T.pack (show n)

-- | Prints one lexer element.
prettyLexerElement :: LexerElement ann -> Text
prettyLexerElement e = case e of
  LexerElementAtom _ a suffix -> prettyLexerAtom a <> prettySuffix suffix
  LexerElementBlock _ alts suffix ->
    T.concat ["(", T.intercalate " | " (map prettyLexerAlternative (NonEmpty.toList alts)), ")", prettySuffix suffix]
  LexerElementAction _ form body -> prettyAction body <> prettyActionForm form

-- | Prints one lexer atom.
prettyLexerAtom :: LexerAtom -> Text
prettyLexerAtom a = case a of
  LexerAtomTerminal t -> prettyTerminal t
  LexerAtomRange r -> prettyCharRange r
  LexerAtomCharSet cs -> prettyCharSet cs
  LexerAtomNotSet s -> prettyNotSet s
  LexerAtomWildcard opts -> "." <> prettyElementOptions opts
