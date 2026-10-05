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

// The canonically commented dialect of the Scala parser canon reads Scala with. Scaladoc comments
// are canonical comments, which the lexer hook places right before the code token they precede;
// each definition is a labeled unit alternative with its Why above its annotations and modifiers
// and its What; a Scaladoc comment the grammar accepts but binds to nothing, as after an annotation,
// above a statement, or inside an expression, is an orphan. Every change from the plain grammar is
// marked canon: and listed in grammars/scala/README.md.
//
// The plain grammar is the Scala parser canon reads Scala with. It is written for canon, from the context-free syntax of
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
// canon: a Scaladoc comment at the end of the file binds to nothing.
compilationUnit
    : topStatements (orphan = canonicalComment)* EOF
    ;

// canon: a Scaladoc comment at the end of a body binds to nothing.
topStatements
    : separator* (topStatement (separator+ topStatement)*)? separator* (orphan = canonicalComment)*
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
// canon: a Scaladoc comment above a package clause, a packaging, an import, an export, an end
// marker, or an expression statement binds to nothing.
packageClause
    : (orphan = canonicalComment)* PACKAGE qualifiedName
    ;

// package p followed by a body of its own, in braces or indented after a colon.
packaging
    : (orphan = canonicalComment)* PACKAGE qualifiedName (COLON INDENT topStatements OUTDENT | NEWLINE? LBRACE topStatements RBRACE)
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
packageObject
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix PACKAGE OBJECT what = definitionName templateHeader templateBody? # object
    ;

// The statements of a class, trait, object, given, or extension body, after its self type if it
// has one.
// canon: a Scaladoc comment at the end of a body binds to nothing.
templateStatements
    : separator* (selfType separator*)? (templateStatement (separator+ templateStatement)*)? separator* (orphan = canonicalComment)*
    ;

// self =>, or this: T =>, which no line break separates from the statement after it.
selfType
    : (orphan = canonicalComment)* (identifier | THIS) (COLON typeItem+)? FAT_ARROW
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
    : (orphan = canonicalComment)* IMPORT soupItem+
    ;

exportStatement
    : (orphan = canonicalComment)* EXPORT soupItem+
    ;

// end p, end if, and the other end markers, which close what precedes them.
endMarker
    : (orphan = canonicalComment)* END (identifier | OP | IF | WHILE | FOR | MATCH | TRY | NEW | THIS | VAL | GIVEN)
    ;

// A statement that declares nothing, with the blocks indented below it.
expressionStatement
    : (orphan = canonicalComment)* soupItem+
    ;

// Annotations, each on its line or before the definition, then modifiers. Each annotation is
// labeled marker, and private, protected, and override are labeled optional.
// canon: a Scaladoc comment after an annotation or a modifier binds to nothing.
definitionPrefix
    : (marker = annotation NEWLINE? (orphan = canonicalComment)*)* (modifier (orphan = canonicalComment)*)*
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
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
classDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CLASS what = definitionName templateHeader templateBody? # class
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
caseClassDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE CLASS what = definitionName templateHeader templateBody? # case_class
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
objectDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE? OBJECT what = definitionName templateHeader templateBody? # object
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
traitDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TRAIT what = definitionName templateHeader templateBody? # trait
    ;

templateHeader
    : headerItem*
    ;

// canon: headers, types, and brackets may hold a Scaladoc comment, which binds to nothing.
headerItem
    : bracketGroup
    | orphan = canonicalComment
    | ~(COLON | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | EQUALS | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// A body in braces, or indented after a colon, which may also stand alone at the end of a line.
templateBody
    : COLON INDENT templateStatements OUTDENT
    | NEWLINE? LBRACE templateStatements RBRACE
    | COLON
    ;

// An enum: its body holds cases and the statements a class body holds.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
enumDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix ENUM what = definitionName templateHeader enumBody? # enum
    ;

enumBody
    : COLON INDENT enumStatements OUTDENT
    | NEWLINE? LBRACE enumStatements RBRACE
    ;

// canon: a Scaladoc comment at the end of a body binds to nothing.
enumStatements
    : separator* (selfType separator*)? (enumStatement (separator+ enumStatement)*)? separator* (orphan = canonicalComment)*
    ;

enumStatement
    : inherited = enumCase
    | templateStatement
    ;

// case A(x: Int) extends E, or case A, B, C, named by its first name.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; a case holds no publicByDefault, since it is labeled inherited.
enumCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) definitionPrefix CASE what = definitionName headerItem* # case
    ;

// def f[T](x: T): T = body, def this(...) = ..., or an abstract def.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
defDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix DEF (what = definitionName | what = THIS) soupItem* # def
    ;

// val x = ..., val x, y: T = ..., or an abstract val; a val that binds a pattern has no name.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; one that binds a pattern has no name and is no unit.
valDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAL what = definitionName (COMMA identifier)* (COLON soupItem* | EQUALS soupItem*)? # val
    | (orphan = canonicalComment)* definitionPrefix VAL soupItem+
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; one that binds a pattern has no name and is no unit.
varDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAR what = definitionName (COMMA identifier)* (COLON soupItem* | EQUALS soupItem*)? # var
    | (orphan = canonicalComment)* definitionPrefix VAR soupItem+
    ;

// type T, type T[A] = ..., type T <: U, opaque type T = ..., and match types.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
typeDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TYPE what = definitionName soupItem* # type
    ;

// A given is named by its name, given name: T, or else by the type it provides, as in
// given [A](using Ord[A]): Ord[List[A]] with ..., given Ord[Int] = ..., or
// given [A: Ord] => Ord[List[A]]: ...
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
givenDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix GIVEN givenSignature givenBody? # given
    ;

// canon: a given's What is its name, or else the type it provides.
givenSignature
    : what = givenName givenParameters* COLON givenConditions? givenType
    | (givenParameters* COLON)? givenConditions? what = givenType
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
    | orphan = canonicalComment
    | ~(COLON | EQUALS | WITH | FAT_ARROW | CONTEXT_ARROW | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
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
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; its comment is optional, since its methods are units of their own.
extensionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) definitionPrefix EXTENSION extensionHeader extensionBody # extension
    ;

extensionHeader
    : (LBRACK groupItem* RBRACK | usingClause)* extensionParameter usingClause*
    ;

// canon: an extension's What is the type it extends.
extensionParameter
    : LPAREN annotation* INLINE? identifier COLON what = extendedType RPAREN
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
// canon: a Scaladoc comment inside an expression binds to nothing.
soupItem
    : group
    | INDENT block OUTDENT
    | orphan = canonicalComment
    | ~(NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
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
    | orphan = canonicalComment
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// canon: an empty rule labeled required, which a definition holds so it needs a comment unless an
// element labeled optional, private, protected, or override, says otherwise.
publicByDefault
    :
    ;

// canon: a Scaladoc comment and its parts.
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE
    ;

docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
