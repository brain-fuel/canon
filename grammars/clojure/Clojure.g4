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

file_
    : form* EOF
    ;

form
    : literal
    | list_
    | vector
    | map_
    | reader_macro
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

// canon: a map is any run of forms, since a discarded form, #_x, may stand among its entries and
// the reader drops it after reading; the Clojure reader, not the grammar, checks that keys and values
// pair. ref:DEC-clojure-grammar-fixes
map_
    : '{' form* '}'
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
    | ns_map
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
quote
    : '\'' form
    ;

backtick
    : '`' form
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

// canon: a var quote may quote an unquoted symbol inside a syntax quote, as #'~name does.
var_quote
    : '#\'' form
    ;

host_expr
    : '#+' form form
    ;

discard
    : '#_' form
    ;

// canon: a namespaced map, #:ns{:a 1} or the auto-resolved #::{:a 1} and #::alias{:a 1}, whose
// keys take the namespace; the prefix is read as a keyword.
ns_map
    : '#' keyword map_
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
    // canon: the symbolic values ##Inf, ##-Inf, and ##NaN.
    | SYMBOLIC_VALUE
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
    ;

// canon: an auto-resolved keyword, ::name, is one token too.
macro_keyword
    : MACRO_KEYWORD
    ;

symbol
    : ns_symbol
    | simple_sym
    ;

simple_sym
    : SYMBOL
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

// canon: the reader's symbolic values, ##Inf, ##-Inf, and ##NaN, read as numbers.
SYMBOLIC_VALUE
    : '##' ('Inf' | '-Inf' | 'NaN')
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

// canon: a quote may follow the first character of a symbol, as x' and db' are written for the
// next value of x and db; only its first character may not be a quote. ref:DEC-clojure-grammar-fixes
fragment SYMBOL_REST
    : SYMBOL_HEAD
    | '0' ..'9'
    | '.'
    | '\''
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
