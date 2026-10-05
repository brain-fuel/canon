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


// The canonically commented dialect of the Scala lexer canon reads Scala with, in which /** comments
// are canonical comments. Every change from the plain lexer is marked canon: and listed in
// grammars/scala/README.md.
//
// The plain lexer is the Scala lexer canon reads Scala with. It is written for canon, from the lexical syntax of the
// Scala 3 reference (https://docs.scala-lang.org/scala3/reference/syntax.html), checked against the
// Scala 3 compiler's scanner (dotty.tools.dotc.parsing.Scanners, Apache-2.0), and covers what
// extraction needs: every token kind of Scala 3 and Scala 2 source, so that comments, strings,
// interpolations, characters, symbols, backquoted names, and XML literals never hide or fake code,
// and the keywords and brackets the parser's structure rests on.
//
// Optional braces are not lexical, so the ScalaLexerBase hook inserts INDENT, OUTDENT, and NEWLINE
// tokens where the compiler's scanner does. See grammars/scala/README.md.

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
// canon: /** opens a Scaladoc comment on the default channel, tokenized in the DocBlock mode; it
// comes before OP, which would otherwise take /** by rule order. /**/ and /*** stay plain comments,
// and a comment nested in a plain one is part of it. The hook holds a Scaladoc comment's tokens
// until the next code token has produced its layout tokens.
DOC_OPEN      : '/**' -> pushMode(DocBlock);
BLOCK_COMMENT : '/*' ('*'+ '/' | '**' NestedCommentRest | ~'*' NestedCommentRest) -> channel(HIDDEN);
LINE_COMMENT  : '//' ~[\r\n]*                   -> channel(HIDDEN);
WHITESPACE    : [ \t\r\n\f]+                    -> channel(HIDDEN);

// Regular keywords. true, false, null, forSome, and macro are names to the parser.
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

// An interpolated string is read in a mode of its own, as the compiler's scanner reads it in a
// region of its own: its text, $$ and $" escapes, and $name holes are tokens of the string, and a
// ${ hole holds Scala code up to its closing brace, in which strings and braces nest as anywhere.
INTERPOLATION_START           : AlphaId '"' -> pushMode(Interpolation);
INTERPOLATION_MULTILINE_START : AlphaId '"""' -> type(INTERPOLATION_START), pushMode(MultilineInterpolation);

// A dedented string, which the Scala 3 compiler reads under language.experimental.dedentedStringLiterals:
// three or more single quotes and a line break open it, and the same quotes at the start of a later
// line close it; a name before it interpolates it. It is one token, holes and all.
DEDENTED_STRING:
    AlphaId? '\'\'\'\'\'' ~[\r\n]* '\r'? '\n' .*? '\n' [ \t]* '\'\'\'\'\''
    | AlphaId? '\'\'\'\'' (~['\r\n] ~[\r\n]*)? '\r'? '\n' .*? '\n' [ \t]* '\'\'\'\''
    | AlphaId? '\'\'\'' (~['\r\n] ~[\r\n]*)? '\r'? '\n' .*? '\n' [ \t]* '\'\'\''
;

// A character literal, before symbols, so 'a' is a character and 'a a Scala 2 symbol literal or a
// quoted name.
CHARACTER : '\'' (~['\\\r\n] | EscapeSequence) '\'';
SYMBOL    : '\'' AlphaId;
QUOTE     : '\'';

NUMBER:
    (DecimalNumeral | HexNumeral | BinaryNumeral) [lL]?
    | DecimalNumeral? '.' Digits ExponentPart? FloatType?
    | DecimalNumeral ExponentPart FloatType?
    | DecimalNumeral FloatType
;

// Brackets, whose nesting the hook tracks. A brace pushes the default mode and its closing brace
// pops it, so the closing brace of Scala code embedded in an XML literal returns to the XML.
LPAREN : '(';
RPAREN : ')';
LBRACK : '[';
RBRACK : ']';
LBRACE : '{' -> pushMode(DEFAULT_MODE);
RBRACE : '}' -> popMode;

// An XML literal, which Scala 2 and the Scala 3 compiler read: a < starts one when the character
// before it is whitespace or one of { ( > and a name, !, or ? follows it, as the compiler's scanner
// decides. The ScalaLexerBase hook answers the predicate from the character before the <. A start
// tag's attributes, an element's content, and nested elements are read in modes of their own, and
// braces in them embed Scala code.
XML_OPEN    : '<' {this.xmlStart()}? XmlName -> pushMode(XmlTag);
XML_SPECIAL : '<' {this.xmlStart()}? XmlSpecial;

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

// canon: a comment inside a block comment, which nests.
fragment NestedComment     : '/*' NestedCommentRest;
fragment NestedCommentRest : (NestedComment | .)*? '*/';

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
fragment XmlName        : [\p{L}_] [\p{L}\p{Nd}_:.\-]*;
fragment XmlSpecial     : '!--' .*? '-->' | '![CDATA[' .*? ']]>' | '?' .*? '?>';

// A name after $ in an interpolated string, which holds no $, so $a$b is two holes.
fragment InterpolationId : [\p{L}\p{Nl}_] [\p{L}\p{Nl}\p{Nd}_]*;

// An interpolated string's text up to its closing quote, a hole, or the end of the line.
mode Interpolation;

INTERPOLATION_TEXT   : (~["\\$\r\n] | '\\' ~[$\r\n])+;
// A backslash before a $, as in the raw "\$$", is text of its own, so the $ still starts a hole.
INTERPOLATION_BACKSLASH : '\\' -> type(INTERPOLATION_TEXT);
INTERPOLATION_ESCAPE : '$$' | '$"';
INTERPOLATION_ID     : '$' InterpolationId;
INTERPOLATION_BLOCK  : '${' -> type(LBRACE), pushMode(DEFAULT_MODE);
INTERPOLATION_END    : '"' -> popMode;

// A multi-line interpolated string's text up to its closing triple quote, which takes any quotes
// after it. One or two quotes before a hole are text of their own.
mode MultilineInterpolation;

MULTILINE_INTERPOLATION_TEXT   : (~["$] | '"' ~["$] | '""' ~["$])+ -> type(INTERPOLATION_TEXT);
MULTILINE_INTERPOLATION_QUOTES : '"' | '""' -> type(INTERPOLATION_TEXT);
MULTILINE_INTERPOLATION_ESCAPE : ('$$' | '$"') -> type(INTERPOLATION_ESCAPE);
MULTILINE_INTERPOLATION_ID     : '$' InterpolationId -> type(INTERPOLATION_ID);
MULTILINE_INTERPOLATION_BLOCK  : '${' -> type(LBRACE), pushMode(DEFAULT_MODE);
MULTILINE_INTERPOLATION_END    : '"""' '"'* -> type(INTERPOLATION_END), popMode;

// canon: a Scaladoc comment, closed by */; a star that decorates a line is dropped, and a comment
// nested in it, as /* ... */ in an example, is skipped, since Scala comments nest. A tag such as
// @param or @see is a word of the prose.
mode DocBlock;

DOC_CLOSE   : '*/' -> popMode;
DOC_NESTED  : '/*' NestedCommentRest -> skip;
DOC_REF     : 'ref:' DocKey;
DOC_LICENSE : 'license:' DocKey;
DOC_STAR    : '*' -> skip;
DOC_WS      : [ \t\r\n]+ -> skip;
DOC_PUNCT   : [,.;:()!?[\]{}"'`<>=+|/];
DOC_WORD    : ~[ \t\r\n*,.;:()!?[\]{}"'`<>=+|/]+;

fragment DocKey: [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;

// An XML start tag's name, attributes, and end: > begins the element's content, /> ends it.
mode XmlTag;

XML_TAG_WS     : [ \t\r\n]+ -> channel(HIDDEN);
XML_NAME       : XmlName;
XML_EQUALS     : '=';
XML_VALUE      : '"' ~'"'* '"' | '\'' ~'\''* '\'';
XML_TAG_LBRACE : '{' -> type(LBRACE), pushMode(DEFAULT_MODE);
XML_TAG_END    : '>' -> mode(XmlContent);
XML_EMPTY_END  : '/>' -> popMode;

// An XML element's content up to its end tag: text, nested elements, comments, character data, and
// Scala code in braces.
mode XmlContent;

XML_END_TAG         : '</' XmlName? [ \t\r\n]* '>' -> popMode;
XML_CONTENT_OPEN    : '<' XmlName -> type(XML_OPEN), pushMode(XmlTag);
XML_CONTENT_SPECIAL : '<' XmlSpecial -> type(XML_SPECIAL);
XML_TEXT            : ('{{' | '}}' | ~[<{])+;
XML_CONTENT_LBRACE  : '{' -> type(LBRACE), pushMode(DEFAULT_MODE);
