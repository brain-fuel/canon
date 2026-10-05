/*
MIT License

Copyright (c) 2026 brain-fuel

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

// A structural lexer for Elixir, written for canon. It tokenizes everything Elixir's tokenizer
// does closely enough for ElixirParser.g4 to find statements, blocks, and definitions; it does not
// tell every operator's precedence apart, because canon needs units, not evaluation order.
// Braces push the default mode and closing braces pop it, so the closing brace of a string
// interpolation returns to the string it interrupted.

lexer grammar ElixirLexer;

// A newline ends a statement unless the parser sees an operator around it. Comment-only lines that
// follow a newline belong to it, so a comment between an attribute and a definition does not
// separate them, while a blank line still does.
NL
    : '\r'? '\n' ([ \t]* '#' ~[\r\n]* '\r'? '\n')*
    ;

WS
    : ([ \t\f] | '\\' '\r'? '\n')+ -> skip
    ;

COMMENT
    : '#' ~[\r\n]* -> skip
    ;

// Reserved words.
TRUE  : 'true';
FALSE : 'false';
NIL   : 'nil';
WHEN  : 'when';
AND   : 'and';
OR    : 'or';
NOT   : 'not';
IN    : 'in';
FN    : 'fn';
DO    : 'do';
END   : 'end';
CATCH : 'catch';
RESCUE: 'rescue';
AFTER : 'after';
ELSE  : 'else';

// The definition macros of Kernel. They are not reserved, but they are what a unit starts with.
DEFMODULE    : 'defmodule';
DEFPROTOCOL  : 'defprotocol';
DEFIMPL      : 'defimpl';
DEFSTRUCT    : 'defstruct';
DEFEXCEPTION : 'defexception';
DEFDELEGATE  : 'defdelegate';
DEFGUARDP    : 'defguardp';
DEFGUARD     : 'defguard';
DEFMACROP    : 'defmacrop';
DEFMACRO     : 'defmacro';
DEFP         : 'defp';
DEF          : 'def';
UNQUOTE      : 'unquote';

// The ExUnit and StreamData macros that define tests and groups of them. They are ordinary
// identifiers to Elixir; a type of their own lets a profile tell a test from the attributes
// above it.
TEST_MACRO
    : 'test'
    | 'describe'
    | 'property'
    ;

// Module attributes. The documentation attributes, the type attributes, and the callback
// attributes have their own types so the parser can tell them from the attributes a definition
// carries; a longer attribute name such as @docs_url is an ordinary ATTRIBUTE by longest match.
DOC_ATTRIBUTE
    : '@' ('moduledoc' | 'doc' | 'typedoc')
    ;

TYPE_ATTRIBUTE
    : '@' ('typep' | 'type' | 'opaque')
    ;

CALLBACK_ATTRIBUTE
    : '@' ('callback' | 'macrocallback')
    ;

ATTRIBUTE
    : '@' IDENTIFIER_START IDENTIFIER_PART* [?!]?
    ;

// A keyword-list key such as do: or opts:, which Elixir writes with no space before the colon.
KEYWORD
    : (IDENTIFIER_START | [A-Z]) IDENTIFIER_PART* [?!]? ':'
    ;

ATOM
    : ':' (IDENTIFIER_START | [A-Z]) (IDENTIFIER_PART | '@')* [?!]?
    | ':' OPERATOR_ATOM
    ;

ATOM_STRING_OPEN
    : ':"' -> pushMode(STRING)
    ;

ALIAS
    : [A-Z] [a-zA-Z0-9_]*
    ;

IDENTIFIER
    : IDENTIFIER_START IDENTIFIER_PART* [?!]?
    ;

CHAR
    : '?' ('\\' . | ~[\\ \t\r\n])
    ;

// Sigils are single tokens: canon reads no code inside them, and their delimiters vary.
SIGIL
    : '~' [a-zA-Z]+ (
        '"""' .*? '"""'
        | '\'\'\'' .*? '\'\'\''
        | '"' ('\\' . | SIGIL_INTERPOLATION | ~["\\])* '"'
        | '\'' ('\\' . | SIGIL_INTERPOLATION | ~['\\])* '\''
        | '/' ('\\' . | SIGIL_INTERPOLATION | ~[/\\])* '/'
        | '|' ('\\' . | SIGIL_INTERPOLATION | ~[|\\])* '|'
        | '(' ('\\' . | SIGIL_INTERPOLATION | ~[)\\])* ')'
        | '[' ('\\' . | SIGIL_INTERPOLATION | ~[\]\\])* ']'
        | '{' ('\\' . | SIGIL_INTERPOLATION | ~[}\\])* '}'
        | '<' ('\\' . | SIGIL_INTERPOLATION | ~[>\\])* '>'
    ) [a-zA-Z0-9]*
    ;

HEX     : '0x' [0-9a-fA-F]+ ('_' [0-9a-fA-F]+)*;
OCTAL   : '0o' [0-7]+ ('_' [0-7]+)*;
BINARY  : '0b' [01]+ ('_' [01]+)*;
FLOAT   : DIGITS '.' DIGITS ([eE] [+-]? DIGITS)?;
INTEGER : DIGITS;

HEREDOC_OPEN
    : '"""' -> pushMode(HEREDOC)
    ;

STRING_OPEN
    : '"' -> pushMode(STRING)
    ;

CHARLIST_HEREDOC
    : '\'\'\'' .*? '\'\'\''
    ;

CHARLIST
    : '\'' ('\\' . | ~['\\])* '\''
    ;

OPEN_BRACE
    : '{' -> pushMode(DEFAULT_MODE)
    ;

OPEN_MAP
    : '%' ([a-zA-Z_] [a-zA-Z0-9_.]*)? '{' -> pushMode(DEFAULT_MODE)
    ;

CLOSE_BRACE
    : '}' -> popMode
    ;

OPEN_PAREN    : '(';
CLOSE_PAREN   : ')';
OPEN_BRACKET  : '[';
CLOSE_BRACKET : ']';
OPEN_BITS     : '<<';
CLOSE_BITS    : '>>';
COMMA         : ',';
SEMICOLON     : ';';
ELLIPSIS      : '...';
CAPTURE       : '&';
AT            : '@';
PIPE_RIGHT    : '|>';
ARROW_RIGHT   : '->';
ARROW_LEFT    : '<-';
FAT_ARROW     : '=>';
DOUBLE_COLON  : '::';
COLON         : ':';
DEFAULT_ARG   : '\\\\';
PLUS          : '+';
MINUS         : '-';
BANG          : '!';
CARET         : '^';
TILDE3        : '~~~';
DOT           : '.';
EQUALS        : '=';
PIPE          : '|';
STAR          : '*';
SLASH         : '/';

// Every other operator. The parser treats them alike, as binary operators.
OPERATOR
    : '===' | '!==' | '==' | '!=' | '=~' | '<=' | '>=' | '<' | '>'
    | '&&&' | '&&' | '|||' | '||' | '<<<' | '>>>' | '^^^'
    | '+++' | '---' | '++' | '--' | '<>' | '..' | '//' | '**'
    | '<<~' | '~>>' | '<~>' | '<|>' | '<~' | '~>'
    ;

fragment OPERATOR_ATOM
    : '===' | '!==' | '==' | '!=' | '=~' | '<=' | '>=' | '<' | '>' | '&&&' | '&&' | '|||' | '||' | '|>'
    | '<<<' | '>>>' | '<<' | '>>' | '^^^' | '+++' | '---' | '++' | '--' | '<>' | '...' | '..' | '//'
    | '**' | '->' | '<-' | '=>' | '::' | '\\\\' | '+' | '-' | '*' | '/' | '!' | '^' | '&' | '@' | '.'
    | '=' | '|' | '~~~' | '%{}' | '{}' | '%' | '<<>>'
    ;

fragment IDENTIFIER_START
    : [\p{Ll}_]
    | [\p{Lo}]
    ;

fragment IDENTIFIER_PART
    : [\p{L}\p{Nd}_]
    ;

fragment DIGITS
    : [0-9]+ ('_' [0-9]+)*
    ;

// An interpolation inside a sigil, whose code may hold the sigil's closing delimiter.
fragment SIGIL_INTERPOLATION
    : '#{' ~[}\r\n]* '}'
    ;

fragment ESCAPE
    : '\\' .
    ;

// The inside of a double-quoted string or quoted atom: text, escapes, and interpolations.
mode STRING;

STRING_CLOSE
    : '"' -> popMode
    ;

STRING_INTERPOLATION
    : '#{' -> pushMode(DEFAULT_MODE)
    ;

STRING_TEXT
    : (~["\\#] | ESCAPE | '#' ~["\\#{])+
    ;

STRING_HASH
    : '#'
    ;

// The inside of a heredoc, which a double quote alone does not close.
mode HEREDOC;

HEREDOC_CLOSE
    : '"""' -> popMode
    ;

HEREDOC_INTERPOLATION
    : '#{' -> pushMode(DEFAULT_MODE)
    ;

HEREDOC_TEXT
    : (~["\\#] | ESCAPE | '#' ~["\\#{] | '"' ~["\\#] | '""' ~["\\#])+
    ;

HEREDOC_PUNCTUATION
    : '#'
    | '"'
    ;
