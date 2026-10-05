/**
MIT License
license:MIT

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

// The Elixir lexer of canon's Elixir dialect: the plain lexer under grammars/elixir, plus lexer modes
// that tokenize @doc, @typedoc, and @moduledoc strings as canonical comments.

lexer grammar ElixirLexer;


/** A line break, which ends a statement unless an operator continues it. Comment-only lines below it belong to it, so a comment does not part an attribute from its definition, while a blank line is another NL. ref:DEC-elixir-dialect */
NL
    : '\r'? '\n' ([ \t]* '#' ~[\r\n]* '\r'? '\n')*
    ;

/** Spaces, tabs, and escaped line breaks, skipped. */
WS
    : ([ \t\f] | '\\' '\r'? '\n')+ -> skip
    ;

/** A # comment, skipped, since Elixir documents with attributes and a comment documents nothing. ref:DEC-elixir-dialect */
COMMENT
    : '#' ~[\r\n]* -> skip
    ;

/** The literal true. */
TRUE  : 'true';
/** The literal false, which after @doc or @moduledoc hides what it documents. ref:DEC-elixir-dialect */
FALSE : 'false';
/** The literal nil. */
NIL   : 'nil';
/** The guard keyword when. */
WHEN  : 'when';
/** The operator and. */
AND   : 'and';
/** The operator or. */
OR    : 'or';
/** The operator not. */
NOT   : 'not';
/** The operator in. */
IN    : 'in';
/** The keyword that opens an anonymous function. */
FN    : 'fn';
/** The keyword that opens a do-block. */
DO    : 'do';
/** The keyword that closes a block. */
END   : 'end';
/** The catch clause keyword of a block. */
CATCH : 'catch';
/** The rescue clause keyword of a block. */
RESCUE: 'rescue';
/** The after clause keyword of a block. */
AFTER : 'after';
/** The else clause keyword of a block. */
ELSE  : 'else';

/** The macro that defines a module. */
DEFMODULE    : 'defmodule';
/** The macro that defines a protocol. */
DEFPROTOCOL  : 'defprotocol';
/** The macro that defines a protocol implementation. */
DEFIMPL      : 'defimpl';
/** The macro that defines a struct. */
DEFSTRUCT    : 'defstruct';
/** The macro that defines an exception. */
DEFEXCEPTION : 'defexception';
/** The macro that defines a delegating function. */
DEFDELEGATE  : 'defdelegate';
/** The macro that defines a private guard. */
DEFGUARDP    : 'defguardp';
/** The macro that defines a public guard. */
DEFGUARD     : 'defguard';
/** The macro that defines a private macro. */
DEFMACROP    : 'defmacrop';
/** The macro that defines a public macro. */
DEFMACRO     : 'defmacro';
/** The macro that defines a private function. */
DEFP         : 'defp';
/** The macro that defines a public function. */
DEF          : 'def';
/** The macro that injects a computed value, which may name a definition. */
UNQUOTE      : 'unquote';

/** The ExUnit and StreamData macros that define a test, test and property, which are a token of their own so the parser can make a test a unit. ref:DEC-elixir-dialect */
TEST_MACRO
    : 'test'
    | 'property'
    ;

/** The ExUnit macro that groups tests, describe. ref:DEC-elixir-dialect */
DESCRIBE_MACRO
    : 'describe'
    ;

/** Opens a @doc or @typedoc heredoc, a canonical comment, whose contents the DocHeredoc mode tokenizes; a lowercase sigil may come before it. ref:DEC-elixir-dialect */
DOC_OPEN
    : '@' ('doc' | 'typedoc') [ \t]+ ('~' [a-z])? '"""' -> pushMode(DocHeredoc)
    ;

/** Opens a @doc or @typedoc heredoc behind an uppercase sigil, which does not interpolate, typed as DOC_OPEN. ref:DEC-elixir-dialect */
DOC_RAW_OPEN
    : '@' ('doc' | 'typedoc') [ \t]+ '~' [A-Z] '"""' -> type(DOC_OPEN), pushMode(DocRawHeredoc)
    ;

/** Opens a @doc or @typedoc string on one line, typed as DOC_OPEN. ref:DEC-elixir-dialect */
DOC_STRING_OPEN
    : '@' ('doc' | 'typedoc') [ \t]+ ('~' [a-z])? '"' -> type(DOC_OPEN), pushMode(DocString)
    ;

/** Opens a @doc or @typedoc string behind an uppercase sigil, typed as DOC_OPEN. ref:DEC-elixir-dialect */
DOC_RAW_STRING_OPEN
    : '@' ('doc' | 'typedoc') [ \t]+ '~' [A-Z] '"' -> type(DOC_OPEN), pushMode(DocRawString)
    ;

/** Opens a @doc or @typedoc heredoc of apostrophes behind a sigil, read without interpolation, typed as DOC_OPEN. ref:DEC-elixir-dialect */
DOC_CHARLIST_OPEN
    : '@' ('doc' | 'typedoc') [ \t]+ '~' [a-zA-Z] '\'\'\'' -> type(DOC_OPEN), pushMode(DocCharlistHeredoc)
    ;

/** Opens a @moduledoc heredoc, the canonical comment of the module around it. ref:DEC-elixir-dialect */
MODULEDOC_OPEN
    : '@moduledoc' [ \t]+ ('~' [a-z])? '"""' -> pushMode(DocHeredoc)
    ;

/** Opens a @moduledoc heredoc of apostrophes behind a sigil, typed as MODULEDOC_OPEN. ref:DEC-elixir-dialect */
MODULEDOC_CHARLIST_OPEN
    : '@moduledoc' [ \t]+ '~' [a-zA-Z] '\'\'\'' -> type(MODULEDOC_OPEN), pushMode(DocCharlistHeredoc)
    ;

/** Opens a @moduledoc heredoc behind an uppercase sigil, typed as MODULEDOC_OPEN. ref:DEC-elixir-dialect */
MODULEDOC_RAW_OPEN
    : '@moduledoc' [ \t]+ '~' [A-Z] '"""' -> type(MODULEDOC_OPEN), pushMode(DocRawHeredoc)
    ;

/** Opens a @moduledoc string on one line, typed as MODULEDOC_OPEN. ref:DEC-elixir-dialect */
MODULEDOC_STRING_OPEN
    : '@moduledoc' [ \t]+ ('~' [a-z])? '"' -> type(MODULEDOC_OPEN), pushMode(DocString)
    ;

/** Opens a @moduledoc string behind an uppercase sigil, typed as MODULEDOC_OPEN. ref:DEC-elixir-dialect */
MODULEDOC_RAW_STRING_OPEN
    : '@moduledoc' [ \t]+ '~' [A-Z] '"' -> type(MODULEDOC_OPEN), pushMode(DocRawString)
    ;

/** The @moduledoc attribute without a string, as in @moduledoc false, which hides the module. ref:DEC-elixir-dialect */
MODULEDOC_ATTRIBUTE
    : '@moduledoc'
    ;

/** The @doc or @typedoc attribute without a string, as in @doc false, which hides the definition below. ref:DEC-elixir-dialect */
DOC_ATTRIBUTE
    : '@' ('doc' | 'typedoc')
    ;

/** The attributes that define a type: @type, @typep, and @opaque. */
TYPE_ATTRIBUTE
    : '@' ('typep' | 'type' | 'opaque')
    ;

/** The attributes that declare a callback: @callback and @macrocallback. */
CALLBACK_ATTRIBUTE
    : '@' ('callback' | 'macrocallback')
    ;

/** Any other module attribute, such as @spec or @impl. */
ATTRIBUTE
    : '@' IDENTIFIER_START IDENTIFIER_PART* [?!]?
    ;

/** A keyword-list key such as do: or opts:, written with no space before the colon. */
KEYWORD
    : (IDENTIFIER_START | [A-Z]) IDENTIFIER_PART* [?!]? ':'
    ;

/** An atom, such as :ok or :+. */
ATOM
    : ':' (IDENTIFIER_START | [A-Z]) (IDENTIFIER_PART | '@')* [?!]?
    | ':' OPERATOR_ATOM
    ;

/** Opens a quoted atom, such as :"a b". */
ATOM_STRING_OPEN
    : ':"' -> pushMode(STRING)
    ;

/** An alias, such as String or Kernel. */
ALIAS
    : [A-Z] [a-zA-Z0-9_]*
    ;

/** A variable or function name. */
IDENTIFIER
    : IDENTIFIER_START IDENTIFIER_PART* [?!]?
    ;

/** A character literal, such as ?a. */
CHAR
    : '?' ('\\' . | ~[\\ \t\r\n])
    ;

/** An uppercase sigil, which does not interpolate and so is a single token. */
SIGIL
    : '~' [A-Z] [A-Z0-9]* (
        '"""' .*? '"""'
        | '\'\'\'' .*? '\'\'\''
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

/** Opens a lowercase sigil delimited by triple quotes, which interpolates, and enters its mode. */
SIGIL_HEREDOC_OPEN    : '~' [a-z] '"""' -> pushMode(SIGIL_HEREDOC);
/** Opens a lowercase sigil delimited by triple apostrophes, which interpolates, and enters its mode. */
SIGIL_CHARDOC_OPEN    : '~' [a-z] '\'\'\'' -> pushMode(SIGIL_CHARDOC);
/** Opens a lowercase sigil delimited by quotes, which interpolates, and enters its mode. */
SIGIL_QUOTE_OPEN      : '~' [a-z] '"' -> pushMode(SIGIL_QUOTE);
/** Opens a lowercase sigil delimited by apostrophes, which interpolates, and enters its mode. */
SIGIL_APOSTROPHE_OPEN : '~' [a-z] '\'' -> pushMode(SIGIL_APOSTROPHE);
/** Opens a lowercase sigil delimited by slashes, which interpolates, and enters its mode. */
SIGIL_SLASH_OPEN      : '~' [a-z] '/' -> pushMode(SIGIL_SLASH);
/** Opens a lowercase sigil delimited by bars, which interpolates, and enters its mode. */
SIGIL_BAR_OPEN        : '~' [a-z] '|' -> pushMode(SIGIL_BAR);
/** Opens a lowercase sigil delimited by parentheses, which interpolates, and enters its mode. */
SIGIL_PAREN_OPEN      : '~' [a-z] '(' -> pushMode(SIGIL_PAREN);
/** Opens a lowercase sigil delimited by brackets, which interpolates, and enters its mode. */
SIGIL_BRACKET_OPEN    : '~' [a-z] '[' -> pushMode(SIGIL_BRACKET);
/** Opens a lowercase sigil delimited by braces, which interpolates, and enters its mode. */
SIGIL_BRACE_OPEN      : '~' [a-z] '{' -> pushMode(SIGIL_BRACE);
/** Opens a lowercase sigil delimited by angle brackets, which interpolates, and enters its mode. */
SIGIL_ANGLE_OPEN      : '~' [a-z] '<' -> pushMode(SIGIL_ANGLE);

/** A hexadecimal integer. */
HEX     : '0x' [0-9a-fA-F]+ ('_' [0-9a-fA-F]+)*;
/** An octal integer. */
OCTAL   : '0o' [0-7]+ ('_' [0-7]+)*;
/** A binary integer. */
BINARY  : '0b' [01]+ ('_' [01]+)*;
/** A float. */
FLOAT   : DIGITS '.' DIGITS ([eE] [+-]? DIGITS)?;
/** A decimal integer. */
INTEGER : DIGITS;

/** Opens a heredoc. */
HEREDOC_OPEN
    : '"""' -> pushMode(HEREDOC)
    ;

/** Opens a double-quoted string. */
STRING_OPEN
    : '"' -> pushMode(STRING)
    ;

/** A charlist heredoc. */
CHARLIST_HEREDOC
    : '\'\'\'' .*? '\'\'\''
    ;

/** A single-quoted charlist. */
CHARLIST
    : '\'' ('\\' . | ~['\\])* '\''
    ;

/** Opens a tuple and pushes the default mode, so the matching brace pops back to whatever mode was current. */
OPEN_BRACE
    : '{' -> pushMode(DEFAULT_MODE)
    ;

/** Opens a map or a struct, pushing the default mode as an opening brace does. */
OPEN_MAP
    : '%' ([a-zA-Z_] [a-zA-Z0-9_.]*)? '{' -> pushMode(DEFAULT_MODE)
    ;

/** Closes a tuple, a map, or an interpolation, popping the mode its opening pushed. */
CLOSE_BRACE
    : '}' -> popMode
    ;

/** An opening parenthesis. */
OPEN_PAREN    : '(';
/** A closing parenthesis. */
CLOSE_PAREN   : ')';
/** An opening bracket. */
OPEN_BRACKET  : '[';
/** A closing bracket. */
CLOSE_BRACKET : ']';
/** Opens a bitstring. */
OPEN_BITS     : '<<';
/** Closes a bitstring. */
CLOSE_BITS    : '>>';
/** A comma. */
COMMA         : ',';
/** A semicolon, which separates statements. */
SEMICOLON     : ';';
/** The ellipsis. */
ELLIPSIS      : '...';
/** The capture operator. */
CAPTURE       : '&';
/** The at sign, as in a module attribute read through @. */
AT            : '@';
/** The pipe operator. */
PIPE_RIGHT    : '|>';
/** The clause arrow. */
ARROW_RIGHT   : '->';
/** The generator arrow. */
ARROW_LEFT    : '<-';
/** The map association arrow. */
FAT_ARROW     : '=>';
/** The type operator. */
DOUBLE_COLON  : '::';
/** A colon. */
COLON         : ':';
/** The default argument operator. */
DEFAULT_ARG   : '\\\\';
/** The plus operator. */
PLUS          : '+';
/** The minus operator. */
MINUS         : '-';
/** The bang operator. */
BANG          : '!';
/** The pin operator. */
CARET         : '^';
/** The bitwise not operator. */
TILDE3        : '~~~';
/** A dot. */
DOT           : '.';
/** The match operator. */
EQUALS        : '=';
/** The cons and union operator. */
PIPE          : '|';
/** The multiplication operator. */
STAR          : '*';
/** The division operator. */
SLASH         : '/';

/** Every other operator, which the parser treats alike as binary operators. */
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

fragment ESCAPE
    : '\\' .
    ;

mode STRING;

/** Closes a string or quoted atom and returns to the enclosing mode. */
STRING_CLOSE
    : '"' -> popMode
    ;

/** Opens an interpolation inside a string, pushing the default mode. */
STRING_INTERPOLATION
    : '#{' -> pushMode(DEFAULT_MODE)
    ;

/** Text and escapes inside a string. */
STRING_TEXT
    : (~["\\#] | ESCAPE | '#' ~["\\#{])+
    ;

/** A hash inside a string that opens no interpolation. */
STRING_HASH
    : '#'
    ;

mode HEREDOC;

/** Closes a heredoc. */
HEREDOC_CLOSE
    : '"""' -> popMode
    ;

/** Opens an interpolation inside a heredoc. */
HEREDOC_INTERPOLATION
    : '#{' -> pushMode(DEFAULT_MODE)
    ;

/** Text and escapes inside a heredoc. */
HEREDOC_TEXT
    : (~["\\#] | ESCAPE | '#' ~["\\#{] | '"' ~["\\#] | '""' ~["\\#])+
    ;

/** A hash or quote inside a heredoc that neither interpolates nor closes it. */
HEREDOC_PUNCTUATION
    : '#'
    | '"'
    ;

mode SIGIL_HEREDOC;

/** Closes a lowercase sigil delimited by triple quotes, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_HEREDOC_CLOSE         : '"""' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by triple quotes, typed as SIGIL_INTERPOLATION. */
SIGIL_HEREDOC_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by triple quotes, typed as SIGIL_TEXT. */
SIGIL_HEREDOC_TEXT          : (~["\\#] | ESCAPE | '#' ~["\\#{] | '"' ~["\\#] | '""' ~["\\#])+ -> type(SIGIL_TEXT);
/** A hash or delimiter character inside a sigil delimited by triple quotes that neither interpolates nor closes it, typed as SIGIL_TEXT. */
SIGIL_HEREDOC_PUNCTUATION   : ('#' | '"') -> type(SIGIL_TEXT);

mode SIGIL_CHARDOC;

/** Closes a lowercase sigil delimited by triple apostrophes, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_CHARDOC_CLOSE         : '\'\'\'' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by triple apostrophes, typed as SIGIL_INTERPOLATION. */
SIGIL_CHARDOC_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by triple apostrophes, typed as SIGIL_TEXT. */
SIGIL_CHARDOC_TEXT          : (~['\\#] | ESCAPE | '#' ~['\\#{] | '\'' ~['\\#] | '\'\'' ~['\\#])+ -> type(SIGIL_TEXT);
/** A hash or delimiter character inside a sigil delimited by triple apostrophes that neither interpolates nor closes it, typed as SIGIL_TEXT. */
SIGIL_CHARDOC_PUNCTUATION   : ('#' | '\'') -> type(SIGIL_TEXT);

mode SIGIL_QUOTE;

/** Closes a lowercase sigil delimited by quotes, with its modifiers, and returns to the enclosing mode. */
SIGIL_CLOSE               : '"' [a-zA-Z0-9]* -> popMode;
/** Opens an interpolation inside a sigil delimited by quotes, pushing the default mode. */
SIGIL_INTERPOLATION       : '#{' -> pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by quotes. */
SIGIL_TEXT                : (~["\\#] | ESCAPE | '#' ~["\\#{])+;
/** A hash inside a sigil delimited by quotes that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_QUOTE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_APOSTROPHE;

/** Closes a lowercase sigil delimited by apostrophes, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_APOSTROPHE_CLOSE         : '\'' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by apostrophes, typed as SIGIL_INTERPOLATION. */
SIGIL_APOSTROPHE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by apostrophes, typed as SIGIL_TEXT. */
SIGIL_APOSTROPHE_TEXT          : (~['\\#] | ESCAPE | '#' ~['\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by apostrophes that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_APOSTROPHE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_SLASH;

/** Closes a lowercase sigil delimited by slashes, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_SLASH_CLOSE         : '/' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by slashes, typed as SIGIL_INTERPOLATION. */
SIGIL_SLASH_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by slashes, typed as SIGIL_TEXT. */
SIGIL_SLASH_TEXT          : (~[/\\#] | ESCAPE | '#' ~[/\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by slashes that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_SLASH_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BAR;

/** Closes a lowercase sigil delimited by bars, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_BAR_CLOSE         : '|' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by bars, typed as SIGIL_INTERPOLATION. */
SIGIL_BAR_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by bars, typed as SIGIL_TEXT. */
SIGIL_BAR_TEXT          : (~[|\\#] | ESCAPE | '#' ~[|\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by bars that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_BAR_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_PAREN;

/** Closes a lowercase sigil delimited by parentheses, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_PAREN_CLOSE         : ')' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by parentheses, typed as SIGIL_INTERPOLATION. */
SIGIL_PAREN_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by parentheses, typed as SIGIL_TEXT. */
SIGIL_PAREN_TEXT          : (~[)\\#] | ESCAPE | '#' ~[)\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by parentheses that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_PAREN_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BRACKET;

/** Closes a lowercase sigil delimited by brackets, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_BRACKET_CLOSE         : ']' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by brackets, typed as SIGIL_INTERPOLATION. */
SIGIL_BRACKET_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by brackets, typed as SIGIL_TEXT. */
SIGIL_BRACKET_TEXT          : (~[\]\\#] | ESCAPE | '#' ~[\]\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by brackets that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_BRACKET_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_BRACE;

/** Closes a lowercase sigil delimited by braces, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_BRACE_CLOSE         : '}' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by braces, typed as SIGIL_INTERPOLATION. */
SIGIL_BRACE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by braces, typed as SIGIL_TEXT. */
SIGIL_BRACE_TEXT          : (~[}\\#] | ESCAPE | '#' ~[}\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by braces that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_BRACE_HASH          : '#' -> type(SIGIL_TEXT);

mode SIGIL_ANGLE;

/** Closes a lowercase sigil delimited by angle brackets, with its modifiers, typed as SIGIL_CLOSE. */
SIGIL_ANGLE_CLOSE         : '>' [a-zA-Z0-9]* -> type(SIGIL_CLOSE), popMode;
/** Opens an interpolation inside a sigil delimited by angle brackets, typed as SIGIL_INTERPOLATION. */
SIGIL_ANGLE_INTERPOLATION : '#{' -> type(SIGIL_INTERPOLATION), pushMode(DEFAULT_MODE);
/** Text and escapes inside a sigil delimited by angle brackets, typed as SIGIL_TEXT. */
SIGIL_ANGLE_TEXT          : (~[>\\#] | ESCAPE | '#' ~[>\\#{])+ -> type(SIGIL_TEXT);
/** A hash inside a sigil delimited by angle brackets that opens no interpolation, typed as SIGIL_TEXT. */
SIGIL_ANGLE_HASH          : '#' -> type(SIGIL_TEXT);

mode DocHeredoc;

/** Closes a documentation heredoc and returns to the enclosing mode. ref:DEC-elixir-dialect */
DOC_CLOSE
    : '"""' -> popMode
    ;

/** Opens an interpolation inside documentation, pushing the default mode, so the code inside it, strings and heredocs included, is read as code. ref:DEC-elixir-dialect */
DOC_INTERPOLATION
    : '#{' -> pushMode(DEFAULT_MODE)
    ;

/** A citation of a registry reference inside documentation. ref:DEC-elixir-dialect */
DOC_REF
    : 'ref:' DocKey
    ;

/** A citation of a registry license inside documentation. ref:DEC-elixir-dialect */
DOC_LICENSE
    : 'license:' DocKey
    ;

/** Whitespace inside documentation, skipped. */
DOC_WS
    : [ \t\r\n]+ -> skip
    ;

/** An escaped character inside documentation, typed as DOC_WORD so an escaped quote does not close it. */
DOC_ESCAPE
    : '\\' . -> type(DOC_WORD)
    ;

/** Punctuation inside documentation, kept apart so a citation followed by a comma is still a citation. ref:DEC-elixir-dialect */
DOC_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/-]
    ;

/** A word of prose inside documentation. ref:DEC-elixir-dialect */
DOC_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+
    ;

mode DocRawHeredoc;

/** Closes a documentation heredoc behind an uppercase sigil, typed as DOC_CLOSE. */
DOC_RAW_CLOSE
    : '"""' -> type(DOC_CLOSE), popMode
    ;

/** A reference citation in documentation behind an uppercase sigil, typed as DOC_REF. */
DOC_RAW_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in documentation behind an uppercase sigil, typed as DOC_LICENSE. */
DOC_RAW_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace in documentation behind an uppercase sigil, skipped. */
DOC_RAW_WS
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation in documentation behind an uppercase sigil, where a hash and a backslash are text, typed as DOC_PUNCT. */
DOC_RAW_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\-] -> type(DOC_PUNCT)
    ;

/** A word in documentation behind an uppercase sigil, typed as DOC_WORD. */
DOC_RAW_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+ -> type(DOC_WORD)
    ;

mode DocCharlistHeredoc;

/** Closes documentation in a heredoc of apostrophes, typed as DOC_CLOSE. */
DOC_CHARLIST_CLOSE
    : '\'\'\'' -> type(DOC_CLOSE), popMode
    ;

/** A reference citation in a heredoc of apostrophes, typed as DOC_REF. */
DOC_CHARLIST_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in a heredoc of apostrophes, typed as DOC_LICENSE. */
DOC_CHARLIST_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace in a heredoc of apostrophes, skipped. */
DOC_CHARLIST_WS
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation in a heredoc of apostrophes, typed as DOC_PUNCT. */
DOC_CHARLIST_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\-] -> type(DOC_PUNCT)
    ;

/** A word in a heredoc of apostrophes, typed as DOC_WORD. */
DOC_CHARLIST_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+ -> type(DOC_WORD)
    ;

mode DocString;

/** Closes documentation on one line, typed as DOC_CLOSE. */
DOC_STRING_CLOSE
    : '"' -> type(DOC_CLOSE), popMode
    ;

/** Opens an interpolation in documentation on one line, typed as DOC_INTERPOLATION. */
DOC_STRING_INTERPOLATION
    : '#{' -> type(DOC_INTERPOLATION), pushMode(DEFAULT_MODE)
    ;

/** A reference citation in documentation on one line, typed as DOC_REF. */
DOC_STRING_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in documentation on one line, typed as DOC_LICENSE. */
DOC_STRING_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace in documentation on one line, skipped. */
DOC_STRING_WS
    : [ \t\r\n]+ -> skip
    ;

/** An escaped character in documentation on one line, typed as DOC_WORD. */
DOC_STRING_ESCAPE
    : '\\' . -> type(DOC_WORD)
    ;

/** Punctuation in documentation on one line, where a quote closes the string instead, typed as DOC_PUNCT. */
DOC_STRING_PUNCT
    : [,.;:()!?[\]{}'`<>=+*#|/-] -> type(DOC_PUNCT)
    ;

/** A word in documentation on one line, typed as DOC_WORD. */
DOC_STRING_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+ -> type(DOC_WORD)
    ;

mode DocRawString;

/** Closes documentation on one line behind an uppercase sigil, typed as DOC_CLOSE. */
DOC_RAW_STRING_CLOSE
    : '"' -> type(DOC_CLOSE), popMode
    ;

/** A reference citation in documentation on one line behind an uppercase sigil, typed as DOC_REF. */
DOC_RAW_STRING_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in documentation on one line behind an uppercase sigil, typed as DOC_LICENSE. */
DOC_RAW_STRING_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace in documentation on one line behind an uppercase sigil, skipped. */
DOC_RAW_STRING_WS
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation in documentation on one line behind an uppercase sigil, typed as DOC_PUNCT. */
DOC_RAW_STRING_PUNCT
    : [,.;:()!?[\]{}'`<>=+*#|/\\-] -> type(DOC_PUNCT)
    ;

/** A word in documentation on one line behind an uppercase sigil, typed as DOC_WORD. */
DOC_RAW_STRING_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+ -> type(DOC_WORD)
    ;

fragment DocKey
    : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?
    ;
