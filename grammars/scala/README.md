# Scala Grammar

`ScalaLexer.g4` and `ScalaParser.g4` are written for canon, under canon's MIT
license, from the [Scala 3 syntax summary](https://docs.scala-lang.org/scala3/reference/syntax.html)
and the reference's [Optional Braces](https://docs.scala-lang.org/scala3/reference/other-new-features/indentation.html)
section. They are recorded as `DEC-scala-grammar` in canon's
`canonical_decisions.yaml`.

## Provenance

canon used to vendor the grammars-v4 Scala 3 grammar and a port of its
`Scala3LexerBase` class. grammars-v4 has no single license: its house rules
leave each grammar to state its own, and the Scala 3 grammar, added in
[grammars-v4 pull request 4836](https://github.com/antlr/grammars-v4/pull/4836),
states none in its files, its readme, or the pull request. canon does not
vendor unlicensed code, so that grammar and the port are gone, and this grammar
and its lexer hook were written for canon from the Scala reference alone,
without reference to them. The example files of the grammars-v4 Scala 3
directory were used only as test inputs.

## What it reads

The grammar reads what extraction needs: the declarations that carry
documentation, and where each one ends. It parses package clauses, packagings
in braces or after a colon, package objects, imports, exports, objects and
case objects, classes, case classes, traits, enums and their cases, `def`s
(auxiliary constructors included), `val`s, `var`s, type aliases and abstract,
opaque, and match types, givens in the current and the older syntax,
extensions, self types, and end markers, with their annotations and modifiers,
in braces or with optional braces. Bodies, expressions, types, and patterns
are runs of tokens: the grammar does not type them or give them precedence, it
only keeps them inside the declaration they belong to, by bracket nesting and
by the layout tokens below. A statement it cannot read as a declaration is
read as an expression with the blocks indented below it, as a script's
top-level code is, and definitions inside a block, such as the locals of a
`def`, are part of the block's run of tokens.

The lexer reads every Scala token, so comments (nested block comments
included), strings (plain, multi-line, and interpolated, holes and all, as one
token each), character literals with escapes, symbols, and backquoted names
never hide code or fake it. Each loop in the lexer takes one character per
step, so lexing stays linear. Soft keywords such as `end`, `extension`,
`using`, `inline`, and `opaque` are tokens of their own that the parser also
reads as names.

Three labels serve canon: `marker` on each annotation, so a JUnit test is told
by its `@Test`; `optional` on `private`, `protected`, qualified or not, and
`override`, since Scaladoc documents public members and an override inherits
the documentation of what it overrides; and `inherited` on enum cases, which
need a comment when their enum does. A definition is named by
`definitionName`, an auxiliary constructor by `this`, a given by `givenName`
or else by `givenType`, the type it provides, and an extension by
`extendedType`, the type it extends.

## Optional braces

Scala 3 ends a block where the indentation does, which no context-free
grammar sees. The lexer's `superClass` option, `ScalaLexerBase`, selects the
`Canon.Antlr4.Lex.Scala` hook in canon, written from the reference's rules and
modelled on the F# hook, recorded as `DEC-scala-indentation`:

- The file and each pair of braces is a region with the width of its first
  line, in which statements are separated and indented. Inside parentheses and
  brackets line breaks are not significant and no layout token is emitted.
- At a line right of the current width, `INDENT` opens an indented region when
  the last token may start one: `=`, `=>`, `?=>`, `<-`, `catch`, `do`, `else`,
  `finally`, `for`, `if`, `match`, `return`, `then`, `throw`, `try`, `while`,
  `yield`, `with`, `:`, the closing parenthesis of an old-style condition, or
  an extension's parameters. After any other token the line continues the one
  above.
- An `OUTDENT` closes each indented region a line is left of, and a closing
  bracket or brace closes those opened inside it.
- `NEWLINE` separates two lines level with each other when the first can end
  a statement and the second can begin one, so a line starting with `.`,
  `then`, `else`, `extends`, `with`, or an infix operator continues the line
  above; and it follows an `OUTDENT` unless the next token cannot begin a
  statement.
- A `case` level with a `match` or `catch` opens a region of case clauses,
  closed by the first other token at that width.
- The file's width is its first code token's column, so a file indented as a
  whole reads as one that is not. Lines holding only comments are blank.
- Layout tokens are empty and sit where the last code token ends, so they
  widen no span.

## Coverage

The grammar parses all 12 files of the Iron sample, finding the units and the
49 decisions it found before; all 45 example files of the grammars-v4 Scala 3
directory; and all 143 files of its `lila` example; and reads no declaration
in them as an expression.

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
orphan and finding what the profile finds, the 45 examples and 143 `lila`
files, and the 57 of those files holding no multi-line string with a doc
comment inserted at the start of every line, after every opening parenthesis
and comma, and after every equals sign.

## Known limits

- Scala 2 XML literals are not read; a `<` starts an operator.
- Inside a `${ }` hole of an interpolated string, braces and strings nest, but
  a character literal holding a brace or a double quote, as `'}'`, ends or
  opens them too soon. No source at hand has one.
- The hook does not insert the `OUTDENT` the reference adds before a token
  such as `else` that closes an indented region on the line it opened on, nor
  the one before a comma inside parentheses; the runs of tokens read such lines
  either way, since no declaration that carries documentation lives there.
- A declaration whose header holds a Scaladoc comment, or that is written in a
  layout the hook does not read, is read as an expression statement, so its
  units are missing from the model rather than the file failing.
