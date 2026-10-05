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
- OTP 29 syntax: native records, declared as `-record #name{...}` and written
  `#name{}`, `#mod:name{}`, `#_{}`, `R#mod:name.field`, and named by an atom,
  a variable, or a reserved word, as `#div{}`; comprehensions of several
  values, as `[A, B || ...]` and `#{K => V, K2 => V2 || ...}`; a call of any
  expression, as `F()(X)`, `fun m:f/1(X)`, and `?MODULE:callback():f()`; and
  `catch` as the right operand of any operator, as `X > catch f()`.
- A macro may name a function, `?MODULE() -> ok.`, the module of a spec or a
  remote type, `-spec ?MODULE:f() -> ok.` and `?MODULE:t()`, or stand for the
  clauses of a function, `?wr_record(a); ?wr_record(b).`. A macro argument may
  be a pattern with a guard, as in `?assertMatch(X when X > 0, f())`.
- A file may hold no form, as an empty header does; a spec may be written
  `- spec`; a type may carry several annotations, as in
  `Default :: AppProto :: binary()`; and strings and sigils may open with up
  to seven quotes.
- The `ErlangPreprocessor` hook does not expand a macro inside its own
  expansion, as epp refuses `-define(A, ?A + ?A).` rather than double it at
  every level; a definition of the same name and another arity still
  expands. It expands the arguments of a call before placing them, and
  `??Arg` becomes a string of the argument as written.

canon reads a source file that is not valid UTF-8 as Latin-1, as Erlang reads
a file that declares `coding: latin-1` (`DEC-source-encoding`).

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
name the comment rules (`DEC-stray-comments`). An EDoc comment between two
clauses of a function, as gen_server callbacks often carry above each clause,
is read there as an `orphan`, and its `@private` hides neither the function
nor the file. A record is tried before the other units and takes the
attributes above it lazily, since an untyped record such as
`-record(r, {a, b}).` also reads as an attribute, which a record or type below
would otherwise take as one of its markers. The ledger records it as
`DEC-erlang-dialect`.

## Corpus

`tools/corpus/erlang.sh` clones these repositories, shallow and at the pinned
commits, into `/tmp/corpus/erlang`, or the directory given as its argument,
and parses every `.erl`, `.hrl`, and `.escript` file with the plain grammar
and then with the dialect. Erlang/OTP is sampled to the `lib/` applications
stdlib, kernel, compiler, ssl, public_key, crypto, inets, ssh, eunit,
common_test, mnesia, syntax_tools, tools, sasl, parsetools, edoc, dialyzer,
debugger, and runtime_tools, with their test suites and test data; RabbitMQ to
the `deps/` rabbit, rabbit_common, amqp_client, amqp10_common, amqp10_client,
rabbitmq_management, rabbitmq_mqtt, rabbitmq_stream, rabbitmq_shovel,
rabbitmq_federation, rabbitmq_prometheus, and rabbitmq_ct_helpers. ejabberd and
recon are whole. Each commit is shortened here; the script pins the full hash.

| Repository | Commit | Files | Parsed | Excluded | CPU seconds |
| --- | --- | --- | --- | --- | --- |
| [erlang/otp](https://github.com/erlang/otp) `lib/` | `cfe4f0379320` | 2819 | 2815 | 4 | 1064.9 |
| [rabbitmq/rabbitmq-server](https://github.com/rabbitmq/rabbitmq-server) `deps/` | `fddc4cf564b3` | 926 | 926 | 0 | 243.7 |
| [processone/ejabberd](https://github.com/processone/ejabberd) | `46b1ceb23bba` | 394 | 394 | 0 | 135.1 |
| [ferd/recon](https://github.com/ferd/recon) | `cb45e7b19808` | 15 | 15 | 0 | 3.0 |
| Total | | 4154 | 4150 | 4 | 1446.7 |

The dialect parses all 4150 files the plain grammar parses. The four
exclusions are files the compiler rejects or never compiles:

- `lib/common_test/test/ct_auto_compile_SUITE_data/bad_SUITE.erl` and
  `lib/common_test/test/ct_error_SUITE_data/error/test/no_compile_SUITE.erl`
  are invalid test fixtures, deliberate syntax errors with which common_test
  tests its report of a module that does not compile.
- `lib/syntax_tools/examples/merl/merl_build.erl` is an example the compiler
  rejects: a `-doc` attribute lacks its closing dot.
- `lib/parsetools/include/leexinc.hrl` is a template, not Erlang: leex fills
  its `##` placeholders to make a scanner.

Each fails within 0.1 CPU seconds. A file takes 0.10 CPU seconds at the
median, 0.79 at the 90th percentile, and 3.45 at the 99th. The slowest are the
largest test suites: `lib/kernel/test/socket_api_SUITE.erl`, 27,883 lines,
takes 25.5 seconds and `lib/stdlib/test/re_testoutput1_split_test.erl`,
32,109 lines, 20.7, so the script allows 60 CPU seconds a file. That time is
the parser's, which grows with a file's length, not the grammar's. The dialect
takes 0.13 seconds at the median and 25.4 at most.

Before the changes listed above, 185 files failed: most at a function named
by a macro, `?MODULE() ->`, in the compiler's test data (77), at a macro
argument with a guard in RabbitMQ's suites (34), and at native records (39);
seven were Latin-1, and the rest were the other forms listed above. The
dialect failed 10 more: five at a parameterized module, a tuple export entry,
and `?MODULE/0` in an export list, and five by running out of time in the
stray-comment recovery, which parsed the file once more for each EDoc comment
it could not place and read the rest of the file for each candidate. The
dialect now reads an EDoc comment between clauses in place, and the recovery
reads a candidate from a bounded span (`DEC-stray-comments`).

To rerun, build canon and run `tools/corpus/erlang.sh [directory]`; `JOBS`
sets the parallel parses and `TIMEOUT` the CPU seconds a file may take. It
prints the table above, the slowest files, the exclusions, and every failure,
and fails when a file fails that no exclusion names.

## Known limitations

- A macro defined in an included header is not expanded. The hook sees only
  the text of the file it lexes, and the header's path depends on the include
  path a build gives the compiler, which canon does not know. Such a macro
  parses only where an expression, a pattern, a type, a record name, a string
  part, a list element, a form, a clause, a function's name, or the module of
  a spec or a remote type may be.
- In the dialect, an `-export_type` entry in the old tuple form,
  `{Name, Arity}`, which OTP still accepts, is read but exports nothing, so
  the type it names requires no comment unless an entry `Name/Arity` exports
  it. Only OTP's dialyzer test data writes it.
- canon does not choose `-ifdef` branches: both parse, and a macro defined in
  both is expanded with the later definition. Which branch a build compiles
  depends on macros given to the compiler with `-D` or defined in headers,
  neither of which canon reads, so there is no build to choose by.
