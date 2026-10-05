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
  import, on a plain parameter, on an accessor, before an initializer block, or
  after the last member, statement, or declaration is an `orphan`.
- A top-level declaration holds the empty rule `publicByDefault`, labeled
  `required`; class, interface, object, and enum bodies are labeled
  `inherited`; `private`, `internal`, `override`, and `actual` are labeled
  `optional`. A constructor property is not inherited, since its class may
  document it with `@property`, and the members of an object expression inherit
  nothing. The modifiers of an accessor and of a primary constructor are
  `innerModifiers`, which carry no labels, so a private setter does not make
  its property optional.
- A companion object without a name is named `companion`, and a secondary
  constructor `constructor`.

A KDoc comment anywhere else inside an expression fails the parse, as no rule
can accept a token between any two tokens of an expression. A class declared
inside a function body is no unit, so its members take their requirement from
the function around it.
