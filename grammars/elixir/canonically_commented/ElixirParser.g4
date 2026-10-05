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

// The Elixir parser of canon's Elixir dialect: the plain parser under grammars/elixir, with each kind
// of definition a labeled unit alternative whose @doc is its Why. A doc comment, @doc false, and the
// attributes above a definition may come in any order; the last doc wins, as in Elixir.

parser grammar ElixirParser;

// canon: a doc comment may stand between any two tokens, as inside an expression; where the grammar
// does not accept one, canon reads the file without it and reports it as an orphan, as the strayComment
// options say. ref:DEC-stray-comments
options {
    tokenVocab = ElixirLexer;
    strayComment = canonicalComment;
    strayComment = typeComment;
    strayComment = moduleComment;
}

/** An Elixir file is a block of statements up to end of input. */
file
    : block EOF
    ;

/** A sequence of statements separated by newlines or semicolons, with separators allowed at either end. */
block
    : separator* (statement (separator+ statement)* separator*)?
    ;

/** What separates two statements: a newline or a semicolon. */
separator
    : NL
    | SEMICOLON
    ;

/** A statement: a definition, an expression, or documentation that documents nothing, labeled orphan and reported, as a @doc before an expression is. ref:DEC-elixir-dialect */
statement
    : definition
    | orphan = canonicalComment
    | orphan = typeComment
    | orphan = moduleComment
    | expression
    ;

/** The statements of a module body. */
moduleBlock
    : separator* (moduleStatement (separator+ moduleStatement)* separator*)?
    ;

/** A statement of a module body. A @moduledoc anywhere in the body is the Why of the module, and a second one is reported. @moduledoc false hides the module and is labeled hidden here only, so a @moduledoc false quoted for a module a function generates does not hide the function. ref:DEC-elixir-dialect ref:DEC-hidden-label */
moduleStatement
    : definition
    | hidden = hiddenModule
    | orphan = canonicalComment
    | orphan = typeComment
    | why = moduleComment
    | expression
    ;

/** @moduledoc false, which hides the module around it from the documentation. ref:DEC-hidden-label */
hiddenModule
    : MODULEDOC_ATTRIBUTE (FALSE | NIL)
    ;

/** A definition of any kind, each a unit. */
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

/** A module attribute a definition carries, such as @spec or @impl, or @doc with keyword metadata. A @doc with a string is a canonical comment instead. ref:DEC-elixir-dialect */
attribute
    : ATTRIBUTE continuation*
    | DOC_ATTRIBUTE KEYWORD continuation*
    ;

/** A module. Its canonical comment is the first @moduledoc in its body, at its start or wherever other statements put it, and is required unless @moduledoc false hides the module; its name is the What and its body the How. ref:DEC-elixir-dialect */
moduleDefinition
    : (orphan = canonicalComment separator+ | marker += attribute NL+)* required = DEFMODULE what = moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* NL* DO separator* why = moduleComment? how = moduleBlock END continuation* # module
    | (orphan = canonicalComment separator+ | marker += attribute NL+)* required = DEFMODULE what = moduleName why = moduleComment? continuation* # module
    ;

/** A protocol, documented by @moduledoc as a module is, whose comment is required. ref:DEC-elixir-dialect */
protocolDefinition
    : (orphan = canonicalComment separator+ | marker += attribute NL+)* required = DEFPROTOCOL what = moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* NL* DO separator* why = moduleComment? how = moduleBlock END continuation* # protocol
    | (orphan = canonicalComment separator+ | marker += attribute NL+)* required = DEFPROTOCOL what = moduleName why = moduleComment? continuation* # protocol
    ;

/** A protocol implementation, documented by @moduledoc as a module is, whose comment is optional. ref:DEC-elixir-dialect */
implementationDefinition
    : (orphan = canonicalComment separator+ | marker += attribute NL+)* DEFIMPL what = moduleName (COMMA NL* KEYWORD NL* (moduleName | operand))* NL* DO separator* why = moduleComment? how = moduleBlock END continuation* # impl
    | (orphan = canonicalComment separator+ | marker += attribute NL+)* DEFIMPL what = moduleName why = moduleComment? continuation* # impl
    ;

/** A public function clause. A @doc above it and its attributes is its Why and is required; the last @doc wins, so an earlier one is an orphan and a later @doc false hides the function. Clauses of one name are labeled merge, so adjacent clauses are one function unless a @doc above a later one starts another. ref:DEC-elixir-dialect ref:DEC-hidden-label */
publicFunction
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) required = DEF merge = definitionHead continuation* # function
    ;

/** A private function clause, whose comment is optional. ref:DEC-elixir-dialect */
privateFunction
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) DEFP merge = definitionHead continuation* # function
    ;

/** A public macro clause, documented and merged as a public function is. ref:DEC-elixir-dialect */
publicMacro
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) required = DEFMACRO merge = definitionHead continuation* # macro
    ;

/** A private macro clause, whose comment is optional. ref:DEC-elixir-dialect */
privateMacro
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) DEFMACROP merge = definitionHead continuation* # macro
    ;

/** A public guard, documented as a public function is. ref:DEC-elixir-dialect */
publicGuard
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) required = DEFGUARD merge = definitionHead continuation* # guard
    ;

/** A private guard, whose comment is optional. ref:DEC-elixir-dialect */
privateGuard
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) DEFGUARDP merge = definitionHead continuation* # guard
    ;

/** A function delegated to another module, documented as a public function is. ref:DEC-elixir-dialect */
delegateDefinition
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) required = DEFDELEGATE what = definitionName continuation* # function
    ;

/** A struct, named by its keyword, whose comment is optional. ref:DEC-elixir-dialect */
structDefinition
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) what = DEFSTRUCT continuation* # struct
    ;

/** An exception, named by its keyword, whose comment is optional. ref:DEC-elixir-dialect */
exceptionDefinition
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) what = DEFEXCEPTION continuation* # exception
    ;

/** A type, documented by @typedoc and by nothing else, whose comment is optional. ref:DEC-elixir-dialect */
typeDefinition
    : ((orphan = typeComment separator+ | orphan = canonicalComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = typeComment separator+ (marker += attribute NL+)* | (orphan = typeComment separator+ | orphan = canonicalComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = typeComment? (marker += attribute NL+)*) TYPE_ATTRIBUTE what = definitionName continuation* # type
    ;

/** A callback, documented as a public function is, whose comment is required. ref:DEC-elixir-dialect */
callbackDefinition
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) required = CALLBACK_ATTRIBUTE what = definitionName continuation* # callback
    ;

/** An ExUnit or StreamData test, or a describe block, named by its string, written with or without parentheses. A test always requires its comment, which cites the requirement it verifies. ref:DEC-elixir-dialect */
namedBlock
    : ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) TEST_MACRO STRING_OPEN what = blockName STRING_CLOSE continuation* # test
    | ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) TEST_MACRO OPEN_PAREN NL* STRING_OPEN what = blockName STRING_CLOSE (NL* COMMA NL* inner)? CLOSE_PAREN continuation* # test
    | ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) DESCRIBE_MACRO STRING_OPEN what = blockName STRING_CLOSE continuation* # describe
    | ((orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* why = canonicalComment separator+ (marker += attribute NL+)* | (orphan = canonicalComment separator+ | orphan = typeComment separator+ | hiddenDoc NL+ | marker += attribute NL+)* hidden = hiddenDoc NL+ (marker += attribute NL+)* | why = canonicalComment? (marker += attribute NL+)*) DESCRIBE_MACRO OPEN_PAREN NL* STRING_OPEN what = blockName STRING_CLOSE (NL* COMMA NL* inner)? CLOSE_PAREN continuation* # describe
    ;

/** The text of a test or describe name, interpolations included. */
blockName
    : stringPart+
    ;

/** What follows a definition keyword: an operator definition such as def a <~> b or def -value, named by its operator, or a name and its arguments. ref:DEC-elixir-dialect */
definitionHead
    : operand what = definitionName operand
    | what = definitionName operand
    | what = definitionName
    ;

/** The name of a definition, the What of its unit. A name computed with unquote, as in def unquote(name)(args), is named by its unquote call. ref:DEC-elixir-dialect */
definitionName
    : IDENTIFIER
    | TEST_MACRO
    | DESCRIBE_MACRO
    | UNQUOTE parenthesized
    | definableOperator
    ;

/** The operators Elixir lets a module define with def or defmacro. */
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
    | OPERATOR
    ;

/** A module name, an alias or an atom with its dotted parts. */
moduleName
    : (ALIAS | IDENTIFIER | ATTRIBUTE) (DOT (ALIAS | IDENTIFIER))*
    ;

/** An expression: an operand and what continues it. */
expression
    : operand continuation*
    ;

/** What continues an expression: a dotted call, a binary operator and its operand, a comma, or an operand applied by juxtaposition. */
continuation
    : NL* DOT operatorName
    | NL* leadingOperator NL* operand
    | trailingOperator NL* operand
    | operand
    ;

/** Binary operators that cannot start an expression, so a newline before one continues the line. */
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

/** The comma, after which a newline continues the line. */
trailingOperator
    : COMMA
    ;

/** An operand with its prefix operators. */
operand
    : prefix* primary
    ;

/** A prefix operator, a keyword key, or a colon before an operand. */
prefix
    : (PLUS | MINUS | BANG | CARET | CAPTURE | NOT | TILDE3 | AT | KEYWORD | COLON) NL*
    ;

/** A literal, a name, a bracketed form, or documentation that stands where a value does, as in x + @doc "text", which documents nothing and is labeled orphan. ref:DEC-elixir-dialect ref:DEC-stray-comments */
// canon: a @doc, @typedoc, or @moduledoc is an attribute, an expression that may be an operand.
primary
    : IDENTIFIER
    | TEST_MACRO
    | DESCRIBE_MACRO
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
    | orphan = canonicalComment
    | orphan = typeComment
    | orphan = moduleComment
    ;

/** A definition keyword used as a plain name, as in a quote. */
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

/** An operator called by name, as in Kernel.<>(a, b). */
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

/** An operator named as a function, as in &+/2. */
capturedOperator
    : (leadingOperator | PLUS | MINUS | BANG | CARET | TILDE3 | CAPTURE | OPEN_BITS) SLASH INTEGER
    ;

/** A double-quoted string. */
string
    : STRING_OPEN stringPart* STRING_CLOSE
    ;

/** A sigil: an uppercase one as a single token, or a lowercase one with its text and interpolations. */
sigil
    : SIGIL
    | sigilOpen sigilPart* SIGIL_CLOSE
    ;

/** The opening of a lowercase sigil, one per delimiter. */
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

/** Text or an interpolation inside a lowercase sigil. */
sigilPart
    : SIGIL_TEXT
    | SIGIL_INTERPOLATION block CLOSE_BRACE
    ;

/** A quoted atom. */
quotedAtom
    : ATOM_STRING_OPEN stringPart* STRING_CLOSE
    ;

/** Text, a hash, or an interpolation inside a string. */
stringPart
    : STRING_TEXT
    | STRING_HASH
    | STRING_INTERPOLATION block CLOSE_BRACE
    ;

/** A heredoc. */
heredoc
    : HEREDOC_OPEN heredocPart* HEREDOC_CLOSE
    ;

/** Text, punctuation, or an interpolation inside a heredoc. */
heredocPart
    : HEREDOC_TEXT
    | HEREDOC_PUNCTUATION
    | HEREDOC_INTERPOLATION block CLOSE_BRACE
    ;

/** A parenthesized block. */
parenthesized
    : OPEN_PAREN inner CLOSE_PAREN
    ;

/** A list. */
list
    : OPEN_BRACKET inner CLOSE_BRACKET
    ;

/** A tuple. */
tuple
    : OPEN_BRACE inner CLOSE_BRACE
    ;

/** A map or a struct. */
map
    : OPEN_MAP inner CLOSE_BRACE
    ;

/** A bitstring. */
bitstring
    : OPEN_BITS inner CLOSE_BITS
    ;

/** The inside of a bracket: statements with an optional trailing comma. */
inner
    : separator* (statement (separator+ statement)* COMMA? separator*)?
    ;

/** A do-block with its else, rescue, catch, and after clauses. */
doBlock
    : DO block (blockKeyword block)* END
    ;

/** A clause keyword inside a do-block. */
blockKeyword
    : ELSE
    | RESCUE
    | CATCH
    | AFTER
    ;

/** An anonymous function. */
anonymousFunction
    : FN block END
    | FN separator* ARROW_RIGHT block END
    ;

/** @doc false or @doc nil, which hides the definition below it from the documentation. Before a definition it is labeled hidden when no later @doc overrides it. ref:DEC-hidden-label */
hiddenDoc
    : DOC_ATTRIBUTE (FALSE | NIL)
    ;

/** A @doc string, the canonical comment of the definition below it, holding prose, citations, and interpolations. ref:DEC-elixir-dialect ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE
    ;

/** A @typedoc string, the canonical comment of the type below it; above anything else it is an orphan. ref:DEC-elixir-dialect */
typeComment
    : TYPEDOC_OPEN docPart* DOC_CLOSE
    ;

/** A @moduledoc string, the canonical comment of the module around it. ref:DEC-elixir-dialect */
moduleComment
    : MODULEDOC_OPEN docPart* DOC_CLOSE
    ;

/** One piece of documentation: a reference citation, a license citation, prose, or an interpolation, whose code is read as code. ref:DEC-elixir-dialect */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    | DOC_INTERPOLATION block CLOSE_BRACE
    ;
