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

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

grammar prolog;

// Prolog text and data formed from terms (6.2)

// canon: a clause and a directive end with END, a full stop followed by layout, a % comment, or the
// end of the file, as ISO 6.4.8 defines the end token; a full stop followed by anything else is a
// graphic atom, so SWI-Prolog's dict access X.key stays inside its clause. A clause's body is a
// bodylist, whose terms a comma or a bar separates. ref:DEC-prolog-grammar-fixes
p_text
    : (directive | clause)* EOF
    ;

directive
    : ':-' bodylist END
    ; // also 3.58

clause
    : bodylist END
    ; // also 3.33

// Abstract Syntax (6.3): terms formed from tokens

termlist
    : term (',' term)*
    ;

// canon: a conjunction, a disjunction written with a bar, as SWI-Prolog's DCG bodies and
// parenthesised goals write (a | b), and the arguments of a clause or a parenthesised term.
bodylist
    : term ((',' | '|') term)*
    ;

// canon: a term is a sequence of primaries and operator atoms, read flat. Prolog's operators are
// user-definable, op/3 declares new ones in the file that uses them, and SWI-Prolog adds its own,
// so no fixed table of priorities reads real Prolog; the grammar reads every atom as a possible
// operator and leaves priority and associativity to Prolog, which canon has no need of: a clause's
// extent is fixed by its end token, and a compound term's arguments by its commas. The flat reading
// is linear where the left-recursive binary_operator alternative was exponential on long bodies.
// Juxtaposed primaries, as SWI-Prolog's dicts write Tag{k: V}, parse as a sequence too.
// ref:DEC-prolog-grammar-fixes
term
    : termPart+
    ;

termPart
    : VARIABLE                           # variable
    | '(' bodylist ')'                   # braced_term
    | integer                            # integer_term
    | FLOAT                              # float
    // structure / compound term
    // canon: an operator is a functor too, as -(X), dynamic(foo/1), and \+(G) write it.
    | (atom | operator_) '(' termlist? ')' # compound_term
    | '[' termlist ( '|' term)? ']'      # list_term
    | '{' bodylist '}'                   # curly_bracketed_term
    // canon: SWI-Prolog's quasi-quotation, {|Syntax||Text|}, read as one token.
    | QUASI_QUOTATION                    # quasi_quotation
    | operator_                          # operator_term
    | atom                               # atom_term
    ;

//TODO: operator priority, associativity, arity. Filter valid priority ranges for e.g. [list] syntax
//TODO: modifying operator table

operator_
    : ':-'
    | '-->'
    | '?-'
    | 'dynamic'
    | 'multifile'
    | 'discontiguous'
    | 'public' //TODO: move operators used in directives to "built-in" definition of dialect
    | ';'
    | '->'
    // canon: ',' is no operator here; termlist and bodylist read it as a separator.
    | '\\+'
    | '='
    | '\\='
    | '=='
    | '\\=='
    | '@<'
    | '@=<'
    | '@>'
    | '@>='
    | '=..'
    | 'is'
    | '=:='
    | '=\\='
    | '<'
    | '=<'
    | '>'
    | '>='
    | ':' // modules: 5.2.1
    | '+'
    | '-'
    | '/\\'
    | '\\/'
    | '*'
    | '/'
    | '//'
    | 'rem'
    | 'mod'
    | '<<'
    | '>>' //TODO: '/' cannot be used as atom because token here not in GRAPHIC. only works because , is operator too. example: swipl/filesex.pl:177
    | '**'
    | '^'
    | '\\'
    ;

atom                                  // 6.4.2 and 6.1.2
    : '[' ']'            # empty_list //NOTE [] is not atom anymore in swipl 7 and later
    | '{' '}'            # empty_braces
    | LETTER_DIGIT       # name
    | GRAPHIC_TOKEN      # graphic
    | QUOTED             # quoted_string
    | DOUBLE_QUOTED_LIST # dq_string
    | BACK_QUOTED_STRING # backq_string
    | ';'                # semicolon
    | '!'                # cut
    ;

integer // 6.4.4
    : DECIMAL
    // canon: an integer in a radix, as 16'FF.
    | RADIX
    | CHARACTER_CODE_CONSTANT
    | BINARY
    | OCTAL
    | HEX
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

// canon: an integer in a radix from 2 to 36, as 16'FF or 2'1010, which ISO leaves to the
// processor and SWI-Prolog and most systems read.
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

// canon: 0''' and SWI-Prolog's 0'' are the code of a quote, as is 0'\'; the space after 0' is a
// character as well.
CHARACTER_CODE_CONSTANT
    : '0' '\'' (SINGLE_QUOTED_CHARACTER | '\'')
    ;

// canon: the exponent's sign is optional, a float may have an exponent and no fraction, as 1e10,
// and SWI-Prolog writes infinity and not-a-number as 1.0Inf and 1.5NaN.
FLOAT
    : DECIMAL '.' [0-9]+ ([eE] [+-]? DECIMAL)? ('Inf' | 'NaN')?
    | DECIMAL [eE] [+-]? DECIMAL
    ;

// canon: the end token of ISO 6.4.8, a full stop followed by layout, a % comment, or the end of the
// file, listed before GRAPHIC_TOKEN so that a lone full stop at the end of a file is END too. A full
// stop followed by anything else is a graphic atom. ref:DEC-prolog-grammar-fixes
END
    : '.' ([ \t\r\n] | '%' ~[\r\n]* | EOF)
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

// canon: SWI-Prolog's escapes besides ISO's: \e (escape), \s (space), \z (end of file), \0 as an
// octal escape, \uXXXX and \UXXXXXXXX code points, and \c, which skips the layout after it; \c
// takes only the line break after it, and the spaces that follow are ordinary characters, since a
// loop of layout inside the escape made the lexer try every split of a run of spaces.
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

WS
    : [ \t\r\n]+ -> skip
    ;

COMMENT
    : '%' ~[\n\r]* ([\n\r] | EOF) -> channel(HIDDEN)
    ;

MULTILINE_COMMENT
    : '/*' (MULTILINE_COMMENT | .)*? ('*/' | EOF) -> channel(HIDDEN)
    ;