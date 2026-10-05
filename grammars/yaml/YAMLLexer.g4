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

// A lexer for the block structure of YAML 1.2, written for canon from the YAML specification. It
// reads mappings, sequences, plain, quoted, and block scalars, flow collections, anchors, aliases,
// tags, and comments, which go to the hidden channel. The YAMLLexerBase hook turns indentation
// into INDENT, DEDENT, and NEWLINE tokens and decides where each block scalar ends.

lexer grammar YAMLLexer;

options {
    superClass = YAMLLexerBase;
}

tokens {
    INDENT,
    DEDENT,
    NEWLINE
}

/** A comment. A hash starts a comment only at the start of a token, since a plain scalar keeps a hash that follows a character other than a space. */
COMMENT : '#' ~[\r\n]* -> channel(HIDDEN);

/** A line break, which the hook reads as layout, so the parser never sees it. */
LINE_BREAK : '\r'? '\n' -> skip;

/** Spaces and tabs between tokens. */
WS : [ \t]+ -> skip;

/** The marker that starts a document. */
DOCUMENT_START : '---';

/** The marker that ends a document. */
DOCUMENT_END : '...';

/** A directive such as %YAML, from the percent sign to the end of the line. */
DIRECTIVE : '%' ~[\r\n]*;

/** The indicator of a block sequence entry, a dash followed by a space or a line break; a dash followed by anything else starts a plain scalar, which is longer. */
DASH : '-';

/** The indicator of a complex mapping key. */
QUESTION : '?';

/** The colon between a mapping key and its value; a colon followed by anything but a space or a line break stays inside a plain scalar, which is longer. */
COLON : ':';

/** Opens a flow sequence, whose contents are tokenized in the Flow mode. */
FLOW_SEQ_OPEN : '[' -> pushMode(Flow);

/** Opens a flow mapping, whose contents are tokenized in the Flow mode. */
FLOW_MAP_OPEN : '{' -> pushMode(Flow);

/** An anchor that names a node. */
ANCHOR : '&' ~[ \t\r\n,[\]{}]+;

/** An alias that refers to an anchored node. */
ALIAS : '*' ~[ \t\r\n,[\]{}]+;

/** A tag that gives a node its type. */
TAG : '!' ~[ \t\r\n,[\]{}]*;

/** A double-quoted scalar, which may span lines. */
DOUBLE_QUOTED : '"' ('\\' . | ~["\\])* '"';

/** A single-quoted scalar, in which two quotes stand for one. */
SINGLE_QUOTED : '\'' ('\'\'' | ~['])* '\'';

/** The header of a literal or folded block scalar, with its chomping and indentation indicators and any comment after it. The hook records the indentation the scalar's lines must exceed, which is that of the key or the sequence entry on the header's line. */
BLOCK_SCALAR : [|>] [-+0-9]* ([ \t]+ ('#' ~[\r\n]*)?)? { this.blockScalarStart(); } -> pushMode(BlockScalar);

/** A plain scalar in block context: it may hold spaces, colons not followed by a space, and hashes not preceded by one, and it cannot start with an indicator unless a dash, question mark, or colon is followed by a character other than a space. */
PLAIN : PlainFirst (PlainInner | [ \t]+ PlainAfterSpace)*;

fragment PlainFirst : ~[-?:,[\]{}#&*!|>'"%@` \t\r\n] | [-?:] ~[ \t\r\n];

fragment PlainInner : ~[: \t\r\n] | ':' ~[ \t\r\n];

fragment PlainAfterSpace : ~[:# \t\r\n] | ':' ~[ \t\r\n];

mode Flow;

/** Opens a nested flow sequence, typed as FLOW_SEQ_OPEN. */
FLOW_NESTED_SEQ_OPEN : '[' -> pushMode(Flow), type(FLOW_SEQ_OPEN);

/** Opens a nested flow mapping, typed as FLOW_MAP_OPEN. */
FLOW_NESTED_MAP_OPEN : '{' -> pushMode(Flow), type(FLOW_MAP_OPEN);

/** Closes a flow sequence and returns to the enclosing mode. */
FLOW_SEQ_CLOSE : ']' -> popMode;

/** Closes a flow mapping and returns to the enclosing mode. */
FLOW_MAP_CLOSE : '}' -> popMode;

/** The separator of flow collection entries. */
COMMA : ',';

/** The colon of a flow mapping entry, typed as COLON. */
FLOW_COLON : ':' -> type(COLON);

/** A comment inside a flow collection, which documents nothing. */
FLOW_COMMENT : '#' ~[\r\n]* -> channel(HIDDEN);

/** Whitespace and line breaks inside a flow collection, which are not layout. */
FLOW_WS : [ \t\r\n]+ -> skip;

/** An anchor inside a flow collection, typed as ANCHOR. */
FLOW_ANCHOR : '&' ~[ \t\r\n,[\]{}]+ -> type(ANCHOR);

/** An alias inside a flow collection, typed as ALIAS. */
FLOW_ALIAS : '*' ~[ \t\r\n,[\]{}]+ -> type(ALIAS);

/** A tag inside a flow collection, typed as TAG. */
FLOW_TAG : '!' ~[ \t\r\n,[\]{}]* -> type(TAG);

/** A double-quoted scalar inside a flow collection, typed as DOUBLE_QUOTED. */
FLOW_DOUBLE_QUOTED : '"' ('\\' . | ~["\\])* '"' -> type(DOUBLE_QUOTED);

/** A single-quoted scalar inside a flow collection, typed as SINGLE_QUOTED. */
FLOW_SINGLE_QUOTED : '\'' ('\'\'' | ~['])* '\'' -> type(SINGLE_QUOTED);

/** A plain scalar inside a flow collection, which cannot hold a comma or a bracket, typed as PLAIN. */
FLOW_PLAIN : FlowPlainFirst (FlowPlainInner | [ \t]+ FlowPlainAfterSpace)* -> type(PLAIN);

fragment FlowPlainFirst : ~[-?:,[\]{}#&*!|>'"%@` \t\r\n] | [-?:] ~[ \t\r\n,[\]{}];

fragment FlowPlainInner : ~[:,[\]{} \t\r\n] | ':' ~[ \t\r\n,[\]{}];

fragment FlowPlainAfterSpace : ~[:#,[\]{} \t\r\n] | ':' ~[ \t\r\n,[\]{}];

mode BlockScalar;

/** The line breaks after a line of a block scalar and the indentation of the next line that is not blank. The hook leaves the mode when that indentation does not exceed the scalar's. */
BLOCK_SCALAR_BREAK : ('\r'? '\n' [ \t]*)+ { this.blockScalarBreak(); } -> channel(HIDDEN);

/** The text of one line of a block scalar. */
BLOCK_SCALAR_TEXT : ~[\r\n]+;
