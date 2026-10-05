# Golang Grammar

An ANTLR4 grammar for Golang based on [The Go Programming Language Specification](https://golang.org/ref/spec).

## How to use

* Generate lexer and parser with ANTLR4 generator
* Include both generated and base classes to project from corresponding
  directory (C#, Java, or Go). For Go runtime you should add prefix `p.` to
  all semantic predicates, i.e: `lineTerminatorAhead` -> `p.lineTerminatorAhead()`
  and so on.

## Main contributors

* Sasa Coh, Michał Błotniak, 2017
    * Initial version
* Ivan Kochurkin and @fred1268, kvanttt@gmail.com, Positive Technologies, 2019:
    * Separated lexer and parser
    * Fixes and refactoring
* Dmitry Rassadin, flipparassa@gmail.com, Positive Technologies, 2019:
    * Samples set
    * Fixes and refactoring

## Reference
* [pldb](http://pldb.info/concepts/go)


## License

[BSD-3](https://opensource.org/licenses/BSD-3-Clause)

## Canonically commented dialect

`canonically_commented/GoLexer.g4` and `GoParser.g4` are the grammar above
with Go doc comments as canonical comments, recorded as `DEC-go-dialect` in
canon's `canonical_decisions.yaml`. Each change is marked `// canon:`:

- The lexer names `GoLexerBase`, which canon supplies as a hook. A comment
  that starts its line outside every bracket, inside the parentheses of a
  grouped `const`, `type`, or `var`, or inside the braces of a `struct` or
  `interface`, and not inside a function body, opens a `DocLine` or `DocBlock`
  mode on the default channel, which tokenizes prose, `ref:KEY`, and
  `license:KEY`. A following `//` line continues a line comment. A comment
  is a doc comment only where the code before has ended a statement or opened
  its group, so a comment inside a value that goes on over several lines is
  hidden. A directive
  such as `//go:generate`, `//nolint`, `//line`, `//extern`, `//export`, or
  `// +build` stays a plain comment and is left out of a doc comment's tokens
  and of its Why, as go/doc leaves it out. Every other comment stays hidden.
- The hook holds a doc comment until the next code token and hides it again
  when a blank line or the end of the file comes first, so a license header or
  a build constraint is no documentation, as go/doc reads it. Comments with no
  blank line between them are held, released, and hidden together.
- `canonicalComment`, `commentPiece`, and `docPart` are the comment rules. A
  canonical comment is one or more pieces with no blank line between them, so
  a `/* */` block followed directly by a `//` comment is one doc comment, as
  go/doc groups them. A line piece ends after its last part, which the
  `GoParserBase` predicate `isCommentEnd` tells, since its close is hidden.
- Each top-level function, method, type, const, and var, each spec of a
  grouped declaration, each struct field, and each interface method and
  embedded element is a labeled unit alternative: `# function`, `# method`,
  `# type`, `# const`, `# var`, `# group`, `# field`, and `# element`. A
  grouped declaration is named by its position. The comment above the package
  clause is the file's Why. Top-level declarations have rules of their own, so
  a declaration inside a function body is the plain grammar's.
- A declared name is labeled `required` when the `GoParserBase` predicate
  `isExported` holds, an upper-case initial; each name of a const or var spec
  is labeled on its own, so `var a, B int` requires a comment because `B` is
  exported. A receiver of unexported type is labeled `optional`. A spec of a group with a comment needs none of its own.
  Fields and interface methods may have a comment.
- A doc comment above an import, or after the last field, element, or spec of
  a struct, interface, or group, is an `orphan`.

## Corpus

`tools/corpus/go.sh` checks the grammar against the Go standard library and
the most used Go projects. It shallow-clones each repository below at the
pinned commit into `/tmp/corpus/go`, or the directory given as its first
argument, parses every `.go` file with the plain grammar under a timeout of 60
seconds per file, and then parses every file the plain grammar parsed with the
dialect, which must parse them all. Go is sampled to `src/`, the standard
library and the toolchain; Kubernetes to `pkg/` and
`staging/src/k8s.io/client-go/`; and moby to everything outside `vendor/`,
which holds copies of other repositories, with a sparse checkout. hugo and
terraform are read whole.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Dialect | Seconds | Dialect seconds |
|------------|--------|---------|------:|-------:|---------:|--------:|--------:|----------------:|
| [golang/go](https://github.com/golang/go) | `6200ca72531c` | `/src/` | 8333 | 8286 | 47 | 8286 | 579.5 | 635.0 |
| [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) | `8ae47e9fc94c` | `/pkg/`, `/staging/src/k8s.io/client-go/` | 5755 | 5755 | 0 | 5755 | 328.0 | 360.2 |
| [moby/moby](https://github.com/moby/moby) | `0598cf16389e` | all but `/vendor/` | 2288 | 2288 | 0 | 2288 | 96.6 | 104.9 |
| [gohugoio/hugo](https://github.com/gohugoio/hugo) | `6b3ba3a7e22a` | all | 914 | 914 | 0 | 914 | 42.7 | 45.8 |
| [hashicorp/terraform](https://github.com/hashicorp/terraform) | `35ab6fb201e4` | all | 2032 | 2032 | 0 | 2032 | 126.6 | 132.9 |
| sample `lang_samples/go-uuid/source` | — | all | 23 | 23 | 0 | 23 | 0.7 | 0.8 |
| Total | | | 19345 | 19298 | 47 | 19298 | 1174.1 | 1279.6 |

Of the 19,345 files, 199 MB, 19,298 parse with the plain grammar and with
the dialect, and 47 are excluded, all in Go's own test data:

| Excluded | Reason |
|----------|--------|
| 44 files under `src/cmd/compile/internal/syntax/testdata`, `src/cmd/compile/internal/types2/testdata/local`, and `src/internal/types/testdata` | invalid-code fixtures: their `ERROR` comments mark the syntax errors the Go parser must report |
| `src/cmd/cover/testdata/ranges/ranges.go` | not Go: cover's test input, whose « and » mark the expected ranges |
| `src/go/parser/testdata/issue42951/not_a_file.go/invalid.go` | not Go: a fixture that `go/parser`'s `ParseDir` must skip |
| `src/cmd/go/internal/modindex/testdata/ignore_non_source/b.go` | not Go: an empty fixture with no package clause |

The seconds are the sum of each file's process time, user and system, of the
`canon parse` process, with 8 files parsed at once; wall time depended on the
load of the machine, which other work shared. A file takes 0.03 seconds at the
median, 0.10 at the 90th percentile, 0.47 at the 99th, and 19.6 at most,
`src/cmd/compile/internal/ssa/ssaop/opGen.go`, a generated file of 124,000
lines; the dialect takes 9% longer in all. 19,111 files take under half a
second, 109 under one, 52 under two, 18 under five, and 8 longer: seven
generated files, the compiler's SSA op table and rewrite rules, Kubernetes'
OpenAPI definitions of 78,000 lines, and the instruction tables and standard
library manifest vendored in `cmd`, and Kubernetes' core validation tests of
33,000 lines. The time is linear in a file's length, about 0.17 milliseconds
a line in the largest. Every excluded file fails within 0.05 seconds.

The corpus found these gaps, now fixed, each marked `canon:`:

- `nil` is a predeclared identifier, not a keyword, so the builtin package's
  `var nil Type` parses; it lexes as an `IDENTIFIER`.
- A method may declare type parameters, as `func (r *Rand) N[Int intType]`
  in `math/rand/v2` does, and a literal value in braces is an operand whose
  type is elided, as `return {"If-Range": {ifHeader}}` in `cmd/go`: the Go
  parser accepts both since 2026.
- A lone semicolon is an empty statement, as in `return; ;`.
- The statements of a block and of each switch or select clause were the rule
  `statementList`, the elements of a literal value `elementList`, and the
  arguments of a call `expressionList`, each of which could end after any
  item, so canon's parser built a tree for each and a run of n items took
  time in n squared: a generated Unicode table took 52 seconds and the largest
  generated files of the toolchain and Kubernetes ran past any timeout. They
  are read in the rule that holds their brackets and take time linear in
  their length.
- In the dialect, a comment on a line of its own inside a value that goes on
  over several lines, after a `+` or a comma in a grouped `const`, was taken
  for a doc comment and failed the parse, as in terraform's `regsrc`; a
  comment is a doc comment only where the code before has ended a statement
  or opened its group.
- In the dialect, a block comment followed directly by a line comment, with
  nothing below them, released the block half visible and failed the parse at
  the end of the file; comments with no blank line between them are held and
  released or hidden together.
- In the dialect, a line comment could end after any of its words, so
  `cmd/go`'s package comment of 3,000 lines took 51 seconds; the predicate
  `isCommentEnd` ends it after its last word, and it takes 0.2 seconds.

Known limits: the grammar accepts some programs the Go compiler rejects, two
statements on one line with no semicolon between them, since the upstream
predicate `closingBracket` holds everywhere, and an unparenthesized composite
literal in an `if`, `for`, or `switch` header, since canon's interpreter keeps
no expression-nesting level; neither changes a unit of a program Go compiles.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/go.sh                         # clones into /tmp/corpus/go
CORPUS_ONLY=hugo tools/corpus/go.sh        # one repository
```
