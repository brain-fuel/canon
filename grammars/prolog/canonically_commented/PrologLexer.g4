/*
BSD License

Copyright (c) 2013, Tom Everett
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

// canon: the canonically commented dialect of the Prolog grammar, as a lexer grammar of its own because
// a combined grammar may not hold modes. The literals the plain grammar's parser rules name are tokens
// of their own here, in the order ANTLR gives the plain grammar's implicit tokens, so they win their
// ties with LETTER_DIGIT and GRAPHIC_TOKEN as they do there; module and test are new, for the module
// directive and plunit's tests. DEFAULT_MODE is the space between clauses, where a PlDoc comment
// may open; the code of a clause is lexed in the Code mode, which the clause's closing full stop
// leaves, so a comment inside a clause, on whatever line, is plain. Every change from the plain
// grammar is marked canon: and recorded as DEC-prolog-dialect.
lexer grammar PrologLexer;

// canon: a PlDoc line comment opens with %! or %% at the start of a line between clauses and is a
// canonical comment on the default channel, tokenized in DocLine. %%% opens a plain comment, as a
// banner of percent signs is no documentation, and so does %! or %% indented or inside a clause,
// whose lines the Code mode reads. A /** comment between clauses, at the start of a line or after
// the full stop of a clause, opens a PlDoc block comment; /*** and /**/ stay plain.
DOC_OPEN       : '%' [!%] -> pushMode(DocLine) ;
BANNER         : '%%%' ~[\r\n]* -> channel(HIDDEN) ;
BLANK_LINE     : [ \t]* ('\r'? '\n' | '\r') -> skip ;
GAP_COMMENT    : ([ \t]+ '%' ~[\r\n]* | '%' (~[!%\r\n] ~[\r\n]*)?) -> channel(HIDDEN) ;
GAP_BLOCK      : [ \t]* PLAIN_BLOCK -> channel(HIDDEN) ;
DOC_BLOCK_OPEN : [ \t]* '/**' -> pushMode(DocBlock) ;
// canon: anything else starts the code of a clause, without consuming it.
LINE_START     : -> pushMode(Code), channel(HIDDEN) ;

// canon: a block comment that is no PlDoc comment: /* followed by anything but a star, /*** and
// more stars, or /**/.
fragment PLAIN_BLOCK
    : '/*' ~[*] (MULTILINE_COMMENT_PART | .)*? ('*/' | EOF)
    | '/**' '*'+ ('/' | ~[*/] (MULTILINE_COMMENT_PART | .)*? ('*/' | EOF))
    | '/**/'
    ;

// canon: the code of a clause, lexed by the plain grammar's rules; the full stop that closes the
// clause returns to the space between clauses.
mode Code;

// canon: the plain grammar's implicit literal tokens, named, and module and test.
NECK          : ':-' ;
// canon: the end token of ISO 6.4.8, a full stop followed by layout, a % comment, or the end of the
// file; a full stop followed by anything else is a graphic atom and stays in the clause, as
// SWI-Prolog's dict access X.key does. ref:DEC-prolog-grammar-fixes
END           : '.' ([ \t\r\n] | '%' ~[\r\n]* | EOF) -> popMode ;
COMMA         : ',' ;
OPEN          : '(' ;
CLOSE         : ')' ;
MINUS         : '-' ;
OPEN_LIST     : '[' ;
BAR           : '|' ;
CLOSE_LIST    : ']' ;
OPEN_CURLY    : '{' ;
CLOSE_CURLY   : '}' ;
DCG_ARROW     : '-->' ;
QUERY         : '?-' ;
DYNAMIC       : 'dynamic' ;
MULTIFILE     : 'multifile' ;
DISCONTIGUOUS : 'discontiguous' ;
PUBLIC        : 'public' ;
SEMICOLON     : ';' ;
IF_THEN       : '->' ;
// canon: the neck of SWI-Prolog's single sided unification rules, Head => Body.
SSU_NECK      : '=>' ;
NOT_PROVABLE  : '\\+' ;
UNIFY         : '=' ;
NOT_UNIFY     : '\\=' ;
IDENTICAL     : '==' ;
NOT_IDENTICAL : '\\==' ;
TERM_LT       : '@<' ;
TERM_LE       : '@=<' ;
TERM_GT       : '@>' ;
TERM_GE       : '@>=' ;
UNIV          : '=..' ;
IS            : 'is' ;
ARITH_EQ      : '=:=' ;
ARITH_NE      : '=\\=' ;
LT            : '<' ;
LE            : '=<' ;
GT            : '>' ;
GE            : '>=' ;
COLON         : ':' ;
PLUS          : '+' ;
BIT_AND       : '/\\' ;
BIT_OR        : '\\/' ;
STAR          : '*' ;
SLASH         : '/' ;
INT_DIV       : '//' ;
REM           : 'rem' ;
MOD           : 'mod' ;
SHIFT_LEFT    : '<<' ;
SHIFT_RIGHT   : '>>' ;
POWER         : '**' ;
CARET         : '^' ;
BACKSLASH     : '\\' ;
CUT           : '!' ;
MODULE        : 'module' ;
TEST          : 'test' ;

// canon: a block comment inside a clause is plain, a /** comment included. It is listed before
// GRAPHIC_TOKEN, which would otherwise win the tie of /**.
CODE_BLOCK_COMMENT
    : '/*' (MULTILINE_COMMENT_PART | .)*? ('*/' | EOF) -> channel(HIDDEN)
    ;

// Lexer (6.4 & 6.5): Tokens formed from Characters

LETTER_DIGIT // 6.4.2
    : SMALL_LETTER ALPHANUMERIC*
    ;

VARIABLE // 6.4.3
    : CAPITAL_LETTER ALPHANUMERIC*
    | '_' ALPHANUMERIC+
    | '_'
    ;

// 6.4.4
// canon: SWI-Prolog's digit groups, 1_000_000, are a decimal too.
DECIMAL
    : DIGIT+ ('_' DIGIT+)*
    ;

// canon: an integer in a radix from 2 to 36, as 16'FF or 2'1010.
RADIX
    : [1-9] [0-9]? '\'' [0-9a-zA-Z]+
    ;

BINARY
    : '0b' [01]+
    ;

OCTAL
    : '0o' [0-7]+
    ;

HEX
    : '0x' HEX_DIGIT+
    ;

// canon: 0''' and SWI-Prolog's 0'' are the code of a quote.
CHARACTER_CODE_CONSTANT
    : '0' '\'' (SINGLE_QUOTED_CHARACTER | '\'')
    ;

// canon: an optional exponent sign, an exponent without a fraction, and 1.0Inf and 1.5NaN.
FLOAT
    : DECIMAL '.' [0-9]+ ([eE] [+-]? DECIMAL)? ('Inf' | 'NaN')?
    | DECIMAL [eE] [+-]? DECIMAL
    ;

// canon: SWI-Prolog's quasi-quotation, {|Syntax||Text|}, whose text is anything up to |}.
QUASI_QUOTATION
    : '{|' .*? '||' .*? '|}'
    ;

GRAPHIC_TOKEN
    : (GRAPHIC | '\\')+
    ; // 6.4.2

fragment GRAPHIC
    : [#$&*+./:<=>?@^~]
    | '-'
    ; // 6.5.1 graphic char

// 6.4.2.1
fragment SINGLE_QUOTED_CHARACTER
    : NON_QUOTE_CHAR
    | '\'\''
    | '"'
    | '`'
    ;

fragment DOUBLE_QUOTED_CHARACTER
    : NON_QUOTE_CHAR
    | '\''
    | '""'
    | '`'
    ;

fragment BACK_QUOTED_CHARACTER
    : NON_QUOTE_CHAR
    | '\''
    | '"'
    | '``'
    ;

fragment NON_QUOTE_CHAR
    : GRAPHIC
    | ALPHANUMERIC
    | SOLO
    | ' ' // space char
    // canon: a character outside ASCII, such as the check mark in marelle's ' ✓', is a character of a
    // quoted atom or string, as SWI-Prolog and every Unicode-aware Prolog read it; ISO leaves the
    // processor character set to the implementation.
    | ~[\u0000-\u007F]
    // canon: a tab inside quotes, which SWI-Prolog reads as itself.
    | '\t'
    | META_ESCAPE
    | CONTROL_ESCAPE
    | OCTAL_ESCAPE
    | HEX_ESCAPE
    ;

fragment META_ESCAPE
    : '\\' [\\'"`]
    ; // meta char

// canon: SWI-Prolog's escapes besides ISO's: \e, \s, \z, \uXXXX, \UXXXXXXXX, and \c with the line
// break after it; the spaces that follow \c are ordinary characters, since a loop of layout inside
// the escape made the lexer try every split of a run of spaces.
fragment CONTROL_ESCAPE
    : '\\' [abrftnvesz]
    | '\\u' HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT
    | '\\U' HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT
    | '\\c' ('\r'? '\n')?
    ;

// canon: the closing backslash of an octal or hexadecimal escape is optional in SWI-Prolog.
fragment OCTAL_ESCAPE
    : '\\' [0-7]+ '\\'?
    ;

fragment HEX_ESCAPE
    : '\\x' HEX_DIGIT+ '\\'?
    ;

QUOTED
    : '\'' (CONTINUATION_ESCAPE | SINGLE_QUOTED_CHARACTER)*? '\''
    ; // 6.4.2

DOUBLE_QUOTED_LIST
    : '"' (CONTINUATION_ESCAPE | DOUBLE_QUOTED_CHARACTER)*? '"'
    ; // 6.4.6

BACK_QUOTED_STRING
    : '`' (CONTINUATION_ESCAPE | BACK_QUOTED_CHARACTER)*? '`'
    ; // 6.4.7

// canon: a backslash before a CR LF line break continues the text too.
fragment CONTINUATION_ESCAPE
    : '\\' '\r'? '\n'
    ;

// 6.5.2
fragment ALPHANUMERIC
    : ALPHA
    | DIGIT
    ;

fragment ALPHA
    : '_'
    | SMALL_LETTER
    | CAPITAL_LETTER
    ;

fragment SMALL_LETTER
    : [a-z_]
    ;

fragment CAPITAL_LETTER
    : [A-Z]
    ;

fragment DIGIT
    : [0-9]
    ;

fragment HEX_DIGIT
    : [0-9a-fA-F]
    ;

// 6.5.3
fragment SOLO
    : [!(),;[{}|%]
    | ']'
    ;

// canon: a line break inside a clause is white space; only the clause's full stop leaves it.
WS
    : [ \t\r\n]+ -> skip
    ;

// canon: a plain comment ends before its line break, which then returns to the start of a line.
COMMENT
    : '%' ~[\n\r]* -> channel(HIDDEN)
    ;

fragment MULTILINE_COMMENT_PART
    : '/*' (MULTILINE_COMMENT_PART | .)*? '*/'
    ;

// canon: a PlDoc line comment: the rest of its line, continued by each following line that starts
// with %, %%, or %!, so a structured header and the lines below it are one canonical comment. A
// following %%% line ends it and is plain; any other line break ends it.
mode DocLine;

DOC_CONTINUE    : ('\r'? '\n' | '\r') [ \t]* '%' [!%]? -> skip ;
DOC_PLAIN_AFTER : ('\r'? '\n' | '\r') [ \t]* '%%%' ~[\r\n]* -> popMode, channel(HIDDEN) ;
DOC_CLOSE       : ('\r'? '\n' | '\r') -> popMode, channel(HIDDEN) ;
DOC_REF         : 'ref:' DocKey ;
DOC_LICENSE     : 'license:' DocKey ;
DOC_WS          : [ \t]+ -> skip ;
DOC_PUNCT       : [,.;:()!?[\]{}"'`<>=+|] ;
DOC_WORD        : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|]+ ;

// canon: a PlDoc block comment, closed by */; a star that decorates a line is dropped, and <module>
// marks the comment that documents the file.
mode DocBlock;

DOC_BLOCK_CLOSE   : '*/' -> popMode ;
DOC_MODULE        : '<module>' ;
DOC_BLOCK_REF     : 'ref:' DocKey -> type(DOC_REF) ;
DOC_BLOCK_LICENSE : 'license:' DocKey -> type(DOC_LICENSE) ;
DOC_BLOCK_STAR    : '*' -> skip ;
DOC_BLOCK_WS      : [ \t\r\n]+ -> skip ;
DOC_BLOCK_PUNCT   : [,.;:()!?[\]{}"'`<>=+|] -> type(DOC_PUNCT) ;
DOC_BLOCK_WORD    : ~[ \t\r\n*,.;:()!?[\]{}"'`<>=+|]+ -> type(DOC_WORD) ;

fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])? ;
