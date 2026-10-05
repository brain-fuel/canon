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

// The canonically commented HCL parser. It is the plain parser with the top-level blocks of a
// Terraform configuration as labeled unit alternatives: a comment directly above a block is its
// Why, its labels are its What, joined with a dot, and its body is its How. The description of a
// variable or an output is a Why too. Comments that bind to nothing are notes, accepted and
// unlabeled, since HCL has no separate doc comment syntax.

parser grammar HCLParser;

options {
    tokenVocab = HCLLexer;
}

/** A configuration file is a body of top-level blocks and attributes up to end of input. ref:DEC-hcl-grammar */
configFile
    : topBody EOF
    ;

/** The top-level body: units, line breaks, and notes, in any order. A unit is tried before a note so that a comment directly above a block binds to it. ref:DEC-hcl-grammar */
topBody
    : (topItem | NEWLINE | note)*
    ;

/** A top-level block or attribute. Each alternative is a unit of its kind, named by its labels, a quoted string or an identifier, joined with a dot as Terraform addresses it, the quotes left out, with the comment directly above it as its Why. A variable or an output requires a Why, because they are a module's interface, and the string of its description attribute is a Why as well as a comment above it, because Terraform shows that description as its documentation; a comment above wins over the description. A run block in a test file is a test. The locals block is no unit: each of its entries is one. Any other block is a unit of kind block named by its type and labels. ref:DEC-hcl-grammar */
topItem
    : why = canonicalComment? 'resource' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # resource
    | why = canonicalComment? 'data' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # data
    | why = canonicalComment? 'module' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # module
    | why = canonicalComment? required = 'variable' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) LBRACE ('description' ASSIGN why = templateExpr | NEWLINE | note | bodyItem)* RBRACE # variable
    | why = canonicalComment? required = 'output' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) LBRACE ('description' ASSIGN why = templateExpr | NEWLINE | note | bodyItem)* RBRACE # output
    | why = canonicalComment? 'provider' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # provider
    | why = canonicalComment? what = 'terraform' how = blockBody # terraform
    | why = canonicalComment? 'run' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # run
    | 'locals' LBRACE (localEntry | NEWLINE | note)* RBRACE # localsBlock
    | why = canonicalComment? what = IDENTIFIER (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER)* how = blockBody # block
    | why = canonicalComment? what = IDENTIFIER ASSIGN how = expression # attribute
    ;

/** One entry of a locals block, a unit of kind local named by its attribute name, with the comment directly above it as its Why and its expression as its How. ref:DEC-hcl-grammar */
localEntry
    : why = canonicalComment? what = IDENTIFIER ASSIGN how = expression # local
    ;

/** A comment that binds to nothing: one followed by a blank line, or one above what is not a unit. It is accepted and is not reported, because HCL comments are not all documentation. ref:DEC-hcl-grammar */
note
    : canonicalComment
    ;

/** A canonical comment: one or more comment lines, joined by the lexer hook when nothing parts them, holding prose, reference citations, and license citations. ref:DEC-comment-reasons ref:DEC-hcl-grammar */
canonicalComment
    : (DOC_OPEN docPart* | DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE)+
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;

/** A block body: attributes, nested blocks, line breaks, and notes between braces. */
blockBody
    : LBRACE (bodyItem | NEWLINE | note)* RBRACE
    ;

/** An attribute or a nested block inside a body. */
bodyItem
    : attribute
    | block
    ;

/** An attribute: a name, an equals sign, and an expression. */
attribute
    : IDENTIFIER ASSIGN expression
    ;

/** A nested block: a type, its labels, and its body. Nested blocks are part of the How of the unit around them. */
block
    : IDENTIFIER blockLabel* blockBody
    ;

/** A label of a nested block, a quoted string or an identifier. */
blockLabel
    : stringLiteral
    | IDENTIFIER
    ;

/** A quoted string without interpolations, as block labels are. */
stringLiteral
    : TEMPLATE_OPEN TEMPLATE_TEXT? TEMPLATE_CLOSE
    ;

/** An expression, with the operators of HCL from tightest to loosest: unary minus and not, multiplication, addition, comparison, equality, and, or, and the conditional. */
expression
    : exprTerm
    | (MINUS | BANG) expression
    | expression (STAR | SLASH | PERCENT) expression
    | expression (PLUS | MINUS) expression
    | expression (LESS | GREATER | LESS_EQUAL | GREATER_EQUAL) expression
    | expression (EQUAL_EQUAL | NOT_EQUAL) expression
    | expression AND expression
    | expression OR expression
    | <assoc = right> expression QUESTION expression COLON expression
    ;

/** A term: a literal, a for expression, a collection, a template, a function call, a variable, or a parenthesized expression, followed by any index, attribute access, or splat. */
exprTerm
    : literalValue
    | forExpr
    | collectionValue
    | templateExpr
    | functionCall
    | variableExpr
    | LPAREN expression RPAREN
    | exprTerm index
    | exprTerm getAttr
    | exprTerm splat
    ;

/** A number, true, false, or null. */
literalValue
    : NUMBER
    | 'true'
    | 'false'
    | 'null'
    ;

/** A tuple or an object. */
collectionValue
    : tuple
    | object
    ;

/** A tuple: expressions between brackets, separated by commas, with an optional trailing comma. */
tuple
    : LBRACK (expression (COMMA expression)* COMMA?)? RBRACK
    ;

/** An object: elements between braces, separated by commas or line breaks, with notes among them. */
object
    : LBRACE (objectElem | NEWLINE | COMMA | note)* RBRACE
    ;

/** An object element: a key expression, an equals sign or a colon, and a value expression. */
objectElem
    : expression (ASSIGN | COLON) expression
    ;

/** A for expression that builds a tuple or an object. The lexer hook hides line breaks inside it. ref:DEC-hcl-grammar */
forExpr
    : LBRACK forIntro expression forCond? RBRACK
    | LBRACE forIntro expression FAT_ARROW expression ELLIPSIS? forCond? RBRACE
    ;

/** The head of a for expression: the key and value names, the collection, and a colon. */
forIntro
    : 'for' IDENTIFIER (COMMA IDENTIFIER)? 'in' expression COLON
    ;

/** The condition that filters the elements of a for expression. */
forCond
    : 'if' expression
    ;

/** A function call, with an optional provider namespace, and arguments of which the last may be expanded with an ellipsis. */
functionCall
    : IDENTIFIER (DOUBLE_COLON IDENTIFIER)* LPAREN (expression (COMMA expression)* (COMMA | ELLIPSIS)?)? RPAREN
    ;

/** A variable, such as var, local, each, or a resource type. */
variableExpr
    : IDENTIFIER
    ;

/** An index into a collection, or a legacy index with a dot and a number. */
index
    : LBRACK expression RBRACK
    | DOT NUMBER
    ;

/** An attribute access. */
getAttr
    : DOT IDENTIFIER
    ;

/** An attribute-only splat, or a full splat followed by attribute accesses and indexes. */
splat
    : DOT STAR getAttr*
    | LBRACK STAR RBRACK (getAttr | index)*
    ;

/** A quoted template or a heredoc template, with text, interpolations, and directives. */
templateExpr
    : TEMPLATE_OPEN templatePart* TEMPLATE_CLOSE
    | HEREDOC_OPEN templatePart* HEREDOC_CLOSE
    ;

/** One part of a template: literal text, an escape, a line break of a heredoc, an interpolation, or a directive. */
templatePart
    : TEMPLATE_TEXT
    | TEMPLATE_ESCAPE
    | TEMPLATE_SIGIL
    | HEREDOC_TEXT
    | HEREDOC_NEWLINE
    | interpolation
    | directive
    ;

/** An interpolation: an expression between a dollar brace and a brace, with optional strip markers. */
interpolation
    : TEMPLATE_INTERP TILDE? expression TILDE? RBRACE
    ;

/** A template directive between a percent brace and a brace, with optional strip markers. */
directive
    : TEMPLATE_DIRECTIVE TILDE? directiveBody TILDE? RBRACE
    ;

/** The body of a template directive: if, else, endif, for, or endfor. */
directiveBody
    : 'if' expression
    | 'else'
    | 'endif'
    | 'for' IDENTIFIER (COMMA IDENTIFIER)? 'in' expression
    | 'endfor'
    ;
