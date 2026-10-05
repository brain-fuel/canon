/*
 [The "BSD licence"] Copyright (c) 2017 Sasa Coh, Michał Błotniak
 Copyright (c) 2019 Ivan Kochurkin, kvanttt@gmail.com, Positive Technologies
 Copyright (c) 2019 Dmitry Rassadin, flipparassa@gmail.com,Positive Technologies All rights reserved.
 Copyright (c) 2021 Martin Mirchev, mirchevmartin2203@gmail.com
 Copyright (c) 2023 Dmitry Litovchenko, i@dlitovchenko.ru

 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met: 1. Redistributions of source code must retain the
 above copyright notice, this list of conditions and the following disclaimer. 2. Redistributions in
 binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution. 3. The name
 of the author may not be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
 BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * A Go grammar for ANTLR 4 derived from the Go Language Specification https://golang.org/ref/spec
 */

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar GoParser;

// canon: the canonically commented dialect of the Go grammar. A comment the GoLexerBase hook finds
// directly above a declaration is a canonical comment on the default channel; each top-level
// declaration, spec of a grouped declaration, struct field, and interface element is a labeled unit
// alternative with its Why and its What; a doc comment the grammar accepts but binds to nothing is
// an orphan. An exported name, one with an upper-case initial, is labeled required, as revive's
// exported rule asks. Every change from the plain grammar is marked canon: and listed in
// grammars/golang/README.md.

// Insert here @header.

options {
    tokenVocab = GoLexer;
    superClass = GoParserBase;
}

// canon: the doc comment above the package clause is the Why of the file, which go/doc reads as the
// package's documentation; one above an import documents nothing and is an orphan. Only top-level
// declarations are units, so a declaration inside a function body is the plain grammar's.
sourceFile
    : why = canonicalComment? packageClause eos ((orphan = canonicalComment)* importDecl eos)* ((functionDecl | methodDecl | topLevelDeclaration) eos)* EOF
    ;

// canon: a top-level const, type, or var declaration.
topLevelDeclaration
    : topLevelConstDecl
    | topLevelTypeDecl
    | topLevelVarDecl
    ;

// canon: a declared name, labeled required when it is exported.
declaredName
    : {this.isExported()}? required = IDENTIFIER
    | {!this.isExported()}? IDENTIFIER
    ;

// canon: the names of a const or var spec, each labeled required when it is exported, so the spec
// requires a comment when any of its names is exported.
declaredNames
    : declaredName (COMMA declaredName)*
    ;

// canon: a single const declaration is a unit; a grouped one is a unit named by its position whose
// Why is the comment above the group. A comment above the group documents its specs, as revive
// accepts a comment on the block in place of one on each spec, so a spec of a documented group needs
// none; the specs of an undocumented group need one when they are exported.
topLevelConstDecl
    : why = canonicalComment? CONST what = declaredNames (type_? ASSIGN expressionList)? # const
    | why = canonicalComment CONST ordinal = L_PAREN (documentedConstSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    | why = canonicalComment? CONST ordinal = L_PAREN (topLevelConstSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    ;

// canon: a spec of an undocumented const group.
topLevelConstSpec
    : why = canonicalComment? what = declaredNames (type_? ASSIGN expressionList)? # const
    ;

// canon: a spec of a documented const group.
documentedConstSpec
    : why = canonicalComment? what = identifierList (type_? ASSIGN expressionList)? # const
    ;

// canon: type declarations, single and grouped, as const declarations are.
topLevelTypeDecl
    : why = canonicalComment? TYPE what = declaredName typeParameters? ASSIGN? type_ # type
    | why = canonicalComment TYPE ordinal = L_PAREN (documentedTypeSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    | why = canonicalComment? TYPE ordinal = L_PAREN (topLevelTypeSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    ;

// canon: a spec of an undocumented type group.
topLevelTypeSpec
    : why = canonicalComment? what = declaredName typeParameters? ASSIGN? type_ # type
    ;

// canon: a spec of a documented type group.
documentedTypeSpec
    : why = canonicalComment? what = IDENTIFIER typeParameters? ASSIGN? type_ # type
    ;

// canon: var declarations, single and grouped, as const declarations are.
topLevelVarDecl
    : why = canonicalComment? VAR what = declaredNames (type_ (ASSIGN expressionList)? | ASSIGN expressionList) # var
    | why = canonicalComment VAR ordinal = L_PAREN (documentedVarSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    | why = canonicalComment? VAR ordinal = L_PAREN (topLevelVarSpec eos)* (orphan = canonicalComment)* R_PAREN # group
    ;

// canon: a spec of an undocumented var group.
topLevelVarSpec
    : why = canonicalComment? what = declaredNames (type_ (ASSIGN expressionList)? | ASSIGN expressionList) # var
    ;

// canon: a spec of a documented var group.
documentedVarSpec
    : why = canonicalComment? what = identifierList (type_ (ASSIGN expressionList)? | ASSIGN expressionList) # var
    ;

packageClause
    : PACKAGE packageName {this.myreset();}
    ;

packageName
    : identifier
    ;

identifier : IDENTIFIER ;

importDecl
    : IMPORT (importSpec | L_PAREN (importSpec eos)* R_PAREN)
    ;

importSpec
    : (DOT | packageName)? importPath {this.addImportSpec();}
    ;

importPath
    : string_
    ;

declaration
    : constDecl
    | typeDecl
    | varDecl
    ;

constDecl
    : CONST (constSpec | L_PAREN (constSpec eos)* R_PAREN)
    ;

constSpec
    : identifierList (type_? ASSIGN expressionList)?
    ;

identifierList
    : IDENTIFIER (COMMA IDENTIFIER)*
    ;

expressionList
    : expression (COMMA expression)*
    ;

typeDecl
    : TYPE (typeSpec | L_PAREN (typeSpec eos)* R_PAREN)
    ;

typeSpec
    : aliasDecl
    | typeDef
    ;

aliasDecl
    : IDENTIFIER typeParameters? ASSIGN type_
    ;

typeDef
    : IDENTIFIER typeParameters? type_
    ;

typeParameters
    : L_BRACKET typeParameterDecl (COMMA typeParameterDecl)* COMMA? R_BRACKET
    ;

typeParameterDecl
    : identifierList typeElement
    ;

typeElement
    : typeTerm (OR typeTerm)*
    ;

typeTerm
    : UNDERLYING? type_
    ;

// Function declarations

// canon: a function is a unit, required when its name is exported.
functionDecl
    : why = canonicalComment? FUNC what = declaredName typeParameters? signature how = block? # function
    ;

// canon: a method is a unit, required when its name and its receiver's type are exported, as revive
// skips a method whose receiver is unexported. A method may declare type parameters, as the Go
// parser accepts since 2026.
methodDecl
    : why = canonicalComment? FUNC receiver what = declaredName typeParameters? signature how = block? # method
    ;

// canon: a receiver whose base type is unexported is labeled optional, which wins over required.
receiver
    : L_PAREN IDENTIFIER? STAR? receiverType typeArgs? COMMA? R_PAREN
    | parameters
    ;

// canon: the base type of a receiver.
receiverType
    : {this.isExported()}? IDENTIFIER
    | {!this.isExported()}? optional = IDENTIFIER
    ;

varDecl
    : VAR (varSpec | L_PAREN (varSpec eos)* R_PAREN)
    ;

varSpec
    : identifierList (type_ (ASSIGN expressionList)? | ASSIGN expressionList)
    ;

// canon: the statements of a block, and of each clause of a switch or select, are read in the rule
// that holds their braces, which was statementList. A rule ending inside a run of statements built a
// tree for every statement it could end after, so a body of n statements took time in n squared, and
// a generated function of thousands of statements took longer than any timeout. A lone semicolon
// is an empty statement, as in return; ;.
block
    : L_CURLY ((SEMI | EOS | /* {this.closingBracket()}? */ ) statement eos | SEMI)* R_CURLY
    ;

statement
    : declaration
    | labeledStmt
    | simpleStmt
    | goStmt
    | returnStmt
    | breakStmt
    | continueStmt
    | gotoStmt
    | fallthroughStmt
    | block
    | ifStmt
    | switchStmt
    | selectStmt
    | forStmt
    | deferStmt
    ;

simpleStmt
    : sendStmt
    | incDecStmt
    | assignment
    | expressionStmt
    | shortVarDecl
    ;

expressionStmt
    : expression
    ;

sendStmt
    : channel = expression RECEIVE expression
    ;

incDecStmt
    : expression (PLUS_PLUS | MINUS_MINUS)
    ;

assignment
    : expressionList assign_op expressionList
    ;

assign_op
    : (PLUS | MINUS | OR | CARET | STAR | DIV | MOD | LSHIFT | RSHIFT | AMPERSAND | BIT_CLEAR)? ASSIGN
    ;

shortVarDecl
    : identifierList DECLARE_ASSIGN expressionList
    ;

labeledStmt
    : IDENTIFIER COLON statement?
    ;

returnStmt
    : RETURN expressionList?
    ;

breakStmt
    : BREAK IDENTIFIER?
    ;

continueStmt
    : CONTINUE IDENTIFIER?
    ;

gotoStmt
    : GOTO IDENTIFIER
    ;

fallthroughStmt
    : FALLTHROUGH
    ;

deferStmt
    : DEFER expression
    ;

ifStmt
    : IF (expression | (SEMI | EOS) expression | simpleStmt (SEMI | EOS) expression) block (ELSE (ifStmt | block))?
    ;

switchStmt
    : exprSwitchStmt
    | typeSwitchStmt
    ;

exprSwitchStmt
    : SWITCH (expression? | simpleStmt? eos expression?) L_CURLY (exprSwitchCase COLON ((SEMI | EOS | /* {this.closingBracket()}? */ ) statement eos | SEMI)*)* R_CURLY
    ;

exprSwitchCase
    : CASE expressionList
    | DEFAULT
    ;

typeSwitchStmt
    : SWITCH (typeSwitchGuard | eos typeSwitchGuard | simpleStmt eos typeSwitchGuard) L_CURLY (typeSwitchCase COLON ((SEMI | EOS | /* {this.closingBracket()}? */ ) statement eos | SEMI)*)* R_CURLY
    ;

typeSwitchGuard
    : (IDENTIFIER DECLARE_ASSIGN)? primaryExpr DOT L_PAREN TYPE R_PAREN
    ;

typeSwitchCase
    : CASE typeList
    | DEFAULT
    ;

// canon: nil is an identifier, so a case nil is a type name here.
typeList
    : type_ (COMMA type_)*
    ;

selectStmt
    : SELECT L_CURLY (commCase COLON ((SEMI | EOS | /* {this.closingBracket()}? */ ) statement eos | SEMI)*)* R_CURLY
    ;

commCase
    : CASE (sendStmt | recvStmt)
    | DEFAULT
    ;

recvStmt
    : (expressionList ASSIGN | identifierList DECLARE_ASSIGN)? recvExpr = expression
    ;

forStmt
    : FOR (condition | forClause | rangeClause)? block
    ;

condition
    : expression
    ;

forClause
    : initStmt = simpleStmt? eos expression? eos postStmt = simpleStmt?
    ;

rangeClause
    : (expressionList ASSIGN | identifierList DECLARE_ASSIGN)? RANGE expression
    ;

goStmt
    : GO expression
    ;

type_
    : typeName typeArgs?
    | typeLit
    | L_PAREN type_ R_PAREN
    ;

typeArgs
    : L_BRACKET typeList COMMA? R_BRACKET
    ;

typeName
    : qualifiedIdent
    | IDENTIFIER
    ;

typeLit
    : arrayType
    | structType
    | pointerType
    | functionType
    | interfaceType
    | sliceType
    | mapType
    | channelType
    ;

arrayType
    : L_BRACKET arrayLength R_BRACKET elementType
    ;

arrayLength
    : expression
    ;

elementType
    : type_
    ;

pointerType
    : STAR type_
    ;

// canon: a doc comment after the last element of an interface documents nothing and is an orphan.
interfaceType
    : INTERFACE L_CURLY ((methodSpec | interfaceElement) eos)* (orphan = canonicalComment)* R_CURLY
    ;

sliceType
    : L_BRACKET R_BRACKET elementType
    ;

// It's possible to replace `type` with more restricted typeLit list and also pay attention to nil maps
mapType
    : MAP L_BRACKET type_ R_BRACKET elementType
    ;

channelType
    : ({this.isNotReceive()}? CHAN | CHAN RECEIVE | RECEIVE CHAN) elementType
    ;

// canon: an interface method is a unit, whose comment is optional, since revive's exported rule
// does not ask for one.
methodSpec
    : why = canonicalComment? what = IDENTIFIER parameters result? # method
    ;

// canon: an embedded interface or a type union in an interface is a unit named by its text.
interfaceElement
    : why = canonicalComment? what = typeElement # element
    ;

functionType
    : FUNC signature
    ;

signature
    : parameters result?
    ;

result
    : parameters
    | type_
    ;

parameters
    : L_PAREN (parameterDecl (COMMA parameterDecl)* COMMA?)? R_PAREN
    ;

parameterDecl
    : identifierList? ELLIPSIS? type_
    ;

expression
    : primaryExpr
    | unary_op = (PLUS | MINUS | EXCLAMATION | CARET | STAR | AMPERSAND | RECEIVE) expression
    | expression mul_op = (STAR | DIV | MOD | LSHIFT | RSHIFT | AMPERSAND | BIT_CLEAR) expression
    | expression add_op = (PLUS | MINUS | OR | CARET) expression
    | expression rel_op = (
        EQUALS
        | NOT_EQUALS
        | LESS
        | LESS_OR_EQUALS
        | GREATER
        | GREATER_OR_EQUALS
    ) expression
    | expression LOGICAL_AND expression
    | expression LOGICAL_OR expression
    ;

primaryExpr :
    ( {this.isOperand()}? operand
    | {this.isConversion()}? conversion
    | {this.isMethodExpr()}? methodExpr )
    ( DOT IDENTIFIER | index | slice_ | typeAssertion | arguments )*
    ;

conversion
    : type_ L_PAREN expression COMMA? R_PAREN
    ;

// canon: a literal value in braces is an operand whose type is elided, which the Go parser accepts
// since 2026, as in return {"a": {x}}.
operand
    : literal
    | operandName typeArgs?
    | L_PAREN expression R_PAREN
    | literalValue
    ;

literal
    : basicLit
    | compositeLit
    | functionLit
    ;

// canon: nil is an identifier, an operand name.
basicLit
    : integer
    | string_
    | FLOAT_LIT
    ;

integer
    : DECIMAL_LIT
    | BINARY_LIT
    | OCTAL_LIT
    | HEX_LIT
    | IMAGINARY_LIT
    | RUNE_LIT
    ;

operandName
    : IDENTIFIER
    | qualifiedIdent
    ;

qualifiedIdent
    : IDENTIFIER DOT IDENTIFIER
    ;

compositeLit
    : literalType literalValue
    ;

literalType
    : structType
    | arrayType
    | L_BRACKET ELLIPSIS R_BRACKET elementType
    | sliceType
    | mapType
    | typeName typeArgs?
    ;

// canon: the elements are read in the rule that holds their braces, which was elementList, so a
// table of n elements takes time linear in n.
literalValue
    : L_CURLY (keyedElement (COMMA keyedElement)* COMMA?)? R_CURLY
    ;

keyedElement
    : (key COLON)? element
    ;

key
    : expression
    | literalValue
    ;

element
    : expression
    | literalValue
    ;

// canon: a doc comment after the last field of a struct documents nothing and is an orphan.
structType
    : STRUCT L_CURLY (fieldDecl eos)* (orphan = canonicalComment)* R_CURLY
    ;

// canon: a field is a unit whose comment is optional, since revive's exported rule does not ask for
// one; an embedded field is named by its unqualified type name, as the Go specification names it.
fieldDecl
    : why = canonicalComment? (what = identifierList type_ | STAR? (IDENTIFIER DOT)? what = IDENTIFIER typeArgs?) tag = string_? # field
    ;

string_
    : RAW_STRING_LIT
    | INTERPRETED_STRING_LIT
    ;

embeddedField
    : STAR? typeName typeArgs?
    ;

functionLit
    : FUNC signature block
    ; // function

index
    : L_BRACKET expression R_BRACKET
    ;

slice_
    : L_BRACKET (expression? COLON expression? | expression? COLON expression COLON expression) R_BRACKET
    ;

typeAssertion
    : DOT L_PAREN type_ R_PAREN
    ;

// canon: the arguments are read in the rule that holds their parentheses, which was expressionList.
arguments
    : L_PAREN (
        ({this.isTypeArgument()}? type_ (COMMA expression)* | {this.isExpressionArgument()}? expression (COMMA expression)*) ELLIPSIS? COMMA?
    )? R_PAREN
    ;

methodExpr
    : type_ DOT IDENTIFIER
    ;

eos
    : SEMI
    | EOS
    | {this.closingBracket()}?
    ;

// canon: a canonical comment, a Go doc comment, holding prose, reference citations, and license
// citations.
// Comments with no blank line between them are one comment, as go/doc groups them, so a block
// comment followed directly by a line comment is one doc comment.
canonicalComment
    : commentPiece+
    ;

// canon: a line or block comment of a canonical comment. A line comment's close is hidden, so the
// GoParserBase predicate isCommentEnd ends it after its last part: ending after any part, the rule
// built a tree for each, and a package comment of a few thousand lines took a minute to parse.
commentPiece
    : DOC_OPEN docPart* {this.isCommentEnd()}?
    | DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
