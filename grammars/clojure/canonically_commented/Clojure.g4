/* Reworked for grammar specificity by Reid Mckenzie. Did a bunch of
   work so that rather than reading "a bunch of crap in parens" some
   syntactic information is preserved and recovered. Dec. 14 2014.

   Converted to ANTLR 4 by Terence Parr. Unsure of provenance. I see
   it commited by matthias.koester for clojure-eclipse project on
   Oct 5, 2009:

   code.google.com/p/clojure-eclipse/

   Seems to me Laurent Petit had a version of this. I also see
   Jingguo Yao submitting a link to a now-dead github project on
   Jan 1, 2011.

   github.com/laurentpetit/ccw/tree/master/clojure-antlr-grammar

   Regardless, there are some issues perhaps related to "sugar";
   I've tried to fix them.

   This parses https://github.com/weavejester/compojure project.

   I also note this is hardly a grammar; more like "match a bunch of
   crap in parens" but I guess that is LISP for you ;)
 */

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

grammar Clojure;

// canon: the canonically commented dialect of the Clojure grammar. Clojure documents a definition
// with the docstring after its name, or with :doc metadata on the name, so each definition form
// that takes one is a labeled unit alternative, tried before the generic list, with the docstring
// as its Why and the name as its What. A string can be told from a docstring only by where it
// stands, so the string itself is labeled why. A ; comment is not documentation. Every change from
// the plain grammar is marked canon: and recorded in canon's ledger as DEC-clojure-dialect.

// canon: the docstring of a file's leading ns form, or its :doc metadata, is the file's Why.
file_
    : '(' NS ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* symbol why = string_? forms ')' form* EOF
    | form* EOF
    ;

// canon: a definition form is tried before the generic list.
form
    : definition
    | literal
    | list_
    | vector
    | map_
    | reader_macro
    ;

// canon: a form read as data or discarded, in which a definition form is not a definition: the
// form of a quote, a syntax quote, or a #_ discard.
plain_form
    : literal
    | list_
    | vector
    | map_
    | reader_macro
    ;

// canon: the definition forms that carry documentation. defn, defmacro, defmulti, and defprotocol
// are labeled required, because a public function, macro, multimethod, or protocol is the API a
// namespace exports; defn- is private, and ^:private and ^:no-doc metadata are labeled optional,
// which wins. A def, a record, a type, and a test may have documentation and need none by their form,
// though a test always needs a Why. A docstring stands after the name, and a string after the
// parameters of a function with more body forms after it is a misplaced docstring, an orphan.
definition
    : '(' required = DEFN ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? map_? function_tail ')' # function
    | '(' DEFN_PRIVATE ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? map_? function_tail ')' # function
    | '(' required = DEFMACRO ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? map_? function_tail ')' # macro
    | '(' required = DEFMULTI ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? map_? form+ ')' # multimethod
    | '(' required = DEFPROTOCOL ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? (keyword form)* inherited = protocol_methods ')' # protocol
    | '(' DEFRECORD ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol vector form* ')' # record
    | '(' DEFTYPE ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol vector form* ')' # type
    | '(' DEF ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol why = string_? form ')' # var
    | '(' DEF ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol ')' # var
    | '(' DEFTEST ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol form* ')' # deftest
    ;

// canon: the method signatures of a protocol need a docstring when their protocol does.
protocol_methods
    : protocol_method*
    ;

// canon: a method signature of a protocol, with its own docstring after its parameter vectors.
protocol_method
    : '(' ('^' '{' metaEntry* DOC_KEYWORD why = string_? metaEntry* '}' | metaMark)* what = symbol vector+ why = string_? ')' # method
    ;

// canon: the parameters and body of a function or macro, of one arity or several. A string after
// the parameters is the body's value when it is the last form, and a misplaced docstring otherwise.
function_tail
    : vector orphan = string_ form+
    | vector forms
    | list_+
    ;

// canon: metadata on a definition's name other than its :doc. ^:private and ^:no-doc are labeled
// optional.
metaMark
    : '^' optional = PRIVATE_KEYWORD
    | '^' optional = NO_DOC_KEYWORD
    | '^' '{' metaEntry* '}'
    | '^' form
    ;

// canon: one entry of a metadata map; :private and :no-doc are labeled optional.
metaEntry
    : optional = PRIVATE_KEYWORD form
    | optional = NO_DOC_KEYWORD form
    | form form
    ;

forms
    : form*
    ;

list_
    : '(' forms ')'
    ;

vector
    : '[' forms ']'
    ;

map_
    : '{' (form form)* '}'
    ;

set_
    : '#{' forms '}'
    ;

reader_macro
    : lambda_
    | meta_data
    | regex
    | var_quote
    | host_expr
    | set_
    | tag
    | discard
    | dispatch
    | deref
    | quote
    | backtick
    | unquote
    | unquote_splicing
    | gensym
    ;

// TJP added '&' (gather a variable number of arguments)
// canon: quoted, syntax-quoted, and discarded forms are plain forms.
quote
    : '\'' plain_form
    ;

backtick
    : '`' plain_form
    ;

unquote
    : '~' form
    ;

unquote_splicing
    : '~@' form
    ;

tag
    : '^' form form
    ;

deref
    : '@' form
    ;

gensym
    : SYMBOL '#'
    ;

lambda_
    : '#(' form* ')'
    ;

meta_data
    : '#^' (map_ form | form)
    ;

var_quote
    : '#\'' symbol
    ;

host_expr
    : '#+' form form
    ;

discard
    : '#_' plain_form
    ;

dispatch
    : '#' symbol form
    ;

regex
    : '#' string_
    ;

literal
    : string_
    | number
    | character
    | nil_
    | BOOLEAN
    | keyword
    | symbol
    | param_name
    ;

string_
    : STRING
    ;

hex_
    : HEX
    ;

bin_
    : BIN
    ;

bign
    : BIGN
    ;

number
    : FLOAT
    | hex_
    | bin_
    | bign
    | LONG
    ;

character
    : named_char
    | u_hex_quad
    | any_char
    ;

named_char
    : CHAR_NAMED
    ;

any_char
    : CHAR_ANY
    ;

u_hex_quad
    : CHAR_U
    ;

nil_
    : NIL
    ;

keyword
    : macro_keyword
    | simple_keyword
    ;

// canon: a keyword is one token, as the Clojure reader reads it: a colon and the constituent
// characters after it, which may include digits, dots, slashes, and #, as :1.8 and :div#id do.
simple_keyword
    : KEYWORD
    | DOC_KEYWORD
    | PRIVATE_KEYWORD
    | NO_DOC_KEYWORD
    ;

// canon: an auto-resolved keyword, ::name, is one token too.
macro_keyword
    : MACRO_KEYWORD
    ;

symbol
    : ns_symbol
    | simple_sym
    ;

// canon: the names of the definition forms are symbols wherever they are not a definition's head.
simple_sym
    : SYMBOL
    | DEFN
    | DEFN_PRIVATE
    | DEFMACRO
    | DEFMULTI
    | DEFPROTOCOL
    | DEFRECORD
    | DEFTYPE
    | DEF
    | DEFTEST
    | NS
    ;

ns_symbol
    : NS_SYMBOL
    ;

param_name
    : PARAM_NAME
    ;

// Lexers
//--------------------------------------------------------------------

// canon: a backslash always starts an escape, so "\\" ends at its second quote; upstream's
// (~'"' | '\\' '"')* let the longest match run on past it to the next quote.
STRING
    : '"' (~["\\] | '\\' .)* '"'
    ;

// FIXME: Doesn't deal with arbitrary read radixes, BigNums
FLOAT
    : '-'? [0-9]+ FLOAT_TAIL
    | '-'? 'Infinity'
    | '-'? 'NaN'
    ;

fragment FLOAT_TAIL
    : FLOAT_DECIMAL FLOAT_EXP
    | FLOAT_DECIMAL
    | FLOAT_EXP
    ;

fragment FLOAT_DECIMAL
    : '.' [0-9]+
    ;

fragment FLOAT_EXP
    : [eE] '-'? [0-9]+
    ;

fragment HEXD
    : [0-9a-fA-F]
    ;

HEX
    : '0' [xX] HEXD+
    ;

BIN
    : '0' [bB] [10]+
    ;

LONG
    : '-'? [0-9]+ [lL]?
    ;

BIGN
    : '-'? [0-9]+ [nN]
    ;

CHAR_U
    : '\\' 'u' [0-9D-Fd-f] HEXD HEXD HEXD
    ;

CHAR_NAMED
    : '\\' ('newline' | 'return' | 'space' | 'tab' | 'formfeed' | 'backspace')
    ;

CHAR_ANY
    : '\\' .
    ;

NIL
    : 'nil'
    ;

BOOLEAN
    : 'true'
    | 'false'
    ;

// canon: the heads of the definition forms, each a symbol the parser can name; a longer symbol
// such as defnx or default is a SYMBOL by the longest match.
DEFN
    : 'defn'
    ;

DEFN_PRIVATE
    : 'defn-'
    ;

DEFMACRO
    : 'defmacro'
    ;

DEFMULTI
    : 'defmulti'
    ;

DEFPROTOCOL
    : 'defprotocol'
    ;

DEFRECORD
    : 'defrecord'
    ;

DEFTYPE
    : 'deftype'
    ;

DEF
    : 'def'
    ;

DEFTEST
    : 'deftest'
    ;

NS
    : 'ns'
    ;

SYMBOL
    : '.'
    | '/'
    | NAME
    ;

NS_SYMBOL
    : NAME '/' SYMBOL
    ;

PARAM_NAME
    : '%' ('1' ..'9' '0' ..'9'* | '&')?
    ;

// canon: keyword tokens; the auto-resolved form is listed first so that ::name is not :name with a
// colon in it.
MACRO_KEYWORD
    : '::' KEYWORD_CHAR+
    ;

// canon: the metadata keys a definition's documentation and visibility are read from, before
// KEYWORD so that they win at equal length.
DOC_KEYWORD
    : ':doc'
    ;

PRIVATE_KEYWORD
    : ':private'
    ;

NO_DOC_KEYWORD
    : ':no-doc'
    ;

KEYWORD
    : ':' KEYWORD_CHAR+
    ;

// Fragments
//--------------------------------------------------------------------

fragment NAME
    : SYMBOL_HEAD SYMBOL_REST* (':' SYMBOL_REST+)*
    ;

fragment SYMBOL_HEAD
    : ~(
        '0' .. '9'
        | '^'
        | '`'
        | '\''
        | '"'
        | '#'
        | '~'
        | '@'
        | ':'
        | '/'
        | '%'
        | '('
        | ')'
        | '['
        | ']'
        | '{'
        | '}'        // FIXME: could be one group
        | [ \n\r\t,] // FIXME: could be WS
    )
    ;

fragment SYMBOL_REST
    : SYMBOL_HEAD
    | '0' ..'9'
    | '.'
    ;

// canon: what may follow the colon of a keyword: anything but whitespace, a comma, and the
// characters that end a token for the reader.
fragment KEYWORD_CHAR
    : ~[ \n\r\t,";@^`~()[\]{}\\]
    ;

// Discard
//--------------------------------------------------------------------

fragment WS
    : [ \n\r\t,]
    ;

fragment COMMENT
    : ';' ~[\r\n]*
    ;

TRASH
    : (WS | COMMENT) -> channel(HIDDEN)
    ;
