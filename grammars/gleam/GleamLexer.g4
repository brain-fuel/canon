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

// A lexer for Gleam, written for canon from the Gleam language tour and the Gleam compiler's
// lexer. Comments of every kind are skipped, because canon scans doc comments from the text.

lexer grammar GleamLexer;

COMMENT
    : '//' ~[\r\n]* -> skip
    ;

WS
    : [ \t\r\n\f]+ -> skip
    ;

PUB    : 'pub';
FN     : 'fn';
TYPE   : 'type';
OPAQUE : 'opaque';
CONST  : 'const';
IMPORT : 'import';
AS     : 'as';
LET    : 'let';
ASSERT : 'assert';
CASE   : 'case';
USE    : 'use';
TODO   : 'todo';
PANIC  : 'panic';
ECHO   : 'echo';
IF     : 'if';

// Words that are names to Gleam 1.x but that canon must see: external, which began an external
// function or type before Gleam 1.0, and internal, the attribute that hides an item from the
// documentation. The parser accepts both wherever it accepts a name.
EXTERNAL : 'external';
INTERNAL : 'internal';

UPNAME
    : [A-Z] [a-zA-Z0-9]*
    ;

NAME
    : [a-z] [a-z0-9_]*
    ;

DISCARD_NAME
    : '_' [a-z0-9_]*
    ;

INTEGER
    : '0x' [0-9a-fA-F_]+
    | '0o' [0-7_]+
    | '0b' [01_]+
    | DIGITS
    ;

FLOAT
    : DIGITS '.' DIGITS? ([eE] '-'? DIGITS)?
    ;

STRING
    : '"' ('\\' . | ~["\\])* '"'
    ;

OPEN_PAREN    : '(';
CLOSE_PAREN   : ')';
OPEN_BRACKET  : '[';
CLOSE_BRACKET : ']';
OPEN_BRACE    : '{';
CLOSE_BRACE   : '}';
OPEN_BITS     : '<<';
CLOSE_BITS    : '>>';
COMMA         : ',';
DOT           : '.';
COLON         : ':';
HASH          : '#';
AT            : '@';
EQUALS        : '=';
ARROW_RIGHT   : '->';
MINUS         : '-';

// Every other operator. Function bodies are read as balanced brackets, so they are told apart only
// where the parser needs them.
OPERATOR
    : '==' | '!=' | '<=.' | '>=.' | '<.' | '>.' | '<=' | '>=' | '<' | '>'
    | '+.' | '-.' | '*.' | '/.' | '+' | '*' | '/' | '%'
    | '<>' | '|>' | '||' | '&&' | '|' | '..' | '<-' | '!'
    ;

fragment DIGITS
    : [0-9] [0-9_]*
    ;
