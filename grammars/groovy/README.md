# Groovy grammar

## Provenance in canon

`GroovyLexer.g4` and `GroovyParser.g4` are Apache Groovy's own ANTLR 4
grammar, `src/antlr/GroovyLexer.g4` and `src/antlr/GroovyParser.g4` from
[apache/groovy](https://github.com/apache/groovy/tree/84b0d5072e2d8d02d10720b8a337493af1bda9fe/src/antlr)
at commit `84b0d5072e2d8d02d10720b8a337493af1bda9fe`, under the Apache License
2.0 in their headers, with the BSD licence of the Java grammar by Terence Parr
and Sam Harwell they were adapted from. grammars-v4 has no Groovy grammar, at
`7df52be94698550d219d299d04105c6bafadd9c3` or in its history, and this is the
grammar the Groovy compiler itself parses with, so it reads what Groovy reads.

The grammar leans on Java: the lexer's superclass `AbstractLexer` and its
`@members`, the parser's superclass `AbstractParser`, and the
`SemanticPredicates` class. canon interprets the grammar and has no port of
those classes, so the lexer's members are ported as the
`Canon.Antlr4.Lex.Groovy` hook, the parser's predicates as the
`Canon.Antlr4.Predicate.Groovy` hook, and what neither can express is rewritten in
the grammar. Every change is marked `// canon:` in the grammar and recorded as
`DEC-groovy-grammar` in canon's `canonical_decisions.yaml`:

- The superclasses are renamed `GroovyLexerBase` and `GroovyParserBase`, the
  names that select the two hooks, since another grammar whose superclass has
  the generic name `AbstractLexer` or `AbstractParser` would otherwise get
  Groovy's hooks.
- The lexer hook keeps the type of the last token on the default channel, so
  `isRegexAllowed` tells a slashy string from a division as upstream's
  `REGEX_CHECK_SET` does, and the stack of open brackets that `enterParen` and
  `exitParen` keep, so a newline inside parentheses or square brackets, but
  not braces or `try (...)`, goes to the hidden channel. It decides the
  identifier predicates on the character just matched, as `_input.LA(-1)`
  does; canon reads code points, so the surrogate-pair alternatives never
  apply.
- canon's lexer predicates see the characters matched, not the ones ahead, so
  each predicate that looked ahead is written as the characters it allowed:
  one or two quotes inside a triple-quoted string are a character when a
  character other than a quote follows them, and may stand before the closing
  quotes or a dollar; a dollar in a slashy or dollar slashy string is a
  character when what follows it cannot start a GString value, read together
  with that character, so the `isFollowedByJavaLetterInGString` predicates
  are dropped; a character beyond ASCII after a dollar starts a value when it
  may start a Java identifier, which the hook's `isJavaLetterInGString` decides
  on the character matched; a slashy string's first character is not a star,
  and one may hold only dollars, as `/$/` does; every dollar before a slashy
  GString's closing slash belongs to its end; a slash in a dollar slashy
  string is a character when anything but a dollar follows it, and a dollar or
  a `$/` escape may stand just before its closing `/$`, as in `$/a$/$` and
  `$/a$//$`. Each of these reads as Groovy 4.0.24's own lexer reads it.
  `DollarSlashDollarEscape` keeps its predicate, which looks behind.
- `NOT_IN` takes the letters after `!in`, and the hook splits `!internal`
  back into `!` and an identifier, which upstream's `isFollowedBy` predicates
  decided; `!instanceof` needs no predicate, since a longer word is split the
  same way.
- `RollBackOne` consumed the character after a GString path and rolled the
  lexer back over it; canon's lexer cannot roll back, so it is an empty match
  that pops the mode and the character is read again in the string's mode.
- The string modes move to the end of the lexer, and `mode DEFAULT_MODE;` no
  longer reopens the default mode, since canon reads each mode section as the
  whole mode.
- Comments go to the hidden channel. Upstream made a comment a newline unless
  it was inside brackets or code followed it on its line; a comment that ends
  its line is followed by the newline token itself, so the parser sees the
  same separators.
- Each kind of type is a rule of its own, `normalClassDeclaration`,
  `interfaceDeclaration`, `enumDeclaration`, `annotationTypeDeclaration`,
  `traitDeclaration`, and `recordDeclaration`, which starts with the type's
  modifiers and annotations, so its node starts at its first annotation and
  the Groovydoc above binds to it. The header between the name and the body
  is `classHeader`. An enum's body is `enumBody`, which upstream chose inside
  `classBody` with the predicate `$t == 2` on a rule argument canon's
  predicates do not see.
- A constructor is `constructorDeclaration`, a member without a return type
  named for its class, which the `isConstructorName` predicate added for
  canon decides; upstream's AST builder told a constructor from a method.
  `def Foo()` in class `Foo` is a constructor, since `def` is a modifier and
  Groovy compiles it as one, while `Object Foo()` is a method.
- An annotation is labeled `marker`, so a test is told by its annotation, and
  `private` is labeled `optional`, since Groovy declarations are public unless
  they say otherwise.

The parser hook answers upstream's predicates on the visible tokens:
`isInvalidMethodDeclaration`, so `foo(1) { }` at the top of a script is a
call; `isInvalidLocalVariableDeclaration` and `isAnnotatedLoopStatement`, so
`println x` is a command and `String s` a declaration; `isIdentifierAssign`
for annotation arguments; `static.` as a name; and
`isFollowingArgumentsOrClosure`, which upstream read from the parse of the
expression before a command's arguments and the hook reads from its tokens.

Known limits of the port, none of which the spock-genesis sources meet:

- canon's predicate hook sees tokens, not the partial parse, so
  `isFollowingArgumentsOrClosure` judges the expression before a command's
  arguments by its brackets and operators: an expression that ends in a
  parenthesis or brace opened after its first token is taken as a path ending
  in arguments or a closure, so a cast such as `(T) f(x) y` may be read as a
  call where upstream reads a cast operand.
- The counters of switch expressions and async closures, which upstream keeps
  in parser actions, are not tracked, so `yield` and `defer` statements are
  admitted anywhere.
- canon's lexer cannot look ahead, so a dollar it cannot judge by the
  character it reads with it can differ from Groovy where code follows a
  dollar slashy string: in `$/a/$$/$` Groovy reads the string `$/a/$` and then
  `$`, `/`, `$`, while canon opens a dollar slashy GString at the `$/` after it;
  in `$/a$//$b/$` Groovy ends the string at the first `/$`, while canon reads
  that `$` as the start of a value; both fail to lex. `$///$`, a dollar slashy
  string holding one slash, lexes as `$` and a line comment.

## Canonically commented dialect

`canonically_commented/GroovyLexer.g4` and `GroovyParser.g4` are the grammar
above with Groovydoc comments as canonical comments, recorded as
`DEC-groovy-dialect`. Each change is marked `// canon:`:

- `/**` opens a Groovydoc comment on the default channel, in the `DocBlock`
  mode, which tokenizes prose, punctuation, `ref:KEY`, and `license:KEY`, and
  drops the stars that decorate its lines. A plain comment may not start with
  two stars, so `/**/` and `/***` stay plain by the longest match.
- `canonicalComment` and `docPart` are the comment rules. Each use of a
  comment takes the newlines after it, which upstream read as separators, so a
  separator never stands between a comment and its declaration, while the
  comment's span, and so its decision's, ends where the comment ends.
- Each type, constructor, method, field, and enum constant is a labeled unit
  alternative: `# class`, `# interface`, `# enum`, `# annotation`, `# trait`,
  `# record`, `# constructor`, `# method`, `# field`, and `# constant`. The
  Groovydoc above the annotations is the `why`, and of several in a row the
  last binds.
- A field declaration is read by `fieldVariables`, `fieldDeclarators`,
  `fieldNamePairs`, `fieldNamePair`, and `fieldKeyedPair`, upstream's variable
  rules with each declared name labeled `declarator`, so `int x, y` makes the
  fields `x` and `y` and `def (a, b) = [1, 2]` the fields `a` and `b`, and the
  Groovydoc above the declaration is one decision binding them all.
- A method named by a string, as a Spock feature method is, is named by the
  string's contents, a slash in it a division slash (∕).
- Each unit holds the empty rule `publicByDefault`, labeled `required`, and
  `private` is labeled `optional`, which wins, so a declaration requires a
  comment unless it is private.
- A Groovydoc comment the grammar accepts but binds to nothing is an
  `orphan`: after an annotation or a modifier, before a statement, a package,
  an import, an initializer block, a case label, or a closure's parameters,
  and after the last member of a body, a block, a closure, or a file.
- The option `strayComment = canonicalComment` lets a Groovydoc comment stand
  anywhere else, as inside an expression or between brackets: where the parse
  fails at such a comment or just after it, canon reads the file without it
  and reports it as an orphan, under `DEC-stray-comments`. Where the grammar
  accepts the comment in one reading, as before a statement, and the parse
  then fails further on, as before a case label or a closure's parameters, the
  grammar names the place instead; a place of that kind not yet named still
  fails the parse.

## Corpus

`tools/corpus/groovy.sh` checks the grammar against widely used Groovy code.
It clones each repository below over https, shallow, blob-filtered, and sparse
where a subdirectory sample is named, pinned to the commit given, into
`/tmp/corpus/groovy` or the directory given as its first argument, and parses
every `.groovy`, `.gvy`, `.gy`, `.gsh`, and `.gradle` file and every
`Jenkinsfile` with the plain grammar and then the dialect, one canon process
per file on one capability, with a limit of 20 seconds of CPU time each. It
prints per repository the files parsed, the deliberate exclusions, the
failures with canon's message, and the slowest files, then the files the plain
grammar parses and the dialect does not, and the distribution of times. Run it
from the repository after `stack build`:

```sh
tools/corpus/groovy.sh                # or: JOBS=8 TIMEOUT=20 tools/corpus/groovy.sh /tmp/corpus/groovy
```

| Repository | Commit | Sampled |
|------------|--------|---------|
| [apache/groovy](https://github.com/apache/groovy) | `84b0d5072e2d8d02d10720b8a337493af1bda9fe` | `src/main`, `src/spec`, `src/test`, and the `groovy-json`, `groovy-xml`, `groovy-sql`, `groovy-templates`, `groovy-console`, `groovy-swing`, `groovy-contracts`, `groovy-ginq`, `groovy-macro`, and `groovy-typecheckers` subprojects |
| [gradle/gradle](https://github.com/gradle/gradle) | `81c85f2d52959d1bb34e523e4309de16ede8fc0c` | `subprojects/core`, `platforms/core-configuration` |
| [spockframework/spock](https://github.com/spockframework/spock) | `61e6461703d572a1cca0f5b4112b521919f6b84a` | whole |
| [apache/grails-core](https://github.com/apache/grails-core) | `232bb340064ff0aead5a435fb2d8a4056d7c59d3` | `grails-core`, `grails-gsp`, `grails-datamapping-core`, `grails-web-url-mappings`, `grails-async`, `grails-events`, `grails-fields` |
| [jenkinsci/pipeline-examples](https://github.com/jenkinsci/pipeline-examples) | `fb9575a8182b51614f5f0df912b46b37d95fbb8d` | whole |
| [fabric8io/fabric8-pipeline-library](https://github.com/fabric8io/fabric8-pipeline-library) | `8f3562d748d0fde2dfcb8b4d9600cfdce6d81e21` | whole, a Jenkins shared library |
| `lang_samples/groovy-spock-genesis` | vendored | whole |

| Repository | Files | Parsed | Excluded | Failed | Dialect parsed | CPU time, plain / dialect | Slowest file |
|------------|------:|-------:|---------:|-------:|---------------:|--------------------------:|-------------:|
| groovy | 2,241 | 2,241 | 0 | 0 | 2,241 | 150 s / 165 s | 4.8 s |
| gradle | 1,364 | 1,364 | 0 | 0 | 1,364 | 105 s / 121 s | 0.8 s |
| spock | 635 | 606 | 29 | 0 | 606 | 36 s / 43 s | 0.5 s |
| grails-core | 1,075 | 1,075 | 0 | 0 | 1,075 | 75 s / 88 s | 0.6 s |
| pipeline-examples | 53 | 53 | 0 | 0 | 53 | 2 s / 3 s | 0.1 s |
| fabric8-pipeline-library | 87 | 87 | 0 | 0 | 87 | 5 s / 6 s | 0.3 s |
| groovy-spock-genesis | 8 | 8 | 0 | 0 | 8 | under 1 s | 0.1 s |

Every file parses, 5,434 of 5,463, but the 29 excluded: Spock's
`spock-specs/src/test/resources/snapshots/`, renderings of the ASTs Spock's
transformations produce and of the compiler errors they report, which its
tests compare against and groovyc rejects. The dialect parses every file the
plain grammar parses. 5,449 files take under half a second of CPU time and all
but two under one; the slowest is Groovy's `ParserPositiveSyntaxTest.groovy`,
4.8 seconds, and the slowest failure, a snapshot, 0.06 seconds. The grammar
needed no change. The profile lists `.groovy`, `.gvy`, `.gy`, and `.gsh`; a
project that wants its `.gradle` files or `Jenkinsfile` read adds them to its
profile's extensions, which the grammar reads as it reads any script.
