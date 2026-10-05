/**
 [The "BSD licence"]
 license:BSD-3-Clause
 Copyright (c) 2013 Terence Parr
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 3. The name of the author may not be used to endorse or promote products
    derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
*/

// The Erlang parser of canon's Erlang dialect: the plain grammar under grammars/erlang, with each
// function, type, record, and callback a labeled unit alternative whose -doc string or EDoc comment is
// its Why, export entries labeled export, and -moduledoc labeled file.

parser grammar ErlangParser;

// canon: a doc comment may stand between any two tokens, as inside an expression; where the grammar
// does not accept one, canon reads the file without it and reports it as an orphan, as the strayComment
// options say. ref:DEC-stray-comments
options {
    tokenVocab = ErlangLexer;
    strayComment = canonicalComment;
    strayComment = moduleComment;
}

/** An Erlang file: its forms, its -moduledoc, labeled file because it documents the module the file is, and documentation that documents nothing, labeled orphan. A module that compiles with export_all exports every function; any other module exports what its export lists name, and none when it has none, so its module declaration is read as one that labels an export that names no unit. A header, without a module declaration, exports everything. ref:DEC-erlang-dialect ref:DEC-export-rule */
// canon: a module without an export list and without export_all exports nothing.
forms
    : (form | file = moduleComment | orphan = canonicalComment)* exportAllAttribute (form | file = moduleComment | orphan = canonicalComment)* EOF
    | (exportingForm | file = moduleComment | orphan = canonicalComment)* EOF
    ;

/** A -compile attribute whose options hold export_all, which exports every function of the module. ref:DEC-erlang-dialect */
exportAllAttribute
    : '-' 'compile' '(' ('export_all' | '[' (compileOption ',')* 'export_all' (',' compileOption)* ']') ')' '.'
    ;

/** One option of a -compile list. */
compileOption
    : expr
    ;

/** A form of a module that does not compile with export_all: the module declaration, which then labels an export, or any other form. ref:DEC-erlang-dialect ref:DEC-export-rule */
exportingForm
    : file = canonicalComment? export = ModuleAttrName '(' tokAtom ')' '.'
    | form
    ;

/** A form: a function, a type, a record, or a callback, each a unit, the module declaration, an export list, another attribute, or a macro call that stands for forms. */
form
    : typeDefinition
    | recordDefinition
    | callbackDefinition
    | functionDefinition
    | moduleDeclaration
    | exportAttribute
    | attribute '.'
    | macroCall '.'
    ;

/** The module declaration. An EDoc comment above it documents the module, so it is labeled file. ref:DEC-erlang-dialect */
moduleDeclaration
    : file = canonicalComment? ModuleAttrName '(' tokAtom ')' '.'
    ;

/** An export list, of functions or of types, whose entries are labeled export, so a unit requires its comment when it is exported. ref:DEC-export-rule ref:DEC-erlang-dialect */
exportAttribute
    : ExportAttrName '[' (exportEntry (',' exportEntry)*)? ']' ')' '.'
    ;

/** One exported name and arity, labeled export, which the export rule matches against the name and arity of a unit. */
exportEntry
    : export = exportedName
    ;

/** A name and an arity, written name/arity. */
exportedName
    : tokAtom '/' tokInteger
    ;

/** A type, -type, -opaque, or -nominal, documented as a function is. ref:DEC-erlang-dialect */
typeDefinition
    : (orphan = canonicalComment | DocHidden '.' | marker += functionAttribute '.')*? why = canonicalComment (marker += functionAttribute '.')* typeAttribute '.' # type
    | (orphan = canonicalComment | marker += functionAttribute '.')*? hidden = DocHidden '.' (marker += functionAttribute '.')* why = canonicalComment? typeAttribute '.' # type
    | (marker += functionAttribute '.')* why = canonicalComment? typeAttribute '.' # type
    ;

/** A record, documented as a function is. ref:DEC-erlang-dialect */
recordDefinition
    : (orphan = canonicalComment | DocHidden '.' | marker += functionAttribute '.')*? why = canonicalComment (marker += functionAttribute '.')* recordAttribute '.' # record
    | (orphan = canonicalComment | marker += functionAttribute '.')*? hidden = DocHidden '.' (marker += functionAttribute '.')* why = canonicalComment? recordAttribute '.' # record
    | (marker += functionAttribute '.')* why = canonicalComment? recordAttribute '.' # record
    ;

/** A callback of a behaviour, whose comment is required. ref:DEC-erlang-dialect */
callbackDefinition
    : (orphan = canonicalComment | DocHidden '.' | marker += functionAttribute '.')*? why = canonicalComment (marker += functionAttribute '.')* required = callbackAttribute '.' # callback
    | (orphan = canonicalComment | marker += functionAttribute '.')*? hidden = DocHidden '.' (marker += functionAttribute '.')* why = canonicalComment? required = callbackAttribute '.' # callback
    | (marker += functionAttribute '.')* why = canonicalComment? required = callbackAttribute '.' # callback
    ;

/** A function with its -spec and -doc metadata. A -doc string or an EDoc comment above or among them is its Why; the last one wins, so an earlier one is an orphan, and a later -doc false hides the function and is labeled hidden. ref:DEC-erlang-dialect ref:DEC-hidden-label */
functionDefinition
    : (orphan = canonicalComment | DocHidden '.' | marker += functionAttribute '.')*? why = canonicalComment (marker += functionAttribute '.')* function_ '.' # function
    | (orphan = canonicalComment | marker += functionAttribute '.')*? hidden = DocHidden '.' (marker += functionAttribute '.')* why = canonicalComment? function_ '.' # function
    | (marker += functionAttribute '.')* why = canonicalComment? function_ '.' # function
    ;

/** An attribute between a unit and the documentation above it, labeled marker: its -spec, its -doc metadata, or another attribute such as -dialyzer, since -doc and EDoc bind to the next definition whatever attributes come between. */
functionAttribute
    : SpecAttrName typeSpec
    | DocAttrName '(' mapExpr ')'
    | DocAttrName mapExpr
    | '-' tokAtom attrVal
    ;

/** An atom; maybe and else are keywords only inside a maybe expression. */
tokAtom
    : TokAtom
    | 'maybe'
    | 'else'
    ;

/** A variable. */
tokVar
    : TokVar
    ;

/** A float. */
tokFloat
    : TokFloat
    ;

/** An integer. */
tokInteger
    : TokInteger
    ;

/** A character. */
tokChar
    : TokChar
    ;

/** A string. */
tokString
    : TokString
    ;

/** Any other attribute: -moduledoc false, labeled hidden, a preprocessor directive, a -define, or the rest. */
attribute
    : hidden = ModuledocHidden
    | ModuledocAttrName attrVal
    | '-' tokAtom attrVal
    | '-' tokAtom typedAttrVal
    | '-' tokAtom '(' typedAttrVal ')'
    | '-' ('if' | 'else' | tokAtom) attrVal?
    | defineAttribute
    | SpecAttrName typeSpec
    | DocAttrName attrVal
    | DocHidden
    ;

/** The type a -type, -opaque, or -nominal attribute defines, named by its name. */
typeAttribute
    : '-' tokAtom what = definedName arity = typeParameters '::' topType
    | '-' tokAtom '(' what = definedName arity = typeParameters '::' topType ')'
    ;

/** The parameters of a type, or the arguments of a callback, labeled arity: their count is the arity in the name of the unit. */
typeParameters
    : '(' topTypes? ')'
    ;

/** The record a -record attribute defines, named by its name. */
recordAttribute
    : '-' tokAtom '(' what = definedName ',' (typedRecordFields | tuple_) ')'
    ;

/** A -callback attribute, named by its function. */
callbackAttribute
    : AttrName what = specFun callbackSignature (';' typeSig)*
    | AttrName '(' what = specFun callbackSignature (';' typeSig)* ')'
    ;

/** The first signature of a callback, whose arguments give its arity. */
callbackSignature
    : arity = typeParameters '->' topType ('when' typeGuards)?
    ;

/** The name of a function, type, or record a form defines. */
definedName
    : tokAtom
    ;

/** A -define whose body is not an expression, read as balanced tokens. */
defineAttribute
    : '-' tokAtom '(' (tokAtom | tokVar) ('(' (tokVar (',' tokVar)*)? ')')? ',' macroBody* ')'
    ;

/** Any token, or a bracketed sequence of them, in the body of a -define. */
macroBody
    : ~('(' | ')' | '[' | ']' | '{' | '}' | '<<' | '>>')
    | '(' macroBody* ')'
    | '[' macroBody* ']'
    | '{' macroBody* '}'
    | '<<' macroBody* '>>'
    ;

/** A macro call or a stringified macro argument. */
macroCall
    : '?' '?'? (tokAtom | tokVar) argumentList?
    ;

/** The function and signatures of a -spec or -callback. */
typeSpec
    : specFun typeSigs
    | '(' specFun typeSigs ')'
    ;

/** The function a -spec or -callback names, its What. */
specFun
    : tokAtom
    | tokAtom ':' tokAtom
    ;

/** The value of a typed attribute. */
typedAttrVal
    : expr ',' typedRecordFields
    | expr '::' topType
    ;

/** The typed fields of a record. */
typedRecordFields
    : '{' typedExprs '}'
    ;

/** Record fields, typed or not. */
typedExprs
    : typedExpr
    | typedExpr ',' typedExprs
    | expr ',' typedExprs
    | typedExpr ',' exprs
    ;

/** A typed record field. */
typedExpr
    : expr '::' topType
    ;

/** The signatures of a spec. */
typeSigs
    : typeSig (';' typeSig)*
    ;

/** One signature with its guards. */
typeSig
    : funType ('when' typeGuards)?
    ;

/** The constraints of a signature. */
typeGuards
    : typeGuard (',' typeGuard)*
    ;

/** One constraint. */
typeGuard
    : tokAtom '(' topTypes ')'
    | tokVar '::' topType
    ;

/** A list of types. */
topTypes
    : topType (',' topType)*
    ;

/** A type, optionally annotated with a variable. */
topType
    : (tokVar '::')? topType100
    ;

/** A union of types. */
topType100
    : type200 ('|' topType)?
    ;

/** A range type. */
type200
    : type300 ('..' type300)?
    ;

/** An additive type expression. */
type300
    : type300 addOp type400
    | type400
    ;

/** A multiplicative type expression. */
type400
    : type400 multOp type500
    | type500
    ;

/** A type with a prefix operator. */
type500
    : prefixOp? type_
    ;

/** A primary type. */
type_
    : '(' topType ')'
    | macroCall
    | tokVar
    | tokAtom
    | tokAtom '(' ')'
    | tokAtom '(' topTypes ')'
    | tokAtom ':' tokAtom '(' ')'
    | tokAtom ':' tokAtom '(' topTypes ')'
    | '[' ']'
    | '[' topType ']'
    | '[' topType ',' '...' ']'
    | '#' '{' '}'
    | '#' '{' mapPairTypes '}'
    | '{' '}'
    | '{' topTypes '}'
    | '#' recordName '{' '}'
    | '#' recordName '{' fieldTypes '}'
    | binaryType
    | tokInteger
    | tokChar
    | 'fun' '(' ')'
    | 'fun' '(' funType100 ')'
    ;

/** A fun type. */
funType100
    : '(' '...' ')' '->' topType
    | funType
    ;

/** The arguments and result of a fun type. */
funType
    : '(' (topTypes)? ')' '->' topType
    ;

/** The pairs of a map type. */
mapPairTypes
    : mapPairType (',' mapPairType)*
    ;

/** One pair of a map type. */
mapPairType
    : topType ('=>' | ':=') topType
    ;

/** The fields of a record type. */
fieldTypes
    : fieldType (',' fieldType)*
    ;

/** One field of a record type. */
fieldType
    : tokAtom '::' topType
    ;

/** A binary type. */
binaryType
    : '<<' '>>'
    | '<<' binBaseType '>>'
    | '<<' binUnitType '>>'
    | '<<' binBaseType ',' binUnitType '>>'
    ;

/** The base of a binary type. */
binBaseType
    : tokVar ':' type_
    ;

/** The unit of a binary type. */
binUnitType
    : tokVar ':' tokVar '*' type_
    ;

/** The value of an attribute. */
attrVal
    : expr
    | '(' expr ')'
    | expr ',' exprs
    | '(' expr ',' exprs ')'
    ;

/** The clauses of a function. */
function_
    : functionClause (';' (functionClause | macroCall))*
    ;

/** One clause of a function; its name and the arity its arguments give are the What of the function. */
functionClause
    : what = definedName arity = clauseArgs clauseGuard clauseBody
    ;

/** The arguments of a clause. */
clauseArgs
    : patArgumentList
    ;

/** The guard of a clause. */
clauseGuard
    : ('when' guard_)?
    ;

/** The body of a clause, the How. */
clauseBody
    : '->' exprs
    ;

/** An expression, or a catch of one. */
expr
    : 'catch' expr
    | expr100
    ;

/** A match or a send. */
expr100
    : expr150 (('=' | '!' | '?=') (expr150 | 'catch' expr))*
    ;

/** An orelse. */
expr150
    : expr160 ('orelse' expr160)*
    ;

/** An andalso. */
expr160
    : expr200 ('andalso' expr200)*
    ;

/** A comparison. */
expr200
    : expr300 (compOp expr300)?
    ;

/** A list operation. */
expr300
    : expr400 (listOp expr400)*
    ;

/** An additive expression. */
expr400
    : expr500 (addOp expr500)*
    ;

/** A multiplicative expression. */
expr500
    : expr600 (multOp expr600)*
    ;

/** A prefix operation. */
expr600
    : prefixOp expr600
    | expr650
    ;

/** A map expression. */
expr650
    : mapExpr
    | expr700
    ;

/** A call or a record expression. */
expr700
    : functionCall
    | recordExpr
    | expr800
    ;

/** A remote expression. */
expr800
    : exprMax (':' exprMax)?
    ;

/** A primary expression. */
exprMax
    : tokVar
    | atomic
    | list_
    | binary
    | listComprehension
    | binaryComprehension
    | tuple_
    | '(' expr ')'
    | 'begin' exprs 'end'
    | ifExpr
    | caseExpr
    | receiveExpr
    | funExpr
    | tryExpr
    | maybeExpr
    | mapComprehension
    | macroCall
    ;

/** A maybe expression. */
maybeExpr
    : 'maybe' exprs ('else' crClauses)? 'end'
    ;

/** A map comprehension. */
mapComprehension
    : '#' '{' expr '=>' expr '||' lcExprs '}'
    ;

/** A pattern. */
patExpr
    : patExpr200 ('=' patExpr)?
    ;

/** A comparison pattern. */
patExpr200
    : patExpr300 (compOp patExpr300)?
    ;

/** A list pattern operation. */
patExpr300
    : patExpr400 (listOp patExpr300)?
    ;

/** An additive pattern. */
patExpr400
    : patExpr400 addOp patExpr500
    | patExpr500
    ;

/** A multiplicative pattern. */
patExpr500
    : patExpr500 multOp patExpr600
    | patExpr600
    ;

/** A prefix pattern. */
patExpr600
    : prefixOp patExpr600
    | patExpr650
    ;

/** A map pattern. */
patExpr650
    : mapPatExpr
    | patExpr700
    ;

/** A record pattern. */
patExpr700
    : recordPatExpr
    | patExpr800
    ;

/** A primary pattern. */
patExpr800
    : patExprMax
    ;

/** A primary pattern. */
patExprMax
    : tokVar
    | macroCall
    | atomic
    | list_
    | binary
    | tuple_
    | '(' patExpr ')'
    ;

/** A map pattern. */
mapPatExpr
    : patExprMax? '#' mapTuple
    | mapPatExpr '#' mapTuple
    ;

/** A record pattern. */
recordPatExpr
    : '#' recordName ('.' tokAtom | recordTuple)
    ;

/** A list. */
list_
    : '[' ']'
    | '[' expr tail
    ;

/** The tail of a list. */
tail
    : ']'
    | '|' expr ']'
    | ',' expr tail
    | ',' macroCall expr tail
    ;

/** The name of a record, which a macro may give. */
recordName
    : tokAtom
    | macroCall
    ;

/** A binary. */
binary
    : '<<' '>>'
    | '<<' binElements '>>'
    ;

/** The elements of a binary. */
binElements
    : binElement (',' binElement)*
    ;

/** One element of a binary. */
binElement
    : bitExpr optBitSizeExpr optBitTypeList
    ;

/** The value of a binary element. */
bitExpr
    : prefixOp? exprMax
    ;

/** The size of a binary element. */
optBitSizeExpr
    : (':' bitSizeExpr)?
    ;

/** The types of a binary element. */
optBitTypeList
    : ('/' bitTypeList)?
    ;

/** A list of bit types. */
bitTypeList
    : bitType ('-' bitType)*
    ;

/** A bit type. */
bitType
    : tokAtom (':' tokInteger)?
    ;

/** A bit size. */
bitSizeExpr
    : exprMax
    ;

/** A list comprehension. */
listComprehension
    : '[' expr '||' lcExprs ']'
    ;

/** A binary comprehension. */
binaryComprehension
    : '<<' exprMax '||' lcExprs '>>'
    ;

/** The generators and filters of a comprehension. */
lcExprs
    : lcExpr ((',' | '&&') lcExpr)*
    ;

/** A generator or a filter. */
lcExpr
    : expr
    | expr ('<-' | '<:-') expr
    | binary ('<=' | '<:=') expr
    | expr ':=' expr ('<-' | '<:-') expr
    ;

/** A tuple. */
tuple_
    : '{' exprs? '}'
    ;

/** A map expression. */
mapExpr
    : exprMax? '#' mapTuple
    | mapExpr '#' mapTuple
    ;

/** The fields of a map. */
mapTuple
    : '{' (mapField (',' mapField)*)? '}'
    ;

/** A map field. */
mapField
    : mapFieldAssoc
    | mapFieldExact
    ;

/** An association. */
mapFieldAssoc
    : mapKey '=>' expr
    ;

/** An exact association. */
mapFieldExact
    : mapKey ':=' expr
    ;

/** A map key. */
mapKey
    : expr
    ;

/** A record expression. */
recordExpr
    : exprMax? '#' recordName ('.' tokAtom | recordTuple)
    | recordExpr '#' recordName ('.' tokAtom | recordTuple)
    ;

/** The fields of a record expression. */
recordTuple
    : '{' recordFields? '}'
    ;

/** Record fields. */
recordFields
    : recordField (',' recordField)*
    ;

/** A record field. */
recordField
    : (tokVar | tokAtom) '=' expr
    ;

/** A function call. */
functionCall
    : expr800 argumentList
    ;

/** An if expression. */
ifExpr
    : 'if' ifClauses 'end'
    ;

/** The clauses of an if. */
ifClauses
    : ifClause (';' ifClause)*
    ;

/** An if clause. */
ifClause
    : guard_ clauseBody
    ;

/** A case expression. */
caseExpr
    : 'case' expr 'of' crClauses 'end'
    ;

/** Case or receive clauses. */
crClauses
    : crClause (';' crClause)*
    ;

/** A case or receive clause. */
crClause
    : expr clauseGuard clauseBody
    ;

/** A receive expression. */
receiveExpr
    : 'receive' crClauses 'end'
    | 'receive' 'after' expr clauseBody 'end'
    | 'receive' crClauses 'after' expr clauseBody 'end'
    ;

/** A fun expression. */
funExpr
    : 'fun' tokAtom '/' tokInteger
    | 'fun' atomOrVar ':' atomOrVar '/' integerOrVar
    | 'fun' funClauses 'end'
    ;

/** An atom, a variable, or a macro. */
atomOrVar
    : tokAtom
    | tokVar
    | macroCall
    ;

/** An integer or a variable. */
integerOrVar
    : tokInteger
    | tokVar
    ;

/** The clauses of a fun. */
funClauses
    : funClause (';' funClause)*
    ;

/** A fun clause. */
funClause
    : patArgumentList clauseGuard clauseBody
    | tokVar patArgumentList clauseGuard clauseBody
    ;

/** A try expression. */
tryExpr
    : 'try' exprs ('of' crClauses)? tryCatch
    ;

/** The catch and after parts of a try. */
tryCatch
    : 'catch' tryClauses 'end'
    | 'catch' tryClauses 'after' exprs 'end'
    | 'after' exprs 'end'
    ;

/** Catch clauses. */
tryClauses
    : tryClause (';' tryClause)*
    ;

/** A catch clause. */
tryClause
    : expr clauseGuard clauseBody
    | (atomOrVar ':')? patExpr tryOptStackTrace clauseGuard clauseBody
    ;

/** A stack trace variable. */
tryOptStackTrace
    : (':' tokVar)?
    ;

/** Call arguments. */
argumentList
    : '(' exprs? ')'
    ;

/** Clause arguments. */
patArgumentList
    : '(' patExprs? ')'
    ;

/** A list of expressions. */
exprs
    : expr (',' expr)*
    ;

/** A list of patterns. */
patExprs
    : patExpr (',' patExpr)*
    ;

/** A guard. */
guard_
    : exprs (';' exprs)*
    ;

/** A literal. */
atomic
    : tokChar
    | tokInteger
    | tokFloat
    | tokAtom
    | stringConcatenation
    ;

/** Adjacent strings, sigils, and macros that stand for strings. */
stringConcatenation
    : macroCall* (tokString | TokSigil) (tokString | TokSigil | macroCall)*
    ;

/** A prefix operator. */
prefixOp
    : '+'
    | '-'
    | 'bnot'
    | 'not'
    ;

/** A multiplicative operator. */
multOp
    : '/'
    | '*'
    | 'div'
    | 'rem'
    | 'band'
    | 'and'
    ;

/** An additive operator. */
addOp
    : '+'
    | '-'
    | 'bor'
    | 'bxor'
    | 'bsl'
    | 'bsr'
    | 'or'
    | 'xor'
    ;

/** A list operator. */
listOp
    : '++'
    | '--'
    ;

/** A comparison operator. */
compOp
    : '=='
    | '/='
    | '=<'
    | '<'
    | '>='
    | '>'
    | '=:='
    | '=/='
    ;

/** A -doc string with the dot that ends it, or an EDoc comment: the canonical comment of the unit below. ref:DEC-erlang-dialect ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE '.'
    | (EDOC_OPEN | hidden = EDOC_HIDDEN_OPEN) docPart* EDOC_CLOSE?
    ;

/** A -moduledoc string with the dot that ends it, the documentation of the module. ref:DEC-erlang-dialect */
moduleComment
    : MODULEDOC_OPEN docPart* DOC_CLOSE '.'
    ;

/** One piece of documentation: a reference citation, a license citation, a hiding tag, or prose. */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | hidden = EDOC_HIDDEN
    | DOC_WORD
    | DOC_PUNCT
    ;
