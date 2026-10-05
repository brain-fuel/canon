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

// The Erlang lexer of canon's Erlang dialect: the tokens of the plain grammar under grammars/erlang,
// with its literals named, plus lexer modes that tokenize -doc strings and EDoc comments as canonical
// comments. The plain grammar is combined; the dialect is split because a combined grammar has no
// lexer modes.

lexer grammar ErlangLexer;

options {
    superClass = ErlangPreprocessor;
}

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

/** The keyword after. */
AFTER
    : 'after'
    ;

/** The keyword and. */
AND
    : 'and'
    ;

/** The keyword andalso. */
ANDALSO
    : 'andalso'
    ;

/** The keyword band. */
BAND
    : 'band'
    ;

/** The keyword begin. */
BEGIN
    : 'begin'
    ;

/** The keyword bnot. */
BNOT
    : 'bnot'
    ;

/** The keyword bor. */
BOR
    : 'bor'
    ;

/** The keyword bsl. */
BSL
    : 'bsl'
    ;

/** The keyword bsr. */
BSR
    : 'bsr'
    ;

/** The keyword bxor. */
BXOR
    : 'bxor'
    ;

/** The keyword case. */
CASE
    : 'case'
    ;

/** The keyword catch. */
CATCH
    : 'catch'
    ;

/** The keyword div. */
DIV
    : 'div'
    ;

/** The keyword else. */
ELSE_KW
    : 'else'
    ;

/** The keyword end. */
END
    : 'end'
    ;

/** The keyword fun. */
FUN
    : 'fun'
    ;

/** The keyword if. */
IF_KW
    : 'if'
    ;

/** The keyword maybe. */
MAYBE
    : 'maybe'
    ;

/** The keyword not. */
NOT
    : 'not'
    ;

/** The keyword of. */
OF
    : 'of'
    ;

/** The keyword or. */
OR
    : 'or'
    ;

/** The keyword orelse. */
ORELSE
    : 'orelse'
    ;

/** The keyword receive. */
RECEIVE
    : 'receive'
    ;

/** The keyword rem. */
REM
    : 'rem'
    ;

/** The keyword try. */
TRY
    : 'try'
    ;

/** The keyword when. */
WHEN
    : 'when'
    ;

/** The keyword xor. */
XOR
    : 'xor'
    ;

/** The punctuation <:-. */
STRICT_LARROW
    : '<:-'
    ;

/** The punctuation =:=. */
EXACT_EQ
    : '=:='
    ;

/** The punctuation =/=. */
EXACT_NEQ
    : '=/='
    ;

/** The punctuation .... */
ELLIPSIS
    : '...'
    ;

/** The punctuation <:=. */
STRICT_BIN_LARROW
    : '<:='
    ;

/** The punctuation ... */
RANGE
    : '..'
    ;

/** The punctuation /=. */
NEQ
    : '/='
    ;

/** The punctuation >>. */
RBITS
    : '>>'
    ;

/** The punctuation ||. */
DOUBLE_BAR
    : '||'
    ;

/** The punctuation ::. */
DOUBLE_COLON
    : '::'
    ;

/** The punctuation <<. */
LBITS
    : '<<'
    ;

/** The punctuation =>. */
ASSOC
    : '=>'
    ;

/** The punctuation &&. */
ZIP
    : '&&'
    ;

/** The punctuation ++. */
PLUS_PLUS
    : '++'
    ;

/** The punctuation >=. */
GE
    : '>='
    ;

/** The punctuation ->. */
ARROW
    : '->'
    ;

/** The punctuation :=. */
EXACT
    : ':='
    ;

/** The punctuation <=. */
BIN_LARROW
    : '<='
    ;

/** The punctuation <-. */
LARROW
    : '<-'
    ;

/** The punctuation =<. */
LE
    : '=<'
    ;

/** The punctuation ?=. */
MAYBE_MATCH
    : '?='
    ;

/** The punctuation ==. */
EQ
    : '=='
    ;

/** The punctuation --. */
MINUS_MINUS
    : '--'
    ;

/** The punctuation ?. */
QUESTION
    : '?'
    ;

/** The punctuation :. */
COLON
    : ':'
    ;

/** The punctuation <. */
LT
    : '<'
    ;

/** The punctuation =. */
MATCH
    : '='
    ;

/** The punctuation (. */
LPAREN
    : '('
    ;

/** The punctuation >. */
GT
    : '>'
    ;

/** The punctuation /. */
SLASH
    : '/'
    ;

/** The punctuation .. */
DOT
    : '.'
    ;

/** The punctuation |. */
BAR
    : '|'
    ;

/** The punctuation *. */
STAR
    : '*'
    ;

/** The punctuation ,. */
COMMA
    : ','
    ;

/** The punctuation -. */
MINUS
    : '-'
    ;

/** The punctuation {. */
LBRACE
    : '{'
    ;

/** The punctuation #. */
HASH
    : '#'
    ;

/** The punctuation ;. */
SEMI
    : ';'
    ;

/** The punctuation [. */
LBRACKET
    : '['
    ;

/** The punctuation ). */
RPAREN
    : ')'
    ;

/** The punctuation +. */
PLUS
    : '+'
    ;

/** The punctuation }. */
RBRACE
    : '}'
    ;

/** The punctuation !. */
SEND
    : '!'
    ;

/** The punctuation ]. */
RBRACKET
    : ']'
    ;

/** An atom, bare or quoted. */
TokAtom
    : LOWERCASE (DIGIT | LOWERCASE | UPPERCASE | '_' | '@')*
    | '\'' ( '\\' (~'\\' | '\\') | ~[\\'])* '\''
    ;

/** A variable. */
TokVar
    : (UPPERCASE | '_') (DIGIT | LOWERCASE | UPPERCASE | '_' | '@')*
    ;

/** A float, without a sign, which prefixOp reads. */
TokFloat
    : DIGITS '.' DIGITS ([Ee] [+-]? DIGITS)?
    | DIGITS '#' [0-9a-zA-Z_]+ '.' [0-9a-zA-Z_]+ ('#' [Ee] [+-]? DIGITS)?
    ;

/** An integer, without a sign, with an optional base and underscores. */
TokInteger
    : DIGITS ('#' (DIGIT | [a-zA-Z]) (DIGIT | [a-zA-Z] | '_')*)?
    ;

fragment DIGITS
    : DIGIT+ ('_' DIGIT+)*
    ;

/** A character literal. */
TokChar
    : '$' ('\\'? ~[\r\n] | '\\' DIGIT DIGIT DIGIT | '\\^' . | '\\x' ([0-9a-fA-F] [0-9a-fA-F] | '{' [0-9a-fA-F]+ '}'))
    ;

/** A string, or a triple-quoted string. */
TokString
    : '"' ('\\' (~'\\' | '\\') | ~[\\"])* '"'
    | '"""' .*? '"""'
    | '""""' .*? '""""'
    | '"""""' .*? '"""""'
    ;

/** A sigil string. */
TokSigil
    : '~' [bs]? (
        '"""' .*? '"""'
        | '""""' .*? '""""'
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

/** The -callback attribute name. */
AttrName
    : '-' 'callback'
    ;

/** The -spec attribute name. */
SpecAttrName
    : '-' 'spec'
    ;

/** -doc false, which hides the function below it. ref:DEC-hidden-label */
DocHidden
    : '-' [ \t]* 'doc' [ \t]* ('false' | '(' [ \t]* 'false' [ \t]* ')')
    ;

/** -moduledoc false, which hides the module. ref:DEC-hidden-label */
ModuledocHidden
    : '-' [ \t]* 'moduledoc' [ \t]* ('false' | '(' [ \t]* 'false' [ \t]* ')')
    ;

/** The -doc attribute name before a map of metadata. */
DocAttrName
    : '-' 'doc'
    ;

/** The -module attribute name. */
ModuleAttrName
    : '-' [ \t]* 'module'
    ;

/** The -moduledoc attribute name before a map of metadata. */
ModuledocAttrName
    : '-' [ \t]* 'moduledoc'
    ;

/** Opens a -doc string of four quotes, which may hold three, typed as DOC_OPEN. ref:DEC-erlang-dialect */
DOC_QUAD_OPEN
    : '-' [ \t]* 'doc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '\"\"\"\"' -> type(DOC_OPEN), pushMode(DocQuad)
    ;

/** Opens a -moduledoc string of four quotes, typed as MODULEDOC_OPEN. ref:DEC-erlang-dialect */
MODULEDOC_QUAD_OPEN
    : '-' [ \t]* 'moduledoc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '\"\"\"\"' -> type(MODULEDOC_OPEN), pushMode(DocQuad)
    ;

/** The -export or -export_type attribute name with its opening parenthesis. */
ExportAttrName
    : '-' [ \t]* 'export' [ \t]* '(' | '-' [ \t]* 'export_type' [ \t]* '('
    ;

/** Opens a -doc string, a canonical comment, and enters the DocTriple mode for a triple-quoted string. ref:DEC-erlang-dialect */
DOC_OPEN
    : '-' [ \t]* 'doc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '"""' -> pushMode(DocTriple)
    ;

/** Opens a -doc string on one line, typed as DOC_OPEN. ref:DEC-erlang-dialect */
DOC_STRING_OPEN
    : '-' [ \t]* 'doc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '"' -> type(DOC_OPEN), pushMode(DocString)
    ;

/** Opens a -moduledoc string, the documentation of the module. ref:DEC-erlang-dialect */
MODULEDOC_OPEN
    : '-' [ \t]* 'moduledoc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '"""' -> pushMode(DocTriple)
    ;

/** Opens a -moduledoc string on one line, typed as MODULEDOC_OPEN. ref:DEC-erlang-dialect */
MODULEDOC_STRING_OPEN
    : '-' [ \t]* 'moduledoc' [ \t]* '('? [ \t]* ('~' [bBsS]?)? '"' -> type(MODULEDOC_OPEN), pushMode(DocString)
    ;

/** Opens an EDoc comment whose first tag is @private or @hidden, which hides what it documents. ref:DEC-erlang-dialect ref:DEC-hidden-label */
EDOC_HIDDEN_OPEN
    : '%'+ [ \t]* '@' ('private' | 'hidden') -> pushMode(Edoc)
    ;

/** Opens an EDoc comment, a comment whose first line starts with a tag such as @doc, and enters the Edoc mode. ref:DEC-erlang-dialect */
EDOC_OPEN
    : '%'+ [ \t]* '@' [a-z]+ -> pushMode(Edoc)
    ;

/** A comment that is no EDoc comment, skipped. ref:DEC-erlang-dialect */
Comment
    : '%'+ [ \t]* (~[@% \t\r\n] ~[\r\n]*)? -> skip
    ;

/** The #! line of an escript, skipped. */
Shebang
    : '#!' ~[\r\n]* -> skip
    ;

/** Whitespace, skipped. */
WS
    : [\u0000-\u0020\u0080-\u00a0]+ -> skip
    ;

mode DocTriple;

/** Closes a documentation string, with the parenthesis of the attribute. ref:DEC-erlang-dialect */
DOC_CLOSE
    : '"""' [ \t]* ')'? -> popMode
    ;

/** A citation of a registry reference inside documentation. ref:DEC-erlang-dialect */
DOC_REF
    : 'ref:' DocKey
    ;

/** A citation of a registry license inside documentation. ref:DEC-erlang-dialect */
DOC_LICENSE
    : 'license:' DocKey
    ;

/** Whitespace inside documentation, skipped. */
DOC_WS
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation inside documentation. */
DOC_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\%~-]
    ;

/** A word of prose inside documentation. */
DOC_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\%~-]+
    ;

mode DocQuad;

/** Closes a string of four quotes, typed as DOC_CLOSE. */
DOC_QUAD_CLOSE
    : '\"\"\"\"' [ \t]* ')'? -> type(DOC_CLOSE), popMode
    ;

/** A reference citation in a string of four quotes, typed as DOC_REF. */
DOC_QUAD_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in a string of four quotes, typed as DOC_LICENSE. */
DOC_QUAD_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace in a string of four quotes, skipped. */
DOC_QUAD_WS
    : [ \t\r\n]+ -> skip
    ;

/** Punctuation in a string of four quotes, typed as DOC_PUNCT. */
DOC_QUAD_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\%~-] -> type(DOC_PUNCT)
    ;

/** A word in a string of four quotes, typed as DOC_WORD. */
DOC_QUAD_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\%~-]+ -> type(DOC_WORD)
    ;

mode DocString;

/** Closes documentation on one line, typed as DOC_CLOSE. */
DOC_STRING_CLOSE
    : '"' [ \t]* ')'? -> type(DOC_CLOSE), popMode
    ;

/** A reference citation on one line, typed as DOC_REF. */
DOC_STRING_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation on one line, typed as DOC_LICENSE. */
DOC_STRING_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Whitespace on one line, skipped. */
DOC_STRING_WS
    : [ \t\r\n]+ -> skip
    ;

/** An escaped character, typed as DOC_WORD. */
DOC_STRING_ESCAPE
    : '\\' . -> type(DOC_WORD)
    ;

/** Punctuation on one line, typed as DOC_PUNCT. */
DOC_STRING_PUNCT
    : [,.;:()!?[\]{}'`<>=+*#|/%~-] -> type(DOC_PUNCT)
    ;

/** A word on one line, typed as DOC_WORD. */
DOC_STRING_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\%~-]+ -> type(DOC_WORD)
    ;

mode Edoc;

/** A line break followed by another comment line, which continues the EDoc comment, skipped. */
EDOC_CONTINUE
    : '\r'? '\n' [ \t]* '%'+ -> skip
    ;

/** A line break followed by anything but a comment, which ends the EDoc comment. ref:DEC-erlang-dialect */
EDOC_CLOSE
    : '\r'? '\n' -> popMode
    ;

/** The @private or @hidden tag inside an EDoc comment, which hides what it documents. ref:DEC-hidden-label */
EDOC_HIDDEN
    : '@' ('private' | 'hidden')
    ;

/** A reference citation in an EDoc comment, typed as DOC_REF. */
EDOC_REF
    : 'ref:' DocKey -> type(DOC_REF)
    ;

/** A license citation in an EDoc comment, typed as DOC_LICENSE. */
EDOC_LICENSE
    : 'license:' DocKey -> type(DOC_LICENSE)
    ;

/** Spaces in an EDoc comment, skipped. */
EDOC_WS
    : [ \t]+ -> skip
    ;

/** Punctuation in an EDoc comment, typed as DOC_PUNCT. */
EDOC_PUNCT
    : [,.;:()!?[\]{}"'`<>=+*#|/\\%~@-] -> type(DOC_PUNCT)
    ;

/** A word in an EDoc comment, typed as DOC_WORD. */
EDOC_WORD
    : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+*#|/\\%~@-]+ -> type(DOC_WORD)
    ;

fragment DocKey
    : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?
    ;
