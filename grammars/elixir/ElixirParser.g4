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

// A structural parser for Elixir, written for canon. A file is a sequence of statements separated
// by newlines or semicolons; a statement is a definition or an expression; an expression is a chain
// of operands joined by juxtaposition, as in a call without parentheses, or by binary operators,
// with brackets, do-blocks, and anonymous functions nested as operands. A newline continues an
// expression after a binary operator, a comma, or a keyword, and before a binary operator that
// cannot start an expression, as Elixir's tokenizer does. Operator precedence is not modelled.
//
// A definition takes the module attributes directly above it, one per line, so that its node
// starts at its first attribute and the @doc above those attributes documents it. Attributes are
// labeled marker. Documentation attributes with a string value are not taken: they are the
// definition's comment, which canon scans from the text.

parser grammar ElixirParser;

options {
    tokenVocab = ElixirLexer;
}

file
    : block EOF
    ;

block
    : separator* (statement (separator+ statement)* separator*)?
    ;

separator
    : NL
    | SEMICOLON
    ;

statement
    : definition
    | expression
    ;

definition
    : moduleDefinition
    | protocolDefinition
    | implementationDefinition
    | publicFunction
    | privateFunction
    | publicMacro
    | privateMacro
    | publicGuard
    | privateGuard
    | delegateDefinition
    | structDefinition
    | exceptionDefinition
    | typeDefinition
    | callbackDefinition
    | namedBlock
    ;

attributes
    : (marker += attribute NL)+
    ;

attribute
    : ATTRIBUTE continuation*
    | DOC_ATTRIBUTE (FALSE | NIL | KEYWORD continuation*)
    ;

moduleDefinition
    : attributes? DEFMODULE moduleName continuation*
    ;

protocolDefinition
    : attributes? DEFPROTOCOL moduleName continuation*
    ;

implementationDefinition
    : attributes? DEFIMPL moduleName continuation*
    ;

publicFunction
    : attributes? DEF definitionName continuation*
    ;

privateFunction
    : attributes? DEFP definitionName continuation*
    ;

publicMacro
    : attributes? DEFMACRO definitionName continuation*
    ;

privateMacro
    : attributes? DEFMACROP definitionName continuation*
    ;

publicGuard
    : attributes? DEFGUARD definitionName continuation*
    ;

privateGuard
    : attributes? DEFGUARDP definitionName continuation*
    ;

delegateDefinition
    : attributes? DEFDELEGATE definitionName continuation*
    ;

structDefinition
    : attributes? DEFSTRUCT continuation*
    ;

exceptionDefinition
    : attributes? DEFEXCEPTION continuation*
    ;

typeDefinition
    : attributes? TYPE_ATTRIBUTE definitionName continuation*
    ;

callbackDefinition
    : attributes? CALLBACK_ATTRIBUTE definitionName continuation*
    ;

// A call such as test "name" do ... end or describe "name" do ... end, with a do-block or do:,
// which the profile turns into a unit by its first word.
// Its node starts at the attributes above it, such as @tag, as a definition's does.
namedBlock
    : attributes? TEST_MACRO STRING_OPEN blockName? STRING_CLOSE continuation*
    ;

blockName
    : stringPart+
    ;

definitionName
    : IDENTIFIER
    | TEST_MACRO
    ;

moduleName
    : (ALIAS | IDENTIFIER | ATTRIBUTE) (DOT (ALIAS | IDENTIFIER))*
    ;

expression
    : operand continuation*
    ;

continuation
    : NL* DOT operatorName
    | NL* leadingOperator NL* operand
    | trailingOperator NL* operand
    | operand
    ;

// Binary operators that cannot start an expression, so a newline before one continues the line.
leadingOperator
    : PIPE_RIGHT
    | DOT
    | WHEN
    | AND
    | OR
    | IN
    | NOT IN
    | ARROW_RIGHT
    | ARROW_LEFT
    | FAT_ARROW
    | DOUBLE_COLON
    | DEFAULT_ARG
    | EQUALS
    | PIPE
    | STAR
    | SLASH
    | OPERATOR
    ;

trailingOperator
    : COMMA
    ;

operand
    : prefix* primary
    ;

prefix
    : (PLUS | MINUS | BANG | CARET | CAPTURE | NOT | TILDE3 | AT | KEYWORD | COLON) NL*
    ;

primary
    : IDENTIFIER
    | TEST_MACRO
    | ALIAS
    | ATOM
    | quotedAtom
    | INTEGER
    | FLOAT
    | HEX
    | OCTAL
    | BINARY
    | CHAR
    | string
    | heredoc
    | CHARLIST
    | CHARLIST_HEREDOC
    | SIGIL
    | TRUE
    | FALSE
    | NIL
    | ELLIPSIS
    | ATTRIBUTE
    | DOC_ATTRIBUTE
    | TYPE_ATTRIBUTE
    | CALLBACK_ATTRIBUTE
    | UNQUOTE
    | definitionWord
    | capturedOperator
    | parenthesized
    | list
    | tuple
    | map
    | bitstring
    | doBlock
    | anonymousFunction
    ;

definitionWord
    : DEFMODULE
    | DEFPROTOCOL
    | DEFIMPL
    | DEFSTRUCT
    | DEFEXCEPTION
    | DEFDELEGATE
    | DEFGUARD
    | DEFGUARDP
    | DEFMACRO
    | DEFMACROP
    | DEF
    | DEFP
    ;

// An operator called by name, as in Kernel.<>(a, b) or :queue.in(x, q).
operatorName
    : leadingOperator
    | PLUS
    | MINUS
    | BANG
    | CARET
    | TILDE3
    | CAPTURE
    | NOT
    ;

// An operator named as a function, as in &+/2 or Kernel.++/2.
capturedOperator
    : (leadingOperator | PLUS | MINUS | BANG | CARET | TILDE3 | CAPTURE | OPEN_BITS) SLASH INTEGER
    ;

string
    : STRING_OPEN stringPart* STRING_CLOSE
    ;

quotedAtom
    : ATOM_STRING_OPEN stringPart* STRING_CLOSE
    ;

stringPart
    : STRING_TEXT
    | STRING_HASH
    | STRING_INTERPOLATION block CLOSE_BRACE
    ;

heredoc
    : HEREDOC_OPEN heredocPart* HEREDOC_CLOSE
    ;

heredocPart
    : HEREDOC_TEXT
    | HEREDOC_PUNCTUATION
    | HEREDOC_INTERPOLATION block CLOSE_BRACE
    ;

parenthesized
    : OPEN_PAREN inner CLOSE_PAREN
    ;

list
    : OPEN_BRACKET inner CLOSE_BRACKET
    ;

tuple
    : OPEN_BRACE inner CLOSE_BRACE
    ;

map
    : OPEN_MAP inner CLOSE_BRACE
    ;

bitstring
    : OPEN_BITS inner CLOSE_BITS
    ;

// The inside of a bracket: statements, as in a parenthesized block, with an optional trailing comma.
inner
    : separator* (statement (separator+ statement)* COMMA? separator*)?
    ;

doBlock
    : DO block (blockKeyword block)* END
    ;

blockKeyword
    : ELSE
    | RESCUE
    | CATCH
    | AFTER
    ;

anonymousFunction
    : FN block END
    | FN separator* ARROW_RIGHT block END
    ;
