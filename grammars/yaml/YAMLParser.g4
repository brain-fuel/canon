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

// A parser for the block structure of YAML 1.2, written for canon from the YAML specification.
// Indentation arrives as INDENT, DEDENT, and NEWLINE tokens from the lexer hook, so block
// mappings and sequences are context-free here.

parser grammar YAMLParser;

options {
    tokenVocab = YAMLLexer;
}

/** A YAML stream: directives, document markers, and documents up to end of input. */
// canon: a bare document may follow a document end marker, as YAML 1.2 allows, and directives may stand before any later document's start marker.
yamlFile
    : (DIRECTIVE NEWLINE)* (DOCUMENT_START NEWLINE?)? document? (NEWLINE? (DOCUMENT_END (NEWLINE document)? | (DIRECTIVE NEWLINE)* DOCUMENT_START NEWLINE? document?))* EOF
    ;

/** A document: one node, which may be indented past the marker that starts it. */
// canon: a document after a start marker may be indented as a whole, as Ansible playbooks often are.
document
    : blockNode
    | INDENT blockNode DEDENT
    ;

/** A node in block context: a mapping, a sequence, a block scalar, or a flow node with any continuation lines. */
// canon: a node's properties may stand on their own line above the block collection they belong to, as in a sequence entry `- &base` or a document `--- !tag`.
blockNode
    : blockMapping
    | blockSequence
    | properties? blockScalar
    | flowNode plainContinuation?
    | properties NEWLINE (blockMapping | blockSequence)
    | properties INDENT blockNode DEDENT
    ;

/** A block mapping: entries at one indentation. */
blockMapping
    : mappingEntry (NEWLINE mappingEntry)*
    ;

/** A mapping entry: a key, a colon, and an optional value, or a complex key after a question mark with its value on the next line. */
// canon: a complex key is any node, a block collection or a block scalar too, which the lexer hook indents to its own column after the question mark, as it indents a value after a colon that starts its line.
mappingEntry
    : key COLON mappingValue?
    | QUESTION (INDENT blockNode DEDENT)? (NEWLINE COLON mappingValue?)?
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

/** A sequence entry: a dash and an optional node, which the lexer hook indents to its own column whether it follows the dash on its line or starts the next line. */
sequenceEntry
    : DASH (INDENT blockNode DEDENT)?
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
