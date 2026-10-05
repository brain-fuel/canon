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
  `license:KEY`. A following `//` line continues a line comment. A directive
  such as `//go:generate`, `//nolint`, `//line`, `//extern`, `//export`, or
  `// +build` stays a plain comment and is left out of a doc comment's tokens
  and of its Why, as go/doc leaves it out. Every other comment stays hidden.
- The hook holds a doc comment until the next code token and hides it again
  when a blank line or the end of the file comes first, so a license header or
  a build constraint is no documentation, as go/doc reads it.
- `canonicalComment`, `commentPiece`, and `docPart` are the comment rules. A
  canonical comment is one or more pieces with no blank line between them, so
  a `/* */` block followed directly by a `//` comment is one doc comment, as
  go/doc groups them.
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
