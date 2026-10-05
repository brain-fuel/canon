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
// Braces push the default mode and closing braces pop it, so the closing brace of a string or
// sigil interpolation returns to the literal it interrupted.

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
// @moduledoc has a type of its own, because @moduledoc false hides the module around it while
// @doc false hides the definition below it.
MODULEDOC_ATTRIBUTE
    : '@moduledoc'
    ;

DOC_ATTRIBUTE
    : '@' ('doc' | 'typedoc')
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
// canon: a key may start with any letter and hold @, as an atom may, as in [Ólá: 0] and [ól@: 0].
KEYWORD
    : [\p{L}_] (IDENTIFIER_PART | '@')* [?!]? ':'
    ;

// canon: an operator is a keyword-list key too, as in import Kernel, except: [==: 2], when a space
// follows its colon; the token takes the space, since Elixir's tokenizer requires one there.
OPERATOR_KEYWORD
    : OPERATOR_ATOM ':' [ \t\r\n] -> type(KEYWORD)
    ;

// canon: an atom may start with any letter, as :Ólá does.
ATOM
    : ':' [\p{L}_] (IDENTIFIER_PART | '@')* [?!]?
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

// An uppercase sigil does not interpolate, so it is a single token: canon reads no code inside it.
// canon: a heredoc closes only at the start of a line, so the \""" that ends a line inside an
// uppercase sigil heredoc, which reads no escapes, does not close it.
SIGIL
    : '~' [A-Z] [A-Z0-9]* (
        '"""' .*? '\n' [ \t]* '"""'
        | '\'\'\'' .*? '\n' [ \t]* '\'\'\''
        | '"' ('\\' . | ~["\\])* '"'
        | '\'' ('\\' . | ~['\\])* '\''
        | '/' ('\\' . | ~[/\\])* '/'
        | '|' ('\\' . | ~[|\\])* '|'
        | '(' ('\\' . | ~[)\\])* ')'
        | '[' ('\\' . | ~[\]\\])* ']'
        | '{' ('\\' . | ~[}\\])* '}'
        | '<' ('\\' . | ~[>\\])* '>'
    ) [a-zA-Z0-9]*
    ;

// A lowercase sigil interpolates, so its opening enters a mode per delimiter, as a string does, and
// an interpolation inside it may hold any code, including the sigil's closing delimiter and
// newlines.
SIGIL_HEREDOC_OPEN    : '~' [a-z] '"""' -> pushMode(SIGIL_HEREDOC);
SIGIL_CHARDOC_OPEN    : '~' [a-z] '\'\'\'' -> pushMode(SIGIL_CHARDOC);
SIGIL_QUOTE_OPEN      : '~' [a-z] '"' -> pushMode(SIGIL_QUOTE);
SIGIL_APOSTROPHE_OPEN : '~' [a-z] '\'' -> pushMode(SIGIL_APOSTROPHE);
SIGIL_SLASH_OPEN      : '~' [a-z] '/' -> pushMode(SIGIL_SLASH);
SIGIL_BAR_OPEN        : '~' [a-z] '|' -> pushMode(SIGIL_BAR);
SIGIL_PAREN_OPEN      : '~' [a-z] '(' -> pushMode(SIGIL_PAREN);
SIGIL_BRACKET_OPEN    : '~' [a-z] '[' -> pushMode(SIGIL_BRACKET);
SIGIL_BRACE_OPEN      : '~' [a-z] '{' -> pushMode(SIGIL_BRACE);
SIGIL_ANGLE_OPEN      : '~' [a-z] '<' -> pushMode(SIGIL_ANGLE);

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

// canon: a charlist heredoc closes only at the start of a line.
CHARLIST_HEREDOC
    : '\'\'\'' .*? '\n' [ \t]* '\'\'\''
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

// canon: a struct whose name is an expression, as in %unquote(type){}, %^module{}, or %@for{},
// starts with a percent sign of its own.
PERCENT
    : '%'
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

// canon: .. has a type of its own, since alone it is an operand, the full range, as in
// Enum.slice(list, ..).
RANGE         : '..';

// Every other operator. The parser treats them alike, as binary operators.
OPERATOR
    : '===' | '!==' | '==' | '!=' | '=~' | '<=' | '>=' | '<' | '>'
    | '&&&' | '&&' | '|||' | '||' | '<<<' | '>>>' | '^^^'
    | '+++' | '---' | '++' | '--' | '<>' | '//' | '**'
    | '<<~' | '~>>' | '<~>' | '<|>' | '<~' | '~>'
    ;

fragment OPERATOR_ATOM
    : '===' | '!==' | '==' | '!=' | '=~' | '<=' | '>=' | '<' | '>' | '&&&' | '&&' | '|||' | '||' | '|>'
    | '<<<' | '>>>' | '<<' | '>>' | '^^^' | '+++' | '---' | '++' | '--' | '<>' | '...' | '..' | '//'
    | '**' | '->' | '<-' | '=>' | '::' | '\\\\' | '+' | '-' | '*' | '/' | '!' | '^' | '&' | '@' | '.'
    | '=' | '|' | '~~~' | '%{}' | '{}' | '%' | '<<>>'
    // canon: the newer operators are atoms too, as in :..// and :<~>.
    | '..//' | '<<~' | '~>>' | '<~>' | '<|>' | '<~' | '~>'
    ;

fragment IDENTIFIER_START
    : [\p{Ll}_]
    | [\p{Lo}]
    ;

// canon: a name may hold combining marks, as Thai names such as บูมเมอแรง do.
fragment IDENTIFIER_PART
    : [\p{L}\p{M}\p{Nd}_]
    ;

fragment DIGITS
    : [0-9]+ ('_' [0-9]+)*
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

// The inside of each lowercase sigil: text, escapes, and interpolations, up to the closing
// delimiter and the sigil's modifiers. The text of every mode is a SIGIL_TEXT.
mode SIGIL_HEREDOC;

SIGIL_HEREDOC_CLOSE         : '"""' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_HEREDOC_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_HEREDOC_TEXT          : (~["\\#] | ESCAPE | '#' ~["\\#{] | '"' ~["\\#] | '""' ~["\\#])+ -> type(SIGIL_TEXT);
SIGIL_HEREDOC_PUNCTUATION   : ('#' | '"') -> type(SIGIL_TEXT);

mode SIGIL_CHARDOC;

SIGIL_CHARDOC_CLOSE         : '\'\'\'' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_CHARDOC_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_CHARDOC_TEXT          : (~['\\#] | ESCAPE | '#' ~['\\#{] | '\'' ~['\\#] | '\'\'' ~['\\#])+ -> type(SIGIL_TEXT);
SIGIL_CHARDOC_PUNCTUATION   : ('#' | '\'') -> type(SIGIL_TEXT);

mode SIGIL_QUOTE;

SIGIL_CLOSE               : '"' [a-zA-Z0-9]* -> popMode;
SIGIL_INTERPOLATION       : '#{' -> pushMode(DEFAULT_MODE);
SIGIL_TEXT                : (~["\\#] | ESCAPE | '#' ~["\\#{])+;
SIGIL_QUOTE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_APOSTROPHE;

SIGIL_APOSTROPHE_CLOSE         : '\'' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_APOSTROPHE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_APOSTROPHE_TEXT          : (~['\\#] | ESCAPE | '#' ~['\\#{])+ -> type(SIGIL_TEXT);
SIGIL_APOSTROPHE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_SLASH;

SIGIL_SLASH_CLOSE         : '/' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_SLASH_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_SLASH_TEXT          : (~[/\\#] | ESCAPE | '#' ~[/\\#{])+ -> type(SIGIL_TEXT);
SIGIL_SLASH_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BAR;

SIGIL_BAR_CLOSE         : '|' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_BAR_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_BAR_TEXT          : (~[|\\#] | ESCAPE | '#' ~[|\\#{])+ -> type(SIGIL_TEXT);
SIGIL_BAR_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_PAREN;

SIGIL_PAREN_CLOSE         : ')' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_PAREN_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_PAREN_TEXT          : (~[)\\#] | ESCAPE | '#' ~[)\\#{])+ -> type(SIGIL_TEXT);
SIGIL_PAREN_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BRACKET;

SIGIL_BRACKET_CLOSE         : ']' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_BRACKET_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_BRACKET_TEXT          : (~[\]\\#] | ESCAPE | '#' ~[\]\\#{])+ -> type(SIGIL_TEXT);
SIGIL_BRACKET_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BRACE;

SIGIL_BRACE_CLOSE         : '}' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_BRACE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_BRACE_TEXT          : (~[}\\#] | ESCAPE | '#' ~[}\\#{])+ -> type(SIGIL_TEXT);
SIGIL_BRACE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_ANGLE;

SIGIL_ANGLE_CLOSE         : '>' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
SIGIL_ANGLE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
SIGIL_ANGLE_TEXT          : (~[>\\#] | ESCAPE | '#' ~[>\\#{])+ -> type(SIGIL_TEXT);
SIGIL_ANGLE_HASH          : '#' -> type(SIGIL_TEXT);
