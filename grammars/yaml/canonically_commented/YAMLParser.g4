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
// canon: a bare document may follow a document end marker, as YAML 1.2 allows, and directives may stand before any later document's start marker.
yamlFile
    : (DIRECTIVE NEWLINE)* (canonicalComment? DOCUMENT_START NEWLINE?)? document? (NEWLINE? (DOCUMENT_END (NEWLINE document)? | (DIRECTIVE NEWLINE)* canonicalComment? DOCUMENT_START NEWLINE? document?))* EOF
    ;

/** A document: a Pulumi program, read by its sections, or any other node. ref:DEC-pulumi-yaml-grammar */
// canon: a document after a start marker may be indented as a whole, as Ansible playbooks often are.
document
    : programMapping
    | blockNode
    | INDENT blockNode DEDENT
    ;

/** The top-level mapping of a Pulumi program. ref:DEC-pulumi-yaml-grammar */
programMapping
    : topEntry (NEWLINE topEntry)*
    ;

/** An entry of a Pulumi program: the resources, variables, outputs, or config section, or the template section's config, whose entries are units, or any other entry such as name, runtime, or description. A comment above a section binds to nothing. ref:DEC-pulumi-yaml-grammar */
topEntry
    : canonicalComment? 'resources' COLON (INDENT resourceEntry (NEWLINE resourceEntry)* DEDENT)? # resourcesSection
    | canonicalComment? 'variables' COLON (INDENT variableEntry (NEWLINE variableEntry)* DEDENT)? # variablesSection
    | canonicalComment? 'outputs' COLON (INDENT outputEntry (NEWLINE outputEntry)* DEDENT)? # outputsSection
    | canonicalComment? 'config' COLON (INDENT configEntry (NEWLINE configEntry)* DEDENT)? # configSection
    | canonicalComment? 'template' COLON INDENT templateField (NEWLINE templateField)* DEDENT # templateSection
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

/** An entry of a program's template section: its config section, whose entries are units, or any other entry such as displayName or description. ref:DEC-pulumi-yaml-grammar */
templateField
    : canonicalComment? 'config' COLON (INDENT templateConfigEntry (NEWLINE templateConfigEntry)* DEDENT)? # templateConfigSection
    | mappingEntry # otherTemplateField
    ;

/** A config key of a program's template, which pulumi new asks for when it makes a project from the program: a unit of kind templateConfig named by its key, read as a config key is. ref:DEC-pulumi-yaml-grammar */
templateConfigEntry
    : why = canonicalComment? keyName COLON INDENT (canonicalComment? 'description' COLON why = docScalar | canonicalComment? required = 'type' COLON mappingValue? | canonicalComment? required = 'default' COLON mappingValue? | mappingEntry) (NEWLINE (canonicalComment? 'description' COLON why = docScalar | canonicalComment? required = 'type' COLON mappingValue? | canonicalComment? required = 'default' COLON mappingValue? | mappingEntry))* DEDENT # templateConfig
    | why = canonicalComment? keyName COLON mappingValue? # templateConfig
    ;

/** The key of a unit, whose text without quotes is its What. ref:DEC-pulumi-yaml-grammar */
keyName
    : what = PLAIN
    | QUOTE_OPEN what = QUOTED_TEXT? QUOTE_CLOSE
    ;

/** A scalar written as documentation: a plain scalar with its continuation lines, a quoted scalar, or a block scalar. ref:DEC-pulumi-yaml-grammar */
docScalar
    : PLAIN plainContinuation?
    | quoted
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
// canon: a comment may stand above a scalar or flow node that is a value on its own line, as above a run command; it binds to nothing.
// canon: a node's properties may stand on their own line above the block collection they belong to, as in a sequence entry `- &base` or a document `--- !tag`.
blockNode
    : blockMapping
    | blockSequence
    | canonicalComment? properties? blockScalar
    | canonicalComment? flowNode plainContinuation?
    | canonicalComment? properties NEWLINE (blockMapping | blockSequence)
    | canonicalComment? properties INDENT blockNode DEDENT
    ;

/** A block mapping: entries at one indentation. */
blockMapping
    : mappingEntry (NEWLINE mappingEntry)*
    ;

/** A mapping entry: a key, a colon, and an optional value, or a complex key after a question mark with its value on the next line. A comment above it binds to nothing. */
// canon: a complex key is any node, a block collection or a block scalar too, which the lexer hook indents to its own column after the question mark, as it indents a value after a colon that starts its line.
mappingEntry
    : canonicalComment? key COLON mappingValue?
    | canonicalComment? QUESTION (INDENT blockNode DEDENT)? (NEWLINE canonicalComment? COLON mappingValue?)?
    ;

/** A mapping key: a scalar, an alias, or a flow collection, with optional properties. */
key
    : properties? (PLAIN | quoted | ALIAS | flowCollection)
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

/** The continuation lines of a plain scalar, indented past its parent, which the lexer hook reads as text whatever they hold. */
// canon: continuation lines are PLAIN_CONTINUATION tokens that take no part in layout, so they may be indented unevenly and hold indicators.
plainContinuation
    : PLAIN_CONTINUATION+
    ;

/** A literal or folded block scalar: its header and the lines the lexer hook keeps in it. */
blockScalar
    : BLOCK_SCALAR BLOCK_SCALAR_TEXT*
    ;

/** A node in flow context, with optional properties, or properties alone. */
flowNode
    : properties? (PLAIN | quoted | ALIAS | flowCollection)
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

/** A double-quoted or single-quoted scalar, which the lexer hook splits into its quotes and its text. */
quoted
    : QUOTE_OPEN QUOTED_TEXT? QUOTE_CLOSE
    ;
