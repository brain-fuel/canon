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

// A parser for the module level of Gleam, written for canon from the Gleam language tour and the
// Gleam compiler's parser. A module is a sequence of imports, constants, types, and functions,
// each with the attributes directly above it, labeled marker, so that the node of an item starts at
// its first attribute and the /// comment above those attributes documents it. Function bodies,
// parameter lists, and constructor fields are read as balanced brackets, since canon needs the
// items of a module and not the expressions inside them.

parser grammar GleamParser;

options {
    tokenVocab = GleamLexer;
}

module
    : item* EOF
    ;

item
    : importStatement
    | publicFunction
    | privateFunction
    | publicType
    | privateType
    | publicConstant
    | privateConstant
    ;

attribute
    : AT NAME arguments?
    ;

importStatement
    : (marker += attribute)* IMPORT modulePath (DOT OPEN_BRACE balanced* CLOSE_BRACE)? (AS (NAME | DISCARD_NAME))?
    ;

modulePath
    : NAME (OPERATOR NAME)*
    ;

publicFunction
    : (marker += attribute)* PUB FN definitionName arguments (ARROW_RIGHT type_)? body?
    ;

privateFunction
    : (marker += attribute)* FN definitionName arguments (ARROW_RIGHT type_)? body?
    ;

publicType
    : (marker += attribute)* PUB OPAQUE? TYPE typeName typeParameters? typeBody?
    ;

privateType
    : (marker += attribute)* TYPE typeName typeParameters? typeBody?
    ;

typeBody
    : OPEN_BRACE constructor* CLOSE_BRACE
    | EQUALS type_
    ;

constructor
    : (marker += attribute)* constructorName fields?
    ;

fields
    : OPEN_PAREN (field (COMMA field)* COMMA?)? CLOSE_PAREN
    ;

// A labelled field is a unit, since Gleam documents it with /// like an item; an unlabelled one
// has no name and is not.
field
    : (fieldName COLON)? type_
    ;

fieldName
    : NAME
    ;

publicConstant
    : (marker += attribute)* PUB CONST definitionName (COLON type_)? EQUALS constantValue
    ;

privateConstant
    : (marker += attribute)* CONST definitionName (COLON type_)? EQUALS constantValue
    ;

definitionName
    : NAME
    ;

typeName
    : UPNAME
    ;

constructorName
    : UPNAME
    ;

typeParameters
    : OPEN_PAREN balanced* CLOSE_PAREN
    ;

type_
    : FN OPEN_PAREN typeList? CLOSE_PAREN ARROW_RIGHT type_
    | HASH OPEN_PAREN typeList? CLOSE_PAREN
    | (NAME DOT)? UPNAME (OPEN_PAREN typeList? CLOSE_PAREN)?
    | NAME
    | DISCARD_NAME
    ;

typeList
    : type_ (COMMA type_)* COMMA?
    ;

constantValue
    : constantTerm (OPERATOR constantTerm)*
    ;

constantTerm
    : MINUS? (INTEGER | FLOAT)
    | STRING
    | OPEN_BRACKET balanced* CLOSE_BRACKET
    | HASH OPEN_PAREN balanced* CLOSE_PAREN
    | OPEN_BITS bitPart* CLOSE_BITS
    | (NAME DOT)? (NAME | UPNAME) arguments?
    ;

bitPart
    : ~(OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET | OPEN_BRACE | CLOSE_BRACE | OPEN_BITS | CLOSE_BITS)
    | arguments
    | OPEN_BITS bitPart* CLOSE_BITS
    ;

arguments
    : OPEN_PAREN balanced* CLOSE_PAREN
    ;

body
    : OPEN_BRACE balanced* CLOSE_BRACE
    ;

balanced
    : ~(OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET | OPEN_BRACE | CLOSE_BRACE)
    | OPEN_PAREN balanced* CLOSE_PAREN
    | OPEN_BRACKET balanced* CLOSE_BRACKET
    | OPEN_BRACE balanced* CLOSE_BRACE
    ;
