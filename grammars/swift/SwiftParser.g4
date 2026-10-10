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



// The Swift parser canon reads Swift with. It is written for canon from the grammar summary of The
// Swift Programming Language
// (https://docs.swift.org/swift-book/documentation/the-swift-programming-language/summaryofthegrammar/),
// rule by rule under the summary's production names in lower camel case (topLevelDeclaration for
// top-level-declaration, functionDeclaration for function-declaration), with the Swift compiler's
// parser (swift-syntax's SwiftParser, Apache-2.0 with the Runtime Library Exception) as the
// authority where the two differ; the differences are tabled in grammars/swift/README.md. It parses
// the declarations that carry documentation: imports, constants, variables, type aliases, functions,
// enums and their cases, structs, classes, actors, protocols and their requirements, initializers,
// deinitializers, extensions, subscripts, macros, operators, precedence groups, and freestanding
// macro expansions, with their attributes and modifiers. Expressions, statements, types, patterns,
// generic clauses, parameter clauses, and code blocks are read structurally, as runs of tokens kept
// whole by the NEWLINE tokens the SwiftLexerBase hook emits and by bracket nesting; each rule that
// does so says so. A top-level statement that declares nothing, as main.swift and scripts hold, is
// read as an expression; a member of a type must be a declaration, as the compiler requires.
//
// Five labels serve canon: marker on each attribute, so a test is told by its attribute; required on
// public and open, which make a declaration API that needs a comment; optional on internal,
// package, and override, Swift's default access and an override, which inherits its documentation;
// hidden on private, fileprivate, and @_spi, which DocC leaves out of a module's documentation; and
// inherited on enum cases and on the bodies of protocols and extensions, whose members take the
// access of the declaration around them.

parser grammar SwiftParser;

options {
    tokenVocab = SwiftLexer;
}

// top-level-declaration → statements?. The statements are written out here and in each body rather
// than as a rule of their own: the parser keeps one tree for every end a rule reaches, and a rule
// holding a body's statements reaches one end per statement, which made a long file quadratic.
topLevel
    : statement? (semi statement?)* EOF
    ;

// A statement separator: ; or a line break that ends a statement, which the hook emits as NEWLINE.
semi
    : NEWLINE
    | SEMI
    ;

// statement → declaration | expression | ..., a statement that declares nothing read as a run of
// tokens.
statement
    : declaration
    | expressionStatement
    ;

// declaration → import-declaration | constant-declaration | variable-declaration |
// typealias-declaration | function-declaration | enum-declaration | struct-declaration |
// class-declaration | actor-declaration | protocol-declaration | initializer-declaration |
// deinitializer-declaration | extension-declaration | subscript-declaration | macro-declaration |
// operator-declaration | precedence-group-declaration, with a protocol's associated type and a
// freestanding macro expansion, which the compiler reads where a declaration stands.
declaration
    : importDeclaration
    | constantDeclaration
    | variableDeclaration
    | typealiasDeclaration
    | associatedtypeDeclaration
    | functionDeclaration
    | enumDeclaration
    | structDeclaration
    | classDeclaration
    | actorDeclaration
    | protocolDeclaration
    | initializerDeclaration
    | deinitializerDeclaration
    | extensionDeclaration
    | subscriptDeclaration
    | macroDeclaration
    | operatorDeclaration
    | precedenceGroupDeclaration
    | macroExpansionDeclaration
    ;

// attributes? declaration-modifiers?, before every declaration. Each declaration rule starts with it,
// so a declaration's node starts at its first attribute and the doc comment above belongs to it. The
// compiler reads attributes and modifiers in any order, and a line break after either.
declarationPrefix
    : (attributeOrSpi NEWLINE? | declarationModifier NEWLINE?)*
    ;

// An attribute, labeled marker, or @_spi, which makes a declaration a system programming interface
// that DocC leaves out of the documentation, labeled hidden.
attributeOrSpi
    : hidden = spiAttribute
    | marker = attribute
    ;

// attribute → @ attribute-name attribute-argument-clause?, the name qualified as a custom
// attribute's type may be, with the generic arguments a custom attribute's type may have; the
// arguments are read as a run of tokens.
attribute
    : AT attributeName genericArgumentClause? attributeArgumentClause?
    ;

attributeName
    : identifier (DOT identifier)*
    ;

attributeArgumentClause
    : LPAREN groupItem* RPAREN
    ;

// generic-argument-clause → < generic-argument-list >, the arguments read as a run of tokens with
// their own generic argument clauses nested.
genericArgumentClause
    : LT genericArgument* GT
    ;

genericArgument
    : genericArgumentClause
    | bracketGroup
    | ~(LT | GT | NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// @_spi(name), the underscored attribute the compiler reads.
spiAttribute
    : AT SPI attributeArgumentClause
    ;

// declaration-modifier → class | convenience | dynamic | final | infix | lazy | optional | override
// | postfix | prefix | required | static | unowned | unowned ( safe ) | unowned ( unsafe ) | weak
// | access-level-modifier | mutation-modifier | actor-isolation-modifier, and the ownership
// modifiers consuming and borrowing, distributed, and indirect, which the summary lists with enum
// cases. override is labeled optional.
declarationModifier
    : accessLevelModifier
    | mutationModifier
    | actorIsolationModifier
    | optional = OVERRIDE
    | CLASS
    | CONVENIENCE
    | DYNAMIC
    | FINAL
    | INFIX
    | LAZY
    | OPTIONAL
    | POSTFIX
    | PREFIX
    | REQUIRED
    | STATIC
    | UNOWNED (LPAREN identifier RPAREN)?
    | WEAK
    | CONSUMING
    | BORROWING
    | DISTRIBUTED
    | INDIRECT
    ;

// access-level-modifier → private | private ( set ) | fileprivate | fileprivate ( set ) | internal
// | internal ( set ) | package | package ( set ) | public | public ( set ) | open | open ( set ).
// public and open are labeled required, internal and package optional, and private and
// fileprivate hidden; a setter's access says nothing of the declaration's.
accessLevelModifier
    : required = PUBLIC
    | required = OPEN
    | optional = INTERNAL
    | optional = PACKAGE
    | hidden = PRIVATE
    | hidden = FILEPRIVATE
    | (PUBLIC | OPEN | INTERNAL | PACKAGE | PRIVATE | FILEPRIVATE) LPAREN identifier RPAREN
    ;

// mutation-modifier → mutating | nonmutating
mutationModifier
    : MUTATING
    | NONMUTATING
    ;

// actor-isolation-modifier → nonisolated, and nonisolated(unsafe), which the compiler reads.
actorIsolationModifier
    : NONISOLATED (LPAREN identifier RPAREN)?
    ;

// import-declaration → attributes? import import-kind? import-path, the kind and path read as a run
// of tokens.
importDeclaration
    : declarationPrefix IMPORT importPart+
    ;

importPart
    : ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// constant-declaration → attributes? declaration-modifiers? let pattern-initializer-list
constantDeclaration
    : declarationPrefix LET patternInitializerList
    ;

// variable-declaration → variable-declaration-head pattern-initializer-list, or a variable with a
// getter-setter block, a getter-setter keyword block, or willSet and didSet blocks; the head is
// attributes? declaration-modifiers? var.
variableDeclaration
    : declarationPrefix VAR patternInitializerList
    ;

// pattern-initializer-list → pattern-initializer | pattern-initializer , pattern-initializer-list.
// The first pattern's name is the declaration's; a tuple or wildcard pattern binds no one name. The
// type annotations, initializers, later patterns, and accessor blocks are read as a run of tokens.
patternInitializerList
    : variableName bindingPart*
    | (UNDERSCORE | bracketGroup) bindingPart*
    ;

variableName
    : identifier
    ;

bindingPart
    : group
    | ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// typealias-declaration → attributes? access-level-modifier? typealias typealias-name
// generic-parameter-clause? typealias-assignment, read after the name as a run of tokens.
typealiasDeclaration
    : declarationPrefix TYPEALIAS declarationName signaturePart*
    ;

// protocol-associated-type-declaration → attributes? access-level-modifier? associatedtype
// typealias-name type-inheritance-clause? typealias-assignment? generic-where-clause?
associatedtypeDeclaration
    : declarationPrefix ASSOCIATEDTYPE declarationName signaturePart*
    ;

// function-declaration → function-head function-name generic-parameter-clause? function-signature
// generic-where-clause? function-body?, function-head → attributes? declaration-modifiers? func.
// The signature is read as a run of tokens up to the body.
functionDeclaration
    : declarationPrefix FUNC functionName signaturePart* codeBlock?
    ;

// function-name → identifier | operator
functionName
    : identifier
    | OP
    | LT
    | GT
    ;

// A generic parameter clause, parameter clause, effects, result type, or where clause, read as a run
// of tokens up to a body.
signaturePart
    : bracketGroup
    | ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// code-block → { statements? }, read as a run of tokens, so a local declaration is part of its block.
codeBlock
    : LBRACE groupItem* RBRACE
    ;

// enum-declaration → attributes? access-level-modifier? union-style-enum | attributes?
// access-level-modifier? raw-value-style-enum. Both styles are one rule here: the name, a header of
// generic parameters, inheritance, and where clauses read as a run of tokens, and the members.
enumDeclaration
    : declarationPrefix ENUM declarationName typeHeader enumBody
    ;

// { union-style-enum-members? } or { raw-value-style-enum-members? }. A case is labeled inherited,
// since it has its enum's access.
enumBody
    : LBRACE enumMember? (semi enumMember?)* RBRACE
    ;

enumMember
    : inherited = enumCaseDeclaration
    | declaration
    ;

// union-style-enum-case-clause → attributes? indirect? case union-style-enum-case-list, and
// raw-value-style-enum-case-clause → attributes? case raw-value-style-enum-case-list. A clause is
// named by its first case; the associated values, raw values, and later cases are a run of tokens.
enumCaseDeclaration
    : declarationPrefix CASE declarationName signaturePart*
    ;

// struct-declaration → attributes? access-level-modifier? struct struct-name
// generic-parameter-clause? type-inheritance-clause? generic-where-clause? struct-body
structDeclaration
    : declarationPrefix STRUCT declarationName typeHeader structBody
    ;

// struct-body → { struct-members? }
structBody
    : LBRACE declaration? (semi declaration?)* RBRACE
    ;

// class-declaration → attributes? access-level-modifier? final? class class-name
// generic-parameter-clause? type-inheritance-clause? generic-where-clause? class-body
classDeclaration
    : declarationPrefix CLASS declarationName typeHeader classBody
    ;

// class-body → { class-members? }
classBody
    : LBRACE declaration? (semi declaration?)* RBRACE
    ;

// actor-declaration → attributes? access-level-modifier? actor actor-name generic-parameter-clause?
// type-inheritance-clause? generic-where-clause? actor-body
actorDeclaration
    : declarationPrefix ACTOR declarationName typeHeader actorBody
    ;

// actor-body → { actor-members? }
actorBody
    : LBRACE declaration? (semi declaration?)* RBRACE
    ;

// protocol-declaration → attributes? access-level-modifier? protocol protocol-name
// type-inheritance-clause? generic-where-clause? protocol-body. Its body is labeled inherited, since
// a requirement has its protocol's access.
protocolDeclaration
    : declarationPrefix PROTOCOL declarationName typeHeader inherited = protocolBody
    ;

// protocol-body → { protocol-members? }, whose members are requirements without bodies, read by the
// declaration rules, whose bodies are optional.
protocolBody
    : LBRACE declaration? (semi declaration?)* RBRACE
    ;

// initializer-declaration → initializer-head generic-parameter-clause? parameter-clause async?
// throws-clause? generic-where-clause? initializer-body, initializer-head → attributes?
// declaration-modifiers? init (? | !)?, read after init as a run of tokens; a protocol's
// requirement has no body.
initializerDeclaration
    : declarationPrefix INIT signaturePart* codeBlock?
    ;

// deinitializer-declaration → attributes? deinit code-block
deinitializerDeclaration
    : declarationPrefix DEINIT codeBlock?
    ;

// extension-declaration → attributes? access-level-modifier? extension type-identifier
// type-inheritance-clause? generic-where-clause? extension-body. Its body is labeled inherited, since
// an extension's access modifier is the default access of its members.
extensionDeclaration
    : declarationPrefix EXTENSION extendedType typeHeader inherited = extensionBody
    ;

// type-identifier → type-name generic-argument-clause? | type-name generic-argument-clause? .
// type-identifier, named by its type names, the generic arguments read with the header; and the
// array and dictionary sugar the compiler accepts.
extendedType
    : identifier (DOT identifier)*
    | LBRACK groupItem* RBRACK
    ;

// extension-body → { extension-members? }
extensionBody
    : LBRACE declaration? (semi declaration?)* RBRACE
    ;

// A type declaration's generic-parameter-clause? type-inheritance-clause? generic-where-clause?, read
// as a run of tokens up to its body.
typeHeader
    : headerPart*
    ;

headerPart
    : bracketGroup
    | ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// subscript-declaration → subscript-head subscript-result generic-where-clause? code-block, or a
// getter-setter block or getter-setter keyword block; subscript-head → attributes?
// declaration-modifiers? subscript generic-parameter-clause? parameter-clause.
subscriptDeclaration
    : declarationPrefix SUBSCRIPT signaturePart* codeBlock?
    ;

// macro-declaration → macro-head identifier generic-parameter-clause? macro-signature
// macro-definition? generic-where-clause, macro-head → attributes? declaration-modifiers? macro
macroDeclaration
    : declarationPrefix MACRO declarationName signaturePart*
    ;

// operator-declaration → prefix-operator-declaration | postfix-operator-declaration |
// infix-operator-declaration, whose prefix, postfix, or infix the prefix reads as a modifier; and
// the Swift 2 form with a body, which the compiler still parses.
operatorDeclaration
    : declarationPrefix OPERATOR operatorName signaturePart* codeBlock?
    ;

// The operator an operator declaration declares.
operatorName
    : OP
    | LT
    | GT
    ;

// precedence-group-declaration → precedencegroup precedence-group-name { precedence-group-attributes? }
precedenceGroupDeclaration
    : declarationPrefix PRECEDENCEGROUP declarationName codeBlock
    ;

// macro-expansion-expression → # identifier generic-argument-clause? function-call-argument-clause?
// trailing-closures?, where a declaration stands, as #warning, #error, #sourceLocation, and
// freestanding declaration macros are; read after the name as a run of tokens.
macroExpansionDeclaration
    : declarationPrefix HASH identifier exprPart*
    ;

// The name a declaration declares.
declarationName
    : identifier
    ;

// identifier → a name, a backquoted name, or a contextual keyword, which is a name where it is not
// a keyword.
identifier
    : ID
    | BACKQUOTED_ID
    | ACTOR
    | BORROWING
    | CONSUMING
    | CONVENIENCE
    | DISTRIBUTED
    | DYNAMIC
    | FINAL
    | INDIRECT
    | INFIX
    | LAZY
    | MACRO
    | MUTATING
    | NONISOLATED
    | NONMUTATING
    | OPEN
    | OPTIONAL
    | OVERRIDE
    | PACKAGE
    | POSTFIX
    | PREFIX
    | REQUIRED
    | SPI
    | UNOWNED
    | WEAK
    ;

// A statement that declares nothing, read as a run of tokens: an expression, an if, guard, for,
// while, repeat, switch, do, defer, or labeled statement, a return, throw, break, or continue, as
// a script's top-level code holds. It starts with no attribute, keyword, or modifier that begins a
// declaration, as the compiler parses a declaration wherever one starts, so a declaration the
// grammar cannot read fails the file rather than reading as an expression; a contextual keyword
// starts one only where a dot, an operator, or a bracket follows it, as package.targets does.
expressionStatement
    : expressionStart exprPart*
    ;

expressionStart
    : group
    | contextualKeyword (DOT | OP | bracketGroup)
    | ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | AT | HASH | ASSOCIATEDTYPE | CASE | CLASS | DEINIT | ENUM | EXTENSION | FILEPRIVATE | FUNC | IMPORT | INIT | INTERNAL | LET | OPERATOR | PRECEDENCEGROUP | PRIVATE | PROTOCOL | PUBLIC | STATIC | STRUCT | SUBSCRIPT | TYPEALIAS | VAR | ACTOR | BORROWING | CONSUMING | CONVENIENCE | DISTRIBUTED | DYNAMIC | FINAL | INDIRECT | INFIX | LAZY | MACRO | MUTATING | NONISOLATED | NONMUTATING | OPEN | OPTIONAL | OVERRIDE | PACKAGE | POSTFIX | PREFIX | REQUIRED | SPI | UNOWNED | WEAK)
    ;

// The contextual keywords that declare or modify a declaration, each a name where it is not one.
contextualKeyword
    : ACTOR
    | BORROWING
    | CONSUMING
    | CONVENIENCE
    | DISTRIBUTED
    | DYNAMIC
    | FINAL
    | INDIRECT
    | INFIX
    | LAZY
    | MACRO
    | MUTATING
    | NONISOLATED
    | NONMUTATING
    | OPEN
    | OPTIONAL
    | OVERRIDE
    | PACKAGE
    | POSTFIX
    | PREFIX
    | REQUIRED
    | SPI
    | UNOWNED
    | WEAK
    ;

exprPart
    : group
    | ~(NEWLINE | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// Brackets and what they hold, line breaks included, read as runs of tokens: argument and parameter
// clauses, tuples, array and dictionary literals and types, subscripts, closures, and code blocks.
group
    : bracketGroup
    | LBRACE groupItem* RBRACE
    ;

bracketGroup
    : LPAREN groupItem* RPAREN
    | LBRACK groupItem* RBRACK
    ;

groupItem
    : group
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;
