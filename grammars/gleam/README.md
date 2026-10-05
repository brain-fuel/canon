# Gleam Grammar

`GleamLexer.g4` and `GleamParser.g4` are a grammar for the module level of
Gleam, written for canon. They read imports, constants, custom types with
their constructors and labelled fields, type aliases, and functions, each with
its attributes; function bodies and parameter lists are read as balanced
brackets, because canon needs the items of a module and not the expressions
inside them.

## Provenance in canon

Both files were written for canon, under canon's MIT license (Copyright (c)
2026 brain-fuel) as their headers state, from the
[Gleam language tour](https://tour.gleam.run/) and the parser of the
[Gleam compiler](https://github.com/gleam-lang/gleam/tree/v1.19.0/compiler-core/src/parse)
at v1.19.0. No ANTLR grammar for Gleam existed to vendor, so no line is marked
as changed. The decision is recorded as `DEC-gleam-grammar` in canon's
`canonical_decisions.yaml`.

## Design

- Comments of every kind are skipped by the lexer; canon scans `///` item
  documentation and `////` module documentation from the text.
- Attributes such as `@external(erlang, "m", "f")`, `@deprecated("...")`,
  `@target(erlang)`, and `@internal` belong to the item below them and are
  labeled `marker`, so an item's node starts at its first attribute and the
  `///` comment above the attributes documents it.
- Public and private functions, types, and constants are separate rules, so
  a profile can require documentation on the public ones only.
- A function without a body is an external function.
- Constructor fields are parsed so that a labelled field, which Gleam
  documents with `///`, is a unit.

## Known limitations

- The syntax removed before Gleam 1.0, such as `external fn` and module-level
  `if erlang { ... }` blocks, is not accepted.
