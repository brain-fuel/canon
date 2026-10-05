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

// The Scala parser canon reads Scala with. It is written for canon, from the context-free syntax of
// the Scala 3 reference (https://docs.scala-lang.org/scala3/reference/syntax.html), and parses the
// declarations that carry documentation: packages, imports and exports, objects, package objects,
// classes, case classes, traits, enums and their cases, defs, vals, vars, type aliases, givens, and
// extensions, with their annotations and modifiers, in braces or with optional braces. Bodies,
// expressions, types, and patterns are runs of tokens, kept whole by the INDENT, OUTDENT, and
// NEWLINE tokens the ScalaLexerBase hook emits and by bracket nesting, so the parser finds where
// each declaration ends without typing what is inside it. A statement it cannot read as a
// declaration is read as an expression, as a script's top-level code is. Definitions inside a block,
// such as the locals of a def, are part of the block's run of tokens. See grammars/scala/README.md.
//
// Three labels serve canon: marker on each annotation, so a test is told by its annotation;
// optional on private, protected, and override, so a comment is required only on public members
// that do not inherit their documentation; and inherited on enum cases, which need a comment when
// their enum does.

parser grammar ScalaParser;

options {
    tokenVocab = ScalaLexer;
}

// A file is its top-level statements: package clauses, packagings, imports, exports, definitions,
// extensions, end markers, and expressions.
compilationUnit
    : topStatements EOF
    ;

topStatements
    : separator* (topStatement (separator+ topStatement)*)? separator*
    ;

topStatement
    : packageObject
    | packaging
    | packageClause
    | templateStatement
    ;

separator
    : NEWLINE
    | SEMI
    ;

// package p, which the rest of the file belongs to.
packageClause
    : PACKAGE qualifiedName
    ;

// package p followed by a body of its own, in braces or indented after a colon.
packaging
    : PACKAGE qualifiedName (COLON INDENT topStatements OUTDENT | NEWLINE? LBRACE topStatements RBRACE)
    ;

packageObject
    : definitionPrefix PACKAGE OBJECT definitionName templateHeader templateBody?
    ;

// The statements of a class, trait, object, given, or extension body, after its self type if it
// has one.
templateStatements
    : separator* (selfType separator*)? (templateStatement (separator+ templateStatement)*)? separator*
    ;

// self =>, or this: T =>, which no line break separates from the statement after it.
selfType
    : (identifier | THIS) (COLON typeItem+)? FAT_ARROW
    ;

templateStatement
    : definition
    | extensionDefinition
    | importStatement
    | exportStatement
    | endMarker
    | expressionStatement
    ;

definition
    : classDefinition
    | caseClassDefinition
    | objectDefinition
    | traitDefinition
    | enumDefinition
    | defDefinition
    | valDefinition
    | varDefinition
    | typeDefinition
    | givenDefinition
    ;

importStatement
    : IMPORT soupItem+
    ;

exportStatement
    : EXPORT soupItem+
    ;

// end p, end if, and the other end markers, which close what precedes them.
endMarker
    : END (identifier | OP | IF | WHILE | FOR | MATCH | TRY | NEW | THIS | VAL | GIVEN)
    ;

// A statement that declares nothing, with the blocks indented below it.
expressionStatement
    : soupItem+
    ;

// Annotations, each on its line or before the definition, then modifiers. Each annotation is
// labeled marker, and private, protected, and override are labeled optional.
definitionPrefix
    : (marker = annotation NEWLINE?)* modifier*
    ;

annotation
    : AT qualifiedName (LBRACK groupItem* RBRACK)? (LPAREN groupItem* RPAREN)*
    ;

modifier
    : optional = accessModifier
    | optional = OVERRIDE
    | ABSTRACT
    | FINAL
    | SEALED
    | IMPLICIT
    | LAZY
    | INLINE
    | TRANSPARENT
    | INFIX
    | OPAQUE
    | OPEN
    ;

accessModifier
    : (PRIVATE | PROTECTED) (LBRACK (identifier | THIS) RBRACK)?
    ;

// Classes, traits, and objects: a name, a header of type and value parameters, extends, with, and
// derives clauses, and a body.
classDefinition
    : definitionPrefix CLASS definitionName templateHeader templateBody?
    ;

caseClassDefinition
    : definitionPrefix CASE CLASS definitionName templateHeader templateBody?
    ;

objectDefinition
    : definitionPrefix CASE? OBJECT definitionName templateHeader templateBody?
    ;

traitDefinition
    : definitionPrefix TRAIT definitionName templateHeader templateBody?
    ;

templateHeader
    : headerItem*
    ;

headerItem
    : bracketGroup
    | ~(COLON | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | EQUALS)
    ;

// A body in braces, or indented after a colon, which may also stand alone at the end of a line.
templateBody
    : COLON INDENT templateStatements OUTDENT
    | NEWLINE? LBRACE templateStatements RBRACE
    | COLON
    ;

// An enum: its body holds cases and the statements a class body holds.
enumDefinition
    : definitionPrefix ENUM definitionName templateHeader enumBody?
    ;

enumBody
    : COLON INDENT enumStatements OUTDENT
    | NEWLINE? LBRACE enumStatements RBRACE
    ;

enumStatements
    : separator* (selfType separator*)? (enumStatement (separator+ enumStatement)*)? separator*
    ;

enumStatement
    : inherited = enumCase
    | templateStatement
    ;

// case A(x: Int) extends E, or case A, B, C, named by its first name.
enumCase
    : definitionPrefix CASE definitionName headerItem*
    ;

// def f[T](x: T): T = body, def this(...) = ..., or an abstract def.
defDefinition
    : definitionPrefix DEF (definitionName | THIS) soupItem*
    ;

// val x = ..., val x, y: T = ..., or an abstract val; a val that binds a pattern has no name.
valDefinition
    : definitionPrefix VAL definitionName (COMMA identifier)* (COLON soupItem* | EQUALS soupItem*)?
    | definitionPrefix VAL soupItem+
    ;

varDefinition
    : definitionPrefix VAR definitionName (COMMA identifier)* (COLON soupItem* | EQUALS soupItem*)?
    | definitionPrefix VAR soupItem+
    ;

// type T, type T[A] = ..., type T <: U, opaque type T = ..., and match types.
typeDefinition
    : definitionPrefix TYPE definitionName soupItem*
    ;

// A given is named by its name, given name: T, or else by the type it provides, as in
// given [A](using Ord[A]): Ord[List[A]] with ..., given Ord[Int] = ..., or
// given [A: Ord] => Ord[List[A]]: ...
givenDefinition
    : definitionPrefix GIVEN givenSignature givenBody?
    ;

givenSignature
    : givenName givenParameters* COLON givenConditions? givenType
    | (givenParameters* COLON)? givenConditions? givenType
    ;

givenName
    : identifier
    ;

givenParameters
    : LBRACK groupItem* RBRACK
    | LPAREN groupItem* RPAREN
    ;

givenConditions
    : (typeItem+ (FAT_ARROW | CONTEXT_ARROW))+
    ;

givenType
    : typeItem+
    ;

typeItem
    : bracketGroup
    | ~(COLON | EQUALS | WITH | FAT_ARROW | CONTEXT_ARROW | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI)
    ;

// = expr, or the further parents and the body of a given that defines members.
givenBody
    : EQUALS soupItem*
    | (WITH typeItem+)* (
        WITH (INDENT templateStatements OUTDENT | LBRACE templateStatements RBRACE)?
        | COLON INDENT templateStatements OUTDENT
        | NEWLINE? LBRACE templateStatements RBRACE
    )?
    ;

// extension [T](x: T)(using Ord[T]) with its methods indented below, in braces, or on its line;
// named by the type it extends.
extensionDefinition
    : definitionPrefix EXTENSION extensionHeader extensionBody
    ;

extensionHeader
    : (LBRACK groupItem* RBRACK | usingClause)* extensionParameter usingClause*
    ;

extensionParameter
    : LPAREN annotation* INLINE? identifier COLON extendedType RPAREN
    ;

usingClause
    : LPAREN USING groupItem* RPAREN
    ;

extendedType
    : groupItem+
    ;

extensionBody
    : COLON? INDENT templateStatements OUTDENT
    | NEWLINE? LBRACE templateStatements RBRACE
    | templateStatement
    ;

// The name a definition declares: a name or an operator.
definitionName
    : identifier
    | OP
    ;

qualifiedName
    : identifier (DOT identifier)*
    ;

// A name, a backquoted name, or a soft keyword, which is a name where it is not a keyword.
identifier
    : ID
    | BACKQUOTED_ID
    | AS
    | DERIVES
    | END
    | EXTENSION
    | INFIX
    | INLINE
    | OPAQUE
    | OPEN
    | TRANSPARENT
    | USING
    ;

// A run of tokens on one logical line, with the blocks indented below it.
soupItem
    : group
    | INDENT block OUTDENT
    | ~(NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// The lines of an indented block; a definition in it is local to it and part of its run of tokens.
block
    : separator* soupItem+ (separator+ soupItem+)* separator*
    ;

// Balanced brackets and what they hold, line breaks and indentation included.
group
    : bracketGroup
    | LBRACE groupItem* RBRACE
    ;

// Parentheses or brackets, as a header or a type holds; braces there begin a body.
bracketGroup
    : LPAREN groupItem* RPAREN
    | LBRACK groupItem* RBRACK
    ;

groupItem
    : group
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;
