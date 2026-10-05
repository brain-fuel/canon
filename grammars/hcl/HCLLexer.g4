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

// A lexer for HCL, the HashiCorp configuration language of Terraform, written for canon from the
// HCL native syntax specification. Comments go to the hidden channel. The HCLLexerBase hook hides
// line breaks inside parentheses, brackets, interpolations, and object for expressions, where HCL
// ignores them, and closes each heredoc at the line holding only its delimiter word.

lexer grammar HCLLexer;

options {
    superClass = HCLLexerBase;
}

tokens {
    HEREDOC_CLOSE
}

/** A line comment, opened with a hash or two slashes. */
COMMENT : ('#' | '//') ~[\r\n]* -> channel(HIDDEN);

/** A block comment. */
BLOCK_COMMENT : '/*' .*? '*/' -> channel(HIDDEN);

/** A line break, which ends an attribute or a block in a body. The hook hides it inside parentheses, brackets, and template interpolations, where HCL ignores line breaks. */
NEWLINE : '\r'? '\n';

/** Spaces and tabs between tokens. */
WS : [ \t\f]+ -> skip;

/** Opens a heredoc template, from the angle brackets to the end of the line; the hook records its delimiter word so that the line holding only that word closes it. */
HEREDOC_OPEN : '<<' '-'? IdentifierFragment [ \t]* '\r'? '\n' { this.heredocOpen(); } -> pushMode(Heredoc);

/** Opens a quoted template, whose text and interpolations are tokenized in the Template mode. */
TEMPLATE_OPEN : '"' -> pushMode(Template);

/** Opens a block body or an object, and pushes the default mode so that the closing brace of an interpolation can return to its template. */
LBRACE : '{' -> pushMode(DEFAULT_MODE);

/** Closes a block body, an object, or an interpolation. */
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

fragment IdentifierFragment : [a-zA-Z_] [a-zA-Z0-9_-]*;

mode Template;

/** Closes a quoted template and returns to the expression around it. */
TEMPLATE_CLOSE : '"' -> popMode;

/** Opens an interpolation, an expression inside a template, closed by a brace. */
TEMPLATE_INTERP : '${' -> pushMode(DEFAULT_MODE);

/** Opens a template directive such as if or for, closed by a brace. */
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

/** Literal text of a heredoc line. When it starts its line and is the delimiter word alone, the hook types it HEREDOC_CLOSE and leaves the mode. */
HEREDOC_TEXT : ~[$%\r\n]+ { this.heredocText(); };

/** A dollar or percent sign inside a heredoc that opens nothing, typed as TEMPLATE_SIGIL. */
HEREDOC_SIGIL : [$%] -> type(TEMPLATE_SIGIL);
