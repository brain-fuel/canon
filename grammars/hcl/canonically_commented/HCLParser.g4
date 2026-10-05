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

/** A configuration file is a body of top-level blocks and attributes up to end of input, in the native syntax or in Terraform's JSON syntax. ref:DEC-hcl-grammar */
configFile
    : topBody EOF
    | jsonFile EOF
    ;

/** The top-level body: units, line breaks, and notes, in any order. A unit is tried before a note so that a comment directly above a block binds to it. ref:DEC-hcl-grammar */
topBody
    : (topItem | NEWLINE | note)*
    ;

/** A top-level block or attribute. Each alternative is a unit of its kind, named by its labels, a quoted string or an identifier, joined with a dot as Terraform addresses it, the quotes left out, with the comment directly above it as its Why. A variable or an output requires a Why, because they are a module's interface, and the string of its description attribute is a Why as well as a comment above it, because Terraform shows that description as its documentation; a comment above wins over the description. A provider with an alias is named by its label and alias, as Terraform addresses it. A moved or removed block is named by the address it moves from and an import block by the address it imports to, which tells apart blocks that have no labels. A run block in a test file is a test. The locals block is no unit: each of its entries is one. Any other block is a unit of kind block named by its type, labels, and any alias. ref:DEC-hcl-grammar */
topItem
    : why = canonicalComment? 'resource' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # resource
    | why = canonicalComment? 'data' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # data
    | why = canonicalComment? 'module' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # module
    | why = canonicalComment? required = 'variable' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) LBRACE ('description' ASSIGN why = templateExpr | NEWLINE | note | bodyItem)* RBRACE # variable
    | why = canonicalComment? required = 'output' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) LBRACE ('description' ASSIGN why = templateExpr | NEWLINE | note | bodyItem)* RBRACE # output
    | why = canonicalComment? 'provider' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) LBRACE ('alias' ASSIGN TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | NEWLINE | note | bodyItem)* RBRACE # provider
    | why = canonicalComment? what = 'terraform' how = blockBody # terraform
    | why = canonicalComment? 'run' (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER) how = blockBody # run
    | why = canonicalComment? 'moved' LBRACE ('from' ASSIGN what = expression | NEWLINE | note | bodyItem)* RBRACE # moved
    | why = canonicalComment? 'removed' LBRACE ('from' ASSIGN what = expression | NEWLINE | note | bodyItem)* RBRACE # removed
    | why = canonicalComment? 'import' LBRACE ('to' ASSIGN what = expression | NEWLINE | note | bodyItem)* RBRACE # importBlock
    | 'locals' LBRACE (localEntry | NEWLINE | note)* RBRACE # localsBlock
    | why = canonicalComment? what = IDENTIFIER (TEMPLATE_OPEN what = TEMPLATE_TEXT? TEMPLATE_CLOSE | what = IDENTIFIER)* LBRACE ('alias' ASSIGN TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | NEWLINE | note | bodyItem)* RBRACE # block
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

/** An if directive, its body, an optional else directive and body, and the endif directive that closes it, so a template whose directives do not pair does not parse. ref:DEC-hcl-grammar */
ifDirective
    : directiveOpen 'if' expression directiveClose templatePart* (directiveOpen 'else' directiveClose templatePart*)? directiveOpen 'endif' directiveClose
    ;

/** A for directive, its body, and the endfor directive that closes it. ref:DEC-hcl-grammar */
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

/** A file in Terraform's JSON syntax: one object whose properties are block types or, in a variables file, attributes. The lexer hook hides its line breaks. ref:DEC-hcl-grammar */
jsonFile
    : LBRACE (jsonTop (COMMA jsonTop)*)? RBRACE
    ;

/** A top-level property of a JSON file. A block type's property holds its blocks keyed by their labels, and each block is a unit named as in the native syntax: the keys above a block that are part of its address are labeled qualifier, and each is the first part of the name of the units below it. terraform is a unit itself. A property named two slashes is a comment. Any other property is a unit of kind attribute, as in a JSON variables file; it may hold a comment only where JSON could, which is nowhere, so it never has a Why. ref:DEC-hcl-grammar */
jsonTop
    : TEMPLATE_OPEN 'resource' TEMPLATE_CLOSE COLON LBRACE (jsonTypeGroup (COMMA jsonTypeGroup)*)? RBRACE # jsonResources
    | TEMPLATE_OPEN 'data' TEMPLATE_CLOSE COLON LBRACE (jsonDataGroup (COMMA jsonDataGroup)*)? RBRACE # jsonData
    | TEMPLATE_OPEN 'module' TEMPLATE_CLOSE COLON LBRACE (jsonModule (COMMA jsonModule)*)? RBRACE # jsonModules
    | TEMPLATE_OPEN 'variable' TEMPLATE_CLOSE COLON LBRACE (jsonVariable (COMMA jsonVariable)*)? RBRACE # jsonVariables
    | TEMPLATE_OPEN 'output' TEMPLATE_CLOSE COLON LBRACE (jsonOutput (COMMA jsonOutput)*)? RBRACE # jsonOutputs
    | TEMPLATE_OPEN 'provider' TEMPLATE_CLOSE COLON LBRACE (jsonProviderGroup (COMMA jsonProviderGroup)*)? RBRACE # jsonProviders
    | TEMPLATE_OPEN 'locals' TEMPLATE_CLOSE COLON LBRACE (jsonLocal (COMMA jsonLocal)*)? RBRACE # jsonLocals
    | TEMPLATE_OPEN qualifier = 'check' TEMPLATE_CLOSE COLON LBRACE (jsonCheck (COMMA jsonCheck)*)? RBRACE # jsonChecks
    | TEMPLATE_OPEN 'moved' TEMPLATE_CLOSE COLON (jsonMoved | LBRACK (jsonMoved (COMMA jsonMoved)*)? RBRACK) # jsonMovedBlocks
    | TEMPLATE_OPEN 'removed' TEMPLATE_CLOSE COLON (jsonRemoved | LBRACK (jsonRemoved (COMMA jsonRemoved)*)? RBRACK) # jsonRemovedBlocks
    | TEMPLATE_OPEN 'import' TEMPLATE_CLOSE COLON (jsonImport | LBRACK (jsonImport (COMMA jsonImport)*)? RBRACK) # jsonImportBlocks
    | why = canonicalComment? TEMPLATE_OPEN what = 'terraform' TEMPLATE_CLOSE COLON LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # terraform
    | TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON jsonValue # jsonComment
    | why = canonicalComment? TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON how = jsonValue # attribute
    ;

/** The resources of one type, whose type, labeled qualifier, is the first part of each resource's name. ref:DEC-hcl-grammar */
jsonTypeGroup
    : TEMPLATE_OPEN qualifier = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE (jsonResource (COMMA jsonResource)*)? RBRACE
    ;

/** The data sources of one type, whose type is the first part of each one's name. ref:DEC-hcl-grammar */
jsonDataGroup
    : TEMPLATE_OPEN qualifier = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE (jsonDataSource (COMMA jsonDataSource)*)? RBRACE
    ;

/** A resource in JSON syntax, named by its type and name. A property named two slashes is a comment in Terraform's JSON syntax, and its string is the Why. ref:DEC-hcl-grammar */
jsonResource
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # resource
    ;

/** A data source in JSON syntax, named by its type and name, with its comment property as its Why. ref:DEC-hcl-grammar */
jsonDataSource
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # data
    ;

/** A module call in JSON syntax, named by its label, with its comment property as its Why. ref:DEC-hcl-grammar */
jsonModule
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # module
    ;

/** A variable in JSON syntax, named by its label. Its comment property is its Why wherever it is written, and its description is when it has none, as a comment above wins over a description in the native syntax. It requires one, which its colon is labeled to say, as the keyword is in the native syntax. ref:DEC-hcl-grammar */
// canon: the alternative with a comment property comes first, so the comment property wins over a description written before it.
jsonVariable
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE required = COLON LBRACE (jsonDescribedMember COMMA)*? TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr (COMMA jsonDescribedMember)* RBRACE # variable
    | TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE required = COLON LBRACE ((TEMPLATE_OPEN 'description' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN 'description' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # variable
    ;

/** An output in JSON syntax, named by its label. Its comment property is its Why wherever it is written, and its description is when it has none. It requires one. ref:DEC-hcl-grammar */
// canon: the alternative with a comment property comes first, so the comment property wins over a description written before it.
jsonOutput
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE required = COLON LBRACE (jsonDescribedMember COMMA)*? TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr (COMMA jsonDescribedMember)* RBRACE # output
    | TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE required = COLON LBRACE ((TEMPLATE_OPEN 'description' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN 'description' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # output
    ;

/** The configurations of one provider, one object or a list of them, whose provider name, labeled qualifier, is the first part of each one's name. ref:DEC-hcl-grammar */
jsonProviderGroup
    : TEMPLATE_OPEN qualifier = TEMPLATE_TEXT TEMPLATE_CLOSE COLON (jsonProvider | LBRACK (jsonProvider (COMMA jsonProvider)*)? RBRACK)
    ;

/** A provider configuration in JSON syntax, named by its provider and any alias, with its comment property as its Why. ref:DEC-hcl-grammar */
jsonProvider
    : LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'alias' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'alias' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember))*)? RBRACE # provider
    ;

/** A local value in JSON syntax, a unit of kind local named by its key; a property named two slashes is a comment and no local. ref:DEC-hcl-grammar */
jsonLocal
    : TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON jsonValue # jsonLocalComment
    | why = canonicalComment? TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON how = jsonValue # local
    ;

/** A check block in JSON syntax, of kind block and named check and its label, as in the native syntax. ref:DEC-hcl-grammar */
jsonCheck
    : TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE COLON LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | jsonMember))*)? RBRACE # block
    ;

/** A moved block in JSON syntax, named by the address it moves from. ref:DEC-hcl-grammar */
jsonMoved
    : LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'from' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'from' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember))*)? RBRACE # moved
    ;

/** A removed block in JSON syntax, named by the address it removes. ref:DEC-hcl-grammar */
jsonRemoved
    : LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'from' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'from' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember))*)? RBRACE # removed
    ;

/** An import block in JSON syntax, named by the address it imports to. ref:DEC-hcl-grammar */
jsonImport
    : LBRACE ((TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'to' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember) (COMMA (TEMPLATE_OPEN '//' TEMPLATE_CLOSE COLON why = templateExpr | TEMPLATE_OPEN 'to' TEMPLATE_CLOSE COLON TEMPLATE_OPEN what = TEMPLATE_TEXT TEMPLATE_CLOSE | jsonMember))*)? RBRACE # importBlock
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

/** A member of a variable or an output that has a comment property: its description, which the comment property wins over, or any other member. ref:DEC-hcl-grammar */
// canon: a description beside a comment property is no Why.
jsonDescribedMember
    : TEMPLATE_OPEN 'description' TEMPLATE_CLOSE COLON templateExpr
    | jsonMember
    ;
