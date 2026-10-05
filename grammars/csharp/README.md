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
- The hook reads one branch of each `#if`: the first whose condition holds for
  some choice of the symbols the file does not `#define` or `#undef`, so the
  code canon reads is code some build compiles. The other branches go to the
  hidden channel. Upstream evaluated the condition with no symbols defined.
- A verbatim interpolated string has a mode of its own instead of the
  `IsRegularCharInside` and `IsVerbatiumDoubleQuoteInside` predicates, and may
  open with `@$` as well as `$@`; an escape in a regular interpolated string is
  any backslash pair, so `\u` and `\x` escapes lex.
- An escape in a regular string is a backslash and the character after it,
  the digits of a `\x` escape being ordinary characters, because a hex escape
  of one to four digits made the lexer try every split of a run of them; and
  strings take the C# 11 `u8` suffix.
- C# 11 raw strings, interpolated or not, are one token each.
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
  labeled `marker`, so a test is told by its attribute.
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

The parser's semantic predicates stay in the grammar, but canon's interpreter
does not run them: `IsLocalVariableDeclaration` is not needed by a parser that
keeps every parse, and `IsRightArrow`,
`IsRightShift`, and `IsRightShiftAssignment`, which required the two tokens of
`=>`, `>>`, and `>>=` to touch, are not checked, so `= >` is read as an arrow.
The holes of an interpolated raw string are not parsed, and an interface member
requires a comment only when it is marked `public`, because the grammar does
not see that it is public by default.

canon's parser keeps one memo table per rule and token, so its memory grows
with both: on this grammar a typical file parses in a tenth of a second, and
a 13,000-line file of collection initializers in 16 seconds and 10 GB.
