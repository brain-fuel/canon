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
  nothing, or inside an expression or brackets is an `orphan`.

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
  hook now reads. Across the 5,900 snapshot cases in which Fantomas tests
  unusual layouts it happened to 104. Those cases exist to exercise every
  layout the offside rule permits, and each needs its own exception to the
  rule's common case, so they are read one at a time as real code needs them.
