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
// A definition takes the module attributes above it, one or more lines apart, so that its node
// starts at its first attribute and the @doc above those attributes documents it, as Elixir binds
// every pending attribute to the next definition whatever blank lines lie between. Attributes are
// labeled marker. Documentation attributes with a string value are not taken: they are the
// definition's comment, which canon scans from the text. @doc false and @doc nil hide the
// definition below them and @moduledoc false the module around it, so each is labeled hidden.

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

// The do-block of a module, a protocol, or an implementation, whose statements may include
// @moduledoc false. Only here is it labeled hidden, so a @moduledoc false quoted inside a function
// for a module the function generates does not hide the function.
moduleBody
    : NL* DO moduleBlock END
    ;

moduleBlock
    : separator* (moduleStatement (separator+ moduleStatement)* separator*)?
    ;

moduleStatement
    : definition
    | hiddenModule
    | expression
    ;

// @moduledoc false, which hides the module around it from the documentation.
hiddenModule
    : hidden = MODULEDOC_ATTRIBUTE (FALSE | NIL)
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
    : (marker += attribute NL+)+
    ;

attribute
    : ATTRIBUTE continuation*
    | hidden = DOC_ATTRIBUTE (FALSE | NIL)
    | DOC_ATTRIBUTE KEYWORD continuation*
    ;

moduleDefinition
    : attributes? DEFMODULE moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* moduleBody continuation*
    | attributes? DEFMODULE moduleName continuation*
    ;

protocolDefinition
    : attributes? DEFPROTOCOL moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* moduleBody continuation*
    | attributes? DEFPROTOCOL moduleName continuation*
    ;

implementationDefinition
    : attributes? DEFIMPL moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* moduleBody continuation*
    | attributes? DEFIMPL moduleName continuation*
    ;

publicFunction
    : attributes? DEF definitionHead continuation*
    ;

privateFunction
    : attributes? DEFP definitionHead continuation*
    ;

publicMacro
    : attributes? DEFMACRO definitionHead continuation*
    ;

privateMacro
    : attributes? DEFMACROP definitionHead continuation*
    ;

publicGuard
    : attributes? DEFGUARD definitionHead continuation*
    ;

privateGuard
    : attributes? DEFGUARDP definitionHead continuation*
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
// which the profile turns into a unit by its first word. The name may be written in parentheses,
// as in test("name", context), and may interpolate; a test without a block is a pending test.
// Its node starts at the attributes above it, such as @tag, as a definition's does.
namedBlock
    : attributes? TEST_MACRO STRING_OPEN blockName STRING_CLOSE continuation*
    | attributes? TEST_MACRO OPEN_PAREN NL* STRING_OPEN blockName STRING_CLOSE (NL* COMMA NL* inner)? CLOSE_PAREN continuation*
    ;

blockName
    : stringPart+
    ;

// What follows a definition keyword: the head of an operator definition such as def a <~> b or
// def -value, whose name is the operator, or a name followed by its arguments.
definitionHead
    : operand definitionName operand
    | definitionName operand
    | definitionName
    ;

// The name of a definition. A name computed with unquote, as in def unquote(name)(args), is named
// by its unquote call, since the name is known only when the macro runs.
definitionName
    : IDENTIFIER
    | TEST_MACRO
    | UNQUOTE parenthesized
    | definableOperator
    ;

// The operators Elixir lets a module define with def or defmacro.
definableOperator
    : PLUS
    | MINUS
    | STAR
    | SLASH
    | BANG
    | CARET
    | TILDE3
    | PIPE_RIGHT
    | AT
    | AND
    | OR
    | NOT
    | IN
    | NOT IN
    | RANGE
    | OPERATOR
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
    | RANGE
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
    | sigil
    | TRUE
    | FALSE
    | NIL
    | ELLIPSIS
    // canon: .. alone is the full range.
    | RANGE
    | ATTRIBUTE
    | DOC_ATTRIBUTE
    | MODULEDOC_ATTRIBUTE
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

// A sigil: an uppercase one is a single token, and a lowercase one holds text and interpolations.
sigil
    : SIGIL
    | sigilOpen sigilPart* SIGIL_CLOSE
    ;

sigilOpen
    : SIGIL_HEREDOC_OPEN
    | SIGIL_CHARDOC_OPEN
    | SIGIL_QUOTE_OPEN
    | SIGIL_APOSTROPHE_OPEN
    | SIGIL_SLASH_OPEN
    | SIGIL_BAR_OPEN
    | SIGIL_PAREN_OPEN
    | SIGIL_BRACKET_OPEN
    | SIGIL_BRACE_OPEN
    | SIGIL_ANGLE_OPEN
    ;

sigilPart
    : SIGIL_TEXT
    | SIGIL_INTERPOLATION block CLOSE_BRACE
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

// canon: a parenthesis may open with ->, as the type of a function of no arguments, (-> result),
// and quote(do: (-> x)) write it.
parenthesized
    : OPEN_PAREN inner CLOSE_PAREN
    | OPEN_PAREN NL* ARROW_RIGHT inner CLOSE_PAREN
    ;

list
    : OPEN_BRACKET inner CLOSE_BRACKET
    ;

tuple
    : OPEN_BRACE inner CLOSE_BRACE
    ;

// canon: a struct's name may be an expression, as in %unquote(type){}, %^module{}, %@for{},
// %:"Elixir.User"{}, or the type %URI.t(){}.
map
    : OPEN_MAP inner CLOSE_BRACE
    | PERCENT structName OPEN_BRACE inner CLOSE_BRACE
    ;

structName
    : CARET? (IDENTIFIER | ALIAS | ATTRIBUTE | ATOM | quotedAtom | UNQUOTE parenthesized) (DOT (ALIAS | IDENTIFIER))* parenthesized?
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
