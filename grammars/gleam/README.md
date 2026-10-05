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
- `@internal` is labeled `hidden`, so the item below it needs no comment.
- The syntax removed before Gleam 1.0 is read too: `external fn` and
  `external type`, and module-level target groups written
  `if erlang { ... }`, whose items are items of the module. `try` and a bare
  `assert` sit inside function bodies, which are balanced brackets. `external`
  and `internal` are tokens, and are names wherever Gleam allows a name.

## Canonically commented dialect

`canonically_commented/GleamLexer.g4` and `GleamParser.g4` are the plain
grammar plus the extraction rules. A lexer mode tokenizes `///` and `////`
lines. Consecutive `///` lines are one canonical comment, the Why of the item
below its attributes, even across blank lines, as the Gleam compiler joins
them. `////` comments are labeled `file`, and canon joins them all into the
Why of the file. `pub` is labeled `required`, and a `///` before an import is
an `orphan`. The ledger records it as `DEC-gleam-dialect`.

## Known limitations

- The profile keeps canon's rule that a blank line parts a `///` comment from
  the item below. The dialect follows Gleam and does not.
- Pre-1.0 syntax was tested on the stdlib at v0.18.0, v0.22.0, v0.25.0, and
  v0.29.0. Syntax older than v0.18.0 may not be read.
