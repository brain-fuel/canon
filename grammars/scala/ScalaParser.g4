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


// The Scala parser canon reads Scala with. It is written for canon from the context-free syntax of
// the Scala 3 reference (https://docs.scala-lang.org/scala3/reference/syntax.html), rule by rule
// under the reference's production names in lower camel case (compilationUnit for CompilationUnit,
// templateStat for TemplateStat), with the Scala 3 compiler's parser
// (dotty.tools.dotc.parsing.Parsers, Apache-2.0) as the authority where the two differ; the
// differences are tabled in grammars/scala/README.md. It parses the declarations that carry
// documentation: packages, imports and exports, objects, package objects, classes, case classes,
// traits, enums and their cases, defs, vals, vars, type definitions, givens, and extensions, with
// their annotations and modifiers, in braces or with optional braces, in Scala 3 and in the Scala 2
// forms the compiler still reads. Expressions, types, patterns, and parameter lists are read
// structurally, as runs of tokens kept whole by the INDENT, OUTDENT, and NEWLINE tokens the
// ScalaLexerBase hook emits and by bracket nesting; each rule that does so says so. A statement it
// cannot read as a declaration is read as an expression, as a script's top-level code is.
//
// Three labels serve canon: marker on each annotation, so a test is told by its annotation;
// optional on private, protected, and override, so a comment is required only on public members
// that do not inherit their documentation; and inherited on enum cases, which need a comment when
// their enum does.

parser grammar ScalaParser;

options {
    tokenVocab = ScalaLexer;
}

// CompilationUnit ::= {'package' QualId semi} TopStats. TopStats ::= TopStat {semi TopStat}, where
// a TopStat may be empty, is written out here and in packaging rather than as a rule of its own:
// the parser keeps one tree for every end a rule reaches, and a rule holding a file's or a body's
// statements reaches one end per statement, which made a long file quadratic. Template, enum, and
// block statements are written out where they are enclosed for the same reason.
compilationUnit
    : (packageClause semi+)* topStat? (semi topStat?)* EOF
    ;

// The 'package' QualId of a compilation unit's leading package clauses.
packageClause
    : PACKAGE qualId
    ;

// TopStat ::= Import | Export | {Annotation [nl]} {Modifier} Def | Extension | Packaging
//           | PackageObject | EndMarker. A top-level expression, as a script holds, is read too.
topStat
    : import_
    | export_
    | def_
    | extension
    | packaging
    | packageObject
    | endMarker
    | expr1
    ;

// semi ::= ';' | nl {nl}; the hook emits one NEWLINE per line break that separates statements.
semi
    : NEWLINE
    | SEMI
    ;

// Packaging ::= 'package' QualId :<<< TopStats >>>
packaging
    : PACKAGE qualId (COLON INDENT topStat? (semi topStat?)* OUTDENT | NEWLINE? LBRACE topStat? (semi topStat?)* RBRACE)
    ;

// PackageObject ::= 'package' 'object' ObjectDef, with the annotations a definition may have.
packageObject
    : definitionPrefix PACKAGE OBJECT objectDef
    ;

// Import ::= 'import' ImportExpr {',' ImportExpr}
import_
    : IMPORT importExpr (COMMA importExpr)*
    ;

// Export ::= 'export' ImportExpr {',' ImportExpr}
export_
    : EXPORT importExpr (COMMA importExpr)*
    ;

// ImportExpr, with its selectors and renamings, read as a run of tokens; a Scala 2 _ wildcard and
// => renaming read alike.
importExpr
    : importPart+
    ;

importPart
    : group
    | ~(COMMA | NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// EndMarker ::= 'end' EndMarkerTag
endMarker
    : END endMarkerTag
    ;

// EndMarkerTag ::= id | 'if' | 'while' | 'for' | 'match' | 'try' | 'new' | 'this' | 'given'
//                | 'extension' | 'val', and throw, as the compiler's endMarkerTokens has it.
endMarkerTag
    : id
    | OP
    | IF
    | WHILE
    | FOR
    | MATCH
    | TRY
    | NEW
    | THIS
    | GIVEN
    | VAL
    | THROW
    ;

// TemplateBody ::= :<<< [SelfType] TemplateStat {semi TemplateStat} >>>. A colon at the end of a
// line with nothing indented below it is an empty body, as the compiler reads one before end.
templateBody
    : COLON INDENT (selfType semi?)? templateStat? (semi templateStat?)* OUTDENT
    | NEWLINE? LBRACE (selfType semi?)? templateStat? (semi templateStat?)* RBRACE
    | COLON
    ;

// SelfType ::= id [':' InfixType] '=>' | 'this' ':' InfixType '=>', the type read as a run of
// tokens. No line break separates it from the statement after it, since => cannot end one.
selfType
    : (id | THIS) (COLON typePart+)? FAT_ARROW
    ;

// TemplateStat ::= Import | Export | {Annotation [nl]} {Modifier} Def | Extension | Expr1
//                | EndMarker
templateStat
    : import_
    | export_
    | def_
    | extension
    | endMarker
    | expr1
    ;

// Def ::= 'val' PatDef | 'var' PatDef | 'def' DefDef | 'type' {nl} TypeDef | TmplDef, with the
// {Annotation [nl]} {Modifier} before it. Each alternative is a rule of its own that starts at its
// annotations and modifiers, so a definition's documentation above them belongs to it.
def_
    : valDefinition
    | varDefinition
    | defDefinition
    | typeDefinition
    | tmplDef
    ;

// {Annotation [nl]} {Modifier}, with a line break allowed after a modifier too, as the compiler
// allows. Each annotation is labeled marker.
definitionPrefix
    : (marker = annotation NEWLINE?)* (modifier NEWLINE?)*
    ;

// Annotation ::= '@' SimpleType {ParArgumentExprs}; the type is a qualified name with type
// arguments, and the arguments are read as runs of tokens.
annotation
    : AT qualId (LBRACK groupItem* RBRACK)* (LPAREN groupItem* RPAREN)*
    ;

// Modifier ::= LocalModifier | AccessModifier | 'override' | 'opaque'. Access modifiers and
// override are labeled optional.
modifier
    : localModifier
    | optional = accessModifier
    | optional = OVERRIDE
    | OPAQUE
    ;

// LocalModifier ::= 'abstract' | 'final' | 'sealed' | 'open' | 'implicit' | 'lazy' | 'inline'
//                 | 'transparent' | 'infix'
localModifier
    : ABSTRACT
    | FINAL
    | SEALED
    | OPEN
    | IMPLICIT
    | LAZY
    | INLINE
    | TRANSPARENT
    | INFIX
    ;

// AccessModifier ::= ('private' | 'protected') [AccessQualifier]
accessModifier
    : (PRIVATE | PROTECTED) accessQualifier?
    ;

// AccessQualifier ::= '[' id ']', and [this], which Scala 2 and the compiler read.
accessQualifier
    : LBRACK (id | THIS) RBRACK
    ;

// 'val' PatDef
valDefinition
    : definitionPrefix VAL patDef
    ;

// 'var' PatDef
varDefinition
    : definitionPrefix VAR patDef
    ;

// PatDef ::= ids [':' Type] ['=' Expr] | Pattern2 [':' Type] ['=' Expr]. The first of the ids is the
// definition's name; a Pattern2 binds no one name, and is read with the rest as a run of tokens.
patDef
    : definitionName (COMMA id)* (COLON exprPart* | EQUALS exprPart*)?
    | exprPart+
    ;

// 'def' DefDef
defDefinition
    : definitionPrefix DEF defDef
    ;

// DefDef ::= DefSig [':' Type] ['=' Expr] | 'this' ConstrParamClauses [DefImplicitClause] '='
// ConstrExpr: the name, or this, then the signature and body as a run of tokens, Scala 2's
// procedure syntax def f() { ... } included.
defDef
    : (definitionName | THIS) exprPart*
    ;

// 'type' {nl} TypeDef
typeDefinition
    : definitionPrefix TYPE NEWLINE* typeDef
    ;

// TypeDef ::= id [HkTypeParamClause] {FunParamClause} TypeBounds ['=' Type]: the name, then the
// rest as a run of tokens, a match type's indented cases and Scala 2's forSome included.
typeDef
    : definitionName exprPart*
    ;

// TmplDef ::= ([case] 'class' | 'trait') ClassDef | [case] 'object' ObjectDef | 'enum' EnumDef
//           | 'given' (GivenDef | OldGivenDef)
tmplDef
    : classDefinition
    | caseClassDefinition
    | traitDefinition
    | objectDefinition
    | enumDefinition
    | givenDefinition
    ;

classDefinition
    : definitionPrefix CLASS classDef
    ;

caseClassDefinition
    : definitionPrefix CASE CLASS classDef
    ;

traitDefinition
    : definitionPrefix TRAIT classDef
    ;

objectDefinition
    : definitionPrefix CASE? OBJECT objectDef
    ;

enumDefinition
    : definitionPrefix ENUM enumDef
    ;

givenDefinition
    : definitionPrefix GIVEN givenDef
    ;

// ClassDef ::= id ClassConstr [Template], Template ::= InheritClauses [TemplateBody]. ClassConstr
// and InheritClauses are read as a run of header tokens.
classDef
    : definitionName templateHeader templateBody?
    ;

// ObjectDef ::= id [Template]
objectDef
    : definitionName templateHeader templateBody?
    ;

// EnumDef ::= id ClassConstr InheritClauses EnumBody
enumDef
    : definitionName templateHeader enumBody?
    ;

// ClassConstr and InheritClauses: type and value parameters, constructor annotations and access,
// extends, with, and derives clauses, read as a run of tokens up to the body.
templateHeader
    : headerPart*
    ;

headerPart
    : bracketGroup
    | ~(COLON | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | EQUALS)
    ;

// EnumBody ::= :<<< [SelfType] EnumStat {semi EnumStat} >>>
enumBody
    : COLON INDENT (selfType semi?)? enumStat? (semi enumStat?)* OUTDENT
    | NEWLINE? LBRACE (selfType semi?)? enumStat? (semi enumStat?)* RBRACE
    ;

// EnumStat ::= TemplateStat | {Annotation [nl]} {Modifier} EnumCase. A case is labeled inherited.
enumStat
    : inherited = enumCase
    | templateStat
    ;

// EnumCase ::= 'case' (id ClassConstr ['extends' ConstrApps] | ids), with its annotations and
// modifiers, named by its first id; the rest is read as a run of tokens.
enumCase
    : definitionPrefix CASE definitionName headerPart*
    ;

// GivenDef ::= [id ':'] GivenSig, and OldGivenDef ::= [OldGivenSig] (AnnotType ['=' Expr] |
// StructuralInstance), the syntax up to Scala 3.5. A given is named by its id, or else by the type
// it provides.
givenDef
    : (givenName COLON)? givenSig
    | oldGivenSig? givenType givenRest?
    ;

givenName
    : id
    ;

// GivenSig ::= GivenImpl | '(' ')' '=>' GivenImpl | GivenConditional '=>' GivenSig
givenSig
    : (givenConditional (FAT_ARROW | CONTEXT_ARROW))* givenImpl
    ;

// GivenConditional ::= DefTypeParamClause | DefTermParamClause | '(' FunArgTypes ')' | GivenType,
// read as a run of type tokens.
givenConditional
    : typePart+
    ;

// GivenImpl ::= GivenType (['=' Expr] | TemplateBody) | ConstrApps TemplateBody
givenImpl
    : givenType givenRest?
    ;

// GivenType ::= AnnotType1 {id [nl] AnnotType1}, read as a run of type tokens.
givenType
    : typePart+
    ;

// OldGivenSig ::= [id] [DefTypeParamClause] {UsingParamClause} ':'
oldGivenSig
    : givenName? givenParameters* COLON
    ;

givenParameters
    : LBRACK groupItem* RBRACK
    | LPAREN groupItem* RPAREN
    ;

// '=' Expr, a TemplateBody, or StructuralInstance's {'with' ConstrApp} ['with' WithTemplateBody].
givenRest
    : EQUALS exprPart*
    | (WITH typePart+)* (WITH withTemplateBody? | templateBody)
    ;

// WithTemplateBody ::= <<< [SelfType] TemplateStat {semi TemplateStat} >>>
withTemplateBody
    : INDENT (selfType semi?)? templateStat? (semi templateStat?)* OUTDENT
    | LBRACE (selfType semi?)? templateStat? (semi templateStat?)* RBRACE
    ;

// A type in a given, read as a run of tokens up to its =, with, colon, arrow, or body.
typePart
    : bracketGroup
    | ~(COLON | EQUALS | WITH | FAT_ARROW | CONTEXT_ARROW | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI)
    ;

// Extension ::= 'extension' [DefTypeParamClause] {UsingParamClause} '(' DefTermParam ')'
// {UsingParamClause} ExtMethods. It is named by the type it extends.
extension
    : EXTENSION (LBRACK groupItem* RBRACK | usingParamClause)* LPAREN defTermParam RPAREN usingParamClause* extMethods
    ;

// UsingParamClause ::= [nl] '(' 'using' (DefTermParams | FunArgTypes) ')', read as a run of tokens.
usingParamClause
    : LPAREN USING groupItem* RPAREN
    ;

// DefTermParam ::= {Annotation} ['inline'] Param, Param ::= id ':' ParamType ['=' Expr]
defTermParam
    : annotation* INLINE? id COLON paramType
    ;

// ParamType ::= [‘=>’] ParamValueType, read as a run of tokens.
paramType
    : groupItem+
    ;

// ExtMethods ::= ExtMethod | [nl] <<< ExtMethod {semi ExtMethod} >>>, an end marker among them
// as the compiler allows.
extMethods
    : extMethod
    | INDENT extMethod? (semi extMethod?)* OUTDENT
    | NEWLINE? LBRACE extMethod? (semi extMethod?)* RBRACE
    ;

// ExtMethod ::= {Annotation [nl]} {Modifier} 'def' DefDef | Export
extMethod
    : defDefinition
    | export_
    | endMarker
    ;

// The name a definition declares: an id, an operator, or a backquoted name.
definitionName
    : id
    | OP
    ;

// QualId ::= id {'.' id}
qualId
    : id (DOT id)*
    ;

// id: a name, a backquoted name, or a soft keyword, which is a name where it is not a keyword.
id
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

// Expr1, a statement that declares nothing, read as a run of tokens with the blocks indented below
// it.
expr1
    : exprPart+
    ;

// A token of an expression, a bracketed group, or an indented Block ::= {BlockStat semi}
// [BlockResult].
exprPart
    : group
    | INDENT blockStat? (semi blockStat?)* OUTDENT
    | ~(NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE)
    ;

// BlockStat: a local definition, import, extension, expression, or end marker, read as a run of
// tokens, so a local definition is no unit.
blockStat
    : exprPart+
    ;

// Brackets and what they hold, line breaks and indentation included, read as runs of tokens: a
// BlockExpr, arguments, parameters, type arguments, refinements, and import selectors.
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
