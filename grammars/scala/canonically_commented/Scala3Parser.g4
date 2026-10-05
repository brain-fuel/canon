// canon: the canonically commented dialect of the Scala 3 parser. Scaladoc comments are canonical
// comments, which the lexer hook places right before the definition they document; each definition
// is a labeled unit alternative with its Why, its What, and its How; a Scaladoc comment the grammar
// accepts but binds to nothing, after an annotation or before a statement, is an orphan. Every change
// from the plain grammar is marked canon: and listed in grammars/scala/README.md.
//
// The plain parser grammar is from antlr/grammars-v4 at commit
// 7df52be94698550d219d299d04105c6bafadd9c3 (scala/scala3), which carries no license header of its
// own; see grammars/scala/README.md. canon interprets it with the Scala3LexerBase port in
// src/Canon/Antlr4/Lex/Scala.hs, and every change from upstream is marked canon:.
/*
 * Scala 3 Parser Grammar
 * Based on https://docs.scala-lang.org/scala3/reference/syntax.html
 *
 * Design notes:
 *   - Handles both brace-delimited and indentation-sensitive Scala 3.
 *   - INDENT/DEDENT are injected by Scala3LexerBase; NEWLINE tokens are kept
 *     on the default channel at statement boundaries (mirroring Dotty's virtual
 *     NEWLINE token) rather than suppressed to the hidden channel.
 *   - end_of_stat : NEWLINE+ | SEMI ; handles both surfaced newlines and ';'.
 *   - Contextual keywords (as, open, infix, transparent, inline, opaque,
 *     derives, end, extension, using) are lexer keywords here for simplicity.
 *   - Left-recursive rules (simpleType, simpleExpr, infixType, infixExpr,
 *     simplePattern1, singleton) use ANTLR4's built-in left-recursion rewrite.
 */

parser grammar Scala3Parser;

options { tokenVocab = Scala3Lexer; superClass = Scala3ParserBase; }

// =====================================================================
// Top-level
// =====================================================================

colonTripleOpen: COLON? (INDENT | '{' INDENT?);
tripleOpen: INDENT | '{' | '{' INDENT;
tripleClose: DEDENT '}' | DEDENT | '}';
indent: INDENT;
outdent: DEDENT;
// Statement separator: NEWLINE kept on default channel or real ';'.
end_of_stat : NEWLINE+ | SEMI ;

// canon: a Scaladoc comment before a package clause or at the end of the file binds to nothing.
compilationUnit
    : ((orphan = canonicalComment)* PACKAGE qualId end_of_stat?)* topStats (orphan = canonicalComment)* EOF
    ;

topStats
    : topStat (end_of_stat topStat)*
    ;

// canon: a Scaladoc comment before an import, an export, a package block, or an end marker binds
// to nothing.
topStat
    : (orphan = canonicalComment)* importDecl
    | (orphan = canonicalComment)* exportDecl
    | definition   // canon: a definition carries its annotations and modifiers
    | extension_
    | (orphan = canonicalComment)* packaging
    | packageObject
    | (orphan = canonicalComment)* endMarker
    ;

packaging
    : PACKAGE qualId (COLON | ) colonTripleOpen topStats? tripleClose
    ;

// canon: a package object is a unit, an object.
packageObject
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault PACKAGE OBJECT how = objectDef # object
    ;

// canon: each kind of definition is a rule of its own that starts at the definition's first
// annotation or modifier, so the Scaladoc comment above them binds to it and the kind names the
// unit. An annotation may stand on a line of its own, which the lexer hook separates with a NEWLINE.
// Annotations are labeled marker, for test recognition, and private, protected, and override are
// labeled optional, since Scaladoc documents the public members and an override inherits the
// documentation of what it overrides.
definition
    : valDefinition
    | varDefinition
    | defDefinition
    | typeDefinition
    | classDefinition
    | caseClassDefinition
    | objectDefinition
    | traitDefinition
    | enumDefinition
    | givenDefinition
    ;

// canon: a Scaladoc comment after an annotation or a modifier binds to nothing, as scaladoc reads
// only the comment above them.
definitionPrefix
    : (marker = annotation NEWLINE? | orphan = canonicalComment)* (definitionModifier | orphan = canonicalComment)*
    ;

definitionModifier
    : localModifier
    | optional = PRIVATE accessQualifier?
    | optional = PROTECTED accessQualifier?
    | optional = OVERRIDE
    | OPAQUE
    ;

// canon: each definition is a unit whose Why is the Scaladoc comment above its annotations and
// modifiers. A definition is public unless it says otherwise, so each holds publicByDefault, labeled
// required, and definitionModifier labels private, protected, and override optional, which wins.
valDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAL how = patDef # val ;
varDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix VAR how = patDef # var ;
defDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix DEF how = defDef # def ;
typeDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TYPE what = definitionName hkTypeParamClause? defParamClauses* typeBounds (ASSIGN how = typeRhs)? # type ;
classDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CLASS how = classDef # class ;
caseClassDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE CLASS how = classDef # case_class ;
objectDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix CASE? OBJECT how = objectDef # object ;
traitDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix TRAIT how = classDef # trait ;
enumDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix ENUM how = enumDef # enum ;
givenDefinition : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault definitionPrefix GIVEN (how = givenDef | how = oldGivenDef) # given ;

// canon: an empty rule that marks a definition public by default; definitionModifier's optional
// labels lift the requirement from a private, protected, or overriding one.
publicByDefault
    : 
    ;

// canon: the name a definition declares, so a unit is named by it rather than by an identifier in
// its annotations.
definitionName
    : id
    ;

// canon: the name of a named given; an anonymous given is named by its givenType.
givenName
    : id
    ;

// canon: a type alias's right-hand side may start on the next line, indented.
typeRhs
    : type_
    | INDENT type_ end_of_stat? DEDENT
    ;

// =====================================================================
// End markers
// =====================================================================

endMarker
    : END endMarkerTag
    ;

endMarkerTag
    : id
    | IF | WHILE | FOR | MATCH | TRY | NEW | THIS | GIVEN | EXTENSION | VAL
    ;

// =====================================================================
// Imports and exports
// =====================================================================

importDecl
    : IMPORT importExpr (COMMA importExpr)*
    ;

exportDecl
    : EXPORT importExpr (COMMA importExpr)*
    ;

importExpr
    : simpleRef (DOT id)* DOT importSpec
    | simpleRef AS id
    ;

importSpec
    : namedSelector
    | wildCardSelector
    | LBRACE importSelectors RBRACE
    ;

namedSelector
    : id (AS (id | USCORE))?
    ;

// wildcard: '*', '_' (--3.0-migration), or 'given [Type]'
wildCardSelector
    : Op                               // the '*' operator
    | {migration30()}? USCORE          // '_' Scala 2-style wildcard (--3.0-migration)
    | GIVEN infixType?
    ;

importSelectors
    : namedSelector (COMMA importSelectors)?
    | wildCardSelector (COMMA wildCardSelector)*
    ;

// =====================================================================
// References and qualified names
// =====================================================================

simpleRef
    : id
    | (id DOT)? THIS
    | (id DOT)? SUPER classQualifier? DOT id
    ;

qualId
    : id (DOT id)*
    ;

ids
    : id (COMMA id)*
    ;

classQualifier
    : LBRACKET id RBRACKET
    ;

// =====================================================================
// Literals
// =====================================================================

simpleLiteral
    : negation? IntegerLiteral
    | negation? FloatingPointLiteral
    | BooleanLiteral
    | CharacterLiteral
    | StringLiteral
    ;

// '-' prefix for negative literals; Op matches '-'
negation
    : Op   // must be '-'
    ;

literal
    : simpleLiteral
    | InterpolatedStringLiteral
    | SymbolLiteral
    | NullLiteral
    ;

// =====================================================================
// Types
// =====================================================================

type_
    : funType
    | typTypeParamClause TLARROW type_       // [T] =>> F[T]
    | matchType_
    | infixType
    ;

funType
    : funTypeArgs (ARROW | CTXARROW) type_
    | typTypeParamClause ARROW type_
    ;

funTypeArgs
    : infixType
    | LPAREN funArgTypes? RPAREN
    | funParamClause
    ;

funParamClause
    : LPAREN typedFunParam (COMMA typedFunParam)* RPAREN
    ;

typedFunParam
    : id COLON type_
    ;

matchType_
    : infixType MATCH tripleOpen typeCaseClauses tripleClose
    ;

infixType
    : refinedType
    | infixType id refinedType
    ;

refinedType
    : annotType refinement*
    ;

annotType
    : simpleType_ annotation*
    ;

simpleType_
    : simpleLiteral                                              // literal type
    | QUESTION typeBounds                                        // wildcard type  ?
    | {migration30()}? USCORE typeBounds?                        // wildcard type  _ (--3.0-migration)
    | singleton DOT TYPE                                         // singleton type
    | singleton DOT id                                           // type selection on singleton
    | id                                                         // type name
    | LPAREN RPAREN                                              // unit type ()
    | LPAREN types RPAREN                                        // tuple type
    | LPAREN nameAndType (COMMA nameAndType)* RPAREN             // named tuple type
    | refinement                                                 // structural type
    | simpleType_ typeArgs                                       // applied type
    | simpleType_ HASH id                                        // type projection
    ;

singleton
    : simpleRef
    | simpleLiteral
    | singleton DOT id
    ;

nameAndType
    : id COLON type_
    ;

funArgType
    : type_
    | ARROW type_
    ;

funArgTypes
    : funArgType (COMMA funArgType)*
    ;

paramType
    : ARROW? paramValueType
    ;

paramValueType
    : type_ Op?    // Op for vararg '*'
    ;

typeArgs
    : LBRACKET types RBRACKET
    ;

refinement
    : colonTripleOpen (refineDcl (end_of_stat refineDcl)*)? tripleClose
    ;

typeBounds
    : (SUPERTYPE type_)? (SUBTYPE type_)?
    ;

typeAndCtxBounds
    : typeBounds (COLON contextBounds)?
    ;

contextBounds
    : contextBound (COLON contextBound)*
    | LBRACE contextBound (COMMA contextBound)* RBRACE
    ;

contextBound
    : type_ (AS id)?
    ;

types
    : type_ (COMMA type_)*
    ;

typeCaseClauses
    : typeCaseClause+
    ;

typeCaseClause
    : CASE (infixType | USCORE) ARROW typeRhs end_of_stat?   // canon: typeRhs, so a case's type may be an indented block
    ;

// =====================================================================
// Expressions
// =====================================================================

expr
    : funParams (ARROW | CTXARROW) expr
    | typTypeParamClause ARROW expr
    | expr1
    ;

// Original @ 757667725:
//   blockResult
//       : funParams (ARROW | CTXARROW) block
//       | typTypeParamClause ARROW block
//       | expr1
//       ;
// Removed '| expr1': it duplicates blockStat's expr1 alternative, causing
// genuine grammar ambiguity (every plain expression at end-of-block matches
// both blockStat and blockResult) and O(n) ALL(*) lookahead.
blockResult
    : funParams (ARROW | CTXARROW) block
    | typTypeParamClause ARROW block
    ;

funParams
    : bindings
    | id
    | USCORE
    ;

// Original @ 757667725:
//   expr1
//       : INLINE? IF LPAREN expr RPAREN expr (SEMI? ELSE expr)?
//       | INLINE? IF expr THEN expr (SEMI? ELSE expr)?
//       | WHILE LPAREN expr RPAREN expr
//       | WHILE expr DO expr
//       | TRY expr catches (FINALLY expr)?
//       | TRY expr (FINALLY expr)?
//       | THROW expr
//       | RETURN expr?
//       | forExpr
//       | simpleExpr DOT id ASSIGN expr
//       | prefixOperator simpleExpr ASSIGN expr
//       | infixExpr id ASSIGN expr
//       | simpleExpr argumentExprs ASSIGN expr
//       | id ASSIGN expr
//       | postfixExpr ascription?
//       | INLINE infixExpr matchClause
//       ;
// Collapsed the five assignment alternatives and 'postfixExpr ascription?' into
// 'postfixExpr (ASSIGN expr | ascription)?': every assignment LHS is a
// sub-case of postfixExpr (since postfixExpr = infixExpr id?), so the old
// alternatives all shared the same prefix, forcing ALL(*) to scan hundreds of
// tokens before ruling out assignment alternatives.
expr1
    : INLINE? IF LPAREN expr RPAREN expr (SEMI? ELSE expr)?   // if (cond) t [else f]
    | INLINE? IF expr THEN expr (SEMI? ELSE expr)?             // if cond then t [else f]
    | WHILE LPAREN expr RPAREN expr                            // while (cond) body
    | WHILE expr DO expr                                       // while cond do body
    | TRY expr catches (FINALLY expr)?
    | TRY expr (FINALLY expr)?
    | THROW expr
    | RETURN expr?
    | forExpr
    | INLINE infixExpr matchClause
    | postfixExpr (ASSIGN expr | ascription)?
    ;

ascription
    : COLON infixType
    | COLON annotation+
    ;

catches
    : CATCH (expr | exprCaseClause)
    ;

postfixExpr
    : infixExpr id?
    ;

infixExpr
    : prefixExpr
    | infixExpr id infixExpr
    | infixExpr id colonArgument
    | infixExpr matchClause
    ;

matchClause
    : MATCH tripleOpen caseClauses tripleClose
    ;

prefixExpr
    : prefixOperator? simpleExpr
    ;

// '-' '+' '~' '!'  — Op token covers all of these
prefixOperator
    : Op
    ;

simpleExpr
    : simpleRef
    | literal
    | USCORE
    | blockExpr
    | quoted
    | QuoteId
    | NEW constrApp (WITH constrApp)* templateBody?
    | NEW templateBody
    | LPAREN RPAREN                                             // unit literal ()
    | LPAREN exprsInParens RPAREN
    | LPAREN namedExprInParens (COMMA namedExprInParens)* RPAREN
    | simpleExpr DOT id
    | simpleExpr DOT matchClause
    | simpleExpr typeArgs
    | simpleExpr argumentExprs
    | simpleExpr colonArgument
    ;

colonArgument
    : COLON lambdaStart? indent (caseClauses | block) outdent
    | COLON lambdaStart? LBRACE (caseClauses | block) RBRACE
    ;

lambdaStart: funParams ('=>' | '?=>')
    | typTypeParamClause '=>'
    ;

quoted
    : QUOTE LBRACE block RBRACE
    | QUOTE LBRACKET type_ RBRACKET
    ;

exprsInParens
    : exprInParens (COMMA exprInParens)*
    ;

// canon: a Scaladoc comment before an argument binds to nothing.
exprInParens
    : (orphan = canonicalComment)* postfixExpr COLON type_
    | (orphan = canonicalComment)* expr
    ;

namedExprInParens
    : id ASSIGN exprInParens
    ;

parArgumentExprs
    : LPAREN RPAREN
    | LPAREN exprsInParens RPAREN
    | LPAREN USING exprsInParens RPAREN
    | LPAREN (exprsInParens COMMA)? postfixExpr Op RPAREN      // varargs: xs*
    ;

argumentExprs
    : parArgumentExprs
    | blockExpr
    ;

blockExpr
    : tripleOpen (caseClauses | block) tripleClose 
    ;

// Original @ 757667725:
//   block
//       : INDENT (blockStat end_of_stat*)* blockResult? DEDENT
//       | USCORE (ARROW | CTXARROW) block
//       | id (ARROW | CTXARROW) block
//       | (blockStat end_of_stat*)* blockResult?
//       ;
// Removed '| USCORE ...' and '| id ...': both are fully subsumed by
// blockResult (funParams covers USCORE and id), so they introduced genuine
// ambiguity with alt 2 and caused deep ALL(*) lookahead.
block
    : INDENT (blockStat end_of_stat*)* blockResult? DEDENT
    | (blockStat end_of_stat*)* blockResult?
    ;

// canon: a Scaladoc comment before a statement of a block, a local definition included, binds to
// nothing, since scaladoc documents members, not locals.
blockStat
    : (orphan = canonicalComment)* importDecl
    | (orphan = canonicalComment)* (annotation NEWLINE? | orphan = canonicalComment)* localModifier* def_   // canon: an annotation may stand on a line of its own
    | extension_
    | (orphan = canonicalComment)* expr1
    | (orphan = canonicalComment)* endMarker
    ;

forExpr
    : FOR LPAREN enumerators0 RPAREN (DO | YIELD)? expr
    | FOR LBRACE enumerators0 RBRACE (DO | YIELD)? expr
    | FOR LBRACE INDENT enumerators0 DEDENT RBRACE (DO | YIELD)? expr
    | FOR INDENT enumerators0 DEDENT (DO | YIELD) indent (blockStat end_of_stat*)* blockResult? outdent
    | FOR INDENT enumerators0 DEDENT (DO | YIELD)? expr
    | FOR enumerators0 (DO | YIELD) expr
    ;

enumerators0
    : enumerators SEMI?
    ;

enumerators
    : generator (end_of_stat enumerator)*
    ;

enumerator
    : generator
    | guard_+
    | pattern1 ASSIGN expr
    ;

generator
    : CASE? pattern1 LARROW expr
    ;

guard_
    : IF postfixExpr
    ;

// =====================================================================
// Case clauses
// =====================================================================

caseClauses
    : caseClause (end_of_stat? caseClause)*
    ;

// canon: a Scaladoc comment before a case clause binds to nothing.
caseClause
    : (orphan = canonicalComment)* CASE pattern guard_? ARROW block
    ;

exprCaseClause
    : (orphan = canonicalComment)* CASE pattern guard_? ARROW expr   // canon: as caseClause
    ;

// =====================================================================
// Patterns
// =====================================================================

pattern
    : pattern1 (Op pattern1)*     // Op for '|'
    ;

pattern1
    : patVar COLON refinedType
    | simpleLiteral COLON refinedType
    | pattern2
    ;

pattern2
    : id AT infixPattern
    | infixPattern
    ;

infixPattern
    : simplePattern (id simplePattern)*
    ;

simplePattern
    : patVar
    | literal
    | LPAREN RPAREN
    | LPAREN patterns RPAREN
    | quoted
    | simplePattern1 typeArgs? argumentPatterns?
    | GIVEN refinedType
    ;

simplePattern1
    : simpleRef
    | simplePattern1 DOT id
    ;

patVar
    : Varid
    | USCORE
    ;

namedPattern
    : id ASSIGN pattern
    ;

patterns
    : pattern (COMMA pattern)*
    | namedPattern (COMMA namedPattern)*
    ;

argumentPatterns
    : LPAREN patterns? RPAREN
    | LPAREN (patterns COMMA)? patVar Op RPAREN    // Op for '*'
    ;

// =====================================================================
// Type and value parameters
// =====================================================================

clsTypeParamClause
    : LBRACKET clsTypeParam (COMMA clsTypeParam)* RBRACKET
    ;

clsTypeParam
    : annotation* variance? id hkTypeParamClause? typeAndCtxBounds
    ;

defTypeParamClause
    : LBRACKET defTypeParam (COMMA defTypeParam)* RBRACKET
    ;

defTypeParam
    : annotation* id hkTypeParamClause? typeAndCtxBounds
    ;

typTypeParamClause
    : LBRACKET typTypeParam (COMMA typTypeParam)* RBRACKET
    ;

typTypeParam
    : annotation* (id | USCORE) hkTypeParamClause? typeBounds
    ;

hkTypeParamClause
    : LBRACKET hkTypeParam (COMMA hkTypeParam)* RBRACKET
    ;

hkTypeParam
    : annotation* variance? (id | USCORE) hkTypeParamClause? typeBounds
    ;

// '+' or '-' variance annotation; Op matches these
variance
    : Op
    ;

clsParamClauses
    : clsParamClause* (LPAREN IMPLICIT clsParams RPAREN)?
    ;

clsParamClause
    : LPAREN clsParams? RPAREN
    | LPAREN USING (clsParams | funArgTypes) RPAREN
    ;

clsParams
    : clsParam (COMMA clsParam)*
    ;

// canon: a Scaladoc comment before a class parameter binds to nothing; the class's comment documents
// its parameters with @param.
clsParam
    : (orphan = canonicalComment)* annotation* modifier* (VAL | VAR)? param
    ;

defParamClauses
    : defParamClause+
    ;

defParamClause
    : defTypeParamClause
    | defTermParamClause
    | usingParamClause
    ;

constrParamClauses
    : constrParamClause+
    ;

constrParamClause
    : defTermParamClause
    | usingParamClause
    ;

defTermParamClause
    : LPAREN defTermParams? RPAREN
    ;

usingParamClause
    : LPAREN USING (defTermParams | funArgTypes) RPAREN
    ;

defImplicitClause
    : LPAREN IMPLICIT defTermParams RPAREN
    ;

defTermParams
    : defTermParam (COMMA defTermParam)*
    ;

defTermParam
    : (orphan = canonicalComment)* annotation* INLINE? param   // canon: as clsParam
    ;

param
    : id COLON paramType (ASSIGN expr)?
    ;

// =====================================================================
// Bindings
// =====================================================================

bindings
    : LPAREN (binding (COMMA binding)*)? RPAREN
    ;

binding
    : (id | USCORE) (COLON type_)?
    ;

// =====================================================================
// Modifiers
// =====================================================================

modifier
    : localModifier
    | accessModifier
    | OVERRIDE
    | OPAQUE
    ;

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

accessModifier
    : (PRIVATE | PROTECTED) accessQualifier?
    ;

accessQualifier
    : LBRACKET id RBRACKET
    ;

// =====================================================================
// Annotations
// =====================================================================

annotation
    : AT simpleType_ parArgumentExprs*
    ;

// =====================================================================
// Declarations and definitions
// =====================================================================

refineDcl
    : VAL valDcl
    | DEF defDcl
    | VAR valDcl
    | TYPE id typeBounds
    ;

valDcl
    : ids COLON type_
    ;

defDcl
    : defSig COLON type_
    ;

def_
    : VAL patDef
    | VAR patDef
    | DEF defDef
    | TYPE id hkTypeParamClause? defParamClauses* typeBounds (ASSIGN type_)?
    | tmplDef
    ;

patDef
    : what = definitionName (COMMA definitionName)* (COLON type_)? (ASSIGN expr)?   // canon: definitionName for ids, the first the What
    | pattern2 (COLON type_)? (ASSIGN expr)?
    ;

defDef
    : defSig (COLON type_)? ASSIGN expr
    | defSig (COLON type_)? LBRACE block RBRACE
    | defSig (COLON type_)? LBRACE INDENT block DEDENT RBRACE
    | what = THIS constrParamClauses defImplicitClause? ASSIGN constrExpr   // canon: an auxiliary constructor is named this
    | defSig (COLON type_)?                        // abstract declaration (no body)
    ;

defSig
    : what = definitionName defParamClauses? defImplicitClause?   // canon: definitionName for id, the What
    ;

// =====================================================================
// Template definitions
// =====================================================================

tmplDef
    : CASE? CLASS classDef
    | CASE? OBJECT objectDef
    | TRAIT classDef
    | ENUM enumDef
    | GIVEN (givenDef | oldGivenDef)
    ;

classDef
    : what = definitionName classConstr template?   // canon: definitionName for id, the What
    ;

classConstr
    : clsTypeParamClause? constrMods? clsParamClauses
    ;

constrMods
    : annotation* accessModifier?
    ;

objectDef
    : what = definitionName template?   // canon: definitionName for id, the What
    ;

enumDef
    : what = definitionName classConstr inheritClauses enumBody   // canon: definitionName for id, the What
    ;

// -----------------------------------------------------------------------
// Given definitions (Scala 3)
// -----------------------------------------------------------------------

givenDef
    : (what = givenName)? COLON givenSig   // canon: givenName for id, the What
    ;

givenSig
    : givenImpl
    | LPAREN RPAREN ARROW givenImpl
    | givenConditional ARROW givenSig
    ;

givenImpl
    : what = givenType (ASSIGN expr | templateBody)?   // canon: an anonymous given's What
    | constrApps templateBody
    ;

givenConditional
    : defTypeParamClause
    | defTermParamClause
    | LPAREN funArgTypes RPAREN
    | givenType
    ;

givenType
    : annotType (id annotType)*
    ;

// Old given syntax (Scala 3.0 compat)
oldGivenDef
    : oldGivenSig? (what = givenType (ASSIGN expr)? | structuralInstance)   // canon: givenType for annotType, which it extends; an anonymous given's What
    ;

oldGivenSig
    : (what = givenName)? defTypeParamClause? usingParamClause* COLON   // canon: givenName for id, the What
    ;

structuralInstance
    : what = givenType parArgumentExprs* (WITH constrApp)* (WITH withTemplateBody)?   // canon: givenType parArgumentExprs* for constrApp, so an anonymous given is named by its type
    ;

// =====================================================================
// Extension methods
// =====================================================================

// canon: an extension is a unit named by the type it extends, its parameter's type. It declares
// nothing itself, so its comment is optional; its methods are definitions of their own.
extension_
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) EXTENSION defTypeParamClause? usingParamClause*
      LPAREN annotation* INLINE? id COLON what = paramType (ASSIGN expr)? RPAREN usingParamClause*
      how = extMethods # extension
    ;

extMethods
    : extMethod | colonTripleOpen (extMethod (end_of_stat extMethod)*)? tripleClose
    ;

extMethod
    : defDefinition   // canon: a definition carries its annotations and modifiers
    | exportDecl
    ;

// =====================================================================
// Templates
// =====================================================================

// template must be non-nullable so that template? in classDef/objectDef
// does not silently consume nothing and leave '{' stranded.
template
    : EXTENDS constrApps (DERIVES qualId (COMMA qualId)*)? templateBody?
    | DERIVES qualId (COMMA qualId)* templateBody?
    | templateBody
    ;

inheritClauses
    : (EXTENDS constrApps)? (DERIVES qualId (COMMA qualId)*)?
    ;

constrApps
    : constrApp (COMMA constrApp | WITH constrApp)*
    ;

constrApp
    : simpleType_ annotation* parArgumentExprs*
    ;

constrExpr
    : selfInvocation
    | tripleOpen selfInvocation (end_of_stat blockStat)* tripleClose
    ;

selfInvocation
    : THIS argumentExprs+
    ;

withTemplateBody
    : tripleOpen end_of_stat? selfType? end_of_stat? (templateStat (end_of_stat templateStat)*)? (orphan = canonicalComment)* tripleClose   // canon: a comment at the end of a body binds to nothing
    ;

templateBody
    : colonTripleOpen end_of_stat? selfType? end_of_stat? (templateStat (end_of_stat templateStat)*)? (orphan = canonicalComment)* tripleClose   // canon: a comment at the end of a body binds to nothing
    ;

// canon: a Scaladoc comment before a statement of a template that is not a definition binds to
// nothing.
templateStat
    : (orphan = canonicalComment)* importDecl
    | (orphan = canonicalComment)* exportDecl
    | definition   // canon: a definition carries its annotations and modifiers
    | extension_
    | (orphan = canonicalComment)* expr1
    | (orphan = canonicalComment)* endMarker
    ;

selfType
    : id (COLON infixType)? ARROW
    | THIS COLON infixType ARROW
    ;

// =====================================================================
// Enum body
// =====================================================================

enumBody
    : colonTripleOpen end_of_stat? selfType? end_of_stat? (enumStat (end_of_stat enumStat)*)? (orphan = canonicalComment)* tripleClose   // canon: a comment at the end of a body binds to nothing
    ;

enumStat
    : templateStat
    | inherited = enumCase   // canon: an enum case carries its annotations and modifiers, and needs a comment when its enum does
    ;

enumCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) definitionPrefix CASE (what = definitionName how = classConstr (EXTENDS constrApps)? | what = definitionName (COMMA definitionName)*) # case   // canon: a unit, with definitionPrefix and definitionName
    ;

// =====================================================================
// Identifier — accepts keywords that are also contextual identifiers
// =====================================================================

id
    : Id
    | Varid
    | BacktickId
    // contextual keywords usable as plain identifiers:
    | AS | OPEN | INFIX | TRANSPARENT | INLINE | OPAQUE | DERIVES
    | USING | EXTENSION | END
    // operator used as identifier (e.g. in backtick positions or import renames)
    | Op
    ;

// canon: a canonical comment, a Scaladoc comment, holding prose, reference citations, and license
// citations.
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
