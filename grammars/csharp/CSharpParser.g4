// EBNF following ECMA 334 Version 7 language specification.
// MIT License.

// Eclipse Public License - v 1.0, http://www.eclipse.org/legal/epl-v10.html
// Copyright (c) 2013, Christian Wulf (chwchw@gmx.de)
// Copyright (c) 2016-2017, Ivan Kochurkin (kvanttt@gmail.com), Positive Technologies.

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar CSharpParser;

options {
    tokenVocab = CSharpLexer;
    superClass = CSharpParserBase;
}

// Insert here @header for parser.


// entry point
// canon: a file-scoped namespace (C# 10) holds the rest of the file, and top-level statements (C# 9)
// may come before the declarations.
compilation_unit
    : BYTE_ORDER_MARK? extern_alias_directives? using_directives? global_attribute_section* (
        file_scoped_namespace_declaration
        | top_level_statements? namespace_member_declarations?
    ) EOF
    ;

// canon: the statements of a C# 9 program without a Main method.
top_level_statements
    : statement+
    ;

//B.2 Syntactic grammar

//B.2.1 Basic concepts

namespace_or_type_name
    : (identifier type_argument_list? | qualified_alias_member) (
        '.' identifier type_argument_list?
    )*
    ;

//B.2.2 Types
type_
    : base_type ('?' | rank_specifier | '*')*
    ;

// canon: C# 9 function pointer types.
base_type
    : simple_type
    | class_type // represents types: enum, class, interface, delegate, type_parameter
    | VOID '*'
    | tuple_type
    | function_pointer_type
    ;

function_pointer_type
    : DELEGATE '*' (identifier ('[' identifier (',' identifier)* ']')?)? '<' function_pointer_parameter (
        ',' function_pointer_parameter
    )* '>'
    ;

function_pointer_parameter
    : (REF READONLY? | IN | OUT)? (type_ | VOID)
    ;

tuple_type
    : '(' tuple_element (',' tuple_element)+ ')'
    ;

tuple_element
    : type_ identifier?
    ;

simple_type
    : numeric_type
    | BOOL
    ;

numeric_type
    : integral_type
    | floating_point_type
    | DECIMAL
    ;

integral_type
    : SBYTE
    | BYTE
    | SHORT
    | USHORT
    | INT
    | UINT
    | LONG
    | ULONG
    | CHAR
    ;

floating_point_type
    : FLOAT
    | DOUBLE
    ;

/** namespace_or_type_name, OBJECT, STRING */
class_type
    : namespace_or_type_name
    | OBJECT
    | DYNAMIC
    | STRING
    ;

type_argument_list
    : '<' type_ (',' type_)* '>'
    ;

//B.2.4 Expressions
argument_list
    : argument (',' argument)*
    ;

// canon: C# 11 scoped arguments.
argument
    : (identifier ':')? refout = (REF | OUT | IN)? (expression | (VAR | SCOPED? type_) expression)
    ;

expression
    : assignment
    | non_assignment_expression
    | REF non_assignment_expression
    ;

non_assignment_expression
    : lambda_expression
    | query_expression
    | conditional_expression
    ;

assignment
    : unary_expression assignment_operator expression
    | unary_expression '??=' throwable_expression
    ;

assignment_operator
    : '='
    | '+='
    | '-='
    | '*='
    | '/='
    | '%='
    | '&='
    | '|='
    | '^='
    | '<<='
    | right_shift_assignment
    ;

conditional_expression
    : null_coalescing_expression ('?' throwable_expression ':' throwable_expression)?
    ;

null_coalescing_expression
    : conditional_or_expression ('??' (null_coalescing_expression | throw_expression))?
    ;

conditional_or_expression
    : conditional_and_expression (OP_OR conditional_and_expression)*
    ;

conditional_and_expression
    : inclusive_or_expression (OP_AND inclusive_or_expression)*
    ;

inclusive_or_expression
    : exclusive_or_expression ('|' exclusive_or_expression)*
    ;

exclusive_or_expression
    : and_expression ('^' and_expression)*
    ;

and_expression
    : equality_expression ('&' equality_expression)*
    ;

equality_expression
    : relational_expression ((OP_EQ | OP_NE) relational_expression)*
    ;

relational_expression
    : shift_expression (('<' | '>' | '<=' | '>=') shift_expression | IS pattern | AS type_)*
    ;

shift_expression
    : additive_expression (('<<' | right_shift) additive_expression)*
    ;

additive_expression
    : multiplicative_expression (('+' | '-') multiplicative_expression)*
    ;

// canon: switch and with expressions (C# 8 and 9) and ranges (C# 8) bind tighter than the
// multiplicative operators, as the C# standard places them.
multiplicative_expression
    : switch_expression (('*' | '/' | '%') switch_expression)*
    ;

switch_expression
    : range_expression (
        SWITCH OPEN_BRACE (switch_expression_arm (',' switch_expression_arm)* ','?)? CLOSE_BRACE
        | WITH OPEN_BRACE (member_initializer_list ','?)? CLOSE_BRACE
    )*
    ;

switch_expression_arm
    : pattern case_guard? right_arrow throwable_expression
    ;

range_expression
    : unary_expression
    | unary_expression? '..' unary_expression?
    ;

// https://msdn.microsoft.com/library/6a71f45d(v=vs.110).aspx
unary_expression
    : cast_expression
    | primary_expression
    | '+' unary_expression
    | '-' unary_expression
    | BANG unary_expression
    | '~' unary_expression
    | '++' unary_expression
    | '--' unary_expression
    | AWAIT unary_expression // C# 5
    | '&' unary_expression
    | '*' unary_expression
    | '^' unary_expression // C# 8 ranges
    ;

cast_expression
    : OPEN_PARENS type_ CLOSE_PARENS unary_expression
    ;

primary_expression // Null-conditional operators C# 6: https://msdn.microsoft.com/en-us/library/dn986595.aspx
    : pe = primary_expression_start '!'? bracket_expression* '!'? (
        (member_access | method_invocation | '++' | '--' | '->' identifier) '!'? bracket_expression* '!'?
    )*
    ;

// canon: target-typed new (C# 9), collection expressions (C# 12), static anonymous methods (C# 9),
// and nameof of an unbound generic type (C# 14).
primary_expression_start
    : literal                                                             # literalExpression
    | identifier type_argument_list?                                      # simpleNameExpression
    | OPEN_PARENS expression CLOSE_PARENS                                 # parenthesisExpressions
    | predefined_type                                                     # memberAccessExpression
    | qualified_alias_member                                              # memberAccessExpression
    | LITERAL_ACCESS                                                      # literalAccessExpression
    | THIS                                                                # thisReferenceExpression
    | BASE ('.' identifier type_argument_list? | '[' expression_list ']') # baseAccessExpression
    | NEW (
        type_ (
            object_creation_expression
            | object_or_collection_initializer
            | '[' expression_list ']' rank_specifier* array_initializer?
            | rank_specifier+ array_initializer
        )
        | anonymous_object_initializer
        | rank_specifier array_initializer
        | object_creation_expression
    )                                                                                               # objectCreationExpression
    | OPEN_PARENS argument ( ',' argument)+ CLOSE_PARENS                                            # tupleExpression
    | TYPEOF OPEN_PARENS (unbound_type_name | type_ | VOID) CLOSE_PARENS                            # typeofExpression
    | CHECKED OPEN_PARENS expression CLOSE_PARENS                                                   # checkedExpression
    | UNCHECKED OPEN_PARENS expression CLOSE_PARENS                                                 # uncheckedExpression
    | DEFAULT (OPEN_PARENS type_ CLOSE_PARENS)?                                                     # defaultValueExpression
    | ASYNC? STATIC? DELEGATE (OPEN_PARENS explicit_anonymous_function_parameter_list? CLOSE_PARENS)? block # anonymousMethodExpression
    | SIZEOF OPEN_PARENS type_ CLOSE_PARENS                                                         # sizeofExpression
    // C# 6: https://msdn.microsoft.com/en-us/library/dn986596.aspx
    | NAMEOF OPEN_PARENS ((identifier '.')* identifier | unbound_type_name) CLOSE_PARENS # nameofExpression
    // C# 7.2: stackalloc in general expression context
    | stackalloc_initializer                                        # stackallocExpression
    | '[' (collection_element (',' collection_element)* ','?)? ']' # collectionExpression
    ;

collection_element
    : '..' expression
    | expression
    ;

throwable_expression
    : expression
    | throw_expression
    ;

throw_expression
    : THROW expression
    ;

member_access
    : '?'? '.' identifier type_argument_list?
    ;

bracket_expression
    : '?'? '[' indexer_argument (',' indexer_argument)* ']'
    ;

indexer_argument
    : (identifier ':')? expression
    ;

predefined_type
    : BOOL
    | BYTE
    | CHAR
    | DECIMAL
    | DOUBLE
    | FLOAT
    | INT
    | LONG
    | OBJECT
    | SBYTE
    | SHORT
    | STRING
    | UINT
    | ULONG
    | USHORT
    ;

expression_list
    : expression (',' expression)*
    ;

object_or_collection_initializer
    : object_initializer
    | collection_initializer
    ;

object_initializer
    : OPEN_BRACE (member_initializer_list ','?)? CLOSE_BRACE
    ;

member_initializer_list
    : member_initializer (',' member_initializer)*
    ;

// canon: nested member initializers without a type, as in { A = { B = 1 } }, and indexers with
// several arguments.
member_initializer
    : (identifier | '[' expression_list ']') '=' initializer_value // C# 6
    ;

initializer_value
    : expression
    | object_or_collection_initializer
    ;

collection_initializer
    : OPEN_BRACE element_initializer (',' element_initializer)* ','? CLOSE_BRACE
    ;

element_initializer
    : non_assignment_expression
    | OPEN_BRACE expression_list CLOSE_BRACE
    ;

anonymous_object_initializer
    : OPEN_BRACE (member_declarator_list ','?)? CLOSE_BRACE
    ;

member_declarator_list
    : member_declarator (',' member_declarator)*
    ;

member_declarator
    : primary_expression
    | identifier '=' expression
    ;

unbound_type_name
    : identifier (generic_dimension_specifier? | '::' identifier generic_dimension_specifier?) (
        '.' identifier generic_dimension_specifier?
    )*
    ;

generic_dimension_specifier
    : '<' ','* '>'
    ;

// canon: static lambdas (C# 9), attributes and explicit return types on lambdas (C# 10).
lambda_expression
    : attributes? (ASYNC | STATIC)* return_type? anonymous_function_signature right_arrow anonymous_function_body
    ;

anonymous_function_signature
    : OPEN_PARENS CLOSE_PARENS
    | OPEN_PARENS explicit_anonymous_function_parameter_list CLOSE_PARENS
    | OPEN_PARENS implicit_anonymous_function_parameter_list CLOSE_PARENS
    | identifier
    ;

explicit_anonymous_function_parameter_list
    : explicit_anonymous_function_parameter (',' explicit_anonymous_function_parameter)*
    ;

// canon: attributes, scoped, params and defaults on lambda parameters (C# 10 to 12).
explicit_anonymous_function_parameter
    : attributes? refout = (REF | OUT | IN | SCOPED | PARAMS)? READONLY? type_ identifier ('=' expression)?
    ;

implicit_anonymous_function_parameter_list
    : identifier (',' identifier)*
    ;

anonymous_function_body
    : throwable_expression
    | REF non_assignment_expression
    | block
    ;

query_expression
    : from_clause query_body
    ;

from_clause
    : FROM type_? identifier IN expression
    ;

query_body
    : query_body_clause* select_or_group_clause query_continuation?
    ;

query_body_clause
    : from_clause
    | let_clause
    | where_clause
    | combined_join_clause
    | orderby_clause
    ;

let_clause
    : LET identifier '=' expression
    ;

where_clause
    : WHERE expression
    ;

combined_join_clause
    : JOIN type_? identifier IN expression ON expression EQUALS expression (INTO identifier)?
    ;

orderby_clause
    : ORDERBY ordering (',' ordering)*
    ;

ordering
    : expression dir = (ASCENDING | DESCENDING)?
    ;

select_or_group_clause
    : SELECT expression
    | GROUP expression BY expression
    ;

query_continuation
    : INTO identifier query_body
    ;

//B.2.5 Statements
statement
    : labeled_Statement
    | declarationStatement
    | embedded_statement
    ;

declarationStatement
    : local_variable_declaration ';'
    | local_constant_declaration ';'
    | local_function_declaration
    ;

// canon: attributes on local functions (C# 9).
local_function_declaration
    : attributes? local_function_header local_function_body
    ;

local_function_header
    : local_function_modifiers? return_type identifier type_parameter_list? OPEN_PARENS formal_parameter_list? CLOSE_PARENS
        type_parameter_constraints_clauses?
    ;

// canon: modifiers in any order, extern included.
local_function_modifiers
    : (ASYNC | UNSAFE | STATIC | EXTERN)+
    ;

local_function_body
    : block
    | right_arrow throwable_expression ';'
    | ';'
    ;

labeled_Statement
    : identifier ':' statement
    ;

embedded_statement
    : block
    | simple_embedded_statement
    ;

// canon: await foreach and await using (C# 8).
simple_embedded_statement
    : ';'            # theEmptyStatement
    | expression ';' # expressionStatement

    // selection statements
    | IF OPEN_PARENS expression CLOSE_PARENS if_body (ELSE if_body)?                    # ifStatement
    | SWITCH OPEN_PARENS expression CLOSE_PARENS OPEN_BRACE switch_section* CLOSE_BRACE # switchStatement
    | SWITCH tuple_expression_for_switch OPEN_BRACE switch_section* CLOSE_BRACE          # switchStatement

    // iteration statements
    | WHILE OPEN_PARENS expression CLOSE_PARENS embedded_statement                                            # whileStatement
    | DO embedded_statement WHILE OPEN_PARENS expression CLOSE_PARENS ';'                                     # doStatement
    | FOR OPEN_PARENS for_initializer? ';' expression? ';' for_iterator? CLOSE_PARENS embedded_statement      # forStatement
    | AWAIT? FOREACH OPEN_PARENS (REF READONLY? | READONLY REF)? local_variable_type identifier IN expression CLOSE_PARENS embedded_statement # foreachStatement
    | AWAIT? FOREACH OPEN_PARENS (VAR parenthesized_variable_designation | tuple_type | OPEN_PARENS argument (',' argument)+ CLOSE_PARENS) IN expression CLOSE_PARENS embedded_statement # foreachDeconstructStatement

    // jump statements
    | BREAK ';'                                                              # breakStatement
    | CONTINUE ';'                                                           # continueStatement
    | GOTO (identifier | CASE expression | DEFAULT) ';'                      # gotoStatement
    | RETURN expression? ';'                                                 # returnStatement
    | THROW expression? ';'                                                  # throwStatement
    | TRY block (catch_clauses finally_clause? | finally_clause)             # tryStatement
    | CHECKED block                                                          # checkedStatement
    | UNCHECKED block                                                        # uncheckedStatement
    | LOCK OPEN_PARENS expression CLOSE_PARENS embedded_statement            # lockStatement
    | AWAIT? USING OPEN_PARENS resource_acquisition CLOSE_PARENS embedded_statement # usingStatement
    | YIELD (RETURN expression | BREAK) ';'                                  # yieldStatement

    // unsafe statements
    | UNSAFE block                                                                             # unsafeStatement
    | FIXED OPEN_PARENS pointer_type fixed_pointer_declarators CLOSE_PARENS embedded_statement # fixedStatement
    ;

// canon: switch (a, b) without extra parentheses (C# 8).
tuple_expression_for_switch
    : OPEN_PARENS argument (',' argument)+ CLOSE_PARENS
    ;

block
    : OPEN_BRACE statement_list? CLOSE_BRACE
    ;

// canon: await using declarations (C# 8), scoped locals (C# 11), and deconstructing declarations.
local_variable_declaration
    : (AWAIT? USING | REF | REF READONLY | SCOPED)? local_variable_type local_variable_declarator (
        ',' local_variable_declarator {this.IsLocalVariableDeclaration()}?
    )*
    | FIXED pointer_type fixed_pointer_declarators
    | VAR parenthesized_variable_designation '=' expression
    ;

local_variable_type
    : VAR
    | SCOPED? type_
    ;

local_variable_declarator
    : identifier ('=' REF? local_variable_initializer)?
    ;

local_variable_initializer
    : expression
    | array_initializer
    | stackalloc_initializer
    ;

local_constant_declaration
    : CONST type_ constant_declarators
    ;

if_body
    : block
    | simple_embedded_statement
    ;

switch_section
    : switch_label+ statement_list
    ;

switch_label
    : CASE pattern case_guard? ':'
    | DEFAULT ':'
    ;

case_guard
    : WHEN expression
    ;

// C# 7.0: pattern matching (ECMA-334 §11.20.4)
// canon: the C# 9 to 11 patterns: or, and, not, relational, parenthesized, property, positional,
// list, and slice patterns, with C# 7's constant pattern narrowed below the relational operators.
pattern
    : conjunctive_pattern (OR conjunctive_pattern)*
    ;

conjunctive_pattern
    : negated_pattern (AND negated_pattern)*
    ;

negated_pattern
    : NOT negated_pattern
    | primary_pattern
    ;

primary_pattern
    : VAR variable_designation                                       // var_pattern
    | type_? positional_pattern_clause property_pattern_clause? simple_designation?
    | type_? property_pattern_clause simple_designation?
    | type_ simple_designation                                       // declaration_pattern
    | type_                                                          // type_pattern
    | ('<' | '>' | '<=' | '>=') shift_expression                     // relational_pattern
    | '[' (pattern (',' pattern)* ','?)? ']' simple_designation?     // list_pattern
    | '..' pattern?                                                  // slice_pattern
    | OPEN_PARENS pattern CLOSE_PARENS                               // parenthesized_pattern
    | shift_expression                                               // constant_pattern
    ;

positional_pattern_clause
    : OPEN_PARENS (subpattern (',' subpattern)*)? CLOSE_PARENS
    ;

property_pattern_clause
    : OPEN_BRACE (subpattern (',' subpattern)* ','?)? CLOSE_BRACE
    ;

subpattern
    : (identifier ('.' identifier)* ':')? pattern
    ;

variable_designation
    : simple_designation
    | parenthesized_variable_designation
    ;

parenthesized_variable_designation
    : OPEN_PARENS variable_designation (',' variable_designation)+ CLOSE_PARENS
    ;

simple_designation
    : identifier
    ;

statement_list
    : statement+
    ;

for_initializer
    : local_variable_declaration
    | expression (',' expression)*
    ;

for_iterator
    : expression (',' expression)*
    ;

catch_clauses
    : specific_catch_clause specific_catch_clause* general_catch_clause?
    | general_catch_clause
    ;

specific_catch_clause
    : CATCH OPEN_PARENS class_type identifier? CLOSE_PARENS exception_filter? block
    ;

general_catch_clause
    : CATCH exception_filter? block
    ;

exception_filter // C# 6
    : WHEN OPEN_PARENS expression CLOSE_PARENS
    ;

finally_clause
    : FINALLY block
    ;

resource_acquisition
    : local_variable_declaration
    | expression
    ;

//B.2.6 Namespaces;
// canon: the qi label is dropped, so the qualified identifier is a plain child that names the unit.
namespace_declaration
    : member_prefix NAMESPACE qualified_identifier namespace_body ';'?
    ;

// canon: a C# 10 file-scoped namespace, whose members are the rest of the file.
file_scoped_namespace_declaration
    : member_prefix NAMESPACE qualified_identifier ';' extern_alias_directives? using_directives? namespace_member_declarations?
    ;

qualified_identifier
    : identifier ('.' identifier)*
    ;

namespace_body
    : OPEN_BRACE extern_alias_directives? using_directives? namespace_member_declarations? CLOSE_BRACE
    ;

extern_alias_directives
    : extern_alias_directive+
    ;

extern_alias_directive
    : EXTERN ALIAS identifier ';'
    ;

using_directives
    : using_directive+
    ;

// canon: global using (C# 10) and aliases of any type (C# 12).
using_directive
    : GLOBAL? USING identifier '=' (namespace_or_type_name | type_) ';' # usingAliasDirective
    | GLOBAL? USING namespace_or_type_name ';'                          # usingNamespaceDirective
    // C# 6: https://msdn.microsoft.com/en-us/library/ms228593.aspx
    | GLOBAL? USING STATIC namespace_or_type_name ';' # usingStaticDirective
    ;

namespace_member_declarations
    : namespace_member_declaration+
    ;

namespace_member_declaration
    : namespace_declaration
    | type_declaration
    ;

// canon: attributes and modifiers move from here into each kind of type through member_prefix, so a
// type's node starts at its first attribute and the doc comment above binds to it. Records are C# 9.
type_declaration
    : class_definition
    | struct_definition
    | interface_definition
    | enum_definition
    | delegate_definition
    | record_definition
    ;

qualified_alias_member
    : identifier '::' identifier type_argument_list?
    ;

//B.2.7 Classes;
type_parameter_list
    : '<' type_parameter (',' type_parameter)* '>'
    ;

type_parameter
    : attributes? identifier
    ;

// canon: arguments to the base type's primary constructor (C# 9 records, C# 12 classes).
class_base
    : ':' class_type (OPEN_PARENS argument_list? CLOSE_PARENS)? (',' namespace_or_type_name)*
    ;

interface_type_list
    : namespace_or_type_name (',' namespace_or_type_name)*
    ;

type_parameter_constraints_clauses
    : type_parameter_constraints_clause+
    ;

type_parameter_constraints_clause
    : WHERE identifier ':' type_parameter_constraints
    ;

// canon: allows ref struct (C# 13).
type_parameter_constraints
    : constructor_constraint
    | primary_constraint (',' secondary_constraints)? (',' constructor_constraint)? (',' identifier REF STRUCT)?
    | identifier REF STRUCT
    ;

// canon: notnull and default constraints (C# 8 and 9) read as class types, and nullable class
// types are accepted.
primary_constraint
    : class_type '?'?
    | CLASS '?'?
    | STRUCT
    | UNMANAGED
    | DEFAULT
    ;

// namespace_or_type_name includes identifier
secondary_constraints
    : namespace_or_type_name '?'? (',' namespace_or_type_name '?'?)*
    ;

constructor_constraint
    : NEW OPEN_PARENS CLOSE_PARENS
    ;

class_body
    : OPEN_BRACE class_member_declarations? CLOSE_BRACE
    ;

class_member_declarations
    : class_member_declaration+
    ;

// canon: attributes and modifiers move from here into each kind of member through member_prefix, so a
// member's node starts at its first attribute and the doc comment above binds to it. Structs and
// interfaces share this rule, which is why fixed-size buffers are here, and C# 14 extension blocks
// hold members of their own.
class_member_declaration
    : constant_declaration
    | field_declaration
    | method_declaration
    | property_declaration
    | event_declaration
    | indexer_declaration
    | operator_declaration
    | conversion_operator_declaration
    | constructor_declaration
    | destructor_definition
    | type_declaration
    | fixed_size_buffer_declaration
    | extension_declaration
    ;

extension_declaration
    : member_prefix EXTENSION type_parameter_list? OPEN_PARENS attributes? parameter_modifier? type_ identifier? CLOSE_PARENS type_parameter_constraints_clauses? class_body
    ;

// canon: what upstream wrote before each member, now the start of each kind of member.
member_prefix
    : attributes? all_member_modifiers?
    ;

all_member_modifiers
    : all_member_modifier+
    ;

// canon: public and protected are labeled required, because a member visible outside its assembly
// is the API whose documentation C# asks for; required, file, and readonly members are C# 8 to 11.
// private and internal are labeled optional, which lifts the requirement a member of an interface
// takes from the interface. protected internal is visible outside the assembly and private protected
// is not, in either order, so each pair is one modifier here, tried before its parts.
all_member_modifier
    : required = (PROTECTED INTERNAL | INTERNAL PROTECTED)
    | optional = (PRIVATE PROTECTED | PROTECTED PRIVATE)
    | NEW
    | required = PUBLIC
    | required = PROTECTED
    | optional = INTERNAL
    | optional = PRIVATE
    | READONLY
    | VOLATILE
    | VIRTUAL
    | SEALED
    | OVERRIDE
    | ABSTRACT
    | STATIC
    | UNSAFE
    | EXTERN
    | PARTIAL
    | ASYNC // C# 5
    | REQUIRED
    | FILE
    ;

// represents the intersection of struct_member_declaration and class_member_declaration
// canon: common_member_declaration and typed_member_declaration are folded into class_member_declaration.

constant_declarators
    : constant_declarator (',' constant_declarator)*
    ;

constant_declarator
    : identifier '=' expression
    ;

variable_declarators
    : variable_declarator (',' variable_declarator)*
    ;

variable_declarator
    : identifier ('=' variable_initializer)?
    ;

variable_initializer
    : expression
    | array_initializer
    ;

// canon: ref returns.
return_type
    : (REF READONLY?)? type_
    | VOID
    ;

member_name
    : namespace_or_type_name
    ;

method_body
    : block
    | ';'
    ;

formal_parameter_list
    : parameter_array
    | fixed_parameters (',' parameter_array)?
    ;

fixed_parameters
    : fixed_parameter (',' fixed_parameter)*
    ;

fixed_parameter
    : attributes? parameter_modifier? arg_declaration
    | ARGLIST
    ;

// canon: scoped and ref readonly parameters (C# 11 and 12).
parameter_modifier
    : SCOPED? REF READONLY?
    | SCOPED? OUT
    | SCOPED? IN
    | REF THIS
    | IN THIS
    | THIS REF
    | THIS IN
    | THIS SCOPED? REF?
    | SCOPED
    ;

// canon: params of any collection type (C# 13).
parameter_array
    : attributes? PARAMS (array_type | type_) identifier
    ;

// canon: init accessors (C# 9) and readonly accessors (C# 8), in any order.
accessor_declarations
    : accessor_declaration+
    ;

accessor_declaration
    : attributes? accessor_modifier? (GET | SET | INIT) accessor_body
    ;

accessor_modifier
    : PROTECTED
    | INTERNAL
    | PRIVATE
    | PROTECTED INTERNAL
    | INTERNAL PROTECTED
    | PRIVATE PROTECTED
    | PROTECTED PRIVATE
    | READONLY
    ;

accessor_body
    : block
    | right_arrow throwable_expression ';'
    | ';'
    ;

// canon: expression-bodied add and remove accessors (C# 7).
event_accessor_declarations
    : attributes? (ADD event_accessor_body remove_accessor_declaration | REMOVE event_accessor_body add_accessor_declaration)
    ;

event_accessor_body
    : block
    | right_arrow throwable_expression ';'
    ;

add_accessor_declaration
    : attributes? ADD event_accessor_body
    ;

remove_accessor_declaration
    : attributes? REMOVE event_accessor_body
    ;

// canon: the unsigned right shift (C# 11).
overloadable_operator
    : '+'
    | '-'
    | BANG
    | '~'
    | '++'
    | '--'
    | TRUE
    | FALSE
    | '*'
    | '/'
    | '%'
    | '&'
    | '|'
    | '^'
    | '<<'
    | '>' '>' '>'
    | right_shift
    | OP_EQ
    | OP_NE
    | '>'
    | '<'
    | '>='
    | '<='
    ;

// canon: the conversion operator as a member of its own, with checked operators (C# 11).
conversion_operator_declaration
    : member_prefix (IMPLICIT | EXPLICIT) OPERATOR CHECKED? type_ OPEN_PARENS arg_declaration CLOSE_PARENS (
        body
        | right_arrow throwable_expression ';'
    )
    ;

constructor_initializer
    : ':' (BASE | THIS) OPEN_PARENS argument_list? CLOSE_PARENS
    ;

body
    : block
    | right_arrow throwable_expression ';'
    | ';'
    ;

//B.2.8 Structs
struct_interfaces
    : ':' interface_type_list
    ;

// canon: struct_body and struct_member_declaration are replaced by class_body.

//B.2.9 Arrays
array_type
    : base_type (('*' | '?')* rank_specifier)+
    ;

rank_specifier
    : '[' ','* ']'
    ;

array_initializer
    : OPEN_BRACE (variable_initializer (',' variable_initializer)* ','?)? CLOSE_BRACE
    ;

//B.2.10 Interfaces
variant_type_parameter_list
    : '<' variant_type_parameter (',' variant_type_parameter)* '>'
    ;

variant_type_parameter
    : attributes? variance_annotation? identifier
    ;

variance_annotation
    : IN
    | OUT
    ;

interface_base
    : ':' interface_type_list
    ;

// canon: interface_body, interface_member_declaration, and interface_accessors were unused upstream.

//B.2.11 Enums
enum_base
    : ':' type_
    ;

enum_body
    : OPEN_BRACE (enum_member_declaration (',' enum_member_declaration)* ','?)? CLOSE_BRACE
    ;

enum_member_declaration
    : attributes? identifier ('=' expression)?
    ;

//B.2.12 Delegates

//B.2.13 Attributes
global_attribute_section
    : '[' global_attribute_target ':' attribute_list ','? ']'
    ;

global_attribute_target
    : keyword
    | identifier
    ;

attributes
    : attribute_section+
    ;

attribute_section
    : '[' (attribute_target ':')? attribute_list ','? ']'
    ;

attribute_target
    : keyword
    | identifier
    ;

// canon: each attribute is labeled marker, so canon can tell a test method by its attribute.
attribute_list
    : marker = attribute (',' marker = attribute)*
    ;

attribute
    : namespace_or_type_name (
        OPEN_PARENS (attribute_argument (',' attribute_argument)*)? CLOSE_PARENS
    )?
    ;

attribute_argument
    : (identifier ':')? expression
    ;

//B.3 Grammar extensions for unsafe code
pointer_type
    : (simple_type | class_type) (rank_specifier | '?')* '*'
    | VOID '*'
    ;

fixed_pointer_declarators
    : fixed_pointer_declarator (',' fixed_pointer_declarator)*
    ;

fixed_pointer_declarator
    : identifier '=' fixed_pointer_initializer
    ;

fixed_pointer_initializer
    : '&'? expression
    | stackalloc_initializer
    ;

fixed_size_buffer_declarator
    : identifier '[' expression ']'
    ;

// canon: the fixed-size buffer upstream had in struct_member_declaration.
fixed_size_buffer_declaration
    : member_prefix FIXED type_ fixed_size_buffer_declarator+ ';'
    ;

stackalloc_initializer
    : STACKALLOC type_ '[' expression ']'
    | STACKALLOC type_? '[' expression? ']' OPEN_BRACE (expression (',' expression)* ','?)? CLOSE_BRACE
    ;

right_arrow
    : '=' '>' {this.IsRightArrow()}? // Nothing between the tokens?
    ;

right_shift
    : '>' '>' {this.IsRightShift()}? // Nothing between the tokens?
    ;

right_shift_assignment
    : '>' '>=' {this.IsRightShiftAssignment()}? // Nothing between the tokens?
    ;

literal
    : boolean_literal
    | string_literal
    | INTEGER_LITERAL
    | HEX_INTEGER_LITERAL
    | BIN_INTEGER_LITERAL
    | REAL_LITERAL
    | CHARACTER_LITERAL
    | NULL_
    ;

boolean_literal
    : TRUE
    | FALSE
    ;

// canon: interpolated raw strings, whose holes are parsed.
string_literal
    : interpolated_regular_string
    | interpolated_verbatium_string
    | interpolated_raw_string
    | REGULAR_STRING
    | VERBATIUM_STRING
    | RAW_STRING
    ;

interpolated_raw_string
    : INTERPOLATED_RAW_STRING_START (interpolated_string_expression | RAW_STRING_CONTENT)* RAW_STRING_END
    ;

interpolated_regular_string
    : INTERPOLATED_REGULAR_STRING_START interpolated_regular_string_part* DOUBLE_QUOTE_INSIDE
    ;

interpolated_verbatium_string
    : INTERPOLATED_VERBATIUM_STRING_START interpolated_verbatium_string_part* DOUBLE_QUOTE_INSIDE
    ;

interpolated_regular_string_part
    : interpolated_string_expression
    | DOUBLE_CURLY_INSIDE
    | REGULAR_CHAR_INSIDE
    | REGULAR_STRING_INSIDE
    ;

interpolated_verbatium_string_part
    : interpolated_string_expression
    | DOUBLE_CURLY_INSIDE
    | VERBATIUM_DOUBLE_QUOTE_INSIDE
    | VERBATIUM_INSIDE_STRING
    ;

interpolated_string_expression
    : expression (',' expression)* (':' FORMAT_STRING+)?
    ;

//B.1.7 Keywords
keyword
    : ABSTRACT
    | AS
    | BASE
    | BOOL
    | BREAK
    | BYTE
    | CASE
    | CATCH
    | CHAR
    | CHECKED
    | CLASS
    | CONST
    | CONTINUE
    | DECIMAL
    | DEFAULT
    | DELEGATE
    | DO
    | DOUBLE
    | ELSE
    | ENUM
    | EVENT
    | EXPLICIT
    | EXTERN
    | FALSE
    | FINALLY
    | FIXED
    | FLOAT
    | FOR
    | FOREACH
    | GOTO
    | IF
    | IMPLICIT
    | IN
    | INT
    | INTERFACE
    | INTERNAL
    | IS
    | LOCK
    | LONG
    | NAMESPACE
    | NEW
    | NULL_
    | OBJECT
    | OPERATOR
    | OUT
    | OVERRIDE
    | PARAMS
    | PRIVATE
    | PROTECTED
    | PUBLIC
    | READONLY
    | REF
    | RETURN
    | SBYTE
    | SEALED
    | SHORT
    | SIZEOF
    | STACKALLOC
    | STATIC
    | STRING
    | STRUCT
    | SWITCH
    | THIS
    | THROW
    | TRUE
    | TRY
    | TYPEOF
    | UINT
    | ULONG
    | UNCHECKED
    | UNMANAGED
    | UNSAFE
    | USHORT
    | USING
    | VIRTUAL
    | VOID
    | VOLATILE
    | WHILE
    ;

// -------------------- extra rules for modularization --------------------------------

// canon: each definition starts with member_prefix. Classes and structs take a C# 12 primary
// constructor, and every type may end with a semicolon instead of a body.
class_definition
    : member_prefix CLASS identifier type_parameter_list? primary_constructor_parameters? class_base? type_parameter_constraints_clauses? (
        class_body ';'?
        | ';'
    )
    ;

primary_constructor_parameters
    : OPEN_PARENS formal_parameter_list? CLOSE_PARENS
    ;

struct_definition
    : member_prefix REF? STRUCT identifier type_parameter_list? primary_constructor_parameters? struct_interfaces? type_parameter_constraints_clauses? (
        class_body ';'?
        | ';'
    )
    ;

// canon: C# 9 records and C# 10 record structs.
record_definition
    : member_prefix RECORD (CLASS | STRUCT)? identifier type_parameter_list? primary_constructor_parameters? class_base? type_parameter_constraints_clauses? (
        class_body ';'?
        | ';'
    )
    ;

// canon: the members of an interface are public unless they say otherwise, so its body is labeled
// inherited: a member needs a comment when the interface does, unless it is private or internal.
interface_definition
    : member_prefix INTERFACE identifier variant_type_parameter_list? interface_base? type_parameter_constraints_clauses? (
        inherited = class_body ';'?
        | ';'
    )
    ;

// canon: an enum's members are as visible as the enum, so its body is labeled inherited.
enum_definition
    : member_prefix ENUM identifier enum_base? inherited = enum_body ';'?
    ;

delegate_definition
    : member_prefix DELEGATE return_type identifier variant_type_parameter_list? OPEN_PARENS formal_parameter_list? CLOSE_PARENS type_parameter_constraints_clauses?
        ';'
    ;

event_declaration
    : member_prefix EVENT type_ (
        member_name ('=' variable_initializer)? (',' variable_declarator)* ';'
        | member_name OPEN_BRACE event_accessor_declarations CLOSE_BRACE
    )
    ;

// canon: the first declarator's identifier is the field's own child, so it names the field.
field_declaration
    : member_prefix (REF READONLY? | READONLY REF)? type_ identifier ('=' REF? variable_initializer)? (
        ',' variable_declarator
    )* ';'
    ;

property_declaration // Property initializer & lambda in properties C# 6
    : member_prefix (REF READONLY? | READONLY REF)? type_ member_name (
        OPEN_BRACE accessor_declarations CLOSE_BRACE ('=' variable_initializer ';')?
        | right_arrow throwable_expression ';'
    )
    ;

// canon: the first declarator's identifier is the constant's own child, so it names the constant.
constant_declaration
    : member_prefix CONST type_ identifier '=' expression (',' constant_declarator)* ';'
    ;

indexer_declaration // lamdas from C# 6
    : member_prefix (REF READONLY? | READONLY REF)? type_ (namespace_or_type_name '.')? THIS '[' formal_parameter_list ']' (
        OPEN_BRACE accessor_declarations CLOSE_BRACE
        | right_arrow throwable_expression ';'
    )
    ;

destructor_definition
    : member_prefix '~' identifier OPEN_PARENS CLOSE_PARENS body
    ;

constructor_declaration
    : member_prefix identifier OPEN_PARENS formal_parameter_list? CLOSE_PARENS constructor_initializer? body
    ;

method_declaration // lamdas from C# 6
    : member_prefix return_type method_member_name type_parameter_list? OPEN_PARENS formal_parameter_list? CLOSE_PARENS type_parameter_constraints_clauses? (
        method_body
        | right_arrow throwable_expression ';'
    )
    ;

method_member_name
    : (identifier | identifier '::' identifier) (type_argument_list? '.' identifier)*
    ;

operator_declaration // lamdas form C# 6
    : member_prefix type_ (namespace_or_type_name '.')? OPERATOR CHECKED? overloadable_operator OPEN_PARENS parameter_modifier? arg_declaration (
        ',' parameter_modifier? arg_declaration
    )? CLOSE_PARENS (body | right_arrow throwable_expression ';')
    ;

arg_declaration
    : type_ identifier ('=' expression)?
    ;

method_invocation
    : OPEN_PARENS argument_list? CLOSE_PARENS
    ;

object_creation_expression
    : OPEN_PARENS argument_list? CLOSE_PARENS object_or_collection_initializer?
    ;

// canon: the contextual keywords canon's lexer adds are identifiers too.
identifier
    : IDENTIFIER
    | ADD
    | ALIAS
    | AND
    | ARGLIST
    | ASCENDING
    | ASYNC
    | AWAIT
    | BY
    | DESCENDING
    | DYNAMIC
    | EQUALS
    | EXTENSION
    | FILE
    | FROM
    | GET
    | GLOBAL
    | GROUP
    | INIT
    | INTO
    | JOIN
    | LET
    | NAMEOF
    | NOT
    | ON
    | OR
    | ORDERBY
    | PARTIAL
    | RECORD
    | REMOVE
    | REQUIRED
    | SCOPED
    | SELECT
    | SET
    | UNMANAGED
    | VAR
    | WHEN
    | WHERE
    | WITH
    | YIELD
    ;
