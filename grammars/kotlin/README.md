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

`KotlinLexer.g4`, `KotlinParser.g4`, and `UnicodeClasses.g4` are from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/master/kotlin/kotlin)
under the Apache 2.0 license above. The README above is upstream's. Each change
is marked `// canon:` in the grammar:

- `whenSubject` may bind a value, `when (val x = ...)`, as Kotlin 1.3 allows,
  recorded with the other patches of `DEC-more-languages`.
- Each annotation is labeled `marker`, so canon recognises a function marked
  `@Test` as a test, recorded as `DEC-kotlin-dialect`.

## Canonically commented dialect

`canonically_commented/KotlinLexer.g4` and `KotlinParser.g4`, with a copy of
`UnicodeClasses.g4` for their import, are the grammar above with KDoc comments
as canonical comments, recorded as `DEC-kotlin-dialect`. Each change is marked
`// canon:`:

- `/**` opens a KDoc comment on the default channel, in the default and
  `Inside` modes, and the `DocBlock` mode tokenizes prose, `ref:KEY`, and
  `license:KEY`; a block tag such as `@param` is a word of the prose. A plain
  block comment may not start with a single star after its opener, so `/**/`
  and `/***` stay plain, and a KDoc comment nested in a plain one is part of it.
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
- A unit is named by what its source writes: a companion object without a
  name by its `companion` keyword, though Kotlin calls it `Companion`, and a
  secondary constructor by its `constructor` keyword, the second
  `constructor#2`. canon reads names from the source text and has no way to
  give a unit a name the source does not write.

The stray-comment recovery reads a comment as an orphan only when the parse
fails at the comment or at the token right after it. Where the grammar accepts
the comment in one reading, as an orphan before a statement, and the parse then
fails further on, as it did before a lambda's parameters, the grammar names the
place instead; a place of that kind not yet named still fails the parse. None
of the Turbine sources has one.
