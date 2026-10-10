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



// The Swift lexer canon reads Swift with. It is written for canon from the Lexical Structure chapter
// of The Swift Programming Language
// (https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/)
// and its grammar summary, checked against the Swift compiler's lexer (swift-syntax's Lexer,
// Apache-2.0 with the Runtime Library Exception), and covers what extraction needs: every token kind
// of Swift 6 source, so that comments, strings with their interpolations, raw and multi-line strings,
// regex literals, and backquoted names never hide or fake code, and the keywords and brackets the
// parser's structure rests on.
//
// Two things are not lexical. Which line breaks end a statement depends on the tokens around them,
// and #if compilation conditions select the code a build compiles; the SwiftLexerBase hook emits a
// NEWLINE token where a line break separates statements and hides the branches a build does not
// read. See grammars/swift/README.md.

lexer grammar SwiftLexer;

options {
    superClass = SwiftLexerBase;
}

// The token the SwiftLexerBase hook emits; no lexer rule matches it.
tokens {
    NEWLINE
}

BYTE_ORDER_MARK: '\uFEFF' -> channel(HIDDEN);

// A script's #! line.
SHEBANG: '#!' ~[\r\n]* -> channel(HIDDEN);

// A conditional compilation directive, with its condition, to the end of its line. The hook reads
// it and hides the branches a build does not compile; #sourceLocation, #warning, and #error are
// read as the macro expansions they look like.
DIRECTIVE: ('#' ('if' | 'elseif') [ \t(!] ~[\r\n]* | '#' ('else' | 'endif') ([ \t/] ~[\r\n]*)?) -> channel(HIDDEN);

// Comments. A block comment nests.
BLOCK_COMMENT : '/*' (BLOCK_COMMENT | .)*? '*/' -> channel(HIDDEN);
LINE_COMMENT  : '//' ~[\r\n]*                   -> channel(HIDDEN);
WHITESPACE    : [ \t\r\n\f\u000B\u0000]+         -> channel(HIDDEN);

// Keywords used in declarations, which the parser's structure rests on. The other keywords of
// statements and expressions are names to the parser, which reads statements and expressions as
// runs of tokens; the hook tells them apart by their text where a line break depends on them.
ASSOCIATEDTYPE  : 'associatedtype';
CASE            : 'case';
CLASS           : 'class';
DEINIT          : 'deinit';
ENUM            : 'enum';
EXTENSION       : 'extension';
FILEPRIVATE     : 'fileprivate';
FUNC            : 'func';
IMPORT          : 'import';
INIT            : 'init';
INTERNAL        : 'internal';
LET             : 'let';
OPERATOR        : 'operator';
PRECEDENCEGROUP : 'precedencegroup';
PRIVATE         : 'private';
PROTOCOL        : 'protocol';
PUBLIC          : 'public';
STATIC          : 'static';
STRUCT          : 'struct';
SUBSCRIPT       : 'subscript';
TYPEALIAS       : 'typealias';
VAR             : 'var';

// Contextual keywords that declare or modify a declaration, which are names everywhere else.
ACTOR       : 'actor';
BORROWING   : 'borrowing';
CONSUMING   : 'consuming' | '__consuming';
CONVENIENCE : 'convenience';
DISTRIBUTED : 'distributed';
DYNAMIC     : 'dynamic';
FINAL       : 'final';
INDIRECT    : 'indirect';
INFIX       : 'infix';
LAZY        : 'lazy';
MACRO       : 'macro';
MUTATING    : 'mutating';
NONISOLATED : 'nonisolated';
NONMUTATING : 'nonmutating';
OPEN        : 'open';
OPTIONAL    : 'optional';
OVERRIDE    : 'override';
PACKAGE     : 'package';
POSTFIX     : 'postfix';
PREFIX      : 'prefix';
REQUIRED    : 'required';
UNOWNED     : 'unowned';
WEAK        : 'weak';

// A string literal is one token, its interpolations and the strings nested in them included, so a
// quote or a bracket inside one never reaches the parser. A single-line string holds escapes and no
// line break outside an interpolation; a multi-line string, whose opening quotes end their line,
// runs to the first """ outside an interpolation.
STRING           : '"' (~["\\\r\n] | '\\' ~[(\r\n] | '\\' Interpolation)* '"';
MULTILINE_STRING : '"""' [ \t]* '\r'? '\n' ('\\' Interpolation | '\\' ~'(' | ~'\\')*? '"""';

// A raw string, delimited by one to seven number signs: a single-line one runs on its line to its
// first quote followed by as many, and a multi-line one, whose opening quotes end their line, to its
// first three quotes followed by as many. Its interpolations are text to the lexer.
RAW_STRING:
    '#"' ~[\r\n]*? '"#'
    | '#"""' [ \t]* '\r'? '\n' .*? '"""#'
    | '##"' ~[\r\n]*? '"##'
    | '##"""' [ \t]* '\r'? '\n' .*? '"""##'
    | '###"' ~[\r\n]*? '"###'
    | '###"""' [ \t]* '\r'? '\n' .*? '"""###'
    | '####"' ~[\r\n]*? '"####'
    | '####"""' [ \t]* '\r'? '\n' .*? '"""####'
    | '#####"' ~[\r\n]*? '"#####'
    | '#####"""' [ \t]* '\r'? '\n' .*? '"""#####'
    | '######"' ~[\r\n]*? '"######'
    | '######"""' [ \t]* '\r'? '\n' .*? '"""######'
    | '#######"' ~[\r\n]*? '"#######'
    | '#######"""' [ \t]* '\r'? '\n' .*? '"""#######'
;

// A regex literal: an extended one between #/ and /#, and a bare one between slashes, which starts
// where an expression may, as the hook answers from the token before it, holds no line break, and
// starts with neither a space nor a tab, as the compiler's lexer decides.
EXTENDED_REGEX : '#/' .*? '/#' | '##/' .*? '/##';
REGEX          : '/' {this.regexStart()}? (~[ \t\r\n/*\\] | '\\' ~[\r\n]) (~[\\/\r\n] | '\\' ~[\r\n])* '/';

NUMBER:
    DecimalLiteral ('.' DecimalDigits)? DecimalExponent?
    | '0x' HexDigit HexChar* ('.' HexDigit HexChar*)? ([pP] [+\-]? DecimalDigits)?
    | '0o' [0-7] [0-7_]*
    | '0b' [01] [01_]*
;

LPAREN    : '(';
RPAREN    : ')';
LBRACK    : '[';
RBRACK    : ']';
LBRACE    : '{';
RBRACE    : '}';
COMMA     : ',';
SEMI      : ';';
COLON     : ':';
AT        : '@';
HASH      : '#';
BACKSLASH : '\\';
DOT       : '.';

// A lone < or >, which opens or closes a generic argument clause or compares; longer operators,
// >> and >= among them, are OP.
LT : '<';
GT : '>';

// An operator: a run of operator characters, or a dot followed by dots and operator characters.
// = -> ? ! & and the rest are all OP to the parser, which reads them inside runs of tokens.
OP: OperatorHead OperatorChar* | '.' ('.' | OperatorHead) ('.' | OperatorChar)*;

// The wildcard, which no declaration is named by, and @_spi's name, before ID, which would take
// them by rule order otherwise.
UNDERSCORE    : '_';
SPI           : '_spi';
BACKQUOTED_ID : '`' ~[`\r\n]+ '`';
ID            : IdentifierHead IdentifierChar*;

fragment Interpolation  : '(' InterpolationItem* ')';
fragment InterpolationItem:
    ~["()#/\\]
    | '\\'
    | Interpolation
    | STRING
    | MULTILINE_STRING
    | RAW_STRING
    | '#'
    | '/'
;
fragment DecimalLiteral : [0-9] [0-9_]*;
fragment DecimalDigits  : [0-9] [0-9_]*;
fragment DecimalExponent: [eE] [+\-]? DecimalDigits;
fragment HexDigit       : [0-9a-fA-F];
fragment HexChar        : [0-9a-fA-F_];
fragment OperatorHead:
    [/=\-+!*%<>&|^~?]
    | [\u00A1-\u00A7\u00A9\u00AB\u00AC\u00AE\u00B0\u00B1\u00B6\u00BB\u00BF\u00D7\u00F7]
    | [\u2016\u2017\u2020-\u2027\u2030-\u203E\u2041-\u2053\u2055-\u205E\u2190-\u23FF\u2500-\u2775\u2794-\u2BFF]
    | [\u2E00-\u2E7F\u3001-\u3003\u3008-\u3020\u3030]
;
fragment OperatorChar   : OperatorHead | [\u0300-\u036F\u1DC0-\u1DFF\u20D0-\u20FF\uFE00-\uFE0F\uFE20-\uFE2F\u{E0100}-\u{E01EF}];
fragment IdentifierHead:
    [\p{L}\p{Nl}_$]
    | [\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA\u00BC-\u00BE]
    | [\u2070-\u218F\u2460-\u24FF\u2776-\u2793\u2C00-\u2DFF\u2E80-\u2FFF\u3004-\u3007\u3021-\u302F\u3031-\u303F]
    | [\u{1F000}-\u{1FAFF}]
;
fragment IdentifierChar : IdentifierHead | [\p{Nd}\p{Mn}\p{Mc}\u200D\uFE0F\u20E3];
