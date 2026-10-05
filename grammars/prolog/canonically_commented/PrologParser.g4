/*
BSD License

Copyright (c) 2013, Tom Everett
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Neither the name of Tom Everett nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// canon: the canonically commented dialect of the Prolog grammar. PlDoc comments are canonical
// comments on the default channel; the clauses of a predicate, a DCG rule, and a plunit test are
// labeled unit alternatives with their Why and their What, and a canonical comment the grammar
// accepts but binds to nothing is an orphan. Every change from the plain grammar is marked canon: and
// recorded as DEC-prolog-dialect.

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar PrologParser;

options {
    tokenVocab = PrologLexer;
}


// Prolog text and data formed from terms (6.2)

// canon: a /** <module> */ comment at the top level is the Why of the file, the first of several
// binding; a canonical comment that no unit follows, as above a directive or at the end of the file,
// is an orphan.
p_text
    : (why = moduleComment | item | orphan = canonicalComment)* EOF
    ;

// canon: what may stand at the top level, the units first so that a canonical comment binds to the
// unit below it rather than standing as an orphan.
item
    : moduleDirective
    | testClause
    | declaration
    | predicateClause
    | nonterminalClause
    | directive
    | clause
    ;

// canon: the module directive. Its export list is the module's public API, so each predicate
// indicator in it is labeled export and the export rule requires a comment on exactly the predicates
// it names. The module's name is labeled export too: it names no predicate, since a predicate is
// named with its arity, and it keeps a module that exports nothing from reading as a file without an
// export list, in which every predicate is visible and requires a comment.
moduleDirective
    : ':-' 'module' '(' export = atom ',' '[' (exportEntry (',' exportEntry)*)? ']' (',' term)? ')' '.'
    ;

// canon: an entry of an export list: a predicate indicator, or an operator declaration.
exportEntry
    : export = predicateIndicator
    | term
    ;

// canon: a predicate indicator, name/arity, or name//arity for a DCG nonterminal. A nonterminal's
// name and arity are labeled, so the entry exports name/arity, the name of the nonterminal's unit.
predicateIndicator
    : atom '/' integer
    | what = atom '//' arity = integer
    ;

// canon: a plunit test, a clause of test/1 or test/2, named by the test's name, its first argument.
testClause
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) 'test' '(' what = term (',' term)? ')' (':-' termlist)? '.' # test
    ;

// canon: a declaration of predicates, as :- dynamic foo/1, is a clause of the first predicate it
// declares, so the comment above it documents that predicate, as PlDoc reads it, and the clauses
// that follow it belong to the same unit. Several predicates may be declared at once, as
// :- dynamic a/1, b/2 or :- dynamic [a/1, b/2], and a declared predicate may be module-qualified.
declaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) ':-' declarationKeyword (declaredPredicates | '(' declaredPredicates ')' | '[' declaredPredicates ']') '.' # predicate
    ;

// canon: the predicates of a declaration; the first names the declaration's unit.
declaredPredicates
    : (atom ':')? what = atom '/' arity = integer (',' (atom ':')? atom '/' integer)*
    ;

// canon: the keywords of a predicate declaration.
declarationKeyword
    : 'dynamic'
    | 'multifile'
    | 'discontiguous'
    | 'public'
    ;

// canon: a clause whose head is an atom or a compound term, a fact or a rule. Its unit is named by
// the head's name and the number of its arguments, name/arity, as Prolog names a predicate, and
// adjacent clauses with one name and arity are one unit, unless a canonical comment above a later
// clause starts a unit of its own. A head may be qualified by its module, as user:portray(X) is,
// and is still named by its own name.
predicateClause
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (atom ':')? what = atom (arity = arguments | arity = noArguments) (':-' termlist)? '.' # predicate
    ;

// canon: a DCG rule, a unit of kind nonterminal named by its head's name and written arity.
nonterminalClause
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (atom ':')? what = atom (arity = arguments | arity = noArguments) (',' term)? '-->' termlist '.' # nonterminal
    ;

// canon: the bracketed arguments of a head, whose arity is the number of its arguments, so a head
// whose one argument is a number, as foo(2) is, has arity one.
arguments
    : '(' termlist ')'
    ;

// canon: the arguments of a head without any, so that a head without arguments has arity zero.
noArguments
    :
    ;

// canon: a directive and a clause read a conjunction, a termlist, since a comma is no operator.
directive
    : ':-' termlist '.'
    ; // also 3.58

clause
    : termlist '.'
    ; // also 3.33

// Abstract Syntax (6.3): terms formed from tokens

termlist
    : term (',' term)*
    ;

term
    : VARIABLE     # variable
    // canon: a comma is no operator in the dialect, so the arguments of a compound term are counted
    // right; a parenthesised term is a conjunction, as a clause's body is.
    | '(' termlist ')' # braced_term
    | '-'? integer # integer_term //TODO: negative case should be covered by unary_operator
    | '-'? FLOAT   # float
    // structure / compound term
    | atom '(' termlist ')'               # compound_term
    | <assoc = right> term operator_ term # binary_operator
    | operator_ term                      # unary_operator
    | '[' termlist ( '|' term)? ']'       # list_term
    | '{' termlist '}'                    # curly_bracketed_term
    | atom                                # atom_term
    ;

//TODO: operator priority, associativity, arity. Filter valid priority ranges for e.g. [list] syntax
//TODO: modifying operator table

operator_
    : ':-'
    | '-->'
    | '?-'
    | 'dynamic'
    | 'multifile'
    | 'discontiguous'
    | 'public' //TODO: move operators used in directives to "built-in" definition of dialect
    | ';'
    | '->'
    // canon: ',' is not an operator here; termlist reads a conjunction.
    | '\\+'
    | '='
    | '\\='
    | '=='
    | '\\=='
    | '@<'
    | '@=<'
    | '@>'
    | '@>='
    | '=..'
    | 'is'
    | '=:='
    | '=\\='
    | '<'
    | '=<'
    | '>'
    | '>='
    | ':' // modules: 5.2.1
    | '+'
    | '-'
    | '/\\'
    | '\\/'
    | '*'
    | '/'
    | '//'
    | 'rem'
    | 'mod'
    | '<<'
    | '>>' //TODO: '/' cannot be used as atom because token here not in GRAPHIC. only works because , is operator too. example: swipl/filesex.pl:177
    | '**'
    | '^'
    | '\\'
    ;

atom                                  // 6.4.2 and 6.1.2
    : '[' ']'            # empty_list //NOTE [] is not atom anymore in swipl 7 and later
    | '{' '}'            # empty_braces
    | LETTER_DIGIT       # name
    | GRAPHIC_TOKEN      # graphic
    | QUOTED             # quoted_string
    | DOUBLE_QUOTED_LIST # dq_string
    | BACK_QUOTED_STRING # backq_string
    | ';'                # semicolon
    | '!'                # cut
    // canon: module and test are tokens of their own in the dialect and still atoms.
    | 'module'           # module_atom
    | 'test'             # test_atom
    ;

integer // 6.4.4
    : DECIMAL
    | CHARACTER_CODE_CONSTANT
    | BINARY
    | OCTAL
    | HEX
    ;

// canon: a PlDoc comment, a %! or %% line comment and the % lines that continue it, or a /** block
// comment, holding prose, reference citations, and license citations.
canonicalComment
    : DOC_OPEN docPart*
    | DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: a /** <module> */ comment, which documents the file.
moduleComment
    : DOC_BLOCK_OPEN DOC_MODULE docPart* DOC_BLOCK_CLOSE
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
