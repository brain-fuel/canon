/*
 [The "BSD licence"]
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

// An ANTLR4 Grammar of Erlang R16B01 made by Pierre Fenoll from
// https://github.com/erlang/otp/blob/maint/lib/stdlib/src/erl_parse.yrl

// Update to Erlang/OTP 23.3

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

grammar Erlang;

// canon: canon's ErlangPreprocessor hook expands the macros a file defines before the parser sees
// them, as epp does, so a macro that stands for part of a form parses as its expansion.
options {
    superClass = ErlangPreprocessor;
}

// canon: changes for canon are marked canon: and listed in grammars/erlang/README.md. They let the
// grammar read what the preprocessor leaves in a file (macros and directives), the syntax of OTP 24
// to 28, and a function together with the attributes that belong to it.

// canon: a file may hold no form, as an empty header does.
forms
    : form* EOF
    ;

// canon: a function is a form of its own, with the attributes directly above it that belong to it,
// and a macro call may stand for whole forms, as ?SPEC(name). does.
form
    : functionDefinition
    | attribute '.'
    | macroCall '.'
    // canon: macro calls may stand for the clauses of a function, as ?wr_record(a); ?wr_record(b). do.
    | macroCall (';' (functionClause | macroCall))+ '.'
    ;

// canon: a function takes its -spec and the -doc attributes that hide it or carry its metadata,
// each labeled marker, so its node starts at the first of them and the comment or -doc string above
// documents it. A -doc with a string is not taken: it is the function's comment, which canon scans
// from the text. -doc false is labeled hidden.
functionDefinition
    : (marker += functionAttribute '.')* function_ '.'
    ;

// canon: a spec may be written with a space after the dash, as - spec f() -> ok.
functionAttribute
    : SpecAttrName typeSpec
    | '-' tokAtom typeSpec
    | hidden = DocHidden
    | DocAttrName '(' mapExpr ')'
    | DocAttrName mapExpr
    ;

/// Tokens

fragment DIGIT
    : [0-9]
    ;

fragment LOWERCASE
    : [a-z]
    | '\u00df' ..'\u00f6'
    | '\u00f8' ..'\u00ff'
    ;

fragment UPPERCASE
    : [A-Z]
    | '\u00c0' ..'\u00d6'
    | '\u00d8' ..'\u00de'
    ;

// canon: maybe and else are keywords only inside a maybe expression, so they may still be atoms.
tokAtom
    : TokAtom
    | 'maybe'
    | 'else'
    ;

TokAtom
    : LOWERCASE (DIGIT | LOWERCASE | UPPERCASE | '_' | '@')*
    | '\'' ( '\\' (~'\\' | '\\') | ~[\\'])* '\''
    ;

tokVar
    : TokVar
    ;

TokVar
    : (UPPERCASE | '_') (DIGIT | LOWERCASE | UPPERCASE | '_' | '@')*
    ;

tokFloat
    : TokFloat
    ;

// canon: a number has no sign of its own, since prefixOp reads a minus, so X-1 is a subtraction
// rather than X followed by -1; digits may be grouped with underscores (OTP 23); and a float may
// have a base, as in 2#1.0#e-53 (OTP 28).
TokFloat
    : DIGITS '.' DIGITS ([Ee] [+-]? DIGITS)?
    | DIGITS '#' [0-9a-zA-Z_]+ '.' [0-9a-zA-Z_]+ ('#' [Ee] [+-]? DIGITS)?
    ;

tokInteger
    : TokInteger
    ;

TokInteger
    : DIGITS ('#' (DIGIT | [a-zA-Z]) (DIGIT | [a-zA-Z] | '_')*)?
    ;

fragment DIGITS
    : DIGIT+ ('_' DIGIT+)*
    ;

tokChar
    : TokChar
    ;

// canon: a character may also be a control escape such as $\^A or a hexadecimal one such as
// $\x{1F600}.
TokChar
    : '$' ('\\'? ~[\r\n] | '\\' DIGIT DIGIT DIGIT | '\\^' . | '\\x' ([0-9a-fA-F] [0-9a-fA-F] | '{' [0-9a-fA-F]+ '}'))
    ;

tokString
    : TokString
    ;

// canon: a triple-quoted string (OTP 27) may span lines and hold quotes, and one opened with four or
// five quotes ends at as many, so it may hold three.
TokString
    : '"' ('\\' (~'\\' | '\\') | ~[\\"])* '"'
    | '"""' .*? '"""'
    | '""""' .*? '""""'
    | '"""""' .*? '"""""'
    // canon: a triple-quoted string may open with any number of quotes from three, as OTP 27 allows.
    | '""""""' .*? '""""""'
    | '"""""""' .*? '"""""""'
    ;

// canon: a sigil (OTP 27) is a string with a prefix, ~, ~b, ~B, ~s, or ~S, and one of the sigil
// delimiters. Uppercase sigils have no escapes.
TokSigil
    : '~' [bs]? (
        '"""' .*? '"""'
        | '""""' .*? '""""'
        // canon: a sigil may be quoted with up to seven quotes.
        | '"""""' .*? '"""""'
        | '""""""' .*? '""""""'
        | '"""""""' .*? '"""""""'
        | '"' ('\\' . | ~["\\])* '"'
        | '(' ('\\' . | ~[)\\])* ')'
        | '[' ('\\' . | ~[\]\\])* ']'
        | '{' ('\\' . | ~[}\\])* '}'
        | '<' ('\\' . | ~[>\\])* '>'
        | '/' ('\\' . | ~[/\\])* '/'
        | '|' ('\\' . | ~[|\\])* '|'
        | '\'' ('\\' . | ~['\\])* '\''
        | '`' ('\\' . | ~[`\\])* '`'
        | '#' ('\\' . | ~[#\\])* '#'
    )
    | '~' [BS] (
        '"""' .*? '"""'
        | '""""' .*? '""""'
        // canon: a sigil may be quoted with up to seven quotes.
        | '"""""' .*? '"""""'
        | '""""""' .*? '""""""'
        | '"""""""' .*? '"""""""'
        | '"' ~["]* '"'
        | '(' ~[)]* ')'
        | '[' ~[\]]* ']'
        | '{' ~[}]* '}'
        | '<' ~[>]* '>'
        | '/' ~[/]* '/'
        | '|' ~[|]* '|'
        | '\'' ~[']* '\''
        | '`' ~[`]* '`'
        | '#' ~[#]* '#'
    )
    ;

// antlr4 would not accept spec as an Atom otherwise.
// canon: -spec has a token of its own, apart from -callback, so a function can take its spec.
AttrName
    : '-' 'callback'
    ;

SpecAttrName
    : '-' 'spec'
    ;

// canon: -doc false and -moduledoc false hide a function or a module from the documentation
// (OTP 27), and -doc before a map gives a function's metadata; each is a token of its own so the
// parser can label it without making doc or false a keyword.
DocHidden
    : '-' [ \t]* 'doc' [ \t]* ('false' | '(' [ \t]* 'false' [ \t]* ')')
    ;

ModuledocHidden
    : '-' [ \t]* 'moduledoc' [ \t]* ('false' | '(' [ \t]* 'false' [ \t]* ')')
    ;

DocAttrName
    : '-' 'doc'
    ;

// canon: a comment may end the file without a line break.
Comment
    : '%' ~[\r\n]* -> skip
    ;

// canon: an escript starts with a #! line, which is not Erlang.
Shebang
    : '#!' ~[\r\n]* -> skip
    ;

WS
    : [\u0000-\u0020\u0080-\u00a0]+ -> skip
    ;

// canon: types, records, and callbacks have rules of their own, named by what they define, so a
// profile can make each a unit; -moduledoc false is labeled hidden; -define takes any tokens as its
// body; and the preprocessor directives without a value, -else and -endif, are attributes too.
attribute
    : typeAttribute
    | recordAttribute
    | callbackAttribute
    | hidden = ModuledocHidden
    | '-' tokAtom attrVal
    | '-' tokAtom typedAttrVal
    | '-' tokAtom '(' typedAttrVal ')'
    | '-' ('if' | 'else' | tokAtom) attrVal?
    | defineAttribute
    | SpecAttrName typeSpec
    | DocAttrName attrVal
    | DocHidden
    ;

// canon: -type, -opaque, or -nominal, named by the type it defines and its arity.
typeAttribute
    : '-' tokAtom definedName arity = typeParameters '::' topType
    | '-' tokAtom '(' definedName arity = typeParameters '::' topType ')'
    ;

// canon: the parameters of a type, or the arguments of a callback, whose count is its arity.
typeParameters
    : '(' topTypes? ')'
    ;

// canon: -record, named by the record it defines; a native record (OTP 29) is declared as
// -record #name{Fields}.
recordAttribute
    : '-' tokAtom '(' definedName ',' (typedRecordFields | tuple_) ')'
    | '-' tokAtom '#' definedName (typedRecordFields | tuple_)
    | '-' tokAtom '(' '#' definedName (typedRecordFields | tuple_) ')'
    ;

// canon: -callback, named by the callback it declares and its arity.
callbackAttribute
    : AttrName specFun callbackSignature (';' typeSig)*
    | AttrName '(' specFun callbackSignature (';' typeSig)* ')'
    ;

callbackSignature
    : arity = typeParameters '->' topType ('when' typeGuards)?
    ;

// canon: the name of a function, type, or record a form defines, which a macro may give, as in
// ?MODULE() -> ok. A native record (OTP 29) may be named by a variable or a reserved word, as in
// -record #Seq{} and -record #div{}.
definedName
    : tokAtom
    | '?' (tokAtom | tokVar)
    | tokVar
    | reservedWord
    ;

// canon: the reserved words, which may name a native record.
reservedWord
    : 'after' | 'and' | 'andalso' | 'band' | 'begin' | 'bnot' | 'bor' | 'bsl' | 'bsr' | 'bxor' | 'case'
    | 'catch' | 'div' | 'end' | 'fun' | 'if' | 'not' | 'of' | 'or' | 'orelse' | 'receive' | 'rem'
    | 'try' | 'when' | 'xor'
    ;

// canon: -define(Name, Body) and -define(Name(Args), Body) whose body is not an expression, which
// may be any tokens with balanced brackets, since a macro need not expand to an expression.
defineAttribute
    : '-' tokAtom '(' (tokAtom | tokVar) ('(' (tokVar (',' tokVar)*)? ')')? ',' macroBody* ')'
    ;

macroBody
    : ~('(' | ')' | '[' | ']' | '{' | '}' | '<<' | '>>')
    | '(' macroBody* ')'
    | '[' macroBody* ']'
    | '{' macroBody* '}'
    | '<<' macroBody* '>>'
    ;

// canon: a macro call, ?NAME or ?NAME(Args), or a stringified argument, ??Arg, which the preprocessor
// expands; canon reads it where an expression, a pattern, or a type may be.
macroCall
    : '?' '?'? (tokAtom | tokVar) macroArguments?
    ;

// canon: an argument of a macro may be a pattern with a guard, as in ?assertMatch(X when X > 0, f()),
// since the macro, often from a header, places it in a clause; epp splits arguments at the commas
// outside brackets, so the guard's tests are joined by ; only.
macroArguments
    : '(' (macroArgument (',' macroArgument)*)? ')'
    ;

macroArgument
    : expr ('when' expr (';' expr)*)?
    ;

/// Typing

typeSpec
    : specFun typeSigs
    | '(' specFun typeSigs ')'
    ;

specFun
    : tokAtom
    | tokAtom ':' tokAtom
    // canon: a macro may name the module of a spec, as in -spec ?MODULE:f() -> ok.
    | macroCall ':' tokAtom
    ;

typedAttrVal
    : expr ',' typedRecordFields
    | expr '::' topType
    ;

typedRecordFields
    : '{' typedExprs '}'
    ;

typedExprs
    : typedExpr
    | typedExpr ',' typedExprs
    | expr ',' typedExprs
    | typedExpr ',' exprs
    ;

typedExpr
    : expr '::' topType
    ;

typeSigs
    : typeSig (';' typeSig)*
    ;

typeSig
    : funType ('when' typeGuards)?
    ;

typeGuards
    : typeGuard (',' typeGuard)*
    ;

typeGuard
    : tokAtom '(' topTypes ')'
    | tokVar '::' topType
    ;

topTypes
    : topType (',' topType)*
    ;

topType
    // canon: a type may carry several annotations, as in Default :: AppProto :: binary().
    : (tokVar '::')* topType100
    ;

// canon: each member of a union may be annotated, as in Name :: {atom(), arity()} | Other :: atom(),
// as erl_parse reads it.
topType100
    : type200 ('|' topType)?
    ;

type200
    : type300 ('..' type300)?
    ;

type300
    : type300 addOp type400
    | type400
    ;

type400
    : type400 multOp type500
    | type500
    ;

type500
    : prefixOp? type_
    ;

type_
    : '(' topType ')'
    | macroCall
    | tokVar
    | tokAtom
    | tokAtom '(' ')'
    | tokAtom '(' topTypes ')'
    // canon: a macro may name the module of a remote type, as in ?MODULE:t().
    | (tokAtom | macroCall) ':' tokAtom '(' ')'
    | (tokAtom | macroCall) ':' tokAtom '(' topTypes ')'
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

funType100
    : '(' '...' ')' '->' topType
    | funType
    ;

funType
    : '(' (topTypes)? ')' '->' topType
    ;

mapPairTypes
    : mapPairType (',' mapPairType)*
    ;

mapPairType
    : topType ('=>' | ':=') topType
    ;

fieldTypes
    : fieldType (',' fieldType)*
    ;

fieldType
    : tokAtom '::' topType
    ;

binaryType
    : '<<' '>>'
    | '<<' binBaseType '>>'
    | '<<' binUnitType '>>'
    | '<<' binBaseType ',' binUnitType '>>'
    ;

binBaseType
    : tokVar ':' type_
    ;

binUnitType
    : tokVar ':' tokVar '*' type_
    ;

/// Exprs

attrVal
    : expr
    | '(' expr ')'
    | expr ',' exprs
    | '(' expr ',' exprs ')'
    ;

// canon: a macro call may stand for a clause, as ?FUNCTION(name, Arg) does.
function_
    : functionClause (';' (functionClause | macroCall))*
    ;

// canon: the name is a rule of its own, so a profile can name a function by it, and the arguments
// are labeled arity, so canon names the function by its name and arity, as Erlang does.
functionClause
    : definedName arity = clauseArgs clauseGuard clauseBody
    ;

clauseArgs
    : patArgumentList
    ;

clauseGuard
    : ('when' guard_)?
    ;

clauseBody
    : '->' exprs
    ;

expr
    : 'catch' expr
    | expr100
    ;

// canon: ?= matches inside a maybe expression (OTP 25), and the right side of a match or a send may
// be a catch expression, as in _ = catch f().
expr100
    : expr150 (('=' | '!' | '?=') (expr150 | 'catch' expr))*
    ;

expr150
    : expr160 ('orelse' expr160)*
    ;

expr160
    : expr200 ('andalso' expr200)*
    ;

expr200
    : expr300 (compOp expr300)?
    ;

expr300
    : expr400 (listOp expr400)*
    ;

expr400
    : expr500 (addOp expr500)*
    ;

expr500
    : expr600 (multOp expr600)*
    ;

// canon: a catch expression may be the right operand of any operator, as in X > catch f(), as
// erl_parse reads it.
expr600
    : prefixOp expr600
    | 'catch' expr
    | expr650
    ;

expr650
    : mapExpr
    | expr700
    ;

expr700
    : functionCall
    | recordExpr
    | expr800
    ;

expr800
    : exprMax (':' exprMax)?
    ;

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

// canon: a maybe expression (OTP 25).
maybeExpr
    : 'maybe' exprs ('else' crClauses)? 'end'
    ;

// canon: a map comprehension (OTP 26).
mapComprehension
    : '#' '{' expr '=>' expr (',' expr '=>' expr)* '||' lcExprs '}'
    ;

patExpr
    : patExpr200 ('=' patExpr)?
    ;

patExpr200
    : patExpr300 (compOp patExpr300)?
    ;

patExpr300
    : patExpr400 (listOp patExpr300)?
    ;

patExpr400
    : patExpr400 addOp patExpr500
    | patExpr500
    ;

patExpr500
    : patExpr500 multOp patExpr600
    | patExpr600
    ;

patExpr600
    : prefixOp patExpr600
    | patExpr650
    ;

patExpr650
    : mapPatExpr
    | patExpr700
    ;

patExpr700
    : recordPatExpr
    | patExpr800
    ;

patExpr800
    : patExprMax
    ;

patExprMax
    : tokVar
    | macroCall
    | atomic
    | list_
    | binary
    | tuple_
    | '(' patExpr ')'
    ;

mapPatExpr
    : patExprMax? '#' mapTuple
    | mapPatExpr '#' mapTuple
    ;

recordPatExpr
    : '#' recordName ('.' tokAtom | recordTuple)
    ;

list_
    : '[' ']'
    | '[' expr tail
    ;

// canon: a macro call directly followed by an element stands for an element and its comma, as
// ?MATCH(X) does where the macro expands to X followed by a comma.
tail
    : ']'
    | '|' expr ']'
    | ',' expr tail
    | ',' macroCall expr tail
    ;

// canon: a record's name, which a macro may give, as in #?RECORD{}. A native record (OTP 29) may
// be named with its module, as in #mod:name{}, or be any native record, #_{}.
recordName
    : tokAtom
    | macroCall
    | tokVar
    | reservedWord
    | (tokAtom | macroCall) ':' (tokAtom | tokVar | reservedWord)
    ;

binary
    : '<<' '>>'
    | '<<' binElements '>>'
    ;

binElements
    : binElement (',' binElement)*
    ;

binElement
    : bitExpr optBitSizeExpr optBitTypeList
    ;

bitExpr
    : prefixOp? exprMax
    ;

optBitSizeExpr
    : (':' bitSizeExpr)?
    ;

optBitTypeList
    : ('/' bitTypeList)?
    ;

bitTypeList
    : bitType ('-' bitType)*
    ;

bitType
    : tokAtom (':' tokInteger)?
    ;

bitSizeExpr
    : exprMax
    ;

// canon: a comprehension may give several values per element (OTP 29), as in [A, B || ...].
listComprehension
    : '[' exprs '||' lcExprs ']'
    ;

binaryComprehension
    : '<<' exprMax '||' lcExprs '>>'
    ;

// canon: zip generators are joined by && (OTP 28).
lcExprs
    : lcExpr ((',' | '&&') lcExpr)*
    ;

// canon: a map generator (OTP 26) and the strict generators (OTP 28).
lcExpr
    : expr
    | expr ('<-' | '<:-') expr
    | binary ('<=' | '<:=') expr
    | expr ':=' expr ('<-' | '<:-') expr
    ;

tuple_
    : '{' exprs? '}'
    ;

mapExpr
    : exprMax? '#' mapTuple
    | mapExpr '#' mapTuple
    ;

mapTuple
    : '{' (mapField (',' mapField)*)? '}'
    ;

mapField
    : mapFieldAssoc
    | mapFieldExact
    ;

mapFieldAssoc
    : mapKey '=>' expr
    ;

mapFieldExact
    : mapKey ':=' expr
    ;

mapKey
    : expr
    ;

/* struct : tokAtom tuple ; */

/* N.B. This is called from expr700.
   N.B. Field names are returned as the complete object, even if they are
   always atoms for the moment, this might change in the future.           */

recordExpr
    : exprMax? '#' recordName ('.' tokAtom | recordTuple)
    | recordExpr '#' recordName ('.' tokAtom | recordTuple)
    ;

recordTuple
    : '{' recordFields? '}'
    ;

recordFields
    : recordField (',' recordField)*
    ;

recordField
    : (tokVar | tokAtom) '=' expr
    ;

/* N.B. This is called from expr700. */

// canon: a call's result may be called, and a remote call may be made on it, as in F()(X), fun
// m:f/1(X), and ?MODULE:callback():reverse(L), since erl_parse calls any expression.
functionCall
    : expr800 argumentList (argumentList | ':' exprMax argumentList)*
    ;

ifExpr
    : 'if' ifClauses 'end'
    ;

ifClauses
    : ifClause (';' ifClause)*
    ;

ifClause
    : guard_ clauseBody
    ;

caseExpr
    : 'case' expr 'of' crClauses 'end'
    ;

crClauses
    : crClause (';' crClause)*
    ;

crClause
    : expr clauseGuard clauseBody
    ;

receiveExpr
    : 'receive' crClauses 'end'
    | 'receive' 'after' expr clauseBody 'end'
    | 'receive' crClauses 'after' expr clauseBody 'end'
    ;

funExpr
    : 'fun' tokAtom '/' tokInteger
    | 'fun' atomOrVar ':' atomOrVar '/' integerOrVar
    | 'fun' funClauses 'end'
    ;

atomOrVar
    : tokAtom
    | tokVar
    | macroCall
    ;

integerOrVar
    : tokInteger
    | tokVar
    ;

funClauses
    : funClause (';' funClause)*
    ;

funClause
    : patArgumentList clauseGuard clauseBody
    | tokVar patArgumentList clauseGuard clauseBody
    ;

tryExpr
    : 'try' exprs ('of' crClauses)? tryCatch
    ;

tryCatch
    : 'catch' tryClauses 'end'
    | 'catch' tryClauses 'after' exprs 'end'
    | 'after' exprs 'end'
    ;

tryClauses
    : tryClause (';' tryClause)*
    ;

tryClause
    : expr clauseGuard clauseBody
    | (atomOrVar ':')? patExpr tryOptStackTrace clauseGuard clauseBody
    ;

tryOptStackTrace
    : (':' tokVar)?
    ;

argumentList
    : '(' exprs? ')'
    ;

patArgumentList
    : '(' patExprs? ')'
    ;

exprs
    : expr (',' expr)*
    ;

patExprs
    : patExpr (',' patExpr)*
    ;

guard_
    : exprs (';' exprs)*
    ;

atomic
    : tokChar
    | tokInteger
    | tokFloat
    | tokAtom
    | stringConcatenation
    ;

// canon: adjacent strings concatenate, and a macro may stand for one of them, as in ?DIR "file".
stringConcatenation
    : macroCall* (tokString | TokSigil) (tokString | TokSigil | macroCall)*
    ;

prefixOp
    : '+'
    | '-'
    | 'bnot'
    | 'not'
    ;

multOp
    : '/'
    | '*'
    | 'div'
    | 'rem'
    | 'band'
    | 'and'
    ;

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

listOp
    : '++'
    | '--'
    ;

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