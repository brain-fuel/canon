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

// A parser for HCL, the HashiCorp configuration language of Terraform, written for canon from the
// HCL native syntax specification. A file is a body of attributes and blocks; expressions follow
// the specification's operators, terms, templates, and for expressions.

parser grammar HCLParser;

options {
    tokenVocab = HCLLexer;
}

/** A configuration file is a body of attributes and blocks up to end of input, in the native syntax or in Terraform's JSON syntax. */
configFile
    : body EOF
    | jsonObject EOF
    ;

/** A body: attributes, blocks, and line breaks. */
body
    : (bodyItem | NEWLINE)*
    ;

/** A block body between braces. */
blockBody
    : LBRACE body RBRACE
    ;

/** An attribute or a nested block inside a body. */
bodyItem
    : attribute
    | block
    ;

/** An attribute: a name, an equals sign, and an expression. */
// canon: an attribute's name may be a quoted string, as HCL 1 allows and Nomad's agent and volume files still write.
attribute
    : (IDENTIFIER | stringLiteral) ASSIGN expression
    ;

/** A block: a type, its labels, and its body. */
// canon: a block's type may be a quoted string, as HCL 1 allows.
block
    : (IDENTIFIER | stringLiteral) blockLabel* blockBody
    ;

/** A block label, a quoted string or an identifier. */
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

/** An object: elements between braces, separated by commas or line breaks. */
object
    : LBRACE (objectElem | NEWLINE | COMMA)* RBRACE
    ;

/** An object element: a key expression, an equals sign or a colon, and a value expression. */
objectElem
    : expression (ASSIGN | COLON) expression
    ;

/** A for expression that builds a tuple or an object. The lexer hook hides line breaks inside it. */
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

/** One part of a template: literal text, an escape, a line break of a heredoc, an interpolation, or an if or for directive with its body. */
templatePart
    : TEMPLATE_TEXT
    | TEMPLATE_ESCAPE
    | TEMPLATE_SIGIL
    | HEREDOC_TEXT
    | HEREDOC_NEWLINE
    | interpolation
    | ifDirective
    | forDirective
    ;

/** An interpolation: an expression between a dollar brace and a brace, with optional strip markers. */
interpolation
    : TEMPLATE_INTERP TILDE? expression TILDE? RBRACE
    ;

/** An if directive, its body, an optional else directive and body, and the endif directive that closes it. */
ifDirective
    : directiveOpen 'if' expression directiveClose templatePart* (directiveOpen 'else' directiveClose templatePart*)? directiveOpen 'endif' directiveClose
    ;

/** A for directive, its body, and the endfor directive that closes it. */
forDirective
    : directiveOpen 'for' IDENTIFIER (COMMA IDENTIFIER)? 'in' expression directiveClose templatePart* directiveOpen 'endfor' directiveClose
    ;

/** The opening of a directive, a percent brace with an optional strip marker. */
directiveOpen
    : TEMPLATE_DIRECTIVE TILDE?
    ;

/** The closing of a directive, a brace with an optional strip marker. */
directiveClose
    : TILDE? RBRACE
    ;

/** A JSON value: an object, an array, a string, which Terraform reads as a template, a number, true, false, or null. */
jsonValue
    : jsonObject
    | LBRACK (jsonValue (COMMA jsonValue)*)? RBRACK
    | templateExpr
    | MINUS? NUMBER
    | 'true'
    | 'false'
    | 'null'
    ;

/** A JSON object of properties. */
jsonObject
    : LBRACE (jsonMember (COMMA jsonMember)*)? RBRACE
    ;

/** A JSON property: a string key, a colon, and a value. */
jsonMember
    : TEMPLATE_OPEN TEMPLATE_TEXT? TEMPLATE_CLOSE COLON jsonValue
    ;
