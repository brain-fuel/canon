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
- The profile sets `joinAcrossBlankLines`, so `///` lines above an item are
  one comment even with blank lines between them, as the Gleam compiler
  joins them.
- The syntax removed before Gleam 1.0 is read too: the tuple type
  `tuple(A, B)`, `external fn` and `external type`, and module-level target groups written
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
an `orphan`. A `///` inside a function body, an argument list, or any other
bracketed part is an `orphan` too, although the Gleam compiler would join it
into the documentation of the next item: where it stands, it documents
nothing. The parser's `strayComment` option names `canonicalComment`, so one
the grammar does not accept where it stands is read out of the file and
reported as an `orphan` (`DEC-stray-comments`). The ledger records it as
`DEC-gleam-dialect`.

## Corpus

`tools/corpus/gleam.sh` clones these repositories, shallow and at the pinned
commits, into `/tmp/corpus/gleam`, or the directory given as its argument,
and parses every `.gleam` file with the plain grammar and then with the
dialect: the standard library, the packages of gleam-lang and the most used
community packages, whole, and the Gleam compiler sampled to its `.gleam`
files, the test projects and fixtures of its test suites.

Each commit is shortened here; the script pins the full hash.

| Repository | Commit | Files | Parsed | Excluded | CPU seconds |
| --- | --- | --- | --- | --- | --- |
| [gleam-lang/stdlib](https://github.com/gleam-lang/stdlib) | `84ac8c701824` | 42 | 42 | 0 | 2.3 |
| [gleam-lang/json](https://github.com/gleam-lang/json) | `9792d8a5ec14` | 3 | 3 | 0 | 0.1 |
| [gleam-lang/otp](https://github.com/gleam-lang/otp) | `235c761d8b87` | 14 | 14 | 0 | 0.5 |
| [gleam-lang/erlang](https://github.com/gleam-lang/erlang) | `dfa7cd705d8e` | 12 | 12 | 0 | 0.4 |
| [gleam-lang/http](https://github.com/gleam-lang/http) | `fa4b3342dba9` | 10 | 10 | 0 | 0.4 |
| [gleam-lang/httpc](https://github.com/gleam-lang/httpc) | `0f5f2fdc88d5` | 3 | 3 | 0 | 0.1 |
| [gleam-lang/crypto](https://github.com/gleam-lang/crypto) | `7f0dc2624b9e` | 3 | 3 | 0 | 0.1 |
| [gleam-lang/javascript](https://github.com/gleam-lang/javascript) | `b51b4365c2b5` | 8 | 8 | 0 | 0.2 |
| [gleam-lang/time](https://github.com/gleam-lang/time) | `09b049db0d69` | 8 | 8 | 0 | 0.4 |
| [gleam-lang/regexp](https://github.com/gleam-lang/regexp) | `4764177ecd1a` | 2 | 2 | 0 | 0.1 |
| [gleam-lang/yielder](https://github.com/gleam-lang/yielder) | `2134616880ea` | 2 | 2 | 0 | 0.2 |
| [lpil/gleeunit](https://github.com/lpil/gleeunit) | `3d6fc20588d5` | 10 | 10 | 0 | 0.3 |
| [gleam-wisp/wisp](https://github.com/gleam-wisp/wisp) | `f6e70b460f31` | 57 | 57 | 0 | 2.0 |
| [lustre-labs/lustre](https://github.com/lustre-labs/lustre) | `64b383521970` | 80 | 80 | 0 | 3.5 |
| [rawhat/mist](https://github.com/rawhat/mist) | `6be7897833c7` | 26 | 26 | 0 | 1.0 |
| [lpil/pog](https://github.com/lpil/pog) | `1260e90168cb` | 2 | 2 | 0 | 0.2 |
| [lpil/sqlight](https://github.com/lpil/sqlight) | `b19f58d9f154` | 2 | 2 | 0 | 0.1 |
| [lpil/envoy](https://github.com/lpil/envoy) | `8c3e845563c7` | 2 | 2 | 0 | 0.1 |
| [giacomocavalieri/birdie](https://github.com/giacomocavalieri/birdie) | `4523e5760d22` | 10 | 10 | 0 | 0.6 |
| [lpil/glance](https://github.com/lpil/glance) | `119266f8ebaf` | 6 | 6 | 0 | 0.6 |
| [bcpeinhardt/simplifile](https://github.com/bcpeinhardt/simplifile) | `8404c143b9d7` | 2 | 2 | 0 | 0.2 |
| [giacomocavalieri/squirrel](https://github.com/giacomocavalieri/squirrel) | `5b6407d14a7c` | 11 | 11 | 0 | 0.8 |
| [gleam-community/maths](https://github.com/gleam-community/maths) | `31fb0d20fa09` | 11 | 11 | 0 | 0.7 |
| [gleam-community/ansi](https://github.com/gleam-community/ansi) | `a5ea289692ea` | 2 | 2 | 0 | 0.1 |
| [gleam-lang/gleam](https://github.com/gleam-lang/gleam) `*.gleam` | `52e735c82d42` | 238 | 238 | 0 | 7.3 |
| Total | | 566 | 566 | 0 | 22.3 |

Every file parses, with the plain grammar and with the dialect, and none needed
a change to either. A file takes 0.03 CPU seconds at the median, 0.06 at the
90th percentile, and 0.26 at most, for `glance/src/glance.gleam`, a Gleam
parser of 2,316 lines. The compiler's fixtures include code it rejects on
purpose, such as the type error under `test/errors`; it is well formed, so it
parses, and none needs an exclusion.

To rerun, build canon and run `tools/corpus/gleam.sh [directory]`; `JOBS` sets
the parallel parses and `TIMEOUT` the CPU seconds a file may take. It prints
the table above, the slowest files, and every failure, and fails when a file
fails that no exclusion names.

## Known limitations

- Pre-1.0 syntax was tested on the stdlib at v0.18.0, v0.22.0, v0.25.0, and
  v0.29.0. The tuple type `tuple(A, B)`, which v0.15 replaced with `#(A, B)`,
  is read too. Other syntax older than v0.18.0 is untested, since no corpus at
  hand holds it, and may not be read.
