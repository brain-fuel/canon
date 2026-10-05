# Kotlin Formal Grammar

ANTLR4 grammar for Kotlin written only in ANTLR's special syntax.

## Reference
* [pldb](http://pldb.info/concepts/kotlin)
* [EBNF Kotlin grammar](http://kotlinlang.org/docs/reference/grammar.html)
* [Kotlin specification](https://github.com/Kotlin/kotlin-spec)

## License
Licensed under the Apache 2.0

## Testing
Test.kt includes the test data from the JetBrains's repository
github.com/JetBrains/kotlin/tree/master/compiler/testData/psi
(stale link).

## Contacts
Anastasiya Shadrina a.shadrina5@mail.ru

## Origin source
<https://github.com/shadrina/kotlin-grammar-antlr4>

## Provenance in canon

`KotlinLexer.g4` and `KotlinParser.g4` are from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/master/kotlin/kotlin)
under the Apache 2.0 license above. The README above is upstream's. Each change
is marked `// canon:` in the grammar, recorded as `DEC-kotlin-grammar` unless
said otherwise:

- `whenSubject` may bind a value, `when (val x = ...)`, as Kotlin 1.3 allows,
  recorded with the other patches of `DEC-more-languages`.
- Each annotation is labeled `marker`, so canon recognises a function marked
  `@Test` as a test, recorded as `DEC-kotlin-dialect`.
- A letter is a character of the Unicode categories `Ll`, `Lm`, `Lo`, `Lt`,
  `Lu`, and `Nl`, and a digit one of `Nd`, written as `[\p{...}]` sets.
  Upstream imported them from `UnicodeClasses.g4`, a table of ranges whose
  rules were tokens, so canon's lexer tried each at every character and
  matched a letter range by range; lexing took five to ten times as long, and
  a 5,000-line file took 17 seconds where it now takes under two.
  `UnicodeClasses.g4` is no longer vendored.
- The syntax Kotlin added since the grammar was written, which the corpus below
  uses: `fun interface` (1.4); `value class`, with `value` a soft keyword, and
  unsigned literals `1u`, `0xFFu`, `1uL` (1.5); definitely non-nullable types
  `T & Any` (1.7); the range `..<` (1.8); context parameters and receivers,
  `context(logger: Logger)` and `context(A)`, before a declaration or a
  function type, with `context` a soft keyword (2.2); guards in `when`
  entries, `is T if cond ->` (2.2); multi-dollar strings `$$"..."` (2.2);
  destructuring by position, `val [a, b] = pair` and `for ([k, v] in map)`,
  and by name, `(val first, val second = other) = pair` (2.3); and companion
  blocks, `companion { ... }` (2.4).
- Trailing commas where Kotlin allows them and the grammar did not: after the
  conditions of a `when` entry, the parameters of a function type, and the
  entries of a destructuring declaration. An expression in `${...}` may span
  lines.
- A script may end with a statement and no newline, as a Gradle build script
  often does.

## Canonically commented dialect

`canonically_commented/KotlinLexer.g4` and `KotlinParser.g4` are the grammar
above with KDoc comments as canonical comments, recorded as
`DEC-kotlin-dialect`. Each change is marked `// canon:`:

- `/**` opens a KDoc comment on the default channel, in the default and
  `Inside` modes, and the `DocBlock` mode tokenizes prose, `ref:KEY`, and
  `license:KEY`; a block tag such as `@param` is a word of the prose. A plain
  block comment may not start with a single star after its opener, so `/**/`
  and `/***` stay plain, and a KDoc comment nested in a plain one is part of it.
  Kotlin's comments nest, so a `/* ... */` inside a KDoc comment is part of
  it, and its `*/` does not close the KDoc.
- `canonicalComment` and `docPart` are the comment rules.
- Each declaration KDoc documents is a labeled unit alternative: a top-level
  `# class` (interfaces included), `# object`, `# function`, `# property`, and
  `# type` in `declaration`; the same, a companion `# object`, and a secondary
  `# constructor` in `classMemberDeclaration`; an enum `# entry`; and a
  constructor parameter declared `val` or `var` as a `# property`. The KDoc
  comment above the annotations and modifiers is the `why`, and of several in a
  row the last binds. A local declaration is no unit; it is parsed by
  `localDeclaration`.
- A KDoc comment above the package directive or the file annotations is the
  file's Why.
- A KDoc comment after an annotation or a modifier, before a statement or an
  import, on a plain parameter, on an accessor, before an initializer block or
  a lambda's parameters, or after the last member, statement, or declaration is
  an `orphan`.
- The option `strayComment = canonicalComment` lets a KDoc comment stand
  anywhere else, as between two operands or two arguments: where the parse
  fails at such a comment or just after it, canon reads the file without it and
  reports it as an orphan, under `DEC-stray-comments`.
- A top-level declaration holds the empty rule `publicByDefault`, labeled
  `required`; class, interface, object, and enum bodies are labeled
  `inherited`; `private`, `internal`, `override`, and `actual` are labeled
  `optional`. A constructor property is not inherited, since its class may
  document it with `@property`, and the members of an object expression inherit
  nothing. The modifiers of an accessor and of a primary constructor are
  `innerModifiers`, which carry no labels, so a private setter does not make
  its property optional.
- A class declared inside a function body is `localClassDeclaration`, no unit,
  whose body is `objectLiteralBody` as an object expression's is, so its
  members are units that inherit no requirement from the function around them.
  A script's statements may declare an enum class, whose body is then an enum
  class body.
- A unit is named by what its source writes: a companion object without a
  name, and a companion block, by its `companion` keyword, though Kotlin calls
  the object `Companion`, and a
  secondary constructor by its `constructor` keyword, the second
  `constructor#2`. canon reads names from the source text and has no way to
  give a unit a name the source does not write.

The stray-comment recovery reads a comment as an orphan only when the parse
fails at the comment or at the token right after it. Where the grammar accepts
the comment in one reading, as an orphan before a statement, and the parse then
fails further on, as it did before a lambda's parameters, the grammar names the
place instead; a place of that kind not yet named still fails the parse. None
of the Turbine sources has one.

## Corpus

`tools/corpus/kotlin.sh` checks the grammar against widely used Kotlin code. It
clones each repository below over https, shallow, blob-filtered, and sparse
where a subdirectory sample is named, pinned to the commit given, into
`/tmp/corpus/kotlin` or the directory given as its first argument, and parses
every `.kt` file from `kotlinFile` and every `.kts` file from `script`, with the
plain grammar and then the dialect, one canon process per file on one
capability, with a limit of 20 seconds of CPU time each. It prints per
repository the files parsed, the deliberate exclusions, the failures with
canon's message, and the slowest files, then the files the plain grammar parses
and the dialect does not, and the distribution of times. Run it from the
repository after `stack build`:

```sh
tools/corpus/kotlin.sh                # or: JOBS=8 TIMEOUT=20 tools/corpus/kotlin.sh /tmp/corpus/kotlin
```

| Repository | Commit | Sampled |
|------------|--------|---------|
| [Kotlin/kotlinx.coroutines](https://github.com/Kotlin/kotlinx.coroutines) | `bd2e9a1b90400fb7b2fa4f8731e7d8148799ab73` | whole |
| [ktorio/ktor](https://github.com/ktorio/ktor) | `1d177d32df5de4df0dfee67cee159e01e226419f` | `ktor-server/ktor-server-core`, `ktor-client/ktor-client-core`, `ktor-http`, `ktor-io`, `ktor-utils`, `ktor-shared/ktor-serialization` |
| [square/okhttp](https://github.com/square/okhttp) | `ac3d46c892ef486eca5bd84259dfb9bc8778d909` | whole |
| [JetBrains/compose-multiplatform](https://github.com/JetBrains/compose-multiplatform) | `6b7b6ad83bfc87ca554e00409fa25c6707513280` | whole |
| [JetBrains/kotlin](https://github.com/JetBrains/kotlin), the standard library | `e5b61f33dedf8f0cd170ed316d321ac837478ffc` | `libraries/stdlib` |
| `lang_samples/kotlin-turbine` | vendored | whole |

| Repository | Files | Parsed | Excluded | Failed | Dialect parsed | CPU time, plain / dialect | Slowest file |
|------------|------:|-------:|---------:|-------:|---------------:|--------------------------:|-------------:|
| kotlinx.coroutines | 1,039 | 1,039 | 0 | 0 | 1,039 | 82 s / 92 s | 1.2 s |
| kotlinx.coroutines `.kts` | 43 | 43 | 0 | 0 | 43 | 3 s / 3 s | 0.1 s |
| ktor | 882 | 882 | 0 | 0 | 882 | 64 s / 74 s | 0.5 s |
| ktor `.kts` | 21 | 21 | 0 | 0 | 21 | 1 s / 1 s | 0.1 s |
| okhttp | 573 | 573 | 0 | 0 | 573 | 65 s / 77 s | 1.8 s |
| okhttp `.kts` | 44 | 44 | 0 | 0 | 44 | 3 s / 3 s | 0.2 s |
| compose-multiplatform | 1,388 | 1,381 | 7 | 0 | 1,381 | 152 s / 170 s | 20 s, excluded |
| compose-multiplatform `.kts` | 230 | 228 | 2 | 0 | 228 | 14 s / 17 s | 0.3 s |
| kotlin-stdlib | 1,318 | 1,318 | 0 | 0 | 1,318 | 145 s / 167 s | 6.2 s |
| kotlin-stdlib `.kts` | 7 | 7 | 0 | 0 | 7 | 2 s / 2 s | 0.7 s |
| kotlin-turbine | 18 | 18 | 0 | 0 | 18 | 2 s / 2 s | 0.3 s |

Every file parses, 5,554 of 5,563, with the plain grammar and with the dialect,
but nine of Compose Multiplatform's, excluded with their reasons in the script:

- five test cases under `html/compose-compiler-integration/testcases/passing/`,
  each several modules in one file that its harness splits at `// @Module:`
  markers, so imports follow declarations, which kotlinc rejects in one file;
- `compose/integrations/compose-with-ktx-serialization/build.gradle.kts`, which
  is written in the Groovy DSL, `group "com.example"`, and kotlinc rejects;
- `gradle-plugins/compose/src/test/test-projects/application/aot/build.gradle.kts`,
  a template whose `%JAVA_VERSION%` placeholder its test fills in;
- `String0.commonMain.kt` and `String100.commonMain.kt` under
  `gradle-plugins/compose/src/test/test-projects/misc/hugeResources/expected/`,
  generated, 0.9 MB each, the expected output of the resource generator for a
  stress test, which canon reads in about 20 seconds of CPU time and 1.8 GB
  of memory, at the limit, so they time out on one run and not the next.

5,505 files take under half a second of CPU time and all but 16 under one; the
slowest file that is not excluded is the standard library's generated
`_Arrays.kt`, 6.2 seconds for 28,000 lines, 7.4 with the dialect, and the
slowest failure 0.05 seconds. canon's parser climbs the grammar's fourteen
levels of expression rules for every operand, so Kotlin reads slower than
Java, and a file of a megabyte is beyond the limit. The parser is
`Canon.Antlr4.Parse`, which the corpus work leaves unchanged.

The Turbine profile maps `.kts` to `kotlinFile`, as a profile has one start
rule, so a build script's top-level statements parse there only where they are
declarations; the corpus reads `.kts` files from `script`, the rule Kotlin's
grammar gives scripts.
