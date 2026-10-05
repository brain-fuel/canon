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

- The `CSharpLexerBase` hook emits an empty `DOC_END` token where a `///`
  comment ends, at its line break, before a `////` line, or at the end of the
  file, and `canonicalComment` ends at it. Before, the rule could end after
  any word, and canon's parser, keeping a tree for each end, took time and
  memory in the square of a comment's length, as in the long `///` blocks of
  the runtime's `AdvSimd.cs`.
- Anywhere else, as inside an expression, the parser's `strayComment` option
  names `canonicalComment`, so a doc comment the grammar does not accept where
  it stands is read out of the file and reported as an `orphan`
  (`DEC-stray-comments`). A doc comment never fails the parse.

## Corpus

`tools/corpus/csharp.sh` checks the grammar against widely used C# code. It
clones each repository below, shallow and pinned to a commit, into a directory
given as its argument (default `/tmp/corpus/csharp`), checking out only the
listed subdirectories of the large ones; parses every `.cs` file with the
plain grammar and then with the dialect, each file under a limit of `TIMEOUT`
(120) seconds of CPU time, which the largest generated files need;
and prints per repository the files, the files parsed, the deliberate
exclusions, the failures, the CPU time, and the slowest files, then the files
the plain grammar parses and the dialect does not, and the distribution of
times. Rerun it with `tools/corpus/csharp.sh [DIR]`; `JOBS` sets the parallel
parses and `ONLY` names one repository. `canon parse` reads each `#if` by the
default choice, the first branch some build reads, so the corpus checks that
choice rather than every build `canon check` reads.

| Repository | Commit | Sampled | Files | Parsed | Excluded | CPU time, plain / dialect |
|---|---|---|---|---|---|---|
| dotnet/runtime | `8e6821d2d912` | `src/libraries/`: `System.Private.CoreLib/src`, `System.Collections`, `System.Linq`, `System.Text.Json/src`, `System.Net.Http/src` | 2,540 | 2,539 | 1 | 788 s / 747 s |
| dotnet/aspnetcore | `aaec58f9ccee` | `src/Http`, `src/Mvc/Mvc.Core`, `src/Servers/Kestrel/Core` | 2,123 | 2,122 | 1 | 438 s / 424 s |
| dotnet/roslyn | `303af2d38ee0` | `src/Compilers/Core/Portable`, `src/Compilers/CSharp/Portable` | 2,091 | 2,091 | 0 | 727 s / 749 s |
| JamesNK/Newtonsoft.Json | `52fa3aef1f2c` | whole | 951 | 951 | 0 | 168 s / 166 s |
| AvaloniaUI/Avalonia | `daed7a2592f1` | `src/Avalonia.Base`, `src/Avalonia.Controls` | 1,845 | 1,845 | 0 | 238 s / 244 s |
| `lang_samples/csharp-guardclauses` | | | 15 | 15 | 0 | 1 s / 1 s |

The full commits are in the script. The dialect parses every file the plain
grammar parses. The two exclusions, listed in the script with their reasons,
are files the compiler rejects in a build that defines a symbol of theirs:
the runtime's `TraceLogging/EnumHelper.cs`, whose `#if EVENTSOURCE_GENERICS`
branch begins with a stray `?using`, and ASP.NET Core's
`ILEmitTrieFactory.cs`, whose `#if IL_EMIT_SAVE_ASSEMBLY` branch lacks a
closing parenthesis. No build of either project defines the symbol, but
canon reads the branch, as it reads every branch some build could select.

Each file is parsed on one capability (`GHCRTS=-N1`) and timed in CPU
seconds, since the machine ran other work at a load of 60 to 140. Of the 9,565
files, the plain grammar parses 8,737 in under half a second, 502 in under
one, 222 in under two, 77 in under five, 14 in under ten, and 13 in ten
seconds or more. The slowest are generated: ASP.NET Core's
`MatcherAzureBenchmarkBase.generated.cs`, a 31,000-line table of 25,000
statements in one method, at 58 s; Roslyn's `Syntax.xml.Internal.Generated.cs`
(39,500 lines) at 44 s and `BoundNodes.xml.Generated.cs` and
`Syntax.xml.Syntax.Generated.cs` at 25 s; the runtime's test data
`InputData.cs` at 18 s; and its `AdvSimd.cs` at 15 s. The slowest file a
person wrote is Newtonsoft.Json's `JsonSerializerTest.cs` at 7 s. The
dialect's times are within 15% of these. The two failing files fail within
0.5 s. Parser speed and memory, not the grammar, are what make the generated
files slow: canon's parser keeps memo entries per token of a long statement
list, and the benchmark table, parsed alone, took 36 CPU seconds and 10.6 GB.

The corpus showed what the grammar lacked; each fix is marked `// canon:` in
both grammars and tested in `CSharpTest.hs`:

- The unsigned right shift `>>>` and its assignment `>>>=` (C# 11), three
  touching greater-than signs, which the `IsRightShift` predicate checks as it
  does for `>>`.
- A constant pattern may use the bitwise operators `&`, `^`, and `|`, as
  `case 'n' ^ 't':` and `(A or B | C, _)` do; the relational operators stay
  out, since they begin relational patterns.
- A union (C# 15), as `public union Pet(Cat, Dog);`, is a type of its own,
  `union_definition`, and a `# union` unit of the dialect; the sample profile
  makes it a unit. `union` stays an identifier.
- The `safe` member modifier of C# 15, which stays an identifier.
- `partial` may follow `ref`, as in `public unsafe ref partial struct`.
- An implicitly typed lambda parameter may take `ref`, `out`, `in`, or
  `scoped` (C# 14), as in `(_, out p) =>`, and a conversion operator's
  parameter may take a modifier, as in `implicit operator T(in S s)`.
- A local may be `scoped ref` or `scoped ref readonly`.
- A conditional's branches may be ref expressions, `c ? ref a : ref b`.
- A pointer may point to a pointer, as in `fixed (T** p = &x)`.
