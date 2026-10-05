/**
MIT License
license:MIT

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

// The Gleam parser of canon's Gleam dialect: the plain parser under grammars/gleam, with each item a
// labeled unit alternative whose /// comment, above its attributes, is its Why.

parser grammar GleamParser;

// canon: a doc comment may stand between any two tokens, as inside an expression; where the grammar
// does not accept one, canon reads the file without it and reports it as an orphan, as the strayComment
// options say. ref:DEC-stray-comments
options {
    tokenVocab = GleamLexer;
    strayComment = canonicalComment;
}

/** A Gleam module: its items, its //// comments, labeled file because Gleam joins them all into the documentation of the module, and /// comments that document nothing, labeled orphan. ref:DEC-gleam-dialect */
module
    : (file = moduleComment | item | orphan = canonicalComment)* EOF
    ;

/** An item of a module. */
item
    : importStatement
    | publicFunction
    | privateFunction
    | publicType
    | privateType
    | publicConstant
    | privateConstant
    | targetGroup
    ;

/** A group of items compiled for one target only, as Gleam wrote it before 1.0. ref:DEC-gleam-grammar */
targetGroup
    : IF name OPEN_BRACE (item | file = moduleComment | orphan = canonicalComment)* CLOSE_BRACE
    ;

/** An attribute of the item below it. @internal hides the item from the documentation and is labeled hidden. ref:DEC-hidden-label */
attribute
    : AT hidden = INTERNAL
    | AT name arguments?
    ;

/** A lowercase name, including the words that are names to Gleam but tokens to canon. */
name
    : NAME
    | EXTERNAL
    | INTERNAL
    ;

/** An import, which is no unit, so a /// comment above it is an orphan. */
importStatement
    : (orphan = canonicalComment)? (marker += attribute)* IMPORT modulePath (DOT OPEN_BRACE balanced* CLOSE_BRACE)? (AS (name | DISCARD_NAME))?
    ;

/** The slash-separated path of a module. */
modulePath
    : name (OPERATOR name)*
    ;

/** A public function, a unit whose /// comment, above its attributes, is required; one without a body is external. ref:DEC-gleam-dialect */
publicFunction
    : why = canonicalComment? (marker += attribute)* required = PUB FN what = definitionName arguments (ARROW_RIGHT type_)? how = body? # function
    | why = canonicalComment? (marker += attribute)* required = PUB EXTERNAL FN what = definitionName arguments ARROW_RIGHT type_ EQUALS STRING STRING # function
    ;

/** A private function, whose comment is optional. ref:DEC-gleam-dialect */
privateFunction
    : why = canonicalComment? (marker += attribute)* FN what = definitionName arguments (ARROW_RIGHT type_)? how = body? # function
    | why = canonicalComment? (marker += attribute)* EXTERNAL FN what = definitionName arguments ARROW_RIGHT type_ EQUALS STRING STRING # function
    ;

/** A public type, custom or alias or external, whose comment is required. ref:DEC-gleam-dialect */
publicType
    : why = canonicalComment? (marker += attribute)* required = PUB OPAQUE? TYPE what = typeName typeParameters? how = typeBody? # type
    | why = canonicalComment? (marker += attribute)* required = PUB EXTERNAL TYPE what = typeName typeParameters? # type
    ;

/** A private type, whose comment is optional. ref:DEC-gleam-dialect */
privateType
    : why = canonicalComment? (marker += attribute)* TYPE what = typeName typeParameters? how = typeBody? # type
    | why = canonicalComment? (marker += attribute)* EXTERNAL TYPE what = typeName typeParameters? # type
    ;

/** The constructors of a custom type, or the type an alias names. */
typeBody
    : OPEN_BRACE (constructor | orphan = canonicalComment)* CLOSE_BRACE
    | EQUALS type_
    ;

/** A constructor of a custom type, whose comment is optional. ref:DEC-gleam-dialect */
constructor
    : why = canonicalComment? (marker += attribute)* what = constructorName fields? # constructor
    ;

/** The fields of a constructor. */
fields
    : OPEN_PAREN (field (COMMA field)* COMMA?)? orphan = canonicalComment? CLOSE_PAREN
    ;

/** A field of a constructor: a labelled one is a unit whose comment is optional; an unlabelled one has no name, so a comment above it is an orphan. ref:DEC-gleam-dialect */
field
    : why = canonicalComment? what = fieldName COLON type_ # field
    | orphan = canonicalComment? type_ # unlabelledField
    ;

/** The label of a field. */
fieldName
    : name
    ;

/** A public constant, whose comment is required. ref:DEC-gleam-dialect */
publicConstant
    : why = canonicalComment? (marker += attribute)* required = PUB CONST what = definitionName (COLON type_)? EQUALS how = constantValue # const
    ;

/** A private constant, whose comment is optional. ref:DEC-gleam-dialect */
privateConstant
    : why = canonicalComment? (marker += attribute)* CONST what = definitionName (COLON type_)? EQUALS how = constantValue # const
    ;

/** The name of a function or a constant, its What. */
definitionName
    : name
    ;

/** The name of a type, its What. */
typeName
    : UPNAME
    ;

/** The name of a constructor, its What. */
constructorName
    : UPNAME
    ;

/** The parameters of a type, read as balanced brackets. */
typeParameters
    : OPEN_PAREN balanced* CLOSE_PAREN
    ;

/** A type annotation, or a tuple type in the syntax before v0.15. ref:DEC-gleam-grammar */
// canon: tuple(A, B) is the tuple type written before Gleam v0.15 replaced it with #(A, B).
type_
    : FN OPEN_PAREN typeList? CLOSE_PAREN ARROW_RIGHT type_
    | HASH OPEN_PAREN typeList? CLOSE_PAREN
    | 'tuple' OPEN_PAREN typeList? CLOSE_PAREN
    | (name DOT)? UPNAME (OPEN_PAREN typeList? CLOSE_PAREN)?
    | name
    | DISCARD_NAME
    ;

/** A list of types. */
typeList
    : type_ (COMMA type_)* COMMA?
    ;

/** The value of a constant. */
constantValue
    : constantTerm (OPERATOR constantTerm)*
    ;

/** A term of a constant value. */
constantTerm
    : MINUS? (INTEGER | FLOAT)
    | STRING
    | OPEN_BRACKET balanced* CLOSE_BRACKET
    | HASH OPEN_PAREN balanced* CLOSE_PAREN
    | OPEN_BITS bitPart* CLOSE_BITS
    | (name DOT)? (name | UPNAME) arguments?
    ;

/** A part of a bit array. */
bitPart
    : ~(OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET | OPEN_BRACE | CLOSE_BRACE | OPEN_BITS | CLOSE_BITS)
    | arguments
    | OPEN_BITS bitPart* CLOSE_BITS
    ;

/** Arguments or parameters, read as balanced brackets. */
arguments
    : OPEN_PAREN balanced* CLOSE_PAREN
    ;

/** The body of a function, read as balanced brackets. */
body
    : OPEN_BRACE balanced* CLOSE_BRACE
    ;

/** Any token, a bracketed sequence of them, so a body is read without its expressions, or /// lines inside it, which document nothing there and are labeled orphan. ref:DEC-gleam-dialect ref:DEC-stray-comments */
// canon: /// lines inside brackets are a canonical comment, an orphan, rather than tokens of the body.
balanced
    : orphan = canonicalComment
    | ~(OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET | OPEN_BRACE | CLOSE_BRACE | DOC_OPEN)
    | OPEN_PAREN balanced* CLOSE_PAREN
    | OPEN_BRACKET balanced* CLOSE_BRACKET
    | OPEN_BRACE balanced* CLOSE_BRACE
    ;

/** Consecutive /// lines, the canonical comment of the item below them. Gleam joins every /// line since the previous item, so blank lines do not part them. ref:DEC-gleam-dialect ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : (DOC_OPEN docPart* DOC_CLOSE)+
    ;

/** Consecutive //// lines, documentation of the module. ref:DEC-gleam-dialect */
moduleComment
    : (MODULE_DOC_OPEN docPart* DOC_CLOSE)+
    ;

/** One piece of documentation: a reference citation, a license citation, or prose. */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
