# Elixir Grammar

`ElixirLexer.g4` and `ElixirParser.g4` are a structural grammar for Elixir,
written for canon. They read a file as statements, definitions, and nested
blocks; they do not model operator precedence, because canon needs units and
their documentation, not evaluation order.

## Provenance in canon

Both files were written for canon, under canon's MIT license (Copyright (c)
2026 brain-fuel) as their headers state, from the
[Elixir syntax reference](https://hexdocs.pm/elixir/syntax-reference.html)
and the behaviour of Elixir's own tokenizer. Nothing in them is copied from
another grammar, so no line is marked as changed.

[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/7df52be94698550d219d299d04105c6bafadd9c3/elixir)
has an Elixir grammar at commit `7df52be94698550d219d299d04105c6bafadd9c3`.
It was evaluated first and is not vendored: in canon's interpreter it parsed
71 of 308 files from Jason, Plug, and Phoenix. Of the rest, 47 stopped in the
lexer, at forms such as the `~c'...'` sigil, and 190 in the parser, most at
a newline (87), such as one before a leading `|>` (20 more stopped at the
`|>` itself), or at a quoted keyword key such as `"bench.encode": [...]`.
Its strings have no interpolation, so a quote inside `#{...}` ends them.
The decision is recorded as `DEC-elixir-grammar` in canon's
`canonical_decisions.yaml`.

## Design

- A statement ends at a newline unless a binary operator, a comma, or a
  keyword key comes before it, or a binary operator that cannot start an
  expression (`|>`, `.`, `when`, `|`, `::`, and the rest) comes after it.
  A newline token takes any comment-only lines below it, so a comment does
  not separate an attribute from its definition, while a blank line does.
- An expression is a chain of operands joined by juxtaposition, as in a call
  without parentheses, or by binary operators. Brackets, maps, bitstrings,
  do-blocks, and `fn` blocks nest as operands.
- Strings, quoted atoms, and heredocs have lexer modes, and their
  interpolations push the default mode, so a closing brace inside `#{...}`
  returns to the string. Sigils are single tokens whose interpolations may
  hold the sigil's closing delimiter.
- Each kind of definition (`defmodule`, `defprotocol`, `defimpl`, `def`,
  `defp`, `defmacro`, `defmacrop`, `defguard`, `defguardp`, `defdelegate`,
  `defstruct`, `defexception`, `@type`, `@typep`, `@opaque`, `@callback`,
  `@macrocallback`) is its own rule, and takes the module attributes above
  it, each labeled `marker`, so its node starts at its first attribute and the
  `@doc` above those attributes documents it. Blank lines do not part an
  attribute from its definition, since Elixir binds every pending attribute to
  the next definition. A documentation attribute with a string value is not
  taken: canon scans it as the definition's comment.
- `@doc false` and `@doc nil` are labeled `hidden`, so the definition below
  needs no comment. `@moduledoc false` in a module body hides the module and
  every definition in it. Only a module body reads it so, so a
  `@moduledoc false` quoted inside a function does not hide the function.
- An operator definition such as `def a <~> b` or `def -value` is named by its
  operator. A definition whose name is computed, such as
  `def unquote(name)(args)`, is named by its `unquote` call.
- An uppercase sigil does not interpolate and is one token. A lowercase sigil
  has a lexer mode per delimiter, so an interpolation inside it may hold any
  code, including the closing delimiter and newlines.
- `test`, `describe`, and `property` are a token of their own, so a profile
  can make an ExUnit or StreamData call a unit by its first token even when
  `@tag` attributes sit above it. A test may name itself in parentheses, as in
  `test("name", context)`, and a test without a block is a pending test.

## Profile

The Elixir profile in `lang_samples/elixir-jason/canon.yaml` names `@doc` and
`@typedoc` as outer doc attributes and `@moduledoc` as an inner one. Its
`interpolation` setting, `["#{", "}"]`, lets canon scan a `@doc` heredoc
whose interpolation holds strings of its own. Blank lines below a `@doc` do
not part it from the definition, as in Elixir.

## Canonically commented dialect

`canonically_commented/ElixirLexer.g4` and `ElixirParser.g4` are the plain
grammar plus the extraction rules. Lexer modes tokenize a `@doc`, `@typedoc`,
or `@moduledoc` string, heredoc, or sigil heredoc as a canonical comment, and
read its interpolations as code. Each kind of definition is a labeled unit
alternative. Documentation, `@doc false`, and attributes may come in any order
above a definition, and the last doc wins: an earlier `@doc` is an `orphan`,
and a later `@doc false` makes the unit `hidden`. A module's Why is the first
`@moduledoc` anywhere in its body. Public definitions label their keyword
`required`. Function, macro, and guard clauses are labeled `merge`, so the
clauses of one name are one unit. On the 308 files of Jason, Plug, and Phoenix
the dialect parses every file and reports the same missing comments as the
profile. The ledger records it as `DEC-elixir-dialect`.

## Known limitations

- Every limitation listed before this version is fixed: computed and
  operator names, `@doc false`, blank lines, sigil interpolation, and test
  names. The ledger records the fixes in `DEC-elixir-grammar`.
- Operator precedence is not modelled, by design.
- In the dialect `@doc` and `@typedoc` share one token, so a `@typedoc` above
  a function documents it, where Elixir would warn.
