/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 by Bart Kiers
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * Project      : python3-parser; an ANTLR4 grammar for Python 3
 *                https://github.com/bkiers/python3-parser
 * Developed by : Bart Kiers, bart@big-o.nl
 */

// Scraping from https://docs.python.org/3/reference/grammar.html

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar Python3Parser;

// canon: the canonically commented dialect of the Python grammar. A docstring, the string literal
// that is the first statement of a module, class, or function body, is the canonical comment of
// what it opens, as PEP 257 defines it; a # comment is never documentation. Each def and class is a
// labeled unit alternative with its Why and its What, and its decorators are its markers. A public
// top-level name is labeled required, a private or dunder name other than __init__ optional, and a
// class body inherited, so the public methods of a public class require a docstring. Every change
// from the plain grammar is marked canon: and listed in grammars/python/README.md.

options {
    superClass = Python3ParserBase;
    tokenVocab = Python3Lexer;
}

// Insert here @header for C++ parser.

// All comments that start with "///" are copy-pasted from
// The Python Language Reference

single_input
    : NEWLINE
    | simple_stmts
    | compound_stmt NEWLINE
    ;

// canon: the module's docstring is the Why of the file.
file_input
    : NEWLINE* why = docString? (NEWLINE | stmt)* EOF
    ;

eval_input
    : testlist NEWLINE* EOF
    ;

// canon: a decorator is any named expression, as Python 3.9 allows (PEP 614).
decorator
    : '@' namedexpr_test NEWLINE
    ;

// canon: decorators, decorated, and async_funcdef are folded into funcdef and classdef, so a
// definition's node starts at its first decorator and each decorator is a marker of it. A def may
// declare type parameters, as Python 3.12 allows (PEP 695).
funcdef
    : (optional = overloadDecorator | marker += decorator)* ASYNC? 'def' what = definitionName type_params? parameters ('->' test)? ':' (
        NEWLINE INDENT why = docString? (NEWLINE stmt* | stmt+) DEDENT
        | why = docString? (NEWLINE | simple_stmts)
    ) # function
    ;

// canon: a definition's name, labeled required when it is public at the top level of a module, in no
// def or class body though perhaps in a module-level if, try, or with block, and optional when it is
// private or a dunder other than __init__.
definitionName
    : {this.isPublicTopLevel()}? required = name
    | {this.isPrivateName()}? optional = name
    | {!this.isPublicTopLevel()}? {!this.isPrivateName()}? name
    ;

// canon: an @overload decorator, labeled optional, since the stub it marks is documented by the
// implementation that follows it.
overloadDecorator
    : {this.isOverload()}? decorator
    ;

// canon: a docstring, a string that is a statement alone and neither a bytes nor an f-string; adjacent
// strings, which Python joins into one, are one docstring.
docString
    : {this.isDocString()}? STRING+
    ;

// canon: type parameters with bounds, defaults (Python 3.13, PEP 696), and the * and ** of type
// variable tuples and parameter specifications.
type_params
    : '[' type_param (',' type_param)* ','? ']'
    ;

type_param
    : name (':' test)? ('=' test)?
    | '*' name ('=' (test | star_expr))?
    | '**' name ('=' test)?
    ;

parameters
    : '(' typedargslist? ')'
    ;

// canon: '/' ends the positional-only parameters, as Python 3.8 allows.
typedargslist
    : (
        tfpdef ('=' test)? (',' tfpdef ('=' test)?)* (',' '/' (',' tfpdef ('=' test)?)*)? (
            ',' (
                '*' tfpdef? (',' tfpdef ('=' test)?)* (',' ('**' tfpdef ','?)?)?
                | '**' tfpdef ','?
            )?
        )?
        | '*' tfpdef? (',' tfpdef ('=' test)?)* (',' ('**' tfpdef ','?)?)?
        | '**' tfpdef ','?
    )
    ;

// canon: the annotation of *args may be starred, as Python 3.11 allows (PEP 646).
tfpdef
    : name (':' (test | star_expr))?
    ;

// canon: '/' ends the positional-only parameters of a lambda too.
varargslist
    : (
        vfpdef ('=' test)? (',' vfpdef ('=' test)?)* (',' '/' (',' vfpdef ('=' test)?)*)? (
            ',' (
                '*' vfpdef? (',' vfpdef ('=' test)?)* (',' ('**' vfpdef ','?)?)?
                | '**' vfpdef (',')?
            )?
        )?
        | '*' vfpdef? (',' vfpdef ('=' test)?)* (',' ('**' vfpdef ','?)?)?
        | '**' vfpdef ','?
    )
    ;

vfpdef
    : name
    ;

stmt
    : simple_stmts
    | compound_stmt
    ;

simple_stmts
    : simple_stmt (';' simple_stmt)* ';'? NEWLINE
    ;

simple_stmt
    : (
        expr_stmt
        | del_stmt
        | pass_stmt
        | type_stmt
        | flow_stmt
        | import_stmt
        | global_stmt
        | nonlocal_stmt
        | assert_stmt
    )
    ;

expr_stmt
    : testlist_star_expr (
        annassign
        | augassign (yield_expr | testlist_star_expr)
        | ('=' (yield_expr | testlist_star_expr))*
    )
    ;

// canon: an annotated assignment's value may be a yield or an unparenthesized tuple, as Python 3.8
// allows.
annassign
    : ':' test ('=' (yield_expr | testlist_star_expr))?
    ;

testlist_star_expr
    : (test | star_expr) (',' (test | star_expr))* ','?
    ;

augassign
    : (
        '+='
        | '-='
        | '*='
        | '@='
        | '/='
        | '%='
        | '&='
        | '|='
        | '^='
        | '<<='
        | '>>='
        | '**='
        | '//='
    )
    ;

// For normal and annotated assignments, additional restrictions enforced by the interpreter
del_stmt
    : 'del' exprlist
    ;

pass_stmt
    : 'pass'
    ;

flow_stmt
    : break_stmt
    | continue_stmt
    | return_stmt
    | raise_stmt
    | yield_stmt
    ;

break_stmt
    : 'break'
    ;

continue_stmt
    : 'continue'
    ;

// canon: a return value may hold starred items, as Python 3.8 allows.
return_stmt
    : 'return' testlist_star_expr?
    ;

// canon: a type alias statement, as Python 3.12 allows (PEP 695); type is a soft keyword.
type_stmt
    : 'type' name type_params? '=' test
    ;

yield_stmt
    : yield_expr
    ;

raise_stmt
    : 'raise' (test ('from' test)?)?
    ;

import_stmt
    : import_name
    | import_from
    ;

// canon: an import may be lazy, as Python 3.15 allows (PEP 810); lazy is a soft keyword.
import_name
    : 'lazy'? 'import' dotted_as_names
    ;

// note below: the ('.' | '...') is necessary because '...' is tokenized as ELLIPSIS
import_from
    : (
        'lazy'? 'from' (('.' | '...')* dotted_name | ('.' | '...')+) 'import' (
            '*'
            | '(' import_as_names ')'
            | import_as_names
        )
    )
    ;

import_as_name
    : name ('as' name)?
    ;

dotted_as_name
    : dotted_name ('as' name)?
    ;

import_as_names
    : import_as_name (',' import_as_name)* ','?
    ;

dotted_as_names
    : dotted_as_name (',' dotted_as_name)*
    ;

dotted_name
    : name ('.' name)*
    ;

global_stmt
    : 'global' name (',' name)*
    ;

nonlocal_stmt
    : 'nonlocal' name (',' name)*
    ;

assert_stmt
    : 'assert' test (',' test)?
    ;

compound_stmt
    : if_stmt
    | while_stmt
    | for_stmt
    | try_stmt
    | with_stmt
    | funcdef
    | classdef
    | async_stmt
    | match_stmt
    ;

// canon: an async def is a funcdef.
async_stmt
    : ASYNC (with_stmt | for_stmt)
    ;

// canon: a condition may be a named expression, as Python 3.8 allows (PEP 572).
if_stmt
    : 'if' namedexpr_test ':' block ('elif' namedexpr_test ':' block)* ('else' ':' block)?
    ;

while_stmt
    : 'while' namedexpr_test ':' block ('else' ':' block)?
    ;

// canon: the iterable may hold starred items, as Python 3.9 allows.
for_stmt
    : 'for' exprlist 'in' testlist_star_expr ':' block ('else' ':' block)?
    ;

try_stmt
    : (
        'try' ':' block (
            (except_clause ':' block)+ ('else' ':' block)? ('finally' ':' block)?
            | 'finally' ':' block
        )
    )
    ;

// canon: the items may be parenthesized over several lines, as Python 3.9 allows.
with_stmt
    : 'with' (with_item (',' with_item)* | '(' with_item (',' with_item)* ','? ')') ':' block
    ;

with_item
    : test ('as' expr)?
    ;

// NB compile.c makes sure that the default except clause is last
// canon: except* handles exception groups, as Python 3.11 allows (PEP 654), and several exception
// types may go without parentheses when there is no as, as Python 3.14 allows (PEP 758).
except_clause
    : 'except' '*'? (test ('as' name)? | test (',' test)+)?
    ;

block
    : simple_stmts
    | NEWLINE INDENT stmt+ DEDENT
    ;

match_stmt
    : 'match' subject_expr ':' NEWLINE INDENT case_block+ DEDENT
    ;

// canon: the subject may be a named expression, and a tuple's items are separated by commas.
subject_expr
    : star_named_expression ',' (star_named_expression (',' star_named_expression)* ','?)?
    | namedexpr_test
    ;

star_named_expressions
    : ',' star_named_expression+ ','?
    ;

// canon: an item of a subject tuple may be a named expression.
star_named_expression
    : '*' expr
    | namedexpr_test
    ;

case_block
    : 'case' patterns guard? ':' block
    ;

// canon: a guard may be a named expression.
guard
    : 'if' namedexpr_test
    ;

patterns
    : open_sequence_pattern
    | pattern
    ;

pattern
    : as_pattern
    | or_pattern
    ;

as_pattern
    : or_pattern 'as' pattern_capture_target
    ;

or_pattern
    : closed_pattern ('|' closed_pattern)*
    ;

closed_pattern
    : literal_pattern
    | capture_pattern
    | wildcard_pattern
    | value_pattern
    | group_pattern
    | sequence_pattern
    | mapping_pattern
    | class_pattern
    ;

literal_pattern
    : signed_number { this.CannotBePlusMinus() }?
    | complex_number
    | strings
    | 'None'
    | 'True'
    | 'False'
    ;

literal_expr
    : signed_number { this.CannotBePlusMinus() }?
    | complex_number
    | strings
    | 'None'
    | 'True'
    | 'False'
    ;

complex_number
    : signed_real_number '+' imaginary_number
    | signed_real_number '-' imaginary_number
    ;

// canon: a number in a pattern may carry a unary plus, as Python 3.15 allows.
signed_number
    : NUMBER
    | ('-' | '+') NUMBER
    ;

signed_real_number
    : real_number
    | ('-' | '+') real_number
    ;

real_number
    : NUMBER
    ;

imaginary_number
    : NUMBER
    ;

capture_pattern
    : pattern_capture_target
    ;

pattern_capture_target
    : /* cannot be '_' */ name { this.CannotBeDotLpEq() }?
    ;

wildcard_pattern
    : '_'
    ;

value_pattern
    : attr { this.CannotBeDotLpEq() }?
    ;

attr
    : name ('.' name)+
    ;

name_or_attr
    : attr
    | name
    ;

group_pattern
    : '(' pattern ')'
    ;

sequence_pattern
    : '[' maybe_sequence_pattern? ']'
    | '(' open_sequence_pattern? ')'
    ;

open_sequence_pattern
    : maybe_star_pattern ',' maybe_sequence_pattern?
    ;

maybe_sequence_pattern
    : maybe_star_pattern (',' maybe_star_pattern)* ','?
    ;

maybe_star_pattern
    : star_pattern
    | pattern
    ;

star_pattern
    : '*' pattern_capture_target
    | '*' wildcard_pattern
    ;

mapping_pattern
    : '{' '}'
    | '{' double_star_pattern ','? '}'
    | '{' items_pattern ',' double_star_pattern ','? '}'
    | '{' items_pattern ','? '}'
    ;

items_pattern
    : key_value_pattern (',' key_value_pattern)*
    ;

key_value_pattern
    : (literal_expr | attr) ':' pattern
    ;

double_star_pattern
    : '**' pattern_capture_target
    ;

class_pattern
    : name_or_attr '(' ')'
    | name_or_attr '(' positional_patterns ','? ')'
    | name_or_attr '(' keyword_patterns ','? ')'
    | name_or_attr '(' positional_patterns ',' keyword_patterns ','? ')'
    ;

positional_patterns
    : pattern (',' pattern)*
    ;

keyword_patterns
    : keyword_pattern (',' keyword_pattern)*
    ;

keyword_pattern
    : name '=' pattern
    ;

// canon: a named expression, as Python 3.8 allows (PEP 572), where an expression may stand alone.
namedexpr_test
    : name ':=' test
    | test
    ;

test
    : or_test ('if' or_test 'else' test)?
    | lambdef
    ;

test_nocond
    : or_test
    | lambdef_nocond
    ;

lambdef
    : 'lambda' varargslist? ':' test
    ;

lambdef_nocond
    : 'lambda' varargslist? ':' test_nocond
    ;

or_test
    : and_test ('or' and_test)*
    ;

and_test
    : not_test ('and' not_test)*
    ;

not_test
    : 'not' not_test
    | comparison
    ;

comparison
    : expr (comp_op expr)*
    ;

// <> isn't actually a valid comparison operator in Python. It's here for the
// sake of a __future__ import described in PEP 401 (which really works :-)
comp_op
    : '<'
    | '>'
    | '=='
    | '>='
    | '<='
    | '<>'
    | '!='
    | 'in'
    | 'not' 'in'
    | 'is'
    | 'is' 'not'
    ;

star_expr
    : '*' expr
    ;

expr
    : atom_expr
    | expr '**' expr
    | ('+' | '-' | '~')+ expr
    | expr ('*' | '@' | '/' | '%' | '//') expr
    | expr ('+' | '-') expr
    | expr ('<<' | '>>') expr
    | expr '&' expr
    | expr '^' expr
    | expr '|' expr
    ;

//expr: xor_expr ('|' xor_expr)*;
//xor_expr: and_expr ('^' and_expr)*;
//and_expr: shift_expr ('&' shift_expr)*;
//shift_expr: arith_expr (('<<'|'>>') arith_expr)*;
//arith_expr: term (('+'|'-') term)*;
//term: factor (('*'|'@'|'/'|'%'|'//') factor)*;
//factor: ('+'|'-'|'~') factor | power;
//power: atom_expr ('**' factor)?;
atom_expr
    : AWAIT? atom trailer*
    ;

// canon: the items of a parenthesized, list, set, or dict display are read in the rule that holds
// their brackets, which were testlist_comp and dictorsetmaker. A rule ending inside a run of items
// built a tree for every item it could end after, so a list of n items took time in n squared, and
// a table of a few thousand numbers took seconds. An item may be a named expression.
atom
    : '(' (yield_expr | (namedexpr_test | star_expr) (comp_for | (',' (namedexpr_test | star_expr))* ','?))? ')'
    | '[' ((namedexpr_test | star_expr) (comp_for | (',' (namedexpr_test | star_expr))* ','?))? ']'
    | '{' (
        (test ':' test | '**' expr) (comp_for | (',' (test ':' test | '**' expr))* ','?)
        | (namedexpr_test | star_expr) (comp_for | (',' (namedexpr_test | star_expr))* ','?)
    )? '}'
    | name
    | NUMBER
    | STRING+
    | '...'
    | 'None'
    | 'True'
    | 'False'
    ;

// canon: case is a soft keyword too, a name outside a match statement.
name
    : NAME
    | '_'
    | 'match'
    | 'case'
    ;

// canon: the arguments and subscripts of a trailer are read in the rule that holds their brackets,
// which were arglist and subscriptlist, so a call with many arguments takes time linear in them.
trailer
    : '(' (argument (',' argument)* ','?)? ')'
    | '[' subscript_ (',' subscript_)* ','? ']'
    | '.' name
    ;

// canon: a subscript may be a named expression, as Python 3.10 allows, or starred, as Python 3.11
// allows (PEP 646).
subscript_
    : namedexpr_test
    | star_expr
    | test? ':' test? sliceop?
    ;

sliceop
    : ':' test?
    ;

exprlist
    : (expr | star_expr) (',' (expr | star_expr))* ','?
    ;

testlist
    : test (',' test)* ','?
    ;

// canon: a class's body is inherited, so its methods require a docstring when it does. A class may
// declare type parameters, as Python 3.12 allows (PEP 695).
classdef
    : (marker += decorator)* 'class' what = definitionName type_params? ('(' (argument (',' argument)* ','?)? ')')? ':' (
        NEWLINE INDENT why = docString? (NEWLINE (inherited += stmt)* | (inherited += stmt)+) DEDENT
        | why = docString? (NEWLINE | inherited = simple_stmts)
    ) # class
    ;

// The reason that keywords are test nodes instead of NAME is that using NAME
// results in an ambiguity. ast.c makes sure it's a NAME.
// "test '=' test" is really "keyword '=' test", but we have no such token.
// These need to be in a single rule to avoid grammar that is ambiguous
// to our LL(1) parser. Even though 'test' includes '*expr' in star_expr,
// we explicitly match '*' here, too, to give it proper precedence.
// Illegal combinations and orderings are blocked in ast.c:
// multiple (test comp_for) arguments are blocked; keyword unpackings
// that precede iterable unpackings are blocked; etc.
// canon: an argument may be a named expression.
argument
    : (namedexpr_test comp_for? | test '=' test | '**' test | '*' test)
    ;

comp_iter
    : comp_for
    | comp_if
    ;

comp_for
    : ASYNC? 'for' exprlist 'in' or_test comp_iter?
    ;

comp_if
    : 'if' test_nocond comp_iter?
    ;

// not used in grammar, but may appear in "node" passed from Parser to Compiler
encoding_decl
    : name
    ;

yield_expr
    : 'yield' yield_arg?
    ;

// canon: a yielded tuple may hold starred items, as Python 3.8 allows.
yield_arg
    : 'from' test
    | testlist_star_expr
    ;

strings
    : STRING+
    ;