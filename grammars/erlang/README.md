# Erlang Grammar

`Erlang.g4` is an ANTLR4 grammar of Erlang made by Pierre Fenoll from
`erl_parse.yrl`, updated to Erlang/OTP 23.3.

## Provenance in canon

`Erlang.g4` is from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/master/erlang),
under the BSD license in its header (Copyright (c) 2013 Terence Parr). As
vendored it parsed 6 of the 16 files of recon. canon changed it where Erlang
or canon requires. Every change is marked `// canon:` in the grammar and
recorded as `DEC-erlang-grammar` in canon's `canonical_decisions.yaml`:

- A number has no sign, so `X-1` is a subtraction. Digits may be grouped with
  underscores, and a float may have a base, as in `2#1.0#e-53`. A character may be a control escape such as `$\^A` or a
  hexadecimal one such as `$\x{1F600}`.
- A comment may end the file, and an escript's `#!` line is skipped.
- Strings may be triple-quoted, or quoted with four or five quotes, and
  sigils such as `~"..."` and `~b[...]` are read, as OTP 27 writes them.
- The `ErlangPreprocessor` hook, named as the grammar's `superClass`, expands
  the macros a file defines before the parser sees them, as `epp` does. It
  records each `-define`, one per name and arity, and replaces each call with
  the body, the arguments in place of the parameters. So a macro that stands
  for part of a form, such as `X,` or `begin`, parses as its expansion. Of two
  definitions in the branches of an `-ifdef`, the later is used.
- A macro the file does not define, such as `?MODULE` or one from a header,
  is read, not run. A macro call, `?NAME`, `?NAME(Args)`, or
  `??Arg`, is read where an expression, a pattern, a type, an atom or variable
  in a fun, a record name, a string part, a whole form, or a function clause
  may be. A macro directly followed by a list element stands for an element
  and its comma. `-define` takes any balanced tokens as its body when it is no
  expression. `-if`, `-ifdef`, `-else`, and `-endif` are attributes, so both
  branches parse.
- OTP 25 to 28 syntax: `maybe` expressions and `?=`, map comprehensions and
  generators, strict and zip generators. `maybe` and `else` stay atoms
  elsewhere.
- A union member may be annotated, as in `A :: atom() | B :: integer()`, and
  the right side of a match may be a `catch`.
- A function is a form of its own with the attributes above it: its `-spec`,
  `-doc` metadata, and other attributes, each labeled `marker`. So an EDoc
  comment above the spec documents the function. A `-doc` with a string is
  not taken, since canon scans it as the function's comment.
- `-doc false` and `-moduledoc false` are labeled `hidden`.
- Types, records, and callbacks have rules of their own, named by what they
  define, so a profile can make each a unit.
- The arguments of a function and the parameters of a type or callback are
  labeled `arity`, so canon names the unit by name and arity, as `info/2`.

On this grammar every file of recon and of OTP's stdlib, kernel, and eunit
parses.

## Profile

The Erlang profile in `lang_samples/erlang-recon/canon.yaml` scans `%`
comments, names `-doc` as a doc attribute and `-moduledoc` as an inner one,
and makes functions, callbacks, types, and records units. A `-doc` binds to
the function below it across blank lines, and `-moduledoc` to the file. Its
`hiddenTags` are EDoc's `@private` and `@hidden`, so a comment holding one
hides the function it documents.

## Canonically commented dialect

`canonically_commented/ErlangLexer.g4` and `ErlangParser.g4` are the plain
grammar split into a lexer and a parser, because a combined grammar may not
have lexer modes; the parser's literals are named lexer tokens. Lexer modes
tokenize `-doc` and `-moduledoc` strings and EDoc comments, a comment whose
first line starts with a tag such as `@doc`. A `-doc` string or an EDoc
comment above a function, type, record, or callback, or among the attributes
above it, is its Why, and the last one wins. `-doc false`, and an EDoc comment
with `@private` or `@hidden`, label the unit `hidden`. `-moduledoc` and an
EDoc comment above `-module` are labeled `file`. Entries of `-export` and
`-export_type` are labeled `export`, so an exported unit requires a comment.
A module that compiles with `export_all` exports every function, and so does
a header, which has no `-module`; any other module exports only what its
export lists name, and nothing when it has none. An EDoc comment the grammar
does not accept where it stands, as inside a function, is read out of the
file and reported as an `orphan`, since the parser's `strayComment` options
name the comment rules (`DEC-stray-comments`). The ledger records it as
`DEC-erlang-dialect`.

## Known limitations

- A macro defined in an included header is not expanded. The hook sees only
  the text of the file it lexes, and the header's path depends on the include
  path a build gives the compiler, which canon does not know. Such a macro
  parses only where an expression, a pattern, a type, a record name, a string
  part, a list element, a form, or a clause may be.
- canon does not choose `-ifdef` branches: both parse, and a macro defined in
  both is expanded with the later definition. Which branch a build compiles
  depends on macros given to the compiler with `-D` or defined in headers,
  neither of which canon reads, so there is no build to choose by.
