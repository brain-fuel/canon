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

// The Gleam lexer of canon's Gleam dialect: the plain lexer under grammars/gleam, plus a lexer mode
// that tokenizes /// and //// comments as canonical comments.

lexer grammar GleamLexer;


/** Opens a //// comment, which documents the module, and enters the DocLine mode. ref:DEC-gleam-dialect */
MODULE_DOC_OPEN
    : '////' -> pushMode(DocLine)
    ;

/** Opens a /// comment, which documents the item below it, and enters the DocLine mode. ref:DEC-gleam-dialect */
DOC_OPEN
    : '///' -> pushMode(DocLine)
    ;

/** A // comment that is not documentation, skipped. ref:DEC-gleam-dialect */
COMMENT
    : '//' (~[/\r\n] ~[\r\n]*)?
    -> skip
    ;

/** Whitespace, skipped. */
WS
    : [ \t\r\n\f]+ -> skip
    ;

/** The keyword pub, which makes an item public. */
PUB    : 'pub';
/** The keyword fn. */
FN     : 'fn';
/** The keyword type. */
TYPE   : 'type';
/** The keyword opaque. */
OPAQUE : 'opaque';
/** The keyword const. */
CONST  : 'const';
/** The keyword import. */
IMPORT : 'import';
/** The keyword as. */
AS     : 'as';
/** The keyword let. */
LET    : 'let';
/** The keyword assert. */
ASSERT : 'assert';
/** The keyword case. */
CASE   : 'case';
/** The keyword use. */
USE    : 'use';
/** The keyword todo. */
TODO   : 'todo';
/** The keyword panic. */
PANIC  : 'panic';
/** The keyword echo. */
ECHO   : 'echo';
/** The keyword if, which before Gleam 1.0 also opened a target group. */
IF     : 'if';

/** The word external, which before Gleam 1.0 began an external function or type; a name to Gleam 1.x. */
EXTERNAL : 'external';
/** The word internal, which as an attribute hides an item from the documentation; a name otherwise. ref:DEC-hidden-label */
INTERNAL : 'internal';

/** A capitalised name, of a type or a constructor. */
UPNAME
    : [A-Z] [a-zA-Z0-9]*
    ;

/** A lowercase name. */
NAME
    : [a-z] [a-z0-9_]*
    ;

/** A discarded name, starting with an underscore. */
DISCARD_NAME
    : '_' [a-z0-9_]*
    ;

/** An integer. */
INTEGER
    : '0x' [0-9a-fA-F_]+
    | '0o' [0-7_]+
    | '0b' [01_]+
    | DIGITS
    ;

/** A float. */
FLOAT
    : DIGITS '.' DIGITS? ([eE] '-'? DIGITS)?
    ;

/** A string. */
STRING
    : '"' ('\\' . | ~["\\])* '"'
    ;

/** An opening parenthesis. */
OPEN_PAREN    : '(';
/** A closing parenthesis. */
CLOSE_PAREN   : ')';
/** An opening bracket. */
OPEN_BRACKET  : '[';
/** A closing bracket. */
CLOSE_BRACKET : ']';
/** An opening brace. */
OPEN_BRACE    : '{';
/** A closing brace. */
CLOSE_BRACE   : '}';
/** Opens a bit array. */
OPEN_BITS     : '<<';
/** Closes a bit array. */
CLOSE_BITS    : '>>';
/** A comma. */
COMMA         : ',';
/** A dot. */
DOT           : '.';
/** A colon. */
COLON         : ':';
/** A hash, which opens a tuple. */
HASH          : '#';
/** The at sign of an attribute. */
AT            : '@';
/** An equals sign. */
EQUALS        : '=';
/** An arrow. */
ARROW_RIGHT   : '->';
/** A minus. */
MINUS         : '-';

/** Every other operator. */
OPERATOR
    : '==' | '!=' | '<=.' | '>=.' | '<.' | '>.' | '<=' | '>=' | '<' | '>'
    | '+.' | '-.' | '*.' | '/.' | '+' | '*' | '/' | '%'
    | '<>' | '|>' | '||' | '&&' | '|' | '..' | '<-' | '!'
    ;

fragment DIGITS
    : [0-9] [0-9_]*
    ;

mode DocLine;

/** The line break that ends a line of documentation and returns to the default mode. ref:DEC-gleam-dialect */
DOC_CLOSE
    : '\r'? '\n' -> popMode
    ;

/** A citation of a registry reference inside documentation. ref:DEC-gleam-dialect */
DOC_REF
    : 'ref:' DocKey
    ;

/** A citation of a registry license inside documentation. ref:DEC-gleam-dialect */
DOC_LICENSE
    : 'license:' DocKey
    ;

/** Spaces inside documentation, skipped. */
DOC_WS
    : [ \t]+ -> skip
    ;

/** Punctuation inside documentation, kept apart so a citation followed by a comma is still a citation. */
DOC_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\-]
    ;

/** A word of prose inside documentation. */
DOC_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\-]+
    ;

fragment DocKey
    : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?
    ;

