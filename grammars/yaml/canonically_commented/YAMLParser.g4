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

// The canonically commented YAML parser, for Pulumi YAML programs. It is the plain parser with the
// sections of a Pulumi program read apart: each entry of resources, variables, outputs, and config
// is a unit named by its key, with the comment directly above it as its Why, and the description
// of a config key is a Why too. Any other YAML file parses as plain YAML and has no units.

parser grammar YAMLParser;

options {
    tokenVocab = YAMLLexer;
}

/** A YAML stream: directives, document markers, and documents up to end of input. ref:DEC-pulumi-yaml-grammar */
yamlFile
    : (DIRECTIVE NEWLINE)* (canonicalComment? DOCUMENT_START NEWLINE?)? document? (NEWLINE? DOCUMENT_END)? (NEWLINE? canonicalComment? DOCUMENT_START NEWLINE? document? (NEWLINE? DOCUMENT_END)?)* EOF
    ;

/** A document: a Pulumi program, read by its sections, or any other node. ref:DEC-pulumi-yaml-grammar */
document
    : programMapping
    | blockNode
    ;

/** The top-level mapping of a Pulumi program. ref:DEC-pulumi-yaml-grammar */
programMapping
    : topEntry (NEWLINE topEntry)*
    ;

/** An entry of a Pulumi program: the resources, variables, outputs, or config section, whose entries are units, or any other entry such as name, runtime, or description. A comment above a section binds to nothing. ref:DEC-pulumi-yaml-grammar */
topEntry
    : canonicalComment? 'resources' COLON (INDENT resourceEntry (NEWLINE resourceEntry)* DEDENT)? # resourcesSection
    | canonicalComment? 'variables' COLON (INDENT variableEntry (NEWLINE variableEntry)* DEDENT)? # variablesSection
    | canonicalComment? 'outputs' COLON (INDENT outputEntry (NEWLINE outputEntry)* DEDENT)? # outputsSection
    | canonicalComment? 'config' COLON (INDENT configEntry (NEWLINE configEntry)* DEDENT)? # configSection
    | mappingEntry # otherEntry
    ;

/** A resource, a unit named by its logical name, with the comment directly above it as its Why and its type, properties, and options as its How. Pulumi defines no description field on a resource. ref:DEC-pulumi-yaml-grammar */
resourceEntry
    : why = canonicalComment? keyName COLON how = mappingValue? # resource
    ;

/** A variable, a unit named by its key, with the comment directly above it as its Why and its expression as its How. ref:DEC-pulumi-yaml-grammar */
variableEntry
    : why = canonicalComment? keyName COLON how = mappingValue? # variable
    ;

/** An output, a unit named by its key, with the comment directly above it as its Why and its expression as its How. An output requires a Why, because it is the stack's interface. ref:DEC-pulumi-yaml-grammar */
outputEntry
    : why = canonicalComment? required = keyName COLON how = mappingValue? # output
    ;

/** A config key, a unit named by its key. The comment directly above it is its Why, and so is its description, which Pulumi shows as its documentation; a comment above wins over the description. A key that declares a type or a default is a declaration of the stack's interface and requires a Why; a key that only sets a value, as a stack file's keys do, does not. ref:DEC-pulumi-yaml-grammar */
configEntry
    : why = canonicalComment? keyName COLON INDENT (canonicalComment? 'description' COLON why = docScalar | canonicalComment? required = 'type' COLON mappingValue? | canonicalComment? required = 'default' COLON mappingValue? | mappingEntry) (NEWLINE (canonicalComment? 'description' COLON why = docScalar | canonicalComment? required = 'type' COLON mappingValue? | canonicalComment? required = 'default' COLON mappingValue? | mappingEntry))* DEDENT # config
    | why = canonicalComment? keyName COLON mappingValue? # config
    ;

/** The key of a unit, whose text is its What; a quoted key keeps its quotes. ref:DEC-pulumi-yaml-grammar */
keyName
    : what = PLAIN
    | what = DOUBLE_QUOTED
    | what = SINGLE_QUOTED
    ;

/** A scalar written as documentation: a plain scalar with its continuation lines, a quoted scalar, or a block scalar. ref:DEC-pulumi-yaml-grammar */
docScalar
    : PLAIN plainContinuation?
    | DOUBLE_QUOTED
    | SINGLE_QUOTED
    | blockScalar
    ;

/** A canonical comment: one or more comment lines with nothing between them, holding prose, reference citations, and license citations. ref:DEC-comment-reasons ref:DEC-pulumi-yaml-grammar */
canonicalComment
    : (DOC_OPEN docPart*)+
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;

/** A node in block context: a mapping, a sequence, a block scalar, or a flow node with any continuation lines. */
blockNode
    : blockMapping
    | blockSequence
    | properties? blockScalar
    | flowNode plainContinuation?
    ;

/** A block mapping: entries at one indentation. */
blockMapping
    : mappingEntry (NEWLINE mappingEntry)*
    ;

/** A mapping entry: a key, a colon, and an optional value, or a complex key after a question mark with its value on the next line. A comment above it binds to nothing. */
mappingEntry
    : canonicalComment? key COLON mappingValue?
    | canonicalComment? QUESTION flowNode? (NEWLINE COLON mappingValue?)?
    ;

/** A mapping key: a scalar, an alias, or a flow collection, with optional properties. */
key
    : properties? (PLAIN | DOUBLE_QUOTED | SINGLE_QUOTED | ALIAS | flowCollection)
    ;

/** The value of a mapping entry: a block scalar or a flow node on the key's line, a node indented below the key, or a sequence at the key's own indentation, which YAML allows. */
mappingValue
    : properties? blockScalar
    | flowNode plainContinuation?
    | properties? INDENT blockNode DEDENT
    | properties? NEWLINE blockSequence
    ;

/** A block sequence: entries at one indentation. */
blockSequence
    : sequenceEntry (NEWLINE sequenceEntry)*
    ;

/** A sequence entry: a dash and an optional node, which the lexer hook indents to its own column whether it follows the dash on its line or starts the next line. A comment above it binds to nothing. */
sequenceEntry
    : canonicalComment? DASH (INDENT blockNode DEDENT)?
    ;

/** The continuation lines of a plain scalar, indented below its first line. */
plainContinuation
    : INDENT PLAIN (NEWLINE PLAIN)* DEDENT
    ;

/** A literal or folded block scalar: its header and the lines the lexer hook keeps in it. */
blockScalar
    : BLOCK_SCALAR BLOCK_SCALAR_TEXT*
    ;

/** A node in flow context, with optional properties, or properties alone. */
flowNode
    : properties? (PLAIN | DOUBLE_QUOTED | SINGLE_QUOTED | ALIAS | flowCollection)
    | properties
    ;

/** The tag and anchor of a node. */
properties
    : (TAG | ANCHOR)+
    ;

/** A flow sequence or a flow mapping. */
flowCollection
    : FLOW_SEQ_OPEN (flowEntry (COMMA flowEntry)* COMMA?)? FLOW_SEQ_CLOSE
    | FLOW_MAP_OPEN (flowEntry (COMMA flowEntry)* COMMA?)? FLOW_MAP_CLOSE
    ;

/** An entry of a flow collection: a node, a pair, or a complex key. */
flowEntry
    : flowNode (COLON flowNode?)?
    | COLON flowNode?
    | QUESTION flowEntry
    ;
