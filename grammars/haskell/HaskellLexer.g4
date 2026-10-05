/**
BSD License
license:BSD-3-Clause
Copyright (c) 2020, Evgeniy Slobodkin
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of Tom Everett nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $antlr-format alignTrailingComments true, columnLimit 150, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine true, allowShortBlocksOnASingleLine true, minEmptyLines 0, alignSemicolons ownLine
// $antlr-format alignColons trailing, singleLineOverrulesHangingColon true, alignLexerCommands true, alignLabels true, alignTrailers true

lexer grammar HaskellLexer;

options {
    superClass = HaskellBaseLexer;
}

/** A line break. Its action tells the layout algorithm that a new line starts, so indentation can be measured, which is why the token exists at all rather than being whitespace. */
NEWLINE:
    ('\r'? '\n' | '\r') {
    this.processNEWLINEToken();
}
;

/** A run of tabs, counted as eight columns each by the layout algorithm. */
TAB:
    [\t]+ {
    this.processTABToken();
}
;

/** A run of spaces, counted by the layout algorithm while it waits for the first token of a line. */
WS:
    [\u0020\u00a0\u1680\u2000\u200a\u202f\u205f\u3000]+ {
    this.processWSToken();
}
;

/** The contextual keyword as, which the parser also accepts as an identifier. */
AS        : 'as';
/** The keyword case. */
CASE      : 'case';
/** The keyword class. */
CLASS     : 'class';
/** The keyword data. */
DATA      : 'data';
/** The keyword default. */
DEFAULT   : 'default';
/** The keyword deriving. */
DERIVING  : 'deriving';
/** The keyword do. */
DO        : 'do';
/** The keyword else. */
ELSE      : 'else';
/** The contextual keyword hiding, which the parser also accepts as an identifier. */
HIDING    : 'hiding';
/** The keyword if. */
IF        : 'if';
/** The keyword import. */
IMPORT    : 'import';
/** The keyword in. */
IN        : 'in';
/** The keyword infix. */
INFIX     : 'infix';
/** The keyword infixl. */
INFIXL    : 'infixl';
/** The keyword infixr. */
INFIXR    : 'infixr';
/** The keyword instance. */
INSTANCE  : 'instance';
/** The keyword let. */
LET       : 'let';
/** The keyword module. */
MODULE    : 'module';
/** The keyword newtype. */
NEWTYPE   : 'newtype';
/** The keyword of. */
OF        : 'of';
/** The contextual keyword qualified, which the parser also accepts as an identifier. */
QUALIFIED : 'qualified';
/** The keyword then. */
THEN      : 'then';
/** The keyword type. */
TYPE      : 'type';
/** The keyword where. */
WHERE     : 'where';
/** The underscore wildcard pattern. */
WILDCARD  : '_';

/** The forall keyword of explicit quantification. */
FORALL        : 'forall';
/** The foreign keyword of the foreign function interface. */
FOREIGN       : 'foreign';
/** The contextual keyword export of a foreign export declaration, usable as an identifier elsewhere. */
EXPORT        : 'export';
/** The contextual keyword safe of a foreign import. */
SAFE          : 'safe';
/** The contextual keyword interruptible of a foreign import. */
INTERRUPTIBLE : 'interruptible';
/** The contextual keyword unsafe of a foreign import. */
UNSAFE        : 'unsafe';
/** The mdo keyword of recursive do. */
MDO           : 'mdo';
/** The contextual keyword family of type and data families. */
FAMILY        : 'family';
/** The contextual keyword role of role annotations. */
ROLE          : 'role';
/** The stdcall calling convention. */
STDCALL       : 'stdcall';
/** The ccall calling convention. */
CCALL         : 'ccall';
/** The capi calling convention. */
CAPI          : 'capi';
/** The cplusplus calling convention. */
CPPCALL       : 'cplusplus';
/** The javascript calling convention. */
JSCALL        : 'javascript';
/** The rec keyword of arrow notation and recursive do. */
REC           : 'rec';
/** The contextual keyword group of transform comprehensions. */
GROUP         : 'group';
/** The contextual keyword by of transform comprehensions. */
BY            : 'by';
/** The contextual keyword using of transform comprehensions. */
USING         : 'using';
/** The contextual keyword pattern of pattern synonyms. */
PATTERN       : 'pattern';
/** The stock deriving strategy. */
STOCK         : 'stock';
/** The anyclass deriving strategy. */
ANYCLASS      : 'anyclass';
/** The via deriving strategy. */
VIA           : 'via';

/** The LANGUAGE pragma name. */
LANGUAGE     : 'LANGUAGE';
/** The OPTIONS_GHC pragma name. */
OPTIONS_GHC  : 'OPTIONS_GHC';
/** The OPTIONS pragma name. */
OPTIONS      : 'OPTIONS';
/** The INLINE pragma name. */
INLINE       : 'INLINE';
/** The NOINLINE pragma name. */
NOINLINE     : 'NOINLINE';
/** The SPECIALISE pragma name. */
SPECIALISE   : 'SPECIALISE';
/** The SPECIALISE_INLINE pragma name. */
SPECINLINE   : 'SPECIALISE_INLINE';
/** The SOURCE pragma name of import cycles. */
SOURCE       : 'SOURCE';
/** The RULES pragma name. */
RULES        : 'RULES';
/** The SCC pragma name, also accepted as a constructor name since Data.Graph exports one. */
SCC          : 'SCC';
/** The DEPRECATED pragma name. */
DEPRECATED   : 'DEPRECATED';
/** The WARNING pragma name. */
WARNING      : 'WARNING';
/** The UNPACK pragma name. */
UNPACK       : 'UNPACK';
/** The NOUNPACK pragma name. */
NOUNPACK     : 'NOUNPACK';
/** The ANN pragma name. */
ANN          : 'ANN';
/** The MINIMAL pragma name. */
MINIMAL      : 'MINIMAL';
/** The CTYPE pragma name. */
CTYPE        : 'CTYPE';
/** The OVERLAPPING pragma name. */
OVERLAPPING  : 'OVERLAPPING';
/** The OVERLAPPABLE pragma name. */
OVERLAPPABLE : 'OVERLAPPABLE';
/** The OVERLAPS pragma name. */
OVERLAPS     : 'OVERLAPS';
/** The INCOHERENT pragma name. */
INCOHERENT   : 'INCOHERENT';
/** The COMPLETE pragma name. */
COMPLETE     : 'COMPLETE';

/** A lambda-case: a backslash followed by case, possibly across whitespace, which opens a layout block like case does. */
LCASE: '\\' (NEWLINE | WS)* 'case';

fragment SYMBOL    : [!#$%&*+./<=>?@\\^|~:\-\p{S}];
/** The context arrow. */
DoubleArrow        : '=>';
/** The type annotation symbol. */
DoubleColon        : '::';
/** The function arrow, also used by case alternatives and lambdas. */
Arrow              : '->';
/** The bind arrow of do notation and comprehensions. */
Revarrow           : '<-';
/** The arrow-notation tail. */
LarrowTail         : '-<';
/** The reversed arrow-notation tail. */
RarrowTail         : '>-';
/** The higher-order arrow-notation tail. */
LLarrowTail        : '-<<';
/** The reversed higher-order arrow-notation tail. */
RRarrowTail        : '>>-';
/** The hash of magic hash names and unboxed tuples. */
Hash               : '#';
/** Less than. */
Less               : '<';
/** Greater than. */
Greater            : '>';
/** Ampersand. */
Ampersand          : '&';
/** The vertical bar of guards, alternatives, and comprehensions. */
Pipe               : '|';
/** The strictness bang. */
Bang               : '!';
/** Caret. */
Caret              : '^';
/** Plus. */
Plus               : '+';
/** Minus, also negation. */
Minus              : '-';
/** Asterisk, also the kind of types. */
Asterisk           : '*';
/** Percent. */
Percent            : '%';
/** Slash. */
Divide             : '/';
/** The laziness tilde. */
Tilde              : '~';
/** The as-pattern and type application at sign. */
Atsign             : '@';
/** The typed splice opener. */
DDollar            : '$$';
/** The untyped splice opener, also the application operator. */
Dollar             : '$';
/** The range and wildcard export dots. */
DoubleDot          : '..';
/** Dot, for qualified names and composition. */
Dot                : '.';
/** An explicit semicolon. */
Semi               : ';';
/** The implicit parameter question mark. */
QuestionMark       : '?';
/** Comma. */
Comma              : ',';
/** The cons operator and the start of constructor operators. */
Colon              : ':';
/** The definition equals sign. */
Eq                 : '=';
/** A single quote, also the promotion tick. */
Quote              : '\'';
/** Two single quotes, the Template Haskell name quote. */
DoubleQuote        : '\'\'';
/** The backslash that opens a lambda. */
ReverseSlash       : '\\';
/** The backquote that turns a name into an operator. */
BackQuote          : '`';
/** The arrow-notation opening banana bracket. */
AopenParen         : '(|' WS;
/** The arrow-notation closing banana bracket. */
AcloseParen        : WS '|)';
/** The typed expression quotation opener. */
TopenTexpQuote     : '[||';
/** The typed expression quotation closer. */
TcloseTExpQoute    : '||]';
/** The expression quotation opener. */
TopenExpQuote      : '[|';
// canon: [e| opens an expression quotation as [| does. ref:DEC-haskell-grammar-fixes
/** The opener of an expression quotation spelled with its e. ref:DEC-haskell-grammar-fixes */
TopenExpQuoteE     : '[e|';
/** The pattern quotation opener. */
TopenPatQuote      : '[p|';
/** The type quotation opener. */
TopenTypQoute      : '[t|';
/** The declaration quotation opener. */
TopenDecQoute      : '[d|';
// canon: a quasi-quotation is one token, its body text the quoter reads and never Haskell, when the
// file enables QuasiQuotes, which the base lexer port learns from the LANGUAGE pragma; without it,
// [x|x<-xs] is a list comprehension. The quoters e, t, d, and p are Template Haskell's own brackets.
// ref:DEC-haskell-grammar-fixes
/** A quasi-quotation, one token from the quoter to the closing bar and bracket, when the file enables QuasiQuotes. ref:DEC-haskell-grammar-fixes */
QUASIQUOTE : '[' (LARGE (SMALL | LARGE | DIGIT | '\'')* '.')* SMALL (SMALL | LARGE | DIGIT | '\'')* '|' {this.isQuasiQuote()}? .*? '|]';
/** The quotation closer. */
TcloseQoute        : '|]';
/** The unboxed tuple opener. */
OpenBoxParen       : '(#';
/** The unboxed tuple closer. */
CloseBoxParen      : '#)';
/** Left parenthesis. */
OpenRoundBracket   : '(';
/** Right parenthesis. */
CloseRoundBracket  : ')';
/** Left square bracket. */
OpenSquareBracket  : '[';
/** Right square bracket. */
CloseSquareBracket : ']';

/** A character literal: one character or escape between single quotes. Written in the standard form with escapes because the enumerated form grammars-v4 publishes rejects escapes and backslashes. ref:DEC-haskell-grammar-fixes */
CHAR:
    '\'' (ESCAPE | ~['\\\r\n]) '\'' '#'?
;

/** A string literal: characters, escapes, and gaps between double quotes. Written in the standard form because the enumerated form let a backslash be an ordinary character, which made a string containing two backslashes match past its closing quote and lexing exponential. ref:DEC-haskell-grammar-fixes */
STRING:
    '"' (StringEscape | GAP | ~["\\\r\n])* '"' '#'?
;

// canon: inside a string an escape is read by its first character only, and the digits or letters
// after it as ordinary characters, which bounds the token the same; reading \x1885 as an escape of
// one to four digits made a string of n numeric escapes lex in time exponential in n.
// ref:DEC-haskell-grammar-fixes
fragment StringEscape:
    '\\' ([abfnrtv\\"'&] | '^' [A-Z@[\\\]^_] | 'x' [0-9a-fA-F] | 'o' [0-7] | [0-9] | [A-Z])
;

fragment ESCAPE:
    '\\' (
        [abfnrtv\\"'&]
        | '^' [A-Z@[\\\]^_]
        | 'x' [0-9a-fA-F]+
        | 'o' [0-7]+
        | [0-9]+
        | 'NUL' | 'SOH' | 'STX' | 'ETX' | 'EOT' | 'ENQ' | 'ACK' | 'BEL' | 'BS' | 'HT' | 'LF' | 'VT' | 'FF' | 'CR' | 'SO' | 'SI' | 'DLE'
        | 'DC1' | 'DC2' | 'DC3' | 'DC4' | 'NAK' | 'SYN' | 'ETB' | 'CAN' | 'EM' | 'SUB' | 'ESC' | 'FS' | 'GS' | 'RS' | 'US' | 'SP' | 'DEL'
    )
;

fragment GAP: '\\' [ \t\r\n]+ '\\';

/** A variable identifier: a small letter or underscore followed by letters, digits, and primes, with optional magic hashes. */
VARID : SMALL (SMALL | LARGE | DIGIT | '\'')* '#'*;
/** A constructor identifier: a capital letter followed by letters, digits, and primes, with optional magic hashes. */
CONID : LARGE (SMALL | LARGE | DIGIT | '\'')* '#'*;

// canon: a whole pragma is one hidden token, as GHC ignores a pragma it does not know and none
// changes what the declarations around it mean to canon; the rules below that read a pragma's parts
// stay for the grammar's record. ref:DEC-haskell-grammar-fixes
/** A whole pragma, hidden: GHC ignores the pragmas it does not know, and canon reads none of them. ref:DEC-haskell-grammar-fixes */
PRAGMA : '{-#' .*? '#-}' -> channel(HIDDEN);
/** The pragma opener. */
OpenPragmaBracket  : '{-#';
/** The pragma closer. */
ClosePragmaBracket : '#-}';

// canon: a C preprocessor directive at the start of a line is one hidden token, with its backslash
// continuation lines; the base lexer port reads its #if, #ifdef, #elif, #else, and #endif and hides the
// branches the build does not read, as GHC's CPP extension runs the preprocessor before the lexer.
// A #! line, which starts a script run by runghc or stack, is hidden the same way. ref:DEC-haskell-grammar-fixes
/** A C preprocessor directive or a script's #! line, at the start of a line and hidden; the base lexer port reads the conditionals among them. ref:DEC-haskell-grammar-fixes */
CPP_DIRECTIVE
    : {this.atLineStart()}? '#' [ \t]* ('if' | 'ifdef' | 'ifndef' | 'elif' | 'else' | 'endif' | 'define' | 'undef' | 'include' | 'error' | 'warning' | 'line' | 'pragma' | '!') ('\\' '\r'? '\n' | ~[\r\n])* -> channel(HIDDEN)
    ;

/** A line comment, skipped; dashes followed by a symbol character are an operator instead. ref:DEC-haskell-grammar-fixes */
// canon: dashes followed by a symbol character are an operator, such as --> or --+, not a comment.
COMMENT  : '--' '-'* (~[\r\n!#$%&*+./<=>?@\\^|~:] ~[\r\n]*)? -> skip;
/** A block comment, skipped; one starting with a hash is a pragma instead. */
// canon: block comments nest, as in Haskell, so a comment may hold another or a pragma.
// ref:DEC-haskell-grammar-fixes
NCOMMENT : '{-' ~[#] (NestedComment | .)*? '-}' -> skip;

fragment NestedComment : '{-' (NestedComment | .)*? '-}';

// canon: operators are read by maximal munch, as the Haskell report's lexical syntax says, so ==>,
// >=>, <$>, .:, and $$ are one token each rather than runs of one-character tokens that the reserved
// operators =>, <-, .., and $$ break apart; a reserved operator alone still wins its tie, since its
// rule comes first. These rules follow the comment rules, so a line of dashes is still a comment. A qualified operator such as Map.! or C.. is one token too.
// ref:DEC-haskell-grammar-fixes
/** A qualified variable operator, such as Map.! or C.., one token by maximal munch. ref:DEC-haskell-grammar-fixes */
QVARSYM : (LARGE (SMALL | LARGE | DIGIT | '\'')* '.')+ SYMBOL_NO_COLON SYMBOL*;
/** A qualified constructor operator, such as NE.:|. ref:DEC-haskell-grammar-fixes */
QCONSYM : (LARGE (SMALL | LARGE | DIGIT | '\'')* '.')+ ':' SYMBOL*;
/** A variable operator, by maximal munch; a reserved operator or a single character that has a token of its own wins the tie, since its rule comes first. These rules follow the comment rules, so a line of dashes is still a comment. ref:DEC-haskell-grammar-fixes */
VARSYM : SYMBOL_NO_COLON SYMBOL*;
/** A constructor operator of two or more symbol characters starting with a colon, by maximal munch. ref:DEC-haskell-grammar-fixes */
CONSYM : ':' SYMBOL+;
/** An operator starting with a hash in parentheses, such as (#.) or (#), which is not an unboxed tuple. ref:DEC-haskell-grammar-fixes */
HashOperatorInParens : '(' '#' SYMBOL* ')';

fragment SYMBOL_NO_COLON: [!#$%&*+./<=>?@\\^|~\-\p{S}];

/** An explicit opening brace. */
OCURLY  : '{';
/** An explicit closing brace. */
CCURLY  : '}';
/** A virtual opening brace, which only the layout algorithm produces; the literal exists so the token has a type and is hidden. */
VOCURLY : 'VOCURLY' { this.SetHidden(); };
/** A virtual closing brace, which only the layout algorithm produces. */
VCCURLY : 'VCCURLY' { this.SetHidden(); };
/** A virtual semicolon, which only the layout algorithm produces. */
SEMI    : 'SEMI'    { this.SetHidden(); };

// canon: integer literals take NumericUnderscores' underscores between digits, binary literals read as
// integers, and MagicHash's one or two trailing hashes. ref:DEC-haskell-grammar-fixes
/** A decimal integer literal, with underscores between digits and a MagicHash suffix allowed. ref:DEC-haskell-grammar-fixes */
DECIMAL     : DIGIT ('_'* DIGIT)* MagicHashes;
/** An octal integer literal. */
OCTAL       : '0' [oO] '_'* OCTIT ('_'* OCTIT)* MagicHashes;
/** A hexadecimal integer literal, or a binary one, which the parser reads as an integer too. ref:DEC-haskell-grammar-fixes */
HEXADECIMAL : ('0' [xX] '_'* HEXIT ('_'* HEXIT)* | '0' [bB] '_'* [01] ('_'* [01])*) MagicHashes;

fragment MagicHashes : ('#' '#'?)?;

// canon: each character class is one set, by Unicode general category, rather than an alternation
// of hundreds of ranges the lexer tried one by one for every character of every name; the classes
// are the same, as the Haskell report defines them. ref:DEC-haskell-grammar-fixes
fragment DIGIT: [0-9\p{Nd}];

fragment OCTIT : [0-7];
fragment HEXIT : [0-9] | [A-F] | [a-f];

/** A floating point literal. */
FLOAT    : ((Digits '.' Digits EXPONENT?) | (Digits EXPONENT)) MagicHashes;

fragment Digits : DIGIT ('_'* DIGIT)*;
/** The exponent part of a floating point literal, which is a token of its own upstream. */
// canon: the exponent is a fragment, as e-1 in show (e-1) is a name, a minus, and a number.
// ref:DEC-haskell-grammar-fixes
fragment EXPONENT : [eE] [+-]? Digits;

fragment LARGE: [A-Z\p{Lu}\p{Lt}];

fragment SMALL    : [_a-z\p{Ll}];

