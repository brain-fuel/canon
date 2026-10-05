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

The hook also reads one branch of each `#if`: the first whose condition holds
for some choice of its symbols, as canon reads C#. The other branches go to the
hidden channel, and extraction neither binds nor reports the doc comments in
them.

This is the offside rule's common case, not the whole of it. The F#
specification lets some tokens sit left of their context (an infix operator at
the start of a line, the closing bracket of a list, the arms of a `function`);
the grammar handles the ones real code uses at the level of declarations: a
function's parameters on the lines below its name with the body at their
column, a primary constructor or the `=` of a class on the line below its name,
a type's name on the line below `type` or `and` and its attributes, a union's
cases at the column of `type`, and match arms at the column of the binding
they end.

## Known limits

- Local bindings inside expressions are not units, so a doc comment on one is
  reported as attached to nothing; F# ignores such comments too.
- A doc comment placed after a declaration's attributes is reported as attached
  to nothing, as F# warns that it is not on a valid element.
- Verbose syntax is read in its common shapes only: `class`, `struct`, and
  `interface ... end` type bodies, `begin ... end` modules, and `with ... end`
  member blocks.
- A declaration in a layout the grammar does not read is taken as an
  expression rather than failing the file, so its units are missing from the
  model and its doc comment is reported as attached to nothing. Across the 579
  source files of FsToolkit.ErrorHandling, Expecto, FsCheck, Argu, Giraffe,
  FSharp.Data, and Fantomas's library this happened to two declarations, both
  with a statically resolved type parameter list spanning lines, and across
  the 5,900 snapshot cases in which Fantomas tests unusual layouts, to 104.
- A union case whose fields hold a multi-line anonymous record followed by
  `with` and members reads the members as part of the case.
- A type parameter whose name is quoted in double backticks does not lex.
- Signature files parse, and `val` declarations are units, but the profile
  cannot tie a `val` in a `.fsi` to the binding it declares, so when the
  comment sits on the `val`, the binding in the `.fs` file is still reported
  as missing one.
