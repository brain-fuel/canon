# TypeScript grammar

## Authors

* Andrii Artiushok (2019) - initial version

## Description

This TypeScript grammar does not exactly correspond to the TypeScript standard.
The main goal during developing was practical usage, performance, and clarity
(getting rid of duplicates).

The syntax is based on [JavaScript grammar](https://github.com/loonydev/grammars-v4/tree/master/javascript)
by [Positive Technologies](https://github.com/PositiveTechnologies).

## Reference

* [pldb](http://pldb.info/concepts/typescript)
* https://www.typescriptlang.org/
* https://github.com/Microsoft/TypeScript/blob/730f18955dc17068be33691f0fb0e0285ebbf9f5/doc/spec.md -- the abandoned specification.

## License

[MIT](https://opensource.org/licenses/MIT)

## Issues

* The grammar is very old and there are many ambiguities: primaryType Decision 11; singleExpression Decision 236; etc.

## Canonically commented dialect

`canonically_commented/TypeScriptLexer.g4` and `TypeScriptParser.g4` are the
grammar above with TSDoc comments as canonical comments, recorded as
`DEC-typescript-dialect`. The lexer is changed as the JavaScript dialect's is,
described in `grammars/javascript/README.md`, a `@type` or `@satisfies` cast
hidden as there, and adds a hashbang line, which the plain grammar lacks, and
the `AfterModule` and `ModuleName` modes, which read the quoted name after
`module` as `MODULE_QUOTE`, `MODULE_NAME`, and `MODULE_QUOTE`. The parser is
changed as follows, each change marked `// canon:`:

- `canonicalComment`, `fileComment`, `taggedFileComment`, and `docPart` are
  the comment rules; `program` makes a file's first doc comment, below a
  hashbang line if there is one, its Why when it holds a file tag such as
  `@packageDocumentation`, or a blank line or an import follows it.
  `moduleItem` and `declaredVariable` read a statement at the top of a module
  or namespace, where a variable statement is a unit.
- Functions, classes, interfaces, type aliases, enums, enum members,
  namespaces, ambient modules, module-level bindings, `export default`,
  constructors, class properties, methods, accessors, abstract members, and
  index signatures, and the members of an object type are labeled unit
  alternatives: `# function`, `# class`, `# interface`, `# type`, `# enum`,
  `# member`, `# namespace`, `# module`, `# variable`, `# export`,
  `# constructor`, `# property`, `# method`, `# accessor`, `# index`,
  `# call`, and `# new`. A call, construct, or index signature is named by
  its position through `ordinal`, an accessor by `get` or `set` and its
  property, through `classGetAccessor` and `classSetAccessor`, and an ambient
  module by its name without quotes, `declare module 'foo'` as `module/foo`.
  Decorators follow a member's doc comment.
- The signature of a function, a method, a constructor, and an interface's
  method is labeled `merge`, so overload signatures and their implementation
  are one unit whose Why is the first doc comment, as TSDoc shows it; a later
  signature with a doc comment of its own starts a unit of its own.
- An object literal that an exported binding, with `as const` or `satisfies`
  after it or not, or `export default` holds directly is a `memberObject`,
  whose properties, methods, and accessors are units as in the JavaScript
  dialect.
- `export` is part of the declaration it exports and is labeled `required`.
  An interface's body, an enum's body, a class's tail, an exported object
  literal, and the whole right side of a type alias are labeled `inherited`,
  so the members of an object type in a union or an intersection require a
  comment as an object type alone does; `private`, `protected`, and a
  `#private` name are labeled `optional`.
- A doc comment above a local binding, after the last statement or member of
  a body or file, after `import`, after `export default`, before `[` in an
  array or indexed type, before a case, before a mapped type's member, or
  before a property or a method of an object literal that `propertyAhead` or
  `methodAhead` sees, as in the JavaScript dialect, is an `orphan` the grammar reads. Anywhere else the
  grammar does not take one, as above another statement, inside an
  expression, before an argument or a parameter, or inside a type, the
  parser's `strayComment` option reads the file without it and reports it as
  an orphan (`DEC-stray-comments`). A named function expression is an
  expression and no unit.
- `import type`, `export type`, and an inline `type` modifier in an import or
  export list are read, which the plain grammar reads as an expression, and a
  template literal type, as `` `pre-${string}` ``, is a primary type.
- `TypeScriptParserBase`'s predicates are answered by the hook the JavaScript
  dialect describes, line terminators included, for the plain grammar too.

Known limitations:

- A destructuring statement at the top of a module is one unit named by its
  pattern, as in JavaScript.
- Two object types in a union with a member of one name give units `kind`
  and `kind#2`.
- `strayComment` finds a stray doc comment where the parse fails at it or a
  few tokens after it. The grammar reads keywords as names and gives most
  declarations an optional Why, so a path can take a stray comment and fail
  further on; the grammar adds orphan slots where a fuzz that put a doc
  comment before every token of a broad TypeScript file and of ky's sources
  found that, and that fuzz now finds no position where the parse fails but
  inside a token or where the code itself no longer parses, as an indexed
  type `T[K]` with a line break before `[`.

## JSX, .tsx, and Flow

TypeScript reads JSX in a `.tsx` file and not in a `.ts` file, where `<T>x` is a
type assertion, and tells the two by the file's extension; a lexer cannot see
the extension, so `TypeScriptJsxLexer.g4`, beside `TypeScriptLexer.g4` in both
the plain grammar's directory and the dialect's, imports its rules under the
base class `TypeScriptJsxLexerBase`, whose hook reads JSX, and a profile names
that lexer for `.tsx` files under a language of its own, `tsx`, whose units are
tests by where they live as TypeScript's are. Both lexers share the parser.
This is recorded as `DEC-javascript-jsx`, and JSX itself is read as the
JavaScript grammar reads it, described in `grammars/javascript/README.md`. In a
`.tsx` file:

- A `<` before a type parameter list, `<T,>`, `<T extends U>`, `<T = U>`, or
  `<const T,>`, is no tag, and nor is a `<` before `Name>(` after a colon or an
  arrow or on the right of a type alias, which opens a generic function type, as
  TypeScript reads both; the lexer matches the list's opening as one token,
  `JsxTypeParameters` or `JsxFunctionTypeParameters`, and the hook splits it
  into the tokens TypeScript's scanner reads.
- A tag's type arguments, as `<Select<number> />`, are read in the default mode
  between `JsxTypeArgumentsOpen` and `JsxTypeArgumentsClose`, the `>` at their
  depth, which the hook counts.

Flow is not TypeScript, but its types are close enough that the `.tsx` pair
reads them, and a Flow project's profile names it for its `.js` files: the
parser adds Flow's maybe types `?T`, exact objects `{| |}`, spread and inexact
object types, variance `+x` and `-x` on properties, members, and type
parameters, bounded type parameters `<T: U>`, unnamed and unparenthesised
function type parameters, `T => U`, the existential type `*`, empty type
arguments `T<>`, casts `(x: T)`, `opaque type` and `declare opaque type` with a
supertype, `import typeof`, `component(...)` types, inline interface types,
`implies` predicates, and optional parameters with defaults. Each change is
marked `// canon:`. A line break ends a class property and an overload
signature, as in a file written without semicolons.

## Corpus

`tools/corpus/typescript.sh` checks the grammar against the TypeScript
compiler, four of the most used TypeScript code bases, and three written with
JSX. It shallow-clones each repository below at the pinned commit into
`/tmp/corpus/typescript`, or the directory given as its first argument, parses
every `.ts`, `.mts`, `.cts`, and `.tsx` file with the plain grammar, a `.tsx`
file through `TypeScriptJsxLexer.g4`, under a timeout of 300 seconds per file,
and then parses every file the plain grammar parsed with the dialect, which
must parse them all. Large repositories are sampled by subdirectory with a
sparse checkout. A file that fails is a deliberate exclusion only when the
TypeScript compiler's own parser rejects it, a `TS1xxx` error from `tsc`;
none does. The script runs in a process group of its own, through
`tools/corpus/process-group.sh`, and shares `tools/corpus/jsts-common.sh` with
its JavaScript twin.

| Repository | Commit | Sampled | Kind | Files | Parsed | Excluded | Seconds |
|------------|--------|---------|------|------:|-------:|---------:|--------:|
| [microsoft/TypeScript](https://github.com/microsoft/TypeScript) | `050880ce59e3` (v6.0.3) | `/src/` | TS | 709 | 709 | 0 | 251.2 |
| [microsoft/vscode](https://github.com/microsoft/vscode) | `729f257fa411` | `/src/vs/base/common/`, `/src/vs/editor/common/` | TS | 383 | 383 | 0 | 80.6 |
| [angular/angular](https://github.com/angular/angular) | `7d96a37af4f7` | `/packages/core/src/`, `/packages/common/src/`, `/packages/router/src/` | TS | 525 | 525 | 0 | 68.4 |
| [nestjs/nest](https://github.com/nestjs/nest) | `35142c3eca8e` | `/packages/` | TS | 975 | 975 | 0 | 127.3 |
| [denoland/std](https://github.com/denoland/std) | `f834d0223364` | all | TS | 1179 | 1179 | 0 | 173.3 |
| [shadcn-ui/ui](https://github.com/shadcn-ui/ui) | `0e3abd65a977` | `/apps/` | TSX | 3246 | 3246 | 0 | 353.1 |
| | | | TS | 172 | 172 | 0 | 23.7 |
| [vercel/next.js](https://github.com/vercel/next.js) | `263f6820b21d` | `/packages/next/src/client/` | TSX | 47 | 47 | 0 | 6.0 |
| | | | TS | 161 | 161 | 0 | 18.4 |
| [mui/material-ui](https://github.com/mui/material-ui) | `daaa525c3af0` | `/packages/mui-material/src/` | TSX | 130 | 130 | 0 | 14.0 |
| | | | TS | 615 | 615 | 0 | 57.6 |
| Total | | | | 8142 | 8142 | 0 | 1173.5 |

Every one of the 8,142 files, 3,423 of them `.tsx` and 4,719 `.ts`, about 55
MB and 1.5 million lines, parses with the plain grammar and with the dialect.
The TypeScript repository's default branch now holds the compiler's Go port,
so the corpus pins the last release written in TypeScript, 6.0.3; its
`tests/cases`, which hold invalid code on purpose, are not sampled. The seconds
are the sum of each file's wall time, the `canon` process included, with 10
files parsed at once. A file takes 0.09 seconds at the median, 0.20 at the
90th percentile, 0.86 at the 99th, and at most 23, `src/compiler/checker.ts`,
3.1 MB and 53,000 lines; through the dialect it takes 68 seconds, since its doc
comments inside function bodies are stray comments read again without them.
The slowest `.tsx` file is shadcn-ui's generated registry index,
`apps/v4/registry/__index__.tsx`, at 9.4 seconds. Files that failed before the
fixes below failed within a few seconds, except those that the identifier fix
below made fast.

The corpus found these gaps, now fixed in the plain grammar and the dialect:

- Exponential lexing of an identifier with many underscores, since `_` was
  both an identifier start and a connector punctuation, `\p{Pc}`; the two
  alternatives no longer overlap. A 30-line file of the compiler took over
  120 seconds before and takes 0.1 now.
- A trailing comma and `const`, `in`, and `out` in a type parameter list.
- Definite assignment, `let x!: T` and `x!: T`, and `override` on a parameter
  property.
- Member modifiers in any order, with `declare`, `abstract`, `override`, and
  `accessor`; generator, async generator, and optional methods; accessors
  without a body, as in an abstract class or an interface; and `extends`
  followed by any expression, as `extends mixin(A, B)`.
- Named, optional, and rest tuple elements and the empty tuple; abstract
  constructor types; `asserts x`, `asserts x is T`, `this is T`, and any type
  after `is`; `infer U extends C`; numeric and negative literal types; import
  types, `import("m").T` and `typeof import("m")`; template literal types with
  `infer` holes; any type as an index, as `T[K extends X ? A : B]`; and index
  signatures keyed by any type, `readonly` ones included.
- `satisfies`, generic arrow functions, typed methods of an object literal,
  `@Decorator<T>(...)`, a line break separating the members of an object type,
  `module`, `declare`, `is`, `infer`, and `require` as names, and a hashbang
  line.
- In the lexer hook, a template literal inside a block inside a template
  expression, whose closing brace the TypeScript form of the hook took for the
  end of the outer expression.
- A class property and an overload signature that a line break ends, as
  Next.js, written without semicolons, writes them.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/typescript.sh                      # clones into /tmp/corpus/typescript
CORPUS_SKIP_FETCH=1 tools/corpus/typescript.sh  # reuses the clones
```
