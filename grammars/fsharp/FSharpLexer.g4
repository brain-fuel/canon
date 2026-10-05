// The F# lexer canon reads F# with. It is written for canon, because grammars-v4 has no F# grammar,
// and it covers what extraction needs: every token kind of F# source, so that comments, strings,
// and characters never hide or fake code, and the brackets and keywords the parser's structure
// rests on. Expressions and types are left as runs of tokens for the parser to skip.
//
// The offside rule is not lexical, so the FSharpLexerBase hook turns indentation into INDENT,
// DEDENT, and NEWLINE tokens outside brackets and BRNL tokens inside them, and reads the first
// branch of each #if that some set of defined symbols compiles. See grammars/fsharp/README.md.
//
// MIT License, as canon.

lexer grammar FSharpLexer;

options {
    superClass = FSharpLexerBase;
}

// Tokens the FSharpLexerBase hook emits; no lexer rule matches them.
tokens {
    INDENT,
    DEDENT,
    NEWLINE,
    BRNL
}

BYTE_ORDER_MARK: '﻿' -> channel(HIDDEN);

// Comments. A block comment nests, and (*) is the multiplication operator, not a comment.
BLOCK_COMMENT : '(*' (~')' (BLOCK_COMMENT | .)*?)? '*)' -> channel(HIDDEN);
LINE_COMMENT  : '//' ~[\r\n]*                         -> channel(HIDDEN);
WHITESPACE    : [ \t\r\n\u000C]+                      -> channel(HIDDEN);

// Directives at the start of a line, the whole line each; the hook reads #if, #else, and #endif.
IF_DIRECTIVE    : '#if' [ \t] ~[\r\n]*   -> channel(HIDDEN);
ELSE_DIRECTIVE  : '#else' ~[\r\n]*       -> channel(HIDDEN);
ENDIF_DIRECTIVE : '#endif' ~[\r\n]*      -> channel(HIDDEN);
OTHER_DIRECTIVE:
    '#' ('nowarn' | 'warnon' | 'load' | 'r' | 'I' | 'light' | 'line' | 'time' | 'indent' | 'help' | 'quit' | 'q' | '!') (
        [ \t] ~[\r\n]*
        | [\r\n]
    ) -> channel(HIDDEN)
;

// Keywords the parser's structure rests on.
ABSTRACT  : 'abstract';
AND       : 'and';
AS        : 'as';
BEGIN     : 'begin';
CLASS     : 'class';
DEFAULT   : 'default';
DELEGATE  : 'delegate';
DO        : 'do';
END       : 'end';
EXCEPTION : 'exception';
EXTERN    : 'extern';
GLOBAL    : 'global';
INHERIT   : 'inherit';
INLINE    : 'inline';
INTERFACE : 'interface';
INTERNAL  : 'internal';
LET       : 'let';
MEMBER    : 'member';
MODULE    : 'module';
MUTABLE   : 'mutable';
NAMESPACE : 'namespace';
NEW       : 'new';
OF        : 'of';
OPEN      : 'open';
OVERRIDE  : 'override';
PRIVATE   : 'private';
PUBLIC    : 'public';
REC       : 'rec';
STATIC    : 'static';
STRUCT    : 'struct';
TYPE      : 'type';
VAL       : 'val';
WITH      : 'with';

// A keyword with a bang is one token, as let! is.
BANG_KEYWORD: ('let' | 'use' | 'do' | 'yield' | 'return' | 'match' | 'and') '!';

// Strings: regular and interpolated strings with escapes, which may span lines; verbatim strings;
// triple-quoted strings, interpolated or not. A byte string ends in B.
STRING:
    '$'? '"' (~["\\] | '\\' .)* '"' 'B'?
    | ('@' | '$@' | '@$') '"' (~'"' | '""')* '"' 'B'?
    | '$'* '"""' .*? '"""'
;

// Characters, before type parameters, so 'a' is a character and 'a a type parameter; ''' is the
// quote character.
CHAR: '\'' (~[\\\r\n] | '\\' ~[\r\n] | '\\' [0-9] [0-9] [0-9] | '\\' [uU] HexDigit+ | '\\' 'x' HexDigit HexDigit) '\'' 'B'?;

TYPE_PARAMETER: '\'' IdentifierStart IdentifierPart*;

NUMBER:
    '0' [xX] [0-9a-fA-F_]+ NumberSuffix?
    | '0' [oO] [0-7_]+ NumberSuffix?
    | '0' [bB] [01_]+ NumberSuffix?
    | [0-9] [0-9_]* ('.' [0-9] [0-9_]*)? ([eE] [+\-]? [0-9]+)? NumberSuffix?
;

// Brackets, whose nesting the hook tracks.
LATTR      : '[<';
RATTR      : '>]';
LBRACKBAR  : '[|';
BARRBRACK  : '|]';
LBRACEBAR  : '{|';
BARRBRACE  : '|}';
LPAREN     : '(';
RPAREN     : ')';
LBRACK     : '[';
RBRACK     : ']';
LBRACE     : '{';
RBRACE     : '}';

// Punctuation the parser's structure rests on, then every other operator as one token.
MULTIPLY_NAME : '(*)';
EQUALS        : '=';
BAR           : '|';
COLON         : ':';
SEMI          : ';';
COMMA         : ',';
DOT           : '.';
LESS          : '<';
GREATER       : '>';
STAR          : '*';
HASH          : '#';
BACKTICK_IDENTIFIER: '``' (~'`' | '`' ~'`')+ '``';
IDENTIFIER          : IdentifierStart IdentifierPart*;
SYMBOLIC_OPERATOR   : [!%&*+\-./=?@^|~:$] [!%&*+\-./<=>?@^|~:$]*;

fragment IdentifierStart : [\p{L}_];
fragment IdentifierPart  : [\p{L}\p{N}_'];
fragment HexDigit        : [0-9a-fA-F];
fragment NumberSuffix    : [a-zA-Z] [a-zA-Z0-9]*;
