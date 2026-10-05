# Prolog grammar

`prolog.g4` is the grammars-v4 Prolog grammar, an ISO Prolog grammar, with the changes marked
`// canon:` in it and recorded as `DEC-prolog-grammar-fixes`. `canonically_commented/` is its
canonically commented dialect, split into `PrologLexer.g4` and `PrologParser.g4` because a
combined grammar may not hold lexer modes (`DEC-prolog-dialect`). Every change to the plain grammar
is mirrored in the dialect.

## Operators

Prolog's operators are user-definable: `op/3` declares new ones in the file that uses them, and
SWI-Prolog adds its own, such as `=>`, `*->`, `:=`, and `table`. No fixed table of priorities reads
real Prolog, and the grammars-v4 grammar's table, a left-recursive `term operator_ term`, failed most
of SWI-Prolog's library and was exponential on long bodies. Both grammars therefore read a term as a
flat run of primaries and operator atoms, `term : termPart+`. Every atom may stand as an operator,
an operator may stand as an atom, as `mode(+, -)` writes, and as a functor, as `-(X)` does.
Priority and associativity are left to Prolog: canon needs only a clause's extent, which its end
token fixes, and a compound term's arguments, which its commas separate. A comma is a separator, not
an operator, and a bar separates the alternatives of a body, `(a | b)`.

## SWI-Prolog syntax

- The end token is ISO's: a full stop followed by layout, a `%` comment, or the end of the file. A
  full stop followed by anything else is a graphic atom, so a dict access, `X = P.x`, stays inside
  its clause.
- Dicts, `point{x: 1}` and `_{a: 1}`, parse as a tag followed by a curly term.
- Quasi-quotations, `{|html||<p>text</p>|}`, are one token, `QUASI_QUOTATION`.
- Escapes: `\e`, `\s`, `\z`, `\uXXXX`, `\UXXXXXXXX`, `\c` with the line break after it, octal and
  hexadecimal escapes without their closing backslash, and a backslash before a CR LF line break.
  A tab inside quotes is itself.
- Numbers: digit groups, `1_000_000`; radix integers, `16'FF`; character codes, `0'c`, `0'\s`,
  and `0''`; exponents without a sign or a fraction, `1e10`; and `1.0Inf` and `1.5NaN`.
- A compound term may have no arguments, `foo()`.
- In the dialect, a single sided unification rule, `Head, Guard => Body`, is a clause of its
  predicate like a `:-` rule.

SWI-Prolog's block strings are not in the library sampled and are not read.

## Corpus

`tools/corpus/prolog.sh` clones the projects below, each pinned to a commit, shallow and
blob-filtered, parses every `.pl` file with `prolog.g4` under a limit of 10 CPU seconds per file, or the
longer limit its `SLOW` list gives a large file, and then parses every file the plain grammar
accepted with the dialect, which must accept it too. Rerun it with:

```
tools/corpus/prolog.sh [clone-dir]   # default /tmp/corpus/prolog
```

| Repository | Commit | Sampled | Files | Parsed | Excluded | Dialect | CPU time |
|---|---|---|---|---|---|---|---|
| SWI-Prolog/swipl-devel | `741efc02f1c2` | `library/` | 207 | 207 | 0 | 207 | 23.6 s |
| LogtalkDotOrg/logtalk3 | `9dda2f8d7f94` | `core/`, `adapters/` | 29 | 29 | 0 | 29 | 17.5 s |
| larsyencken/marelle | `02fb567b1049` | whole | 13 | 13 | 0 | 13 | 0.7 s |

logtalk3 is sampled to the Prolog its compiler and backend adapters are written in; its `library/`
is Logtalk source, `.lgt`, and generated Unicode tables. Every file parses with both grammars, and
nothing is excluded. Time is the plain grammar's CPU seconds summed over a repository's files. Of
249 files, 242 took less than half a second, 5 from half a second to one, 1 from one to two, and one
longer: logtalk3's `core/core.pl`, the Logtalk compiler in one file of 30,363 lines and 1.6 MB,
which parses in 11 CPU seconds, roughly linearly in its size. That time is the parser's, and the
script's `SLOW` list gives that file 60 CPU seconds and clpfd's 7,906 lines (1.5 s) 20. A file with a syntax error fails in
the time its prefix takes to parse: half a second at the top of `prolog_xref.pl` and one second at
its end.

Before the changes above, 172 of 249 files failed: most on operators the table lacked, used as
atoms, or declared by the file, and 22 in the lexer on SWI-Prolog's escapes; `\c` followed by a run
of spaces made the lexer try every split of the run, so one 244-line file took 47 seconds.

## Limitations

- An operator a file declares is read like any other atom, so a head written with one, such as
  `X ===> Y :- ...`, is no unit in the dialect.
- The flat term accepts juxtaposed terms that Prolog rejects, such as `a b`; a syntax error that is
  only a wrong operator priority is not reported.
- A full stop directly before a `%` comment ends the clause and takes the comment into the end
  token.
