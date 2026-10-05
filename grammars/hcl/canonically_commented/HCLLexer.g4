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

// The canonically commented HCL lexer. It is the plain lexer with every comment tokenized in a
// DocLine or DocBlock mode, so the parser can read a comment as the Why of the block below it. The
// HCLLexerBase hook hides a comment that is not the first thing on its line or that sits inside
// brackets, and hides the line break between a comment and the line directly below it.

lexer grammar HCLLexer;

options {
    superClass = HCLLexerBase;
}

tokens {
    HEREDOC_CLOSE
}

/** Opens a line comment, with a hash or two slashes, which is a canonical comment tokenized in the DocLine mode. Every HCL comment can document the block below it, since HCL has no separate doc comment syntax. ref:DEC-hcl-grammar */
DOC_OPEN : ('#' | '//') -> pushMode(DocLine);

/** Opens a block comment, which is a canonical comment tokenized in the DocBlock mode. ref:DEC-hcl-grammar */
DOC_BLOCK_OPEN : '/*' -> pushMode(DocBlock);

/** A line break, which ends an attribute or a block in a body. The hook hides it inside parentheses, brackets, and template interpolations, where HCL ignores line breaks. ref:DEC-hcl-grammar */
NEWLINE : '\r'? '\n';

/** Spaces and tabs between tokens. */
WS : [ \t\f]+ -> skip;

/** Opens a heredoc template, from the angle brackets to the end of the line; the hook records its delimiter word so that the line holding only that word closes it. ref:DEC-hcl-grammar */
HEREDOC_OPEN : '<<' '-'? IdentifierFragment [ \t]* '\r'? '\n' { this.heredocOpen(); } -> pushMode(Heredoc);

/** Opens a quoted template, whose text and interpolations are tokenized in the Template mode. ref:DEC-hcl-grammar */
TEMPLATE_OPEN : '"' -> pushMode(Template);

/** Opens a block body or an object, and pushes the default mode so that the closing brace of an interpolation can return to its template. ref:DEC-hcl-grammar */
LBRACE : '{' -> pushMode(DEFAULT_MODE);

/** Closes a block body, an object, or an interpolation. ref:DEC-hcl-grammar */
RBRACE : '}' -> popMode;

/** Opens a parenthesized expression or a function call's arguments. */
LPAREN : '(';

/** Closes a parenthesized expression or a function call's arguments. */
RPAREN : ')';

/** Opens a tuple, an index, or a full splat. */
LBRACK : '[';

/** Closes a tuple, an index, or a full splat. */
RBRACK : ']';

/** The arrow between key and value in an object for expression. */
FAT_ARROW : '=>';

/** The equality operator. */
EQUAL_EQUAL : '==';

/** The inequality operator. */
NOT_EQUAL : '!=';

/** The less-or-equal operator. */
LESS_EQUAL : '<=';

/** The greater-or-equal operator. */
GREATER_EQUAL : '>=';

/** The logical and operator. */
AND : '&&';

/** The logical or operator. */
OR : '||';

/** The ellipsis that expands a tuple into function arguments or groups values in an object for expression. */
ELLIPSIS : '...';

/** The separator of a provider-defined function's namespace, as in provider::aws::arn_parse. */
DOUBLE_COLON : '::';

/** The assignment of an attribute or an object element. */
ASSIGN : '=';

/** The less-than operator. */
LESS : '<';

/** The greater-than operator. */
GREATER : '>';

/** The addition operator. */
PLUS : '+';

/** The subtraction or negation operator. */
MINUS : '-';

/** The multiplication operator, or the star of a splat. */
STAR : '*';

/** The division operator. */
SLASH : '/';

/** The modulo operator. */
PERCENT : '%';

/** The logical not operator. */
BANG : '!';

/** The question mark of a conditional expression. */
QUESTION : '?';

/** The colon of a conditional expression, an object element, or a for expression. */
COLON : ':';

/** The separator of tuple elements, object elements, and arguments. */
COMMA : ',';

/** The dot of an attribute access or a splat. */
DOT : '.';

/** The whitespace strip marker of a template interpolation or directive. */
TILDE : '~';

/** A number literal: digits with an optional fraction and exponent. */
NUMBER : [0-9]+ ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?;

/** An identifier, which HCL allows to contain dashes. Keywords such as for, in, if, true, false, and null are identifiers the parser reads by their text. */
IDENTIFIER : IdentifierFragment;

// canon: an identifier is a Unicode identifier, ID_Start or an underscore and then ID_Continue or a dash, as the HCL specification says, so a local named with a Greek letter lexes. ASCII comes first in each set, and the two sets are separate fragments, so no character can be matched two ways.
fragment IdentifierFragment : IdentifierStart IdentifierContinue*;

fragment IdentifierStart : [a-zA-Z_\p{L}\p{Nl}\u1885\u1886\u2118\u212E\u309B\u309C];

fragment IdentifierContinue : [a-zA-Z0-9_\-\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}\u1885\u1886\u2118\u212E\u309B\u309C\u00B7\u0387\u1369-\u1371\u19DA];

mode DocLine;

/** The line break that ends a line comment, typed as NEWLINE. The hook hides it when the next line is code or another comment, which joins consecutive comment lines into one canonical comment and binds the comment to the line directly below it. ref:DEC-hcl-grammar */
DOC_LINE_END : '\r'? '\n' -> popMode, type(NEWLINE);

/** A citation of a registry reference inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_REF : 'ref:' DocKey;

/** A citation of a registry license inside a canonical comment. ref:DEC-grammar-carries-extraction-rules */
DOC_LICENSE : 'license:' DocKey;

/** Whitespace inside a line comment. */
DOC_WS : [ \t]+ -> skip;

/** Punctuation inside a canonical comment, kept separate so a citation followed by a comma is still a citation. */
DOC_PUNCT : [,.;:()!?[\]{}"'`<>=+|#*/];

/** A word of prose inside a canonical comment. */
DOC_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|#*/]+;

mode DocBlock;

/** Closes a block comment and returns to the enclosing mode. ref:DEC-hcl-grammar */
DOC_BLOCK_CLOSE : '*/' -> popMode;

/** A citation of a registry reference inside a block comment, typed as DOC_REF. */
DOC_BLOCK_REF : 'ref:' DocKey -> type(DOC_REF);

/** A citation of a registry license inside a block comment, typed as DOC_LICENSE. */
DOC_BLOCK_LICENSE : 'license:' DocKey -> type(DOC_LICENSE);

/** Whitespace inside a block comment, including line breaks, which never end an attribute. */
DOC_BLOCK_WS : [ \t\r\n]+ -> skip;

/** Punctuation inside a block comment, typed as DOC_PUNCT. */
DOC_BLOCK_PUNCT : [,.;:()!?[\]{}"'`<>=+|#*/] -> type(DOC_PUNCT);

/** A word of prose inside a block comment, typed as DOC_WORD. */
DOC_BLOCK_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|#*/]+ -> type(DOC_WORD);

fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;

mode Template;

/** Closes a quoted template and returns to the expression around it. ref:DEC-hcl-grammar */
TEMPLATE_CLOSE : '"' -> popMode;

/** Opens an interpolation, an expression inside a template, closed by a brace. ref:DEC-hcl-grammar */
TEMPLATE_INTERP : '${' -> pushMode(DEFAULT_MODE);

/** Opens a template directive such as if or for, closed by a brace. ref:DEC-hcl-grammar */
TEMPLATE_DIRECTIVE : '%{' -> pushMode(DEFAULT_MODE);

/** A doubled sigil before a brace, which is literal text rather than an interpolation or directive. */
TEMPLATE_ESCAPE : '$${' | '%%{';

/** Literal text of a quoted template, with backslash escapes. */
TEMPLATE_TEXT : (~["\\$%\r\n] | '\\' ~[\r\n])+;

/** A dollar or percent sign that opens nothing, which is literal text. */
TEMPLATE_SIGIL : [$%];

mode Heredoc;

/** Opens an interpolation inside a heredoc, typed as TEMPLATE_INTERP. */
HEREDOC_INTERP : '${' -> pushMode(DEFAULT_MODE), type(TEMPLATE_INTERP);

/** Opens a directive inside a heredoc, typed as TEMPLATE_DIRECTIVE. */
HEREDOC_DIRECTIVE : '%{' -> pushMode(DEFAULT_MODE), type(TEMPLATE_DIRECTIVE);

/** A doubled sigil before a brace inside a heredoc, typed as TEMPLATE_ESCAPE. */
HEREDOC_ESCAPE : ('$${' | '%%{') -> type(TEMPLATE_ESCAPE);

/** A line break inside a heredoc, which is part of its text. */
HEREDOC_NEWLINE : '\r'? '\n';

/** Literal text of a heredoc line. When it starts its line and is the delimiter word alone, the hook types it HEREDOC_CLOSE and leaves the mode. ref:DEC-hcl-grammar */
HEREDOC_TEXT : ~[$%\r\n]+ { this.heredocText(); };

/** A dollar or percent sign inside a heredoc that opens nothing, typed as TEMPLATE_SIGIL. */
HEREDOC_SIGIL : [$%] -> type(TEMPLATE_SIGIL);
