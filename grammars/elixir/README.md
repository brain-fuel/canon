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
  `@macrocallback`) is its own rule, and takes the module attributes on the
  lines directly above it, each labeled `marker`, so its node starts at its
  first attribute and the `@doc` above those attributes documents it. A
  documentation attribute with a string value is not taken: canon scans it as
  the definition's comment. `@doc false` and `@doc since: "1.0"` are taken.
- `test`, `describe`, and `property` are a token of their own, so a profile
  can make an ExUnit or StreamData call a unit by its first token even when
  `@tag` attributes sit above it.

## Known limitations

- A definition whose name is computed, such as `def unquote(name)(args)`, is
  not a unit, so a `@doc` above it is reported as attached to nothing.
- A blank line between an attribute and its definition, or between a `@doc`
  and the attributes below it, separates them, as everywhere in canon.
- Operator definitions such as `def left <> right` take the left operand as
  their name.
- A lowercase sigil's interpolation may not contain `}` or a newline.
