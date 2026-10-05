# F# Grammar

`FSharpLexer.g4` and `FSharpParser.g4` are written for canon, under canon's
MIT license, because [antlr/grammars-v4](https://github.com/antlr/grammars-v4)
has no F# grammar (checked at commit
`7df52be94698550d219d299d04105c6bafadd9c3`). They are recorded as
`DEC-fsharp-grammar` in canon's `canonical_decisions.yaml`.

## What it reads

The grammar reads what extraction needs: the declarations that carry
documentation, and where each one ends. It parses namespaces, top-level and
nested modules, `let` and `let rec ... and` bindings with or without
parameters, the bindings of a class, records and their fields, unions and
their cases, enums, classes, interfaces, delegates, type abbreviations, type
extensions, types without a representation such as units of measure,
exceptions, `member`, `override`, `default`, `abstract`, and `new`
declarations, and `val` declarations, with their attributes and access
modifiers. Expressions, patterns, and types are runs of tokens: the grammar
does not type them or give them precedence, it only keeps them inside the
declaration they belong to. A line it cannot read as a declaration, such as
`open`, `do`, `#load`, or a script's top-level expression, is read as an
expression with the lines indented below it.

The lexer reads every F# token, so comments (nested block comments
included), strings (verbatim, triple-quoted, interpolated, and byte strings,
which may span lines), characters, and type parameters never hide code or
fake it, and `(*)` is the multiplication operator rather than a comment.

## The offside rule

F# ends a declaration by indentation, which no context-free grammar sees.
The grammar's `superClass` option, `FSharpLexerBase`, selects the
`Canon.Antlr4.Lex.FSharp` hook in canon, which turns indentation into tokens
the way Python's tokenizer does:

- Outside brackets, the first token of a line is preceded by `INDENT` when it
  is right of the current block, `NEWLINE` when it is level with it, and a
  `DEDENT` for each block it is left of, then `NEWLINE` when it lands on an open
  block's column or `INDENT` when it lands between two.
- Inside parentheses, brackets, braces, and attribute brackets, which F# also
  lets close at any column, no layout tokens are emitted; the first token of
  each line is preceded by `BRNL` instead, which separates record fields.
- Layout tokens are empty and sit where the last code token ends, so they
  widen no span.

The hook also reads the branches of each `#if` that a build selects, as canon
reads C#: canon reads a file once per build of a few that together read every
branch some build compiles, and merges what each finds. In each build the other
branches go to the hidden channel, and a doc comment in them is neither bound
nor reported.

A less-than sign that touches the name before it may open a type application,
as in `f< ^a when ^a : (static member Zero : ^a)>` or `List<int>`, whose angle
brackets F# lets span lines. The hook holds the tokens from it to its closing
greater-than sign and lays them out as inside brackets. A token a type cannot
hold, such as an equals sign outside parentheses or a `let`, shows it was a
comparison, and the tokens are laid out as usual.

This is the offside rule's common case, not the whole of it. The F#
specification lets some tokens sit left of their context (an infix operator at
the start of a line, the closing bracket of a list, the arms of a `function`);
the grammar handles the ones real code uses at the level of declarations: a
function's parameters on the lines below its name with the body at their
column, a primary constructor or the `=` of a class on the line below its name,
a type's name on the line below `type` or `and` and its attributes, a union's
cases at the column of `type`, and match arms at the column of the binding
they end.

## Local bindings and signature files

A line of a body that starts with `let` is a local binding, a unit that may
have a comment, so a doc comment on one binds to it. A union case's fields may
continue on indented lines, as a multi-line anonymous record does, and an
indented `with` below them begins the union's members.

A signature file, `.fsi`, declares what its implementation exports and carries
its documentation. The profile's `signatures` maps `.fsi` to `.fs`, and when
`canon check` reads both files of a name, the comment is required on the
signature and not on the implementation, and what the signature leaves out is
private, as `DEC-fsharp-signatures` records.

## Canonically commented dialect

`canonically_commented/FSharpLexer.g4` and `FSharpParser.g4` are the grammar
with `///` comments as canonical comments, recorded as `DEC-fsharp-dialect`.
Each change is marked `// canon:`:

- `///` opens a doc comment on the default channel, in the `DocLine` mode,
  which tokenizes prose, `ref:KEY`, and `license:KEY`; a following `///` line
  continues it, and `////` stays a plain comment by the longest match.
- The hook holds a doc comment's tokens until the next code token has produced
  its layout tokens, and emits them just before it, as the Haskell port does,
  so the offside rule reads the file as it reads it without comments.
- `canonicalComment` and `docPart` are the comment rules.
- Each namespace, module, binding, type, field, case, member, constructor,
  `val`, and exception is a labeled unit alternative whose `why` is the doc
  comment above its attributes. A case's comment comes before its bar, so the
  bar is part of the case, in `barUnionCase` and `barEnumCase`.
- A declaration that is public by default holds `publicByDefault`, an empty
  rule labeled `required`; `private` and `internal` are labeled `optional`,
  which wins, so the dialect requires what the profile requires.
- A doc comment after a declaration's attributes, above a line that declares
  nothing, or inside an expression or brackets is an `orphan`. One the grammar
  does not accept where it stands is read out of the file and reported as an
  `orphan` too, since the parser's `strayComment` option names
  `canonicalComment` (`DEC-stray-comments`), so a doc comment never fails the
  parse.

## Corpus

`tools/corpus/fsharp.sh` checks the grammar against widely used F# code. It
clones each repository below, shallow and pinned to a commit, into a directory
given as its argument (default `/tmp/corpus/fsharp`), checking out only the
listed subdirectories of the large ones; parses every `.fs`, `.fsi`, and `.fsx`
file with the plain grammar and then with the dialect, each file under a limit
of `TIMEOUT` (20) seconds of CPU time; and prints per repository the files,
the files parsed, the deliberate exclusions, the failures, the CPU time, and
the slowest files, then the files the plain grammar parses and the dialect does
not, and the distribution of times. Rerun it with `tools/corpus/fsharp.sh
[DIR]`; `JOBS` sets the parallel parses and `ONLY` names one repository.

| Repository | Commit | Sampled | Files | Parsed | Excluded | CPU time, plain / dialect |
|---|---|---|---|---|---|---|
| dotnet/fsharp | `d16ac1bc6d29` | `src/FSharp.Core` | 67 | 67 | 0 | 7 s / 10 s |
| fsprojects/fantomas | `0b69ef139388` | `src`, with the 5,846 files of `Fantomas.Core.SnapshotTests` | 5,988 | 5,988 | 0 | 105 s / 117 s |
| giraffe-fsharp/Giraffe | `279fe3a30c27` | whole | 49 | 49 | 0 | 2 s / 2 s |
| fsprojects/FAKE | `e8e1cae79e35` | `src/app` | 188 | 188 | 0 | 7 s / 10 s |
| fsprojects/Paket | `641da499fb70` | `src/Paket.Core`, `src/Paket` | 78 | 78 | 0 | 5 s / 7 s |
| `lang_samples/fsharp-giraffe-viewengine` | | | 3 | 3 | 0 | 0 s / 0 s |

The full commits are in the script. Every file parses with the plain grammar
and with the dialect, and none is excluded. Each file is parsed on one
capability (`GHCRTS=-N1`) and timed in CPU seconds, since the machine ran other
work at a load of 60 to 140. Of the 6,373 files, the plain grammar parses
6,371 in under half a second, 1 in under one, and 1 in under two; the slowest
are FSharp.Core's `prim-types.fs` at 1.4 s, `prim-types.fsi` at 0.6 s, and
`Query.fs` at 0.5 s. The dialect's slowest are `prim-types.fs` at 1.4 s,
`prim-types.fsi` at 0.8 s, and `array.fsi` at 0.5 s.

Since the grammar reads a line it cannot take as a declaration as an
expression, a file that parses may still have lost a declaration that way, so
the corpus was also searched for them: a declaration keyword (`type`,
`member`, `override`, `abstract`, `exception`, `module`, `let`, `default`,
`val`, `new`, `and`, `static`, or `interface`) that opens a line the plain
grammar reads through `otherModuleElement` or `otherClassMember`. In the 523
files outside Fantomas's snapshot tests the search found 14 such declarations
in 10 files with canon-parity's grammar and finds none now; in the 5,846
snapshot files it found 100 in 92 files and finds 70 in 62, a few of them
`static do` lines read correctly. Each fix is marked `// canon: corpus` in the
grammar and tested in `FSharpTest.hs`:

- A type's constraints may follow its parameters, as in
  `type S<'T> when 'T: comparison =`; `when` is a keyword token.
- A type parameter list may hold a constraint whose member signature is in
  parentheses and holds `=`, `<`, or `>`, as in
  `NonStructural<'T when 'T: (static member (<): 'T * 'T -> bool)>`. The hook
  counts angle brackets only outside parentheses.
- The hook does not count a byte order mark as a column, so a type at the top
  of such a file whose `=` is one column right of it is read as a class.
- Classes: a primary constructor indented below the name with the members left
  of it; an `=` on a line of its own with the members indented further; a
  `class ... end` body at the column of `=`, as Fantomas lays out a long
  constructor; `class` on the line of `=` with `end` at the members' column;
  `class ... end` followed by `with` members; and an empty `class` or
  `interface` whose `end` is on the next line.
- Unions: cases at the column of `type` followed by indented members without
  `with`, and a union whose `=` starts the line below its name.
- An abbreviation whose name is on the line below `and`, after its attributes.
- Bindings: an access on each name of a tuple binding, as
  `let private get, _, public set = ...`; a value named by `as`, as
  `let (a, b) as t = ...`; `struct (...)` as a parameter or a binding; a
  function's return type on the line below its parameters; and a value's `=` on
  the line below its return type.
- `default val` auto-properties, and an attribute whose lone argument is a
  name, as `[<DefaultValue false>]`.
- Dialect: the hook emits an empty `DOC_END` where a `///` comment ends, and
  `canonicalComment` ends at it. Before, the rule could end after any word, and
  canon's parser, keeping a tree for each end, took time and memory in the
  square of a comment's length: FSharp.Core's `array.fsi` took 25 seconds.
- Dialect: a doc comment above the attributes of a line that declares nothing,
  such as an `extern`, is an orphan.

## Known limits

A doc comment placed after a declaration's attributes is reported as attached
to nothing. That is F#'s own rule, not a gap: the compiler warns that such a
comment is not on a valid element and does not use it.

Two limits are left, because each is open-ended rather than a construct with
one fix:

- Verbose syntax is read in its common shapes only: `class`, `struct`, and
  `interface ... end` type bodies, `begin ... end` modules, and `with ... end`
  member blocks. Verbose syntax is the compiler's older mode, and code written
  in it today is rare enough that no corpus at hand shows which other shapes
  matter.
- A declaration in a layout the grammar does not read is taken as an
  expression rather than failing the file, so its units are missing from the
  model and its doc comment is reported as attached to nothing. Across the 579
  source files of FsToolkit.ErrorHandling, Expecto, FsCheck, Argu, Giraffe,
  FSharp.Data, and Fantomas's library this happened to two declarations, both
  with a statically resolved type parameter list spanning lines, which the
  hook now reads. Across the 523 source files of the corpus above outside
  Fantomas's snapshot tests it happens to none, the layouts that corpus showed
  being read now. Across the snapshot files in which Fantomas tests unusual
  layouts it happens to 70 declarations in 62 files, down from 100 in 92,
  among them `static extern` members, a doc comment between a type's name and
  its constructor, `#if` around an access modifier or `inline`, and extensions
  of tuple types.
  Those cases exist to exercise every layout the offside rule permits, and each
  needs its own exception to the rule's common case, so they are read one at a
  time as real code needs them.
