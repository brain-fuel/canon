# C# Version 7 Grammar

C# grammar targeting ECMA-334 7th edition (December 2023), with full support of C# 7.x features and below.
This grammar is based on the v6 grammar and adds C# 7 additions: expression-bodied constructors/destructors/accessors,
`private protected` access modifier, `ref` iteration variables in `foreach`, `stackalloc` in general expression context,
and `ref` returns in anonymous functions.

## Preprocessing

This grammar handles C# preprocessor directives (`#if`, `#elif`, `#else`, `#endif`, `#define`, `#undef`) as part
of normal lexing — no separate preprocessor pass is required. The logic lives entirely in `CSharpLexerBase` via
a `NextToken()` override.

When a `#if` / `#elif` / `#else` condition evaluates to false, the skipped source text is collected into a single
`SKIPPED_SECTION` token emitted on the hidden channel. The parser never sees the false branch. Nested `#if` blocks
are handled correctly by tracking a condition stack and a "was any branch taken" stack.

Supported directives:

| Directive | Behaviour |
|---|---|
| `#define SYM` | Adds `SYM` to the active symbol set (only when in an active section) |
| `#undef SYM` | Removes `SYM` from the active symbol set (only when in an active section) |
| `#if EXPR` | Evaluates `EXPR`; skips the block if false |
| `#elif EXPR` | Evaluates `EXPR` if no prior branch was taken; skips the block if false |
| `#else` | Active if no prior branch was taken |
| `#endif` | Closes the current conditional block |
| `#region` / `#endregion` | Lexed and discarded (no semantic effect) |
| `#line` / `#pragma` / `#warning` / `#error` | Lexed and discarded |

Preprocessor expressions support `!`, `&&`, `||`, `==`, `!=`, parentheses, `true`, `false`, and symbol names.

### Command-Line Options

Symbols can be pre-defined before parsing using the `--D` option (analogous to `csc /define:`):

```
--DSYM              Define a single symbol SYM
--DSYM1;SYM2;SYM3   Define multiple symbols separated by semicolons
```

**Java** (`CSharpLexerBase.java`): pass `--DSYM` as a JVM system property or as a program argument;
the base class reads `System.getProperty("sun.java.command", "")` and scans for `--D` prefixed tokens.

**C#** (`CSharpLexerBase.cs`): pass `--DSYM` on the command line; the base class reads
`Environment.GetCommandLineArgs()` and scans for `--D` prefixed arguments.

Example (C# test harness):

```
Test.exe --DCOMPILERCORE myfile.cs
Test.exe --DDEBUG;TRACE myfile.cs
```

### `--no-semantics`

The parser uses one semantic predicate, `IsLocalVariableDeclaration()`, to disambiguate
`var x = ...` (implicitly-typed local) from a type named `var`. Passing `--no-semantics`
disables this predicate (it returns `true` unconditionally), which lets the parser run
without any context-sensitive logic — useful for quick batch testing or fuzzing.

```
--no-semantics                           Disable all semantic predicates
--no-semantics=IsLocalVariableDeclaration  Disable a specific predicate by name
```

**Java**: pass as a JVM system property: `-Dno-semantics` is not used here; instead pass
`--no-semantics` in `sun.java.command` (i.e. as a normal program argument to the test harness).

**C#**: pass on the command line to the test harness:

```
Test.exe --no-semantics myfile.cs
```

## Grammar Symbol Mapping

See [grammar-symbol-mapping.md](grammar-symbol-mapping.md) for the full mapping between ANTLR4 rule names
and their corresponding symbols in the ECMA-334 7th edition specification.

## Reference
* [pldb](http://pldb.info/concepts/csharp)
* [ECMA 334](https://ecma-international.org/publications-and-standards/standards/ecma-334/)

## Performance

Runtime of `examples/*.cs` on AMD Ryzen 7 2700 Eight-Core Processor; 16GB DDR4;
Samsung SSD 990 EVO Plus 2TB;
Windows: Version 10.0.26200.7623 (this is a Windows 11 Insider Preview build); 
.NET SDK: 10.0.102. Sample size 20.

Parse of `testing/roslyn/src/**/*.cs` is 76000 +/- 1000 tokens per second (SD). Sample size 5, port CSharp. 13287206 tokens.

## License

MIT

## Provenance in canon

`CSharpLexer.g4` and `CSharpParser.g4` are the C# 7 grammar from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/7df52be94698550d219d299d04105c6bafadd9c3/csharp/v7)
at commit `7df52be94698550d219d299d04105c6bafadd9c3`, under the licenses in
their headers (MIT, and the Eclipse Public License 1.0 of the C# ANTLR 3
grammar it derives from; Copyright (c) 2013 Christian Wulf, Copyright (c)
2016-2017 Ivan Kochurkin, Positive Technologies). The README above is
upstream's, without its performance chart. canon interprets the grammar itself
and has no port of the `CSharpLexerBase` and `CSharpParserBase` classes, so
the lexer's base class is ported as the `Canon.Antlr4.Lex.CSharp` hook, the
lexer's predicates are replaced, and C# 8 to 14 syntax is added. Every change
is marked `// canon:` in the grammar and recorded as `DEC-csharp-grammar`
in canon's `canonical_decisions.yaml`:

- The hook tracks the braces of each interpolation hole, so the brace that
  closes a hole returns to the string, and switches to the format mode at a
  colon outside parentheses and brackets in the hole, which upstream found by
  looking ahead in the character stream.
- The hook reads the branches of each `#if` that a build selects, and hides
  the others. A build is an assignment of the symbols the file's conditions
  name; a symbol the file `#define`s or `#undef`s overrides it. canon reads a
  file once per build of a few that together read every branch some build
  compiles, and merges what each finds, as `DEC-preprocessor-builds` records.
  Upstream evaluated the condition with no symbols defined.
- A verbatim interpolated string has a mode of its own instead of the
  `IsRegularCharInside` and `IsVerbatiumDoubleQuoteInside` predicates, and may
  open with `@$` as well as `$@`; an escape in a regular interpolated string is
  any backslash pair, so `\u` and `\x` escapes lex.
- An escape in a regular string is a backslash and the character after it,
  the digits of a `\x` escape being ordinary characters, because a hex escape
  of one to four digits made the lexer try every split of a run of them; and
  strings take the C# 11 `u8` suffix.
- A C# 11 raw string without interpolation is one token. An interpolated raw
  string has a mode of its own, `INTERPOLATION_RAW_STRING`: the hook counts the
  dollars and quotes of its opener, so a run of as many braces as dollars opens
  a hole, which is parsed, and a run of as many quotes closes the string.
- The byte order mark is also the decoded character, which is how canon reads
  a file; a shebang line and the `#:` directives of a C# 14 file-based program
  are hidden.
- The contextual keywords `and`, `extension`, `file`, `global`, `init`, `not`,
  `or`, `record`, `required`, `scoped`, and `with` are tokens, and identifiers
  too.
- Attributes and modifiers move from `type_declaration` and
  `class_member_declaration` into each kind of type and member through
  `member_prefix`, so a member's node starts at its first attribute and the doc
  comment above binds to it. `common_member_declaration`,
  `typed_member_declaration`, `struct_body`, `struct_member_declaration`, and
  the unused `interface_body`, `interface_member_declaration`, and
  `interface_accessors` are folded in or removed; a field's and a constant's
  first declarator is the member's own identifier, the conversion operator is
  a member of its own, and the namespace's `qi` label is dropped, so each unit
  is named by a child of its own.
- `public` and `protected` are labeled `required` in `all_member_modifier`, so a
  member visible outside its assembly requires a comment, and each attribute is
  labeled `marker`, so a test is told by its attribute. `private` and
  `internal` are labeled `optional`. `protected internal` is labeled `required`
  and `private protected` `optional`, in either order, each pair tried before
  its parts.
- The body of an interface and of an enum is labeled `inherited`, so a member
  needs a comment when its interface or enum does, as `DEC-inherited-label`
  records; a private or internal interface member does not.
- C# 8 to 14 syntax upstream rejects: file-scoped namespaces, top-level
  statements, global using and aliases of any type, records and record
  structs, primary constructors, `init` and `readonly` accessors in any order,
  `required` and `file` members, switch and `with` expressions, ranges,
  patterns (`and`, `or`, `not`, relational, property, positional, list, and
  slice), target-typed `new`, collection expressions, static and attributed
  lambdas with return types and default parameters, `await foreach` and `await
  using`, `scoped` and `ref readonly` parameters, `params` of any collection
  type, checked and unsigned-shift operators, expression-bodied event
  accessors, function pointer types, the `notnull`, `default`, and `allows ref
  struct` constraints, `nameof` of an unbound generic type, and extension
  blocks.

The parser's semantic predicates stay in the grammar, and canon answers them
through the `CSharpParserBase` hook, selected by the parser's `superClass`, as
`DEC-parser-predicates` records: `IsRightArrow`, `IsRightShift`, and
`IsRightShiftAssignment` hold when the two tokens of `=>`, `>>`, and `>>=`
touch, and `IsLocalVariableDeclaration` fails when a `var` declaration has a
second declarator.

canon's parser keeps a memo entry only for a rule tried at a token it can
start with, and reads a loop without pairing each item with every later end,
as `DEC-parser-memory` records: on this grammar a typical file parses in a
tenth of a second, and a 13,000-line file of collection initializers in 10
seconds and under 1 GB.

## Canonically commented dialect

`canonically_commented/CSharpLexer.g4` and `CSharpParser.g4` are the grammar
above with XML doc comments as canonical comments, recorded as
`DEC-csharp-dialect`. Each change is marked `// canon:`:

- `///` and `/**` open a doc comment on the default channel, in the `DocLine`
  and `DocBlock` modes, which tokenize prose, markup punctuation, `ref:KEY`,
  and `license:KEY`. A following `///` line continues a line comment. A plain
  comment may not start with a third slash or two stars, so `////`, `/**/`,
  and `/***` stay plain by the longest match.
- `canonicalComment` and `docPart` are the comment rules.
- Each namespace, type, member, and enum member is a labeled unit alternative:
  `# namespace`, `# class`, `# struct`, `# record`, `# interface`, `# enum`,
  `# delegate`, `# method`, `# constructor`, `# destructor`, `# property`,
  `# indexer`, `# event`, `# operator`, `# field`, `# constant`, `# member`,
  and `# extension`. The doc comment above the attributes is the `why`, and of
  several in a row the last binds.
- A doc comment the compiler warns is on no valid element is an `orphan`:
  after an attribute, before a statement, a switch section, a using directive,
  an extern alias, an assembly attribute, an accessor, a parameter, an
  argument, an initializer's element, or a switch expression's arm, and after
  the last member of a body, an enum, or a file.

A doc comment anywhere else inside an expression fails the parse, since the
grammar would have to accept it between any two tokens of an expression.

