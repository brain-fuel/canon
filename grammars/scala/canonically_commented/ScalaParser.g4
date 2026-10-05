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
// The plain grammar is the Scala parser canon reads Scala with. It is written for canon from the context-free syntax of
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
// canon: a Scaladoc comment above a package clause, at the end of a body, or at the end of the file
// binds to nothing.
compilationUnit
    : ((orphan = canonicalComment)* packageClause semi+)* topStat? (semi topStat?)* (orphan = canonicalComment)* EOF
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
// canon: a Scaladoc comment above it binds to nothing.
packaging
    : (orphan = canonicalComment)* PACKAGE qualId (COLON INDENT topStat? (semi topStat?)* (orphan = canonicalComment)* OUTDENT | NEWLINE? LBRACE topStat? (semi topStat?)* (orphan = canonicalComment)* RBRACE)
    ;

// PackageObject ::= 'package' 'object' ObjectDef, with the annotations a definition may have.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
packageObject
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix PACKAGE OBJECT objectDef # object
    ;

// Import ::= 'import' ImportExpr {',' ImportExpr}
// canon: a Scaladoc comment above it binds to nothing.
import_
    : (orphan = canonicalComment)* IMPORT importExpr (COMMA importExpr)*
    ;

// Export ::= 'export' ImportExpr {',' ImportExpr}
// canon: a Scaladoc comment above it binds to nothing.
export_
    : (orphan = canonicalComment)* EXPORT importExpr (COMMA importExpr)*
    ;

// ImportExpr, with its selectors and renamings, read as a run of tokens; a Scala 2 _ wildcard and
// => renaming read alike.
importExpr
    : importPart+
    ;

importPart
    : group
    | orphan = canonicalComment
    | ~(COMMA | NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// EndMarker ::= 'end' EndMarkerTag
// canon: a Scaladoc comment above it binds to nothing.
endMarker
    : (orphan = canonicalComment)* END endMarkerTag
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
    : COLON INDENT (selfType semi?)? templateStat? (semi templateStat?)* (orphan = canonicalComment)* OUTDENT
    | NEWLINE? LBRACE (selfType semi?)? templateStat? (semi templateStat?)* (orphan = canonicalComment)* RBRACE
    | COLON
    ;

// SelfType ::= id [':' InfixType] '=>' | 'this' ':' InfixType '=>', the type read as a run of
// tokens. No line break separates it from the statement after it, since => cannot end one.
// canon: a Scaladoc comment above it binds to nothing.
selfType
    : (orphan = canonicalComment)* (id | THIS) (COLON typePart+)? FAT_ARROW
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
// canon: a Scaladoc comment after an annotation or a modifier binds to nothing.
definitionPrefix
    : (marker = annotation NEWLINE? (orphan = canonicalComment)*)* (modifier NEWLINE? (orphan = canonicalComment)*)*
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
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
valDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAL patDef # val
    ;

// 'var' PatDef
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
varDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAR patDef # var
    ;

// PatDef ::= ids [':' Type] ['=' Expr] | Pattern2 [':' Type] ['=' Expr]. The first of the ids is the
// definition's name; a Pattern2 binds no one name, and is read with the rest as a run of tokens.
// canon: the first id is the What; a Pattern2 binds no name, so a val or var holding one is no unit.
patDef
    : what = definitionName (COMMA id)* (COLON exprPart* | EQUALS exprPart*)?
    | exprPart+
    ;

// 'def' DefDef
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
defDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix DEF defDef # def
    ;

// DefDef ::= DefSig [':' Type] ['=' Expr] | 'this' ConstrParamClauses [DefImplicitClause] '='
// ConstrExpr: the name, or this, then the signature and body as a run of tokens, Scala 2's
// procedure syntax def f() { ... } included.
// canon: the name, or this, is the What.
defDef
    : (what = definitionName | what = THIS) exprPart*
    ;

// 'type' {nl} TypeDef
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
typeDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TYPE NEWLINE* typeDef # type
    ;

// TypeDef ::= id [HkTypeParamClause] {FunParamClause} TypeBounds ['=' Type]: the name, then the
// rest as a run of tokens, a match type's indented cases and Scala 2's forSome included.
// canon: the name is the What.
typeDef
    : what = definitionName exprPart*
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

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
classDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CLASS classDef # class
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
caseClassDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE CLASS classDef # case_class
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
traitDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TRAIT classDef # trait
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
objectDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE? OBJECT objectDef # object
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
enumDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix ENUM enumDef # enum
    ;

// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers.
givenDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix GIVEN givenDef # given
    ;

// ClassDef ::= id ClassConstr [Template], Template ::= InheritClauses [TemplateBody]. ClassConstr
// and InheritClauses are read as a run of header tokens.
// canon: the name is the What.
classDef
    : what = definitionName templateHeader templateBody?
    ;

// ObjectDef ::= id [Template]
// canon: the name is the What.
objectDef
    : what = definitionName templateHeader templateBody?
    ;

// EnumDef ::= id ClassConstr InheritClauses EnumBody
// canon: the name is the What.
enumDef
    : what = definitionName templateHeader enumBody?
    ;

// ClassConstr and InheritClauses: type and value parameters, constructor annotations and access,
// extends, with, and derives clauses, read as a run of tokens up to the body.
templateHeader
    : headerPart*
    ;

// canon: headers, types, imports, expressions, and brackets may hold a Scaladoc comment, which binds
// to nothing.
headerPart
    : bracketGroup
    | orphan = canonicalComment
    | ~(COLON | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | EQUALS | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// EnumBody ::= :<<< [SelfType] EnumStat {semi EnumStat} >>>
enumBody
    : COLON INDENT (selfType semi?)? enumStat? (semi enumStat?)* (orphan = canonicalComment)* OUTDENT
    | NEWLINE? LBRACE (selfType semi?)? enumStat? (semi enumStat?)* (orphan = canonicalComment)* RBRACE
    ;

// EnumStat ::= TemplateStat | {Annotation [nl]} {Modifier} EnumCase. A case is labeled inherited.
enumStat
    : inherited = enumCase
    | templateStat
    ;

// EnumCase ::= 'case' (id ClassConstr ['extends' ConstrApps] | ids), with its annotations and
// modifiers, named by its first id; the rest is read as a run of tokens.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; a case holds no publicByDefault, since it is labeled inherited.
enumCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) definitionPrefix CASE what = definitionName headerPart* # case
    ;

// GivenDef ::= [id ':'] GivenSig, and OldGivenDef ::= [OldGivenSig] (AnnotType ['=' Expr] |
// StructuralInstance), the syntax up to Scala 3.5. A given is named by its id, or else by the type
// it provides.
// canon: a given's What is its name, or else the type it provides.
givenDef
    : (what = givenName COLON)? givenSig
    | oldGivenSig? what = givenType givenRest?
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
    : what = givenType givenRest?
    ;

// GivenType ::= AnnotType1 {id [nl] AnnotType1}, read as a run of type tokens.
givenType
    : typePart+
    ;

// OldGivenSig ::= [id] [DefTypeParamClause] {UsingParamClause} ':'
oldGivenSig
    : (what = givenName)? givenParameters* COLON
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
    : INDENT (selfType semi?)? templateStat? (semi templateStat?)* (orphan = canonicalComment)* OUTDENT
    | LBRACE (selfType semi?)? templateStat? (semi templateStat?)* (orphan = canonicalComment)* RBRACE
    ;

// A type in a given, read as a run of tokens up to its =, with, colon, arrow, or body.
typePart
    : bracketGroup
    | orphan = canonicalComment
    | ~(COLON | EQUALS | WITH | FAT_ARROW | CONTEXT_ARROW | LBRACE | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | NEWLINE | INDENT | OUTDENT | SEMI | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// Extension ::= 'extension' [DefTypeParamClause] {UsingParamClause} '(' DefTermParam ')'
// {UsingParamClause} ExtMethods. It is named by the type it extends.
// canon: a labeled unit alternative whose Why is the Scaladoc comment above its annotations and
// modifiers; its comment is optional, since its methods are units of their own.
extension
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) EXTENSION (LBRACK groupItem* RBRACK | usingParamClause)* LPAREN defTermParam RPAREN usingParamClause* extMethods # extension
    ;

// UsingParamClause ::= [nl] '(' 'using' (DefTermParams | FunArgTypes) ')', read as a run of tokens.
usingParamClause
    : LPAREN USING groupItem* RPAREN
    ;

// DefTermParam ::= {Annotation} ['inline'] Param, Param ::= id ':' ParamType ['=' Expr]
// canon: an extension's What is the type it extends.
defTermParam
    : annotation* INLINE? id COLON what = paramType
    ;

// ParamType ::= [‘=>’] ParamValueType, read as a run of tokens.
paramType
    : groupItem+
    ;

// ExtMethods ::= ExtMethod | [nl] <<< ExtMethod {semi ExtMethod} >>>, an end marker among them
// as the compiler allows.
extMethods
    : extMethod
    | INDENT extMethod? (semi extMethod?)* (orphan = canonicalComment)* OUTDENT
    | NEWLINE? LBRACE extMethod? (semi extMethod?)* (orphan = canonicalComment)* RBRACE
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
// canon: a Scaladoc comment above it binds to nothing.
expr1
    : (orphan = canonicalComment)* exprPart+
    ;

// A token of an expression, a bracketed group, or an indented Block ::= {BlockStat semi}
// [BlockResult].
exprPart
    : group
    | INDENT blockStat? (semi blockStat?)* (orphan = canonicalComment)* OUTDENT
    | orphan = canonicalComment
    | ~(NEWLINE | INDENT | OUTDENT | SEMI | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | DOC_OPEN | DOC_CLOSE | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
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
