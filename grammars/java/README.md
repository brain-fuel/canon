# Java grammar

## Provenance in canon

`JavaLexer.g4` and `JavaParser.g4` are the Java grammar of
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/master/java/java),
by Terence Parr, Sam Harwell, Ivan Kochurkin, and Michał Lorek, under the BSD
licence in their headers. canon gave every parser rule and every non-fragment
lexer rule a canonical comment, recorded as `DEC-java-grammar-comments`, and
changed the grammar where Java syntax newer than upstream's needed it. Each
change is marked `// canon:` above the rule's comment and recorded as
`DEC-java-grammar`:

- A component of a record pattern may declare its variable with `var`, as in
  `case Point(var x, var y)` (Java 21), or be the unnamed pattern `_` (Java
  22). The lexer reads `_` as an identifier, so a component pattern may be a
  bare name; Java accepts only `_` there.
- A type annotation may stand before the type an array or instance creation
  makes and before each of its dimensions: `new @Nullable Object[n]`,
  `new int @A [n]`, `new p.@A C()`.
- `import module java.base;` imports every package a module exports (Java 25).
- A compact source file (Java 25) declares methods and fields at the top level,
  in a class the compiler declares: `void main() { ... }` is a compilation
  unit.

`canonically_commented/` holds the dialect, which carries the same changes.
Its rules are described in canon's README under `grammars/`. In the dialect a
method or field of a compact source file is a unit as it is in a class body,
and the Javadoc comment directly above a module declaration, after the
imports of `module-info.java`, is the module's Why, as javadoc reads it; a
Javadoc comment before an import is an orphan.

## Corpus

`tools/corpus/java.sh` checks the grammar against widely used Java code. It
clones each repository below over https, shallow, blob-filtered, and sparse
where a subdirectory sample is named, pinned to the commit given, into
`/tmp/corpus/java` or the directory given as its first argument, and parses
every `.java` file with the plain grammar and then the dialect, one canon
process per file on one capability, with a limit of 20 seconds of CPU time
each. It prints per repository the files parsed, the deliberate exclusions, the
failures with canon's message, and the slowest files, then the files the plain
grammar parses and the dialect does not, and the distribution of times. Run it
from the repository after `stack build`:

```sh
tools/corpus/java.sh                  # or: JOBS=8 TIMEOUT=20 tools/corpus/java.sh /tmp/corpus/java
```

| Repository | Commit | Sampled |
|------------|--------|---------|
| [spring-projects/spring-framework](https://github.com/spring-projects/spring-framework) | `3a91d153165490b0736c9907fda1d8669c6ef3f4` | `spring-core`, `spring-beans`, `spring-context`, `spring-web` |
| [google/guava](https://github.com/google/guava) | `81c7d030f8f144a4885ccf8efdc72c92605b4eec` | `guava`, `guava-testlib`, `guava-tests` |
| [elastic/elasticsearch](https://github.com/elastic/elasticsearch) | `c11078209dc8e63b7669216655cc62185487b70b` | `libs`, `modules/lang-painless`, `server/src/main/java/org/elasticsearch/cluster` |
| [openjdk/jdk](https://github.com/openjdk/jdk) | `8cbb6b7036f1cbc48efea2d9e4830d240ab01fec` | `src/java.base` |
| [apache/commons-lang](https://github.com/apache/commons-lang) | `682a8ff5cddfeedecb98f62ac7c8d94b5ff65f33` | whole |
| `lang_samples/java-commons-lang`, `java-gson`, `java-joda-time` | vendored | whole |

| Repository | Files | Parsed | Excluded | Failed | Dialect parsed | CPU time, plain / dialect | Slowest file |
|------------|------:|-------:|---------:|-------:|---------------:|--------------------------:|-------------:|
| spring-framework | 4,153 | 4,153 | 0 | 0 | 4,153 | 204 s / 246 s | 0.8 s |
| guava | 1,618 | 1,618 | 0 | 0 | 1,618 | 98 s / 117 s | 1.1 s |
| elasticsearch | 2,059 | 2,059 | 0 | 0 | 2,059 | 123 s / 144 s | 0.9 s |
| jdk | 3,324 | 3,324 | 0 | 0 | 3,324 | 216 s / 259 s | 5.7 s |
| commons-lang | 629 | 629 | 0 | 0 | 629 | 47 s / 53 s | 2.0 s |
| java-commons-lang | 629 | 629 | 0 | 0 | 629 | 47 s / 51 s | 1.9 s |
| java-gson | 264 | 264 | 0 | 0 | 264 | 16 s / 17 s | 0.4 s |
| java-joda-time | 330 | 330 | 0 | 0 | 330 | 31 s / 34 s | 0.4 s |

All 13,006 files parse with the plain grammar and with the dialect, none
excluded. 12,969 take under half a second of CPU time and all but four under
one; the slowest is the JDK's `sun/nio/cs/GB18030.java`, 5.7 seconds for
12,000 lines of string literals concatenated into its tables. Before the changes above, 16 files failed:
14 of Guava's on `new @Nullable T[n]`, one of Elasticsearch's and one of the
JDK's on a `var` component of a record pattern, and the dialect failed on
Elasticsearch's `module-info.java`, whose Javadoc stands after its imports.
