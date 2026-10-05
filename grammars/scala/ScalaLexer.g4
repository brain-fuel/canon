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

// The Scala lexer canon reads Scala with. It is written for canon, from the lexical syntax of the
// Scala 3 reference (https://docs.scala-lang.org/scala3/reference/syntax.html), and covers what
// extraction needs: every token kind of Scala source, so that comments, strings, interpolations,
// characters, and backquoted names never hide or fake code, and the keywords and brackets the
// parser's structure rests on.
//
// Optional braces are not lexical, so the ScalaLexerBase hook turns indentation into INDENT,
// OUTDENT, and NEWLINE tokens where the reference's Optional Braces section inserts them. See
// grammars/scala/README.md.

lexer grammar ScalaLexer;

options {
    superClass = ScalaLexerBase;
}

// Tokens the ScalaLexerBase hook emits; no lexer rule matches them.
tokens {
    INDENT,
    OUTDENT,
    NEWLINE
}

BYTE_ORDER_MARK: '\uFEFF' -> channel(HIDDEN);

// Comments. A block comment nests.
BLOCK_COMMENT : '/*' (BLOCK_COMMENT | .)*? '*/' -> channel(HIDDEN);
LINE_COMMENT  : '//' ~[\r\n]*                   -> channel(HIDDEN);
WHITESPACE    : [ \t\r\n\f]+                    -> channel(HIDDEN);

// Regular keywords. true, false, and null are literals the parser reads as names.
ABSTRACT  : 'abstract';
CASE      : 'case';
CATCH     : 'catch';
CLASS     : 'class';
DEF       : 'def';
DO        : 'do';
ELSE      : 'else';
ENUM      : 'enum';
EXPORT    : 'export';
EXTENDS   : 'extends';
FINAL     : 'final';
FINALLY   : 'finally';
FOR       : 'for';
GIVEN     : 'given';
IF        : 'if';
IMPLICIT  : 'implicit';
IMPORT    : 'import';
LAZY      : 'lazy';
MATCH     : 'match';
NEW       : 'new';
OBJECT    : 'object';
OVERRIDE  : 'override';
PACKAGE   : 'package';
PRIVATE   : 'private';
PROTECTED : 'protected';
RETURN    : 'return';
SEALED    : 'sealed';
SUPER     : 'super';
THEN      : 'then';
THROW     : 'throw';
THIS      : 'this';
TRAIT     : 'trait';
TRY       : 'try';
TYPE      : 'type';
VAL       : 'val';
VAR       : 'var';
WHILE     : 'while';
WITH      : 'with';
YIELD     : 'yield';

// Soft keywords, which are names everywhere the parser does not read them as keywords.
AS          : 'as';
DERIVES     : 'derives';
END         : 'end';
EXTENSION   : 'extension';
INFIX       : 'infix';
INLINE      : 'inline';
OPAQUE      : 'opaque';
OPEN        : 'open';
TRANSPARENT : 'transparent';
USING       : 'using';

// Strings. A plain string holds escapes and no line break; a multi-line string runs to the first
// """ and takes any quotes after it, as """a"""" ends in a quote.
STRING           : '"' (~["\\\r\n] | '\\' .)* '"';
MULTILINE_STRING : '"""' .*? '"""' '"'*;

// An interpolated string is one token, holes and all: $$ and $" are escapes, $name a hole, and ${
// opens a block whose braces and strings nest. Each loop takes one character per step, so lexing
// stays linear.
INTERPOLATED_STRING           : AlphaId '"' (~["\\$\r\n] | '\\' . | '$' ~'{' | '$' '{' InterpolationBlock '}')* '"';
INTERPOLATED_MULTILINE_STRING : AlphaId '"""' (~'$' | '$' ~'{' | '$' '{' InterpolationBlock '}')*? '"""' '"'*;

// A character literal, before symbols, so 'a' is a character and 'a a symbol or a quoted name.
CHARACTER : '\'' (~['\\\r\n] | EscapeSequence) '\'';
SYMBOL    : '\'' AlphaId;
QUOTE     : '\'';

NUMBER:
    (DecimalNumeral | HexNumeral | BinaryNumeral) [lL]?
    | DecimalNumeral? '.' Digits ExponentPart? FloatType?
    | DecimalNumeral ExponentPart FloatType?
    | DecimalNumeral FloatType
;

// Brackets, whose nesting the hook tracks.
LPAREN : '(';
RPAREN : ')';
LBRACK : '[';
RBRACK : ']';
LBRACE : '{';
RBRACE : '}';

// Delimiters and reserved symbols, before operators, so a lone = is EQUALS and == an operator.
DOT           : '.';
COMMA         : ',';
SEMI          : ';';
COLON         : ':';
EQUALS        : '=';
FAT_ARROW     : '=>' | '\u21D2';
CONTEXT_ARROW : '?=>';
LEFT_ARROW    : '<-' | '\u2190';
SUBTYPE       : '<:';
SUPERTYPE     : '>:';
HASH          : '#';
AT            : '@';

BACKQUOTED_ID : '`' (~[`\\\r\n] | '\\' .)+ '`';
ID            : AlphaId;
OP            : OpChar+;

fragment AlphaId        : IdStart IdPart* ('_' OpChar+)?;
fragment IdStart        : [\p{L}\p{Nl}$_];
fragment IdPart         : [\p{L}\p{Nl}\p{Nd}$_];
fragment OpChar         : [!#%&*+\-/:<=>?@\\^|~] | [\p{Sm}\p{So}];
fragment EscapeSequence : '\\' ('u'+ HexDigit HexDigit HexDigit HexDigit | [btnfr"'\\] | [0-7] [0-7]? [0-7]?);
fragment HexDigit       : [0-9a-fA-F];
fragment Digits         : [0-9] ([0-9_]* [0-9])?;
fragment DecimalNumeral : Digits;
fragment HexNumeral     : '0' [xX] HexDigit ([0-9a-fA-F_]* HexDigit)?;
fragment BinaryNumeral  : '0' [bB] [01] ([01_]* [01])?;
fragment ExponentPart   : [eE] [+\-]? Digits;
fragment FloatType      : [fFdD];

// The code in a ${ } hole: braces nest, and a string inside it may hold a closing brace.
fragment InterpolationBlock : (~[{}"] | '{' InterpolationBlock '}' | '"' (~["\\\r\n] | '\\' .)* '"')*;
