/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 by Bart Kiers (original author) and Alexandre Vitorelli (contributor -> ported to CSharp)
 * Copyright (c) 2017 by Ivan Kochurkin (Positive Technologies):
    added ECMAScript 6 support, cleared and transformed to the universal grammar.
 * Copyright (c) 2018 by Juan Alvarez (contributor -> ported to Go)
 * Copyright (c) 2019 by Andrii Artiushok (contributor -> added TypeScript support)
 * Copyright (c) 2024 by Andrew Leppard (www.wegrok.review)
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

// $antlr-format alignTrailingComments true, columnLimit 150, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine true, allowShortBlocksOnASingleLine true, minEmptyLines 0, alignSemicolons ownLine
// $antlr-format alignColons trailing, singleLineOverrulesHangingColon true, alignLexerCommands true, alignLabels true, alignTrailers true

lexer grammar TypeScriptLexer;

channels {
    ERROR
}

// canon: the quotes and the name of an ambient module, as in declare module 'foo', which the
// AfterModule mode reads so the module is named without its quotes.
tokens {
    MODULE_QUOTE,
    MODULE_NAME
}

options {
    superClass = TypeScriptLexerBase;
}

// canon: in the canonically commented dialect a JSDoc or TSDoc comment is a canonical comment on the
// default channel, tokenized in a mode of its own into prose, ref:KEY, and license:KEY. /** opens one;
// /**/ and /*** stay plain comments by the longest match, a plain comment not starting with two
// stars. The first /** of a file, before any code, opens FILE_DOC_OPEN instead, in a mode that also
// tells the file tags apart and marks a blank line after the comment, so the parser can tell a
// file's Why from the Why of the declaration below it.
// canon: a hashbang line, which only the first line of a file may hold, as in the JavaScript grammar.
HashBangLine      : {this.IsStartOfFile()}? '#!' ~[\r\n\u2028\u2029]*;
FILE_DOC_OPEN     : {this.IsStartOfFile()}? '/**' -> pushMode(FileDocBlock);
DOC_BLOCK_OPEN    : '/**' -> pushMode(DocBlock);
MultiLineComment  : '/*' (~'*' .*? | '**' .*? | '*')? '*/' -> channel(HIDDEN);
SingleLineComment : '//' ~[\r\n\u2028\u2029]* -> channel(HIDDEN);
RegularExpressionLiteral:
    '/' RegularExpressionFirstChar RegularExpressionChar* {this.IsRegexPossible()}? '/' IdentifierPart*
;

OpenBracket                : '[';
CloseBracket               : ']';
OpenParen                  : '(';
CloseParen                 : ')';
OpenBrace                  : '{' {this.ProcessOpenBrace();};
TemplateCloseBrace         :     {this.IsInTemplateString()}? '}' -> popMode;
CloseBrace                 : '}' {this.ProcessCloseBrace();};
SemiColon                  : ';';
Comma                      : ',';
Assign                     : '=';
QuestionMark               : '?';
QuestionMarkDot            : '?.';
Colon                      : ':';
Ellipsis                   : '...';
Dot                        : '.';
PlusPlus                   : '++';
MinusMinus                 : '--';
Plus                       : '+';
Minus                      : '-';
BitNot                     : '~';
Not                        : '!';
Multiply                   : '*';
Divide                     : '/';
Modulus                    : '%';
Power                      : '**';
NullCoalesce               : '??';
Hashtag                    : '#';
LeftShiftArithmetic        : '<<';
// We can't match these in the lexer because it would cause issues when parsing
// types like Map<string, Map<string, string>>
// RightShiftArithmetic       : '>>';
// RightShiftLogical          : '>>>';
LessThan                   : '<';
MoreThan                   : '>';
LessThanEquals             : '<=';
GreaterThanEquals          : '>=';
Equals_                    : '==';
NotEquals                  : '!=';
IdentityEquals             : '===';
IdentityNotEquals          : '!==';
BitAnd                     : '&';
BitXOr                     : '^';
BitOr                      : '|';
And                        : '&&';
Or                         : '||';
MultiplyAssign             : '*=';
DivideAssign               : '/=';
ModulusAssign              : '%=';
PlusAssign                 : '+=';
MinusAssign                : '-=';
LeftShiftArithmeticAssign  : '<<=';
RightShiftArithmeticAssign : '>>=';
RightShiftLogicalAssign    : '>>>=';
BitAndAssign               : '&=';
BitXorAssign               : '^=';
BitOrAssign                : '|=';
PowerAssign                : '**=';
NullishCoalescingAssign    : '??=';
OrAssign                   : '||='; // canon
AndAssign                  : '&&='; // canon
ARROW                      : '=>';

/// Null Literals

NullLiteral: 'null';

/// Boolean Literals

BooleanLiteral: 'true' | 'false';

/// Numeric Literals

DecimalLiteral:
    DecimalIntegerLiteral '.' [0-9] [0-9_]* ExponentPart?
    | '.' [0-9] [0-9_]* ExponentPart?
    | DecimalIntegerLiteral ExponentPart?
;

/// Numeric Literals

HexIntegerLiteral    : '0' [xX] [0-9a-fA-F] HexDigit*;
OctalIntegerLiteral  : '0' [0-7]+ {!this.IsStrictMode()}?;
OctalIntegerLiteral2 : '0' [oO] [0-7] [_0-7]*;
BinaryIntegerLiteral : '0' [bB] [01] [_01]*;

BigHexIntegerLiteral     : '0' [xX] [0-9a-fA-F] HexDigit* 'n';
BigOctalIntegerLiteral   : '0' [oO] [0-7] [_0-7]* 'n';
BigBinaryIntegerLiteral  : '0' [bB] [01] [_01]* 'n';
BigDecimalIntegerLiteral : DecimalIntegerLiteral 'n';

/// Keywords

Break      : 'break';
Do         : 'do';
Instanceof : 'instanceof';
Typeof     : 'typeof';
Case       : 'case';
Else       : 'else';
New        : 'new';
Var        : 'var';
Catch      : 'catch';
Finally    : 'finally';
Return     : 'return';
Void       : 'void';
Continue   : 'continue';
For        : 'for';
Switch     : 'switch';
While      : 'while';
Debugger   : 'debugger';
Function_  : 'function';
This       : 'this';
With       : 'with';
Default    : 'default';
If         : 'if';
Throw      : 'throw';
Delete     : 'delete';
In         : 'in';
Try        : 'try';
As         : 'as';
From       : 'from';
ReadOnly   : 'readonly';
Async      : 'async';
Await      : 'await';
Yield      : 'yield';
YieldStar  : 'yield*';

/// Future Reserved Words

Class   : 'class';
Enum    : 'enum';
Extends : 'extends';
Super   : 'super';
Const   : 'const';
Export  : 'export';
Import  : 'import';

/// The following tokens are also considered to be FutureReservedWords
/// when parsing strict mode

Implements : 'implements';
Let        : 'let';
Private    : 'private';
Public     : 'public';
Interface  : 'interface';
Package    : 'package';
Protected  : 'protected';
Static     : 'static';

//keywords:
Any        : 'any';
Number     : 'number';
Never      : 'never';
Boolean    : 'boolean';
String     : 'string';
Unique     : 'unique';
Symbol     : 'symbol';
Undefined  : 'undefined';
Object     : 'object';

Of      : 'of';
KeyOf   : 'keyof';
Infer   : 'infer'; // canon

TypeAlias: 'type';

Constructor : 'constructor';
Namespace   : 'namespace';
Require     : 'require';
Module      : 'module' -> pushMode(AfterModule); // canon: a quoted name may follow
Declare     : 'declare';

Abstract: 'abstract';

Is: 'is';

//
// Ext.2 Additions to 1.8: Decorators
//
At: '@';

/// Identifier Names and Identifiers

Identifier: IdentifierStart IdentifierPart*;

/// String Literals
StringLiteral:
    ('"' DoubleStringCharacter* '"' | '\'' SingleStringCharacter* '\'') {this.ProcessStringLiteral();}
;

BackTick: '`' {this.IncreaseTemplateDepth();} -> pushMode(TEMPLATE);

WhiteSpaces: [\t\u000B\u000C\u0020\u00A0]+ -> channel(HIDDEN);

LineTerminator: [\r\n\u2028\u2029] -> channel(HIDDEN);

/// Comments

HtmlComment         : '<!--' .*? '-->'      -> channel(HIDDEN);
CDataComment        : '<![CDATA[' .*? ']]>' -> channel(HIDDEN);
UnexpectedCharacter : .                     -> channel(ERROR);

mode TEMPLATE;

TemplateStringEscapeAtom      : '\\' .;
BackTickInside                : '`'  {this.DecreaseTemplateDepth();} -> type(BackTick), popMode;
TemplateStringStartExpression : '${' {this.StartTemplateString();} -> pushMode(DEFAULT_MODE);
TemplateStringAtom            : ~[`\\];

// Fragment rules

fragment DoubleStringCharacter: ~["\\\r\n] | '\\' EscapeSequence | LineContinuation;

fragment SingleStringCharacter: ~['\\\r\n] | '\\' EscapeSequence | LineContinuation;

fragment EscapeSequence:
    CharacterEscapeSequence
    | '0' // no digit ahead! TODO
    | HexEscapeSequence
    | UnicodeEscapeSequence
    | ExtendedUnicodeEscapeSequence
;

fragment CharacterEscapeSequence: SingleEscapeCharacter | NonEscapeCharacter;

fragment HexEscapeSequence: 'x' HexDigit HexDigit;

fragment UnicodeEscapeSequence:
    'u' HexDigit HexDigit HexDigit HexDigit
    | 'u' '{' HexDigit HexDigit+ '}'
;

fragment ExtendedUnicodeEscapeSequence: 'u' '{' HexDigit+ '}';

fragment SingleEscapeCharacter: ['"\\bfnrtv];

fragment NonEscapeCharacter: ~['"\\bfnrtv0-9xu\r\n];

fragment EscapeCharacter: SingleEscapeCharacter | [0-9] | [xu];

fragment LineContinuation: '\\' [\r\n\u2028\u2029]+;

fragment HexDigit: [_0-9a-fA-F];

fragment DecimalIntegerLiteral: '0' | [1-9] [0-9_]*;

fragment ExponentPart: [eE] [+-]? [0-9_]+;

// canon: the connector punctuation other than _, which IdentifierStart already matches, so an
// identifier with many underscores has one match rather than two per underscore.
fragment IdentifierPart: IdentifierStart | [\p{Mn}] | [\p{Nd}] | [\u203F\u2040\u2054\uFE33\uFE34\uFE4D-\uFE4F\uFF3F] | '\u200C' | '\u200D';

fragment IdentifierStart: [\p{L}] | [$_] | '\\' UnicodeEscapeSequence;

fragment RegularExpressionFirstChar:
    ~[*\r\n\u2028\u2029\\/[]
    | RegularExpressionBackslashSequence
    | '[' RegularExpressionClassChar* ']'
;

fragment RegularExpressionChar:
    ~[\r\n\u2028\u2029\\/[]
    | RegularExpressionBackslashSequence
    | '[' RegularExpressionClassChar* ']'
;

fragment RegularExpressionClassChar: ~[\r\n\u2028\u2029\]\\] | RegularExpressionBackslashSequence;

fragment RegularExpressionBackslashSequence: '\\' ~[\r\n\u2028\u2029];

// canon: a JSDoc or TSDoc block, closed by */; a star that decorates a line is dropped, and a block
// tag such as @param or @returns is a word like any other.
mode DocBlock;

DOC_BLOCK_CLOSE   : '*/' -> popMode;
DOC_REF           : 'ref:' DocKey;
DOC_LICENSE       : 'license:' DocKey;
DOC_BLOCK_STAR    : '*' -> skip;
DOC_BLOCK_WS      : [ \t\r\n\u000B\u000C\u00A0\u2028\u2029]+ -> skip;
DOC_PUNCT         : [,.;:()!?[\]{}"'`<>=+|/];
DOC_WORD          : ~[ \t\r\n\u000B\u000C\u00A0\u2028\u2029*,.;:()!?[\]{}"'`<>=+|/]+;

// canon: the first /** of a file. @file, @fileoverview, @overview, @module, @license, and TSDoc's
// @packageDocumentation are DOC_FILE_TAG, which says the comment documents the file; its close is
// followed by FileDocAfter, which marks a blank line below the comment with DOC_BLANK_LINE.
mode FileDocBlock;

FILE_DOC_CLOSE    : '*/' -> type(DOC_BLOCK_CLOSE), mode(FileDocAfter);
FILE_DOC_REF      : 'ref:' DocKey -> type(DOC_REF);
FILE_DOC_LICENSE  : 'license:' DocKey -> type(DOC_LICENSE);
DOC_FILE_TAG      : '@file' | '@fileoverview' | '@overview' | '@module' | '@license' | '@packageDocumentation';
FILE_DOC_STAR     : '*' -> skip;
FILE_DOC_WS       : [ \t\r\n\u000B\u000C\u00A0\u2028\u2029]+ -> skip;
FILE_DOC_PUNCT    : [,.;:()!?[\]{}"'`<>=+|/] -> type(DOC_PUNCT);
FILE_DOC_WORD     : ~[ \t\r\n\u000B\u000C\u00A0\u2028\u2029*,.;:()!?[\]{}"'`<>=+|/]+ -> type(DOC_WORD);

// canon: what follows the first /** of a file: a blank line, or anything else, which is left to the
// default mode.
mode FileDocAfter;

DOC_BLANK_LINE    : [ \t\u000B\u000C\u00A0]* DocLineEnd [ \t\u000B\u000C\u00A0]* DocLineEnd -> popMode;
FILE_DOC_AFTER    : -> popMode, skip;

fragment DocLineEnd : '\r'? '\n' | '\r' | [\u2028\u2029];
fragment DocKey     : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;

// canon: what follows the module keyword: a quoted name, read as MODULE_QUOTE, MODULE_NAME, and
// MODULE_QUOTE, or anything else, which is left to the default mode.
mode AfterModule;

MODULE_WS         : [ \t]+ -> channel(HIDDEN);
MODULE_OPEN       : ['"] -> type(MODULE_QUOTE), mode(ModuleName);
MODULE_OTHER      : -> popMode, skip;

mode ModuleName;

MODULE_TEXT       : ~['"\r\n]+ -> type(MODULE_NAME);
MODULE_CLOSE      : ['"] -> type(MODULE_QUOTE), popMode;
