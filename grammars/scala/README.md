# Scala 3 Grammar

## Source
EBNF adapted from https://docs.scala-lang.org/scala3/reference/syntax.html (read May 6, 2026).
NB: https://scala-lang.org/files/archive/spec/3.4/13-syntax-summary.html seems incomplete (e.g., Import).
So, I decided to not use that, but the "docs" version instead. Note, the "docs" grammar
contains several problems with newlines, semicolons, and statements. I tried to mirror what
the Dotty compiler does rather than assume blind allegiance to a human-scraped EBNF.

## Options

The lexer and parser base classes recognise the following command-line option:

| Option | Description |
|--------|-------------|
| `--3.0-migration` | Enable Scala 2-compatible syntax accepted by the Scala 3 compiler under `-source:3.0-migration`. Currently enables: `._` wildcard import selectors (e.g. `import scala.jdk.CollectionConverters._`) and `_` as a wildcard type argument (e.g. `Seq[_]`). Without this flag these constructs are rejected; the Scala 3 equivalents are `.*` and `?` respectively. |

## Reference
* [pldb](http://pldb.info/concepts/scala)
* Dotty compiler parser: https://github.com/scala/scala3/blob/main/compiler/src/dotty/tools/dotc/parsing/Parsers.scala
* Playground: https://onecompiler.com/scala
* Playground: https://www.tutorialspoint.com/compilers/online-scala-compiler.htm

## Parser Rule Coverage

The grammar is tested using the Trash Toolkit `trcover` tool, which instruments the
ANTLR4 parser grammar and tracks which rule call sites are exercised by the example
inputs in `examples/`. Coverage is reported as the number of rule call sites (references
from one parser rule to another) that were reached during parsing.

To regenerate coverage after adding or modifying example files:

```sh
cd Generated-CSharp
dotnet trash cover ../examples/*.scala
```

This writes `cover.html`, an annotated copy of the grammar where covered call sites are
highlighted. Call sites with no highlighting were not reached by any example.

### Current coverage

**750 of 763 rule call sites covered (98.3%)**

The 13 uncovered call sites fall on 8 grammar alternative lines, all of which are
permanently unreachable with this grammar and parser.  (Multiple rule references on a
single alternative line each count as a separate call site, hence 13 sites on 8 lines.)

| Grammar location | Reason unreachable |
|---|---|
| `funParamClause` / `typedFunParam` (L165, L169, L173 — 4 call sites) | `simpleType_: LPAREN nameAndType RPAREN` absorbs `(x: Int)` before `funParamClause` is considered in `funTypeArgs`; ANTLR always takes the `infixType` alternative first |
| `INLINE infixExpr matchClause` in `expr1` (L309 — 2 call sites) | `postfixExpr ascription?` (L308) appears earlier and consumes `inline` as a plain identifier; the remaining `x match { … }` is then parsed as a separate statement |
| `LPAREN namedExprInParens … RPAREN` / `namedExprInParens` in `simpleExpr` (L356, L383 — 3 call sites) | `LPAREN exprsInParens RPAREN` appears earlier in `simpleExpr` and always wins; named arguments (`f(x = 1)`) are absorbed by `exprsInParens` via `expr1: id ASSIGN expr` |
| Varargs `LPAREN … postfixExpr Op RPAREN` in `parArgumentExprs` (L390 — 2 call sites) | `LPAREN exprsInParens RPAREN` wins first; `args*` is parsed as a postfix expression inside `exprsInParens` |
| `defSig (COLON type_)?` (abstract declaration) in `defDef` (L704 — 2 call sites) | This alternative **is** executed for abstract method declarations, but the coverage tool cannot track it independently: all three `defDef` alternatives that start with `defSig (COLON type_)?` share the same ATN prefix, so hits are attributed to the first alternative |

### Known grammar limitations

The following are deliberate simplifications that keep the grammar self-contained and
easy to maintain.  Each accepts a slightly broader set of inputs than strict Scala 3
syntax requires.

**`importSelectors` — mixed named/wildcard import lists not supported**

```antlr
importSelectors
    : namedSelector (COMMA importSelectors)?
    | wildCardSelector (COMMA wildCardSelector)*
    ;
```

Valid Scala 3 allows mixing named selectors and wildcards in one import, e.g.
`import foo.{bar, given, *}`.  The rule above only accepts a list of `namedSelector`s
*or* a list of `wildCardSelector`s, not both together.  This covers the common cases
without the added complexity of a fully mixed rule.

**`wildCardSelector`, `negation`, and `variance` — `Op` used for single-character operators**

The lexer has no dedicated tokens for the individual characters `*`, `+`, and `-`;
all contiguous operator characters are emitted as a single `Op` token.  Three grammar
rules therefore use `Op` where only one specific character is valid:

| Rule | Intended operator | Also accepted (over-broadly) |
|---|---|---|
| `wildCardSelector : Op` | `*` import wildcard | any operator sequence |
| `negation : Op` | `-` before a numeric literal | any operator sequence |
| `variance : Op` | `+` or `-` type-parameter variance | any operator sequence |

Adding dedicated single-character lexer tokens (e.g. `STAR`, `MINUS`, `PLUS`) would
require fragmented operator lexing throughout the grammar and is not warranted for a
reference grammar.  The comment on each rule documents the intended restriction.


## Provenance in canon

`Scala3Lexer.g4` and `Scala3Parser.g4` are from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/7df52be94698550d219d299d04105c6bafadd9c3/scala/scala3)
at commit `7df52be94698550d219d299d04105c6bafadd9c3`. The README above is
upstream's. Neither grammar file carries a license header, and grammars-v4 has
no single license for its grammars; canon vendors them as it vendors the other
grammars-v4 grammars, with that commit recorded. grammars-v4 also has a Scala 2
grammar, `scala/scala2/Scala.g4`; canon reads Scala 3, which current Scala
projects are written in and whose compiler still accepts most Scala 2 syntax,
as recorded in `DEC-scala-grammar` in canon's `canonical_decisions.yaml`.

The `Scala3LexerBase` class is ported as the lexer hook
`src/Canon/Antlr4/Lex/Scala.hs`, which the grammar's `superClass` selects. It
turns optional braces into `INDENT`, `DEDENT`, and statement-separating
`NEWLINE` tokens as the Java class does, recorded as `DEC-scala-indentation`,
with three differences: every layout token is empty and placed where the last
code token ends, the source's own line breaks staying hidden; a comma or a
closing bracket closes only the indented blocks opened inside its brackets, so
an indented enum body survives `case A, B`; and the file's own indentation is
its first code token's column, so a file indented as a whole reads as one
that is not. `Scala3ParserBase`'s one predicate,
`migration30`, holds, since the Scala 3 compiler accepts the Scala 2 wildcards
it gates.

Every change to the grammar is marked `// canon:`:

- The interpolated string fragments match one character per iteration instead
  of a run inside a starred loop, which made lexing exponential.
- A character literal may hold any character and a Unicode escape, as
  `'\u000B'` and `'é'`.
- Each kind of definition, `val`, `var`, `def`, `type`, `class`, `case class`,
  `object`, `trait`, `enum`, and `given`, is a rule of its own whose node starts
  at the definition's first annotation or modifier, under `definition` in
  templates and at the top level, so the Scaladoc comment above the
  annotations binds to it. Local definitions in blocks keep upstream's
  `def_` and are not units. An annotation may stand on a line of its own.
- Each annotation of a definition is labeled `marker`, and `private`,
  `protected`, and `override` are labeled `optional`: Scaladoc documents public
  members, and an override inherits the documentation of what it overrides.
- An enum case carries its annotations and modifiers and is labeled
  `inherited`, so it needs a comment when its enum does.
- `definitionName` is the name a definition declares and `givenName` a named
  given's, so a unit is named by it rather than by an identifier in its
  annotations; an anonymous given is named by its `givenType`, which replaces
  the type in `oldGivenDef` and `structuralInstance`.
- A type alias's right-hand side, and a match type case's, may be an indented
  block on the next line.

The grammar parses all 45 files of upstream's `examples/` and the 143 files of
`examples/lila/`, and the 32 files of Iron 3.3.2's core module and its tests.

## Canonically commented dialect

`canonically_commented/Scala3Lexer.g4` and `Scala3Parser.g4` are the grammar
above with Scaladoc comments as canonical comments, recorded as
`DEC-scala-dialect`. Each change is marked `// canon:`:

- `/**` opens a Scaladoc comment on the default channel, in the `DocBlock`
  mode, which tokenizes prose, `ref:KEY`, and `license:KEY` and drops the stars
  that decorate its lines. `/**/` and `/***` stay plain comments, and a
  comment nested in a plain one is part of it. `DOC_OPEN` comes before `Op`,
  which would otherwise take `/**`.
- The hook holds a Scaladoc comment's tokens until the next code token has
  produced its layout tokens and emits them just before it, so a line holding
  only a comment is blank to the layout, as it is to the compiler.
- `canonicalComment` and `docPart` are the comment rules.
- Each definition, package object, enum case, and extension is a labeled unit
  alternative whose `why` is the Scaladoc comment above its annotations and
  modifiers: `# val`, `# var`, `# def`, `# type`, `# class`, `# case_class`,
  `# object`, `# trait`, `# enum`, `# given`, `# case`, and `# extension`. An
  auxiliary constructor is named `this`, and an extension by the type it
  extends.
- A definition holds `publicByDefault`, an empty rule labeled `required`;
  `private`, `protected`, and `override` are labeled `optional`, which wins, so
  the dialect requires what the profile requires. An extension's comment is
  optional, since its methods are definitions of their own.
- A Scaladoc comment after an annotation or a modifier, before a package
  clause, an import, an export, an end marker, or an expression statement,
  before a local definition, a case clause, an argument, or a parameter, at
  the end of a body, or at the end of the file is an `orphan`.

## Known limits

- A Scaladoc comment elsewhere inside an expression or a type, as between
  the operands of an infix expression, is not accepted, and the file fails to
  parse. The comment documents nothing there, and none of the sources above
  has one.
- A `val` that binds a pattern, as `val (a, b) = pair`, has no name and is no
  unit.
