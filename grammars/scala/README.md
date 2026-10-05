# Scala Grammar

`ScalaLexer.g4` and `ScalaParser.g4` are written for canon, under canon's MIT
license. The parser follows the context-free syntax of the
[Scala 3 syntax summary](https://docs.scala-lang.org/scala3/reference/syntax.html)
production by production, under the summary's names in lower camel case, and
takes the Scala 3 compiler's parser,
[`Parsers.scala`](https://github.com/scala/scala3/blob/39f42801b17af4a49df3ae37f35ce65ab874e2a9/compiler/src/dotty/tools/dotc/parsing/Parsers.scala)
(Apache-2.0), as the authority where the two differ. The lexer follows the
summary's lexical syntax and the compiler's
[`Scanners.scala`](https://github.com/scala/scala3/blob/39f42801b17af4a49df3ae37f35ce65ab874e2a9/compiler/src/dotty/tools/dotc/parsing/Scanners.scala),
and the indentation hook follows `Scanners.scala` and the reference's
[Optional Braces](https://docs.scala-lang.org/scala3/reference/other-new-features/indentation.html)
section. [PLDB's Scala entry](https://pldb.io/concepts/scala.html) was
consulted for Scala's keywords and comment forms. The grammar is recorded as
`DEC-scala-grammar`, the hook as `DEC-scala-indentation`, and the dialect as
`DEC-scala-dialect` in canon's `canonical_decisions.yaml`, and these sources as
`scala3-syntax`, `scala3-compiler-parser`, `scala3-compiler-scanners`,
`scala3-indentation`, and `pldb-scala` in its registry.

## Provenance

canon used to vendor the grammars-v4 Scala 3 grammar and a port of its
`Scala3LexerBase` class. grammars-v4 has no single license: its house rules
leave each grammar to state its own, and the Scala 3 grammar, added in
[grammars-v4 pull request 4836](https://github.com/antlr/grammars-v4/pull/4836),
states none in its files, its readme, or the pull request. canon does not
vendor unlicensed code, so that grammar and the port are gone, and this grammar
and its hook were written for canon from the Scala reference and the Scala 3
compiler's sources, without reference to them. The
[grammars-v4 Scala directory](https://github.com/antlr/grammars-v4/tree/master/scala)
is listed in canon's registry as `grammars-v4-scala-page`, because the owner
allowed consulting it for structure; the grammar is not written from it. The
example files of its Scala 3 directory are used as test inputs only.

## Rules and the syntax summary

Each production the grammar reads has a rule of the same name, its EBNF quoted
above it: `compilationUnit`, `packageClause`, `topStat`, `semi`, `packaging`,
`packageObject`, `import_` and `export_` (Import and Export, whose names ANTLR
reserves), `importExpr`, `endMarker`, `endMarkerTag`, `templateBody`,
`selfType`, `templateStat`, `def_`, `annotation`, `modifier`, `localModifier`,
`accessModifier`, `accessQualifier`, `patDef`, `defDef`, `typeDef`, `tmplDef`,
`classDef`, `objectDef`, `enumDef`, `enumBody`, `enumStat`, `enumCase`,
`givenDef`, `givenSig`, `givenConditional`, `givenImpl`, `givenType`,
`oldGivenSig`, `withTemplateBody`, `extension`, `usingParamClause`,
`defTermParam`, `paramType`, `extMethods`, `extMethod`, `qualId`, `id`,
`expr1`, and `blockStat`. canon adds rules of its own, each said so where it
stands:

- `def_`'s alternatives are rules of their own, `valDefinition`,
  `varDefinition`, `defDefinition`, `typeDefinition`, and, under `tmplDef`,
  `classDefinition`, `caseClassDefinition`, `traitDefinition`,
  `objectDefinition`, `enumDefinition`, and `givenDefinition`, each holding
  `definitionPrefix`, the `{Annotation [nl]} {Modifier}` before it, so a
  definition's node starts at its first annotation and the Scaladoc comment
  above it belongs to it. `definitionName` is the name a definition declares,
  and `givenName` a given's.
- TopStats, TemplateStats, EnumStats, and Block are written out where they are
  enclosed, in `compilationUnit`, `packaging`, `templateBody`,
  `withTemplateBody`, `enumBody`, and `exprPart`, rather than as rules of their
  own: the parser keeps one tree for every end a rule reaches, and a rule
  holding a body's statements reaches one end per statement, which made a
  class of 3,500 methods take 24 seconds; written out, it takes 4.
- Expressions, types, patterns, parameter clauses, ClassConstr and
  InheritClauses (`templateHeader`), and a definition's signature and body are
  read structurally, as runs of tokens: `exprPart`, `headerPart`, `typePart`,
  `importPart`, `group`, `bracketGroup`, and `groupItem` keep brackets
  balanced and indented blocks whole without typing what is inside them. A
  statement that declares nothing is `expr1`, and so is a script's top-level
  code, which TopStat does not list.

Where the summary and the compiler differ, the grammar follows the compiler:

| Production | The syntax summary says | The compiler does | canon follows |
|---|---|---|---|
| ImportExpr, ImportSpec | `*` and `as` | also Scala 2's `_` wildcard and `=>` renaming, under `-source:3.0-migration` | the compiler; selectors are a run of tokens |
| VarDef | PatDef | also `var x: T = _`, deprecated | the compiler |
| AccessQualifier | `'[' id ']'` | also `[this]`, Scala 2's | the compiler |
| TopStat, TemplateStat | no end marker in TopStat's EBNF in Parsers.scala | `end` markers after any statement, `checkEndMarker` | an end marker is a statement |
| TemplateBody | `:<<< ... >>>` | a colon at the end of a line before `end` is an empty body (`newTemplateStart`) | an empty body |
| Extension | `'(' DefTermParam ')' {UsingParamClause} ExtMethods` | rejects a colon after the parameters ("no `:` expected here"); accepts `export` and end markers among the methods | the compiler; a colon makes the extension an expression |
| GivenDef | GivenDef | GivenDef and OldGivenDef, the syntax up to Scala 3.5 | both |
| TypeDef | `TypeBounds` | `TypeAndCtxBounds`, and capture sets under capture checking | a run of tokens |
| InheritClauses | `extends` and `derives` | also an experimental `uses` clause | a run of tokens |
| SimpleExpr | no XML | XML literals (`XMLSTART`), Scala 2's | XML literals |
| DefDef | `DefSig [':' Type] ['=' Expr]` | also Scala 2's procedure syntax `def f() { ... }`, rewritten under migration | procedure syntax |
| Literal | `symbolLiteral` | `'sym`, deprecated | symbol literals |
| (lexical) | `'''` is no literal | dedented string literals under `language.experimental.dedentedStringLiterals` | dedented strings |

## Scala 2

Most of the projects below are written in Scala 2, so the grammar reads the
Scala 2 forms the Scala 3 compiler still reads under `-source:3.0-migration`:
procedure syntax, `_` wildcard imports and `=>` renamings, `_` type arguments,
symbol literals, `implicit` classes, defs, vals, and parameters, existential
types with `forSome` (read inside a type's run of tokens), `private[this]`,
`<%` view bounds, old-style `if (...)`, `while (...)`, and `for (...)` without
`then` or `do`, template bodies in braces on the line below their class, and
XML literals. Not read: Scala 2 macro implementations' quasiquotes are read as
interpolated strings, which they lexically are, so nothing is lost; early
initializers, `class A extends { val x = 1 } with B`, are read as an
expression, so the class is missing from the model; and an XML literal whose
`<` does not follow whitespace or one of `{`, `(`, `>` is an operator, as it is
to the compiler.

## The lexer

The lexer reads every Scala token. A block comment nests. A string holds
escapes, a multi-line string runs to its first `"""` and takes any quotes after
it, and a dedented string runs from three or more single quotes and a line
break to the same quotes at the start of a later line. An interpolated string
is read in modes of its own, as the compiler reads it in a region of its own:
its text, `$$` and `$"` escapes, `$name` holes, and the Scala code of each `${`
hole, in which strings, braces, and character literals nest as anywhere else;
a raw backslash before a `$` is text. A character literal comes before a
symbol, so `'a'` is a character and `'a` a symbol. An XML literal starts at a
`<` that follows whitespace or one of `{`, `(`, `>` and comes before a name,
`!`, or `?`, which the hook answers as a predicate from the character before
it; its start tags, content, and nested elements are read in modes of their
own, and braces in them embed Scala code. A brace pushes the lexer's default
mode and its closing brace pops it, so code embedded in a string hole or an
XML literal returns to them. Soft keywords such as `end`, `extension`,
`using`, `inline`, and `opaque` are tokens of their own that `id` also reads
as names. Each loop takes one character per step, so lexing stays linear.

## Optional braces

Scala 3 ends a block where the indentation does, which no context-free grammar
sees. The lexer's `superClass` option, `ScalaLexerBase`, selects the
`Canon.Antlr4.Lex.Scala` hook in canon, which inserts layout tokens where the
compiler's scanner does, by its `handleNewLine`, its regions, and its token
sets, recorded as `DEC-scala-indentation`:

- The regions are the file's own, an indented region with its width and the
  token that opened it, braces, parentheses and brackets, interpolated
  strings, and XML literals. In braces the width is the first line's; in
  parentheses or brackets it is the line's after an opening bracket that ends
  its line, and the enclosing region's otherwise; inside a string or XML
  literal a line break means nothing.
- `NEWLINE` separates two lines where the region separates statements (the
  file, braces, or an indented region the line is not left of), the last
  token can end a statement (a name or operator, a literal, `this`, `super`,
  `return`, `type`, `given`, a closing bracket, an `OUTDENT`, or an end
  marker's tag), the next can start one and is no leading infix operator (an
  operator followed by whitespace, not after a blank line), and the line does
  not continue the last as an indented line starting with a bracket or after
  `return` does.
- Otherwise an `OUTDENT` closes each indented region the line is left of, or
  level with when the region holds the cases of a `match` or `catch` and the
  line starts with anything but `case`, unless the last token continues a
  statement (`then`, `else`, `do`, `catch`, `finally`, `yield`, `match`); and
  `INDENT` opens a region when the line is right of the width, or a `case` is
  level with a `match` or `catch`, and the last token may start one: `=`,
  `=>`, `?=>`, `<-`, `if`, `then`, `else`, `while`, `do`, `try`, `catch`,
  `finally`, `for`, `yield`, `match`, `throw`, `return`, `with`, a colon after
  a name, a closing bracket, `this`, `super`, or `new`, and the closing
  parenthesis of an old-style condition or an extension's parameters.
- A closing bracket or brace closes the indented regions opened inside it, a
  comma inside parentheses closes those opened since the parenthesis, and
  `else`, `then`, `do`, `yield`, `catch`, or `finally` in the middle of a line
  closes the region opened by the token it answers, as the compiler's parser
  asks its scanner for those `OUTDENT`s. A colon at the end of a line before
  an end marker gets a `NEWLINE`, as the compiler reads an empty body.
- The file's width is its first code token's column, and a line left of it
  narrows it, so a file indented as a whole reads as one that is not. Lines
  holding only comments are blank. Layout tokens are empty and sit where the
  last code token ends, so they widen no span.

Two of the compiler's rules are left out, since both depend on what its parser
is reading: an arrow after a self type opens no region (canon reads the self
type's arrow as any arrow, which matters only when the line after it is
indented further), and the parser's skipping of a `NEWLINE` before a `{` that
continues an argument list under Scala 2 migration.

## Coverage

`tools/corpus/scala.sh` clones each repository below at its commit, parses
every `.scala` file with the plain grammar or the dialect under a 30-second
limit, and prints the files parsed per repository. Files in the excluded
classes, listed in the script, are counted apart: negative tests and other
sources the compilers' and build tools' test suites keep because they do not
compile (`neg`, `neg-macros`, `untried/neg`, and the like; the Scala 3
parser's fuzzing inputs; its `pending` and `disabled` tests; fixtures of
parse, format, presentation-compiler, and incremental-compile errors, three
sbt scripted-test sources broken on purpose named one by one), one file
encoded in UTF-16, which canon does not read, and the Scala 3 test of
experimental dedented string literals, which nests them in each other's
holes.

Every file outside the excluded classes parses with the plain grammar and with
the dialect, 46,521 files in all; of the 8,031 excluded files, 7,803 parse too,
and the 228 that do not are code the compilers reject on purpose.

| Repository | Commit | Files | Parsed | Excluded (of which parse) | Dialect parsed |
|---|---|---|---|---|---|
| [scala/scala3](https://github.com/scala/scala3) | `39f42801b17a` | 13168 | 13168 (100%) | 5809 (5620) | 13168 |
| [scala/scala](https://github.com/scala/scala) | `8b318bf418a1` | 7366 | 7366 (100%) | 1988 (1962) | 7366 |
| [sbt/sbt](https://github.com/sbt/sbt) | `b7bba1147a29` | 1935 | 1935 (100%) | 220 (210) | 1935 |
| [com-lihaoyi/mill](https://github.com/com-lihaoyi/mill) | `b214318529f6` | 1521 | 1521 (100%) | 13 (10) | 1521 |
| [apache/spark](https://github.com/apache/spark) | `b93fb8d49959` | 6449 | 6449 (100%) | 0 (0) | 6449 |
| [apache/pekko](https://github.com/apache/pekko) | `ecd05d1d6409` | 2797 | 2797 (100%) | 0 (0) | 2797 |
| [playframework/playframework](https://github.com/playframework/playframework) | `069b71cd37eb` | 845 | 845 (100%) | 1 (1) | 845 |
| [apache/kafka](https://github.com/apache/kafka) | `c2fbf6f52f78` | 257 | 257 (100%) | 0 (0) | 257 |
| [twitter/finagle](https://github.com/twitter/finagle) | `ca472deb355c` | 1898 | 1898 (100%) | 0 (0) | 1898 |
| [linkerd/linkerd](https://github.com/linkerd/linkerd) | `ea82499d386e` | 744 | 744 (100%) | 0 (0) | 744 |
| [gatling/gatling](https://github.com/gatling/gatling) | `045b67dc7892` | 768 | 768 (100%) | 0 (0) | 768 |
| [lichess-org/lila](https://github.com/lichess-org/lila) | `1dc9cb2df29c` | 1569 | 1569 (100%) | 0 (0) | 1569 |
| [typelevel/cats](https://github.com/typelevel/cats) | `4a2ea736632c` | 835 | 835 (100%) | 0 (0) | 835 |
| [typelevel/cats-effect](https://github.com/typelevel/cats-effect) | `de84c01f76b2` | 457 | 457 (100%) | 0 (0) | 457 |
| [typelevel/fs2](https://github.com/typelevel/fs2) | `8aa47aba3845` | 457 | 457 (100%) | 0 (0) | 457 |
| [zio/zio](https://github.com/zio/zio) | `9005388637be` | 975 | 975 (100%) | 0 (0) | 975 |
| [http4s/http4s](https://github.com/http4s/http4s) | `f81cb4ac926f` | 667 | 667 (100%) | 0 (0) | 667 |
| [circe/circe](https://github.com/circe/circe) | `23a9bcd82d09` | 230 | 230 (100%) | 0 (0) | 230 |
| [scalaz/scalaz](https://github.com/scalaz/scalaz) | `9980ce1d41fa` | 569 | 569 (100%) | 0 (0) | 569 |
| [milessabin/shapeless](https://github.com/milessabin/shapeless) | `de22d6a0a698` | 171 | 171 (100%) | 0 (0) | 171 |
| [scalameta/scalameta](https://github.com/scalameta/scalameta) | `f31620cefa9a` | 695 | 695 (100%) | 0 (0) | 695 |
| [scalatest/scalatest](https://github.com/scalatest/scalatest) | `fe1d39319d50` | 1837 | 1837 (100%) | 0 (0) | 1837 |
| [slick/slick](https://github.com/slick/slick) | `24c2956f7da5` | 311 | 311 (100%) | 0 (0) | 311 |
| all | | 46521 | 46521 | 8031 (7803) | 46521 |

The grammar also parses all 12 files of the Iron sample, finding the units and
the 49 decisions it found before, all 45 example files of the grammars-v4
Scala 3 directory, and all 143 files of its `lila` example. Over a random
sample of 669 corpus files no definition is read as an expression and none is
swallowed into another's run of tokens.

Parsing is linear in the length of a file and failing files fail fast. Over
the 54,552 files, run ten at a time on a machine shared with other builds,
the median file took 0.10 seconds, the 90th percentile 0.25, the 99th 1.1, and
the 99.9th 3.7 with the plain grammar (4.4 with the dialect), and a failing
file at most 1.75. The slowest files are generated or stress-test sources of a
quarter to two thirds of a megabyte; measured alone, the slowest, Scala 3's
`tests/pos/jzon/SealedTrait.scala` (520 KB), takes 4.4 seconds of CPU with the
plain grammar, `KafkaApisTest.scala` (648 KB) 2.4, Scala 3's
`tests/pos/jzon/encoders.scala` (366 KB) 2.5, and `tests/pos/large.scala`
(237 KB) 2.0; with the dialect, ScalaTest's Scaladoc-heavy `Matchers.scala`
(350 KB) takes 5.5. Wall-clock times under load were up to five times those.

## Canonically commented dialect

`canonically_commented/ScalaLexer.g4` and `ScalaParser.g4` are the grammar
with Scaladoc comments as canonical comments, recorded as
`DEC-scala-dialect`. Each change is marked `// canon:`:

- `/**` opens a Scaladoc comment on the default channel, in the `DocBlock`
  mode, which tokenizes prose, `ref:KEY`, and `license:KEY` and drops the stars
  that decorate its lines. `/**/` and `/***` stay plain comments, and a
  comment nested in a plain one is part of it. `DOC_OPEN` comes before `OP`,
  which would otherwise take `/**`.
- The hook holds a Scaladoc comment's tokens until the next code token has
  produced its layout tokens and emits them just before it, so a line holding
  only a comment is blank to the layout, as it is to the compiler.
- `canonicalComment` and `docPart` are the comment rules.
- Each definition, package object, enum case, and extension is a labeled unit
  alternative whose `why` is the Scaladoc comment above its annotations and
  modifiers: `# val`, `# var`, `# def`, `# type`, `# class`, `# case_class`,
  `# object`, `# trait`, `# enum`, `# given`, `# case`, and `# extension`. A
  `val` or `var` that binds a pattern is no unit.
- A definition holds `publicByDefault`, an empty rule labeled `required`;
  `private`, `protected`, and `override` are labeled `optional`, which wins, so
  the dialect requires what the profile requires. An enum case is labeled
  `inherited`, and an extension's comment is optional, since its methods are
  definitions of their own.
- A Scaladoc comment after an annotation or a modifier, before a package
  clause, a packaging, an import, an export, an end marker, a self type, an
  expression statement, or a `val` that binds a pattern, inside an expression,
  a header, a type, or brackets, at the end of a body, or at the end of the
  file is an `orphan`. A declaration with one inside its header, as
  `def /** x */ f`, is read as an expression statement, so a misplaced
  Scaladoc comment never fails the parse.

The dialect parses the Iron sample, binding its 49 Scaladoc comments with no
orphan and finding what the profile finds; the 45 examples and 143 `lila`
files; the 57 sample and example files holding no multi-line string with a
doc comment inserted at the start of every line, after every opening
parenthesis and comma, and after every equals sign; and every corpus file the
plain grammar parses, no more and no fewer.

## Known limits

- A given's name, when it has none, is its type; when an anonymous given's
  body holds a named given, the profile, which looks for `givenName` anywhere
  in the definition, names the outer given by the inner one's name. The
  dialect names it by its type.
- An enum case listing several names, `case Green, Blue`, is one unit named by
  the first.
- An interpolated string, an XML literal, or a dedented string nested in a hole
  of a dedented string is not read; dedented strings are experimental.
- A declaration whose header holds a Scaladoc comment, or that is written in a
  layout the hook does not read, such as an early initializer, is read as an
  expression statement, so its units are missing from the model rather than
  the file failing.
