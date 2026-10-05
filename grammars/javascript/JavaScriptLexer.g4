/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 by Bart Kiers (original author) and Alexandre Vitorelli (contributor -> ported to CSharp)
 * Copyright (c) 2017-2020 by Ivan Kochurkin (Positive Technologies):
    added ECMAScript 6 support, cleared and transformed to the universal grammar.
 * Copyright (c) 2018 by Juan Alvarez (contributor -> ported to Go)
 * Copyright (c) 2019 by Student Main (contributor -> ES2020)
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

lexer grammar JavaScriptLexer;

channels {
    ERROR
}

options {
    superClass = JavaScriptLexerBase;
}

// Insert here @header for C++ lexer.

HashBangLine      :                           { this.IsStartOfFile()}? '#!' ~[\r\n\u2028\u2029]*; // only allowed at start
MultiLineComment  : '/*' .*? '*/'             -> channel(HIDDEN);
SingleLineComment : '//' ~[\r\n\u2028\u2029]* -> channel(HIDDEN);
RegularExpressionLiteral:
    '/' RegularExpressionFirstChar RegularExpressionChar* {this.IsRegexPossible()}? '/' IdentifierPart*
;

OpenBracket                : '[';
CloseBracket               : ']';
OpenParen                  : '(';
CloseParen                 : ')';
OpenBrace                  : '{' {this.ProcessOpenBrace();};
// canon: the brace that closes a JSX expression container, as {x} in <a href={x}>, which returns to
// the JSX mode the container opened from; the hook tracks the containers as it tracks templates.
JsxExpressionClose         : {this.IsJsxExpressionClose()}? '}' {this.ProcessJsxCloseBrace();} -> popMode;
TemplateCloseBrace         :     {this.IsInTemplateString()}? '}' // Break lines here to ensure proper transformation by Go/transformGrammar.py
                                                                  {this.ProcessTemplateCloseBrace();} -> popMode;
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
RightShiftArithmetic       : '>>';
LeftShiftArithmetic        : '<<';
RightShiftLogical          : '>>>';
// canon: a < where an expression may start opens a JSX tag when the lexer reads JSX, as JavaScript's
// always does and TypeScript's does in a .tsx file; the hook decides from the token before it, as
// TypeScript's scanner does, so a < after an operand is still less-than.
JsxTagOpen                 : {this.IsJsxPossible()}? '<' -> pushMode(JSX_TAG);
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
OrAssign                   : '||='; // canon: logical assignment, ES2021
AndAssign                  : '&&='; // canon: logical assignment, ES2021
ARROW                      : '=>';

/// Null Literals

NullLiteral: 'null';

/// Boolean Literals

BooleanLiteral: 'true' | 'false';

/// Numeric Literals

DecimalLiteral:
    DecimalIntegerLiteral '.' ([0-9] [0-9_]*)? ExponentPart? // canon: 1. with no fraction digits
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
Of         : 'of';
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

Async : 'async';
Await : 'await';

/// The following tokens are also considered to be FutureReservedWords
/// when parsing strict mode

Implements   : 'implements' {this.IsStrictMode()}?;
StrictLet    : 'let'        {this.IsStrictMode()}?;
NonStrictLet : 'let'        {!this.IsStrictMode()}?;
Private      : 'private'    {this.IsStrictMode()}?;
Public       : 'public'     {this.IsStrictMode()}?;
Interface    : 'interface'  {this.IsStrictMode()}?;
Package      : 'package'    {this.IsStrictMode()}?;
Protected    : 'protected'  {this.IsStrictMode()}?;
Static       : 'static'     {this.IsStrictMode()}?;

/// Identifier Names and Identifiers

Identifier: IdentifierStart IdentifierPart*;
/// String Literals
StringLiteral:
    ('"' DoubleStringCharacter* '"' | '\'' SingleStringCharacter* '\'') {this.ProcessStringLiteral();}
;

BackTick: '`' -> pushMode(TEMPLATE);

WhiteSpaces: [\t\u000B\u000C\u0020\u00A0]+ -> channel(HIDDEN);

LineTerminator: [\r\n\u2028\u2029] -> channel(HIDDEN);

/// Comments

HtmlComment         : '<!--' .*? '-->'      -> channel(HIDDEN);
CDataComment        : '<![CDATA[' .*? ']]>' -> channel(HIDDEN);
UnexpectedCharacter : .                     -> channel(ERROR);

// canon: a JSX tag: its name, namespaced as a:b or a member as A.B, its attributes, strings
// without escapes, expression containers, and comments; > opens its children and /> ends it.
mode JSX_TAG;

JsxTagClose                : '>' -> mode(JSX_CHILDREN);
JsxAttributeElementOpen    : {this.IsJsxAttributeValue()}? '<' -> type(JsxTagOpen), pushMode(JSX_TAG); // canon: an element as an attribute's value
JsxSelfClose               : '/>' -> popMode;
JsxName                    : JsxNameStart JsxNamePart*;
JsxColon                   : ':';
JsxDot                     : '.';
JsxAssign                  : '=';
JsxString                  : '"' ~'"'* '"' | '\'' ~'\''* '\'';
JsxExpressionOpen          : '{' {this.ProcessJsxOpenBrace();} -> pushMode(DEFAULT_MODE);
JsxTagWhiteSpace           : [ \t\r\n\u000B\u000C\u00A0\u2028\u2029]+ -> channel(HIDDEN);
JsxTagComment              : '/*' .*? '*/' -> channel(HIDDEN);
JsxTagLineComment          : '//' ~[\r\n\u2028\u2029]* -> channel(HIDDEN);

// canon: the children of a JSX element: text, with entities as written, expression containers,
// nested elements, and the closing tag, which </ opens.
mode JSX_CHILDREN;

JsxText                    : ~[{<]+;
JsxCloseOpen               : '<' [ \t\r\n]* '/' -> mode(JSX_CLOSE);
JsxChildOpen               : '<' -> type(JsxTagOpen), pushMode(JSX_TAG);
JsxChildExpressionOpen     : '{' {this.ProcessJsxOpenBrace();} -> type(JsxExpressionOpen), pushMode(DEFAULT_MODE);

// canon: a JSX closing tag, </a> or the </> of a fragment.
mode JSX_CLOSE;

JsxCloseName               : JsxNameStart JsxNamePart* -> type(JsxName);
JsxCloseColon              : ':' -> type(JsxColon);
JsxCloseDot                : '.' -> type(JsxDot);
JsxCloseEnd                : '>' -> popMode;
JsxCloseWhiteSpace         : [ \t\r\n]+ -> channel(HIDDEN);

mode TEMPLATE;

BackTickInside                : '`' -> type(BackTick), popMode;
TemplateStringStartExpression : '${' {this.ProcessTemplateOpenBrace();} -> pushMode(DEFAULT_MODE);
TemplateStringEscapeAtom      : '\\' . -> type(TemplateStringAtom);
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
// canon: a JSX name is an identifier that may hold hyphens, as aria-label does.
fragment JsxNameStart: IdentifierStart;
fragment JsxNamePart: IdentifierPart | '-';

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