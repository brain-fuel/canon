# JavaScript Grammar

This JavaScript grammar does not exactly corresponds to ECMAScript standard.
The main goal during developing was practical usage, performance and clarity
(getting rid of duplicates).

# Status

This grammar works the following targets: C# (CSharp = Antlr4.Runtime.Standard)
and Java.
It works for the JavaScript target, but requires a fix in Antlr
post version 4.9.1.

## Universal Actions & Semantic Predicates

Some modern JavaScript syntax cannot be handled with standard context-free
grammars, for example detection of `get` keyword in getters and `get` identifiers
in other cases. Moreover, some parser options can be defined externally (`use strict`)
and should be considered during parsing process.

For such complex syntax [actions](https://github.com/antlr/antlr4/blob/master/doc/actions.md)
and [predicates](https://github.com/antlr/antlr4/blob/master/doc/predicates.md)
are used. This is a first grammar in repository with attempt to use an **universal**
actions and predicates.

## Syntax support

### ECMAScript 6

Grammar supports the following list of ECMAScript 6 features taken from
<http://es6-features.org>:

* Arrow Functions
* Classes
* Constants
* Destructuring Assignment
* Enhanced Object Properties
* Enhanced Regular Expression
* Extended Literals
* Extended Parameter Handling
* Generators
* Internationalization & Localization
* Iterators
* Map/Set& WeakMap/WeakSet
* Meta-Programming
* Modules
* New Built-In Methods
* Promises
* Scoping
* Strict Functions
* Strict Global
* Symbol Type
* Template Literals
* Typed Arrays

See [examples](examples) directory with test data files.

### ES6 to ES2020

* HashBang Comment
* `**` and `**=`
* Numeric Literal Separator (`1_23`)
* BigInt (`123456n`)
* Async Await 
* Async Iteration (`for await`)
* Dynamic Import (`import()`)
* Private Field (`#field`)
* Null Coalesce (`a??b`)
* Optional Chain (`a?.b`)
* Calculated Property (`[name]:value`)

### Outdated

Also this grammar supports outdated syntax such as

* Html Comment
* CData section

## Main contributors

* Bart Kiers (2014) - initial version
* Ivan Kochurkin (2017, Positive Technologies):
  * Updated for EcmaScript 6 support
  * Cleared & optimized
  * Universal code actions & predicates
  * Support of some outdated syntax (Html comment, CData)
* Student Main (2019):
  * Update to ES2020

## Running fuzz test

1. You need recent Node.js
2. `npm i -g eslump`
3. `generate.bat` (For linux: manually run them....)
4. `fuzztest.bat` (Or: `eslump wrapper.js gen/`)
5. Ctrl-C to stop

Error will show in terminal, correspond code located in `gen/temp.js`

## Reference
* [pldb](http://pldb.info/concepts/javascript)


## License

[MIT](https://opensource.org/licenses/MIT)

## Canonically commented dialect

`canonically_commented/JavaScriptLexer.g4` and `JavaScriptParser.g4` are the
grammar above with JSDoc comments as canonical comments, recorded as
`DEC-javascript-dialect`. Each change is marked `// canon:`:

- `/**` opens a doc comment on the default channel, in the `DocBlock` mode,
  which tokenizes prose, `ref:KEY`, and `license:KEY`, drops the stars that
  decorate a line, and reads a block tag such as `@param` as a word. A plain
  comment may not start with two stars, so `/**/` and `/***` stay plain by
  the longest match.
- The first `/**` of a file, before any code but a hashbang line, opens
  `FILE_DOC_OPEN` through the base lexer's `IsStartOfFile` predicate, in the
  `FileDocBlock` mode, which reads `@file`, `@fileoverview`, `@overview`,
  `@module`, `@license`, and `@packageDocumentation` as `DOC_FILE_TAG`; the
  `FileDocAfter` mode marks a blank line below it with `DOC_BLANK_LINE`.
  `program` makes it the file's Why when it holds a file tag or a blank line
  or an import follows it, and otherwise it documents the declaration below.
- The lexer hook, `Canon.Antlr4.Lex.JavaScript`, hides a doc comment whose
  first word is `@type` or `@satisfies`: it is a type cast or a type
  annotation, which TypeScript's checker reads as a type, not documentation,
  so it is neither a Why nor an orphan wherever it stands, above a local
  binding included.
- `canonicalComment`, `fileComment`, `taggedFileComment`, and `docPart` are
  the comment rules, and `moduleItem` reads a statement at the top of a
  module, where a variable statement is a unit.
- A function declaration wherever it stands, a class declaration, each method,
  accessor, and field of a class, a module-level `var`, `let`, or `const`
  statement, and `export default` are labeled unit alternatives: `# function`,
  `# class`, `# method`, `# accessor`, `# field`, `# variable`, and
  `# export`. An accessor is named by `get` or `set` and its property, a
  variable statement by its first binding, and `export default` by `default`.
  Of several doc comments in a row the last binds.
- An object literal that an exported binding or `export default` holds
  directly is a `memberObject`: its properties, methods, and accessors are
  units, `# property`, `# method`, and `# accessor`, and a property whose
  value is such an object literal holds units of its own. It is labeled
  `inherited`, so what the module exports requires a comment down to these
  members. The properties of any other object literal are no units.
- `export` is part of the declaration it exports and is labeled `required`; a
  class's tail is labeled `inherited`, and a `#private` name `optional`.
- A doc comment after the last statement or member of a body or file, before
  or after the last property of an object literal, before a case, or before a
  list of exports, is an `orphan` the grammar reads; before a property it is
  read only when the predicate `propertyAhead`, which canon's parser hook
  answers, sees a name and a colon after it, so a path that reads a block's
  braces as an object literal does not take it; before a method of an object
  literal it is read when `methodAhead` sees a name, a parenthesised list, and
  a brace or a colon after it. One above a local binding or
  an expression statement, as JSDoc writes above `this.x = x`, is an orphan
  the grammar reads too, since both are common. Anywhere else the grammar
  does not take one, as above another statement, inside an expression, before
  an argument, or before a parameter, the parser's `strayComment` option reads
  the file without it and reports it as an orphan (`DEC-stray-comments`). A named function expression
  is an expression and no unit, and `exportStatement` keeps only lists of
  exports and `export default`.
- `JavaScriptParserBase`'s predicates are answered by canon's parser hook:
  `n` and `p` compare the next or previous token's text, and
  `lineTerminatorAhead`, `notLineTerminator`, `closeBrace`, and
  `notOpenBraceAndNotFunction` compare the lines of the code tokens on either
  side, so a statement without a semicolon ends at a line break, as automatic
  semicolon insertion ends it, in the plain grammar and in the dialect.

Known limitations:

- A destructuring statement at the top of a module, as
  `export const {a, b} = o`, is one unit named by its pattern, `{a,b}`,
  because its one comment documents all its bindings together.
- `strayComment` finds a stray doc comment where the parse fails at it or a
  few tokens after it; a fuzz that put a doc comment before every token of a
  broad JavaScript file, and of the chalk sample's sources, on the line of the
  code and on a line of its own, found no position where the parse fails but
  inside a token or where the code itself no longer parses, as `throw` with a
  line break after it.

## JSX

canon reads JSX, recorded as `DEC-javascript-jsx`, in the plain grammar and the
dialect, in `.js`, `.jsx`, `.mjs`, and `.cjs` files, as Babel and every React
toolchain read it. Each change is marked `// canon:`:

- The lexer decides whether a `<` opens a JSX tag from the token before it, as
  TypeScript's scanner does: where an expression may start, after no token,
  an operator, punctuation, or one of the keywords an expression follows
  (`return`, `typeof`, `void`, `delete`, `await`, `yield`, `case`, `do`,
  `else`, `in`, `of`, `throw`, `default`, `instanceof`, `new`), it opens a tag;
  after an operand, a name, or a keyword used as a name, as `x.default < 3`,
  it is less-than. The hook, `Canon.Antlr4.Lex.JavaScript`, answers the
  predicate `IsJsxPossible`.
- The modes `JSX_TAG`, `JSX_CHILDREN`, and `JSX_CLOSE` read a tag's name,
  namespaced as `a:b` or a member as `A.B`, its attributes, whose strings have
  no escapes, its text, with entities as written, and its closing tag. A `{`
  in a tag or among the children opens an expression container in the default
  mode, and the hook tracks the containers' braces as it tracks a template's,
  so `IsJsxExpressionClose` returns to JSX at the brace that closes the
  container, a template or a block inside it included. Comments between
  attributes are hidden, and an element may be an attribute's value.
- `jsxElement` reads elements, fragments, self-closing tags, spread attributes
  and children, and empty and comment-only containers, and is a primary
  expression. A JSX element is no unit: a component is the function or class
  that returns it, documented as any function is, and a doc comment inside a
  container is a stray comment and an orphan.

The grammar does not read Flow, which is no ECMAScript. A Flow project, such as
React, names the TypeScript grammar's `.tsx` pair for its `.js` files, which
reads Flow's types and JSX; `grammars/typescript/README.md` lists what it reads.

## Corpus

`tools/corpus/javascript.sh` checks the grammar against seven of the most used
JavaScript code bases, three of them written with JSX and React's written in
Flow. It shallow-clones each repository below at the pinned commit into
`/tmp/corpus/javascript`, or the directory given as its first argument, parses
every `.js`, `.jsx`, `.mjs`, and `.cjs` file with the plain grammar under a
timeout of 300 seconds per file, and then parses every file the plain grammar
parsed with the dialect, which must parse them all. A file whose first comment
holds `@flow`, and every file of React, as a Flow project's profile reads them,
is read by the TypeScript grammar's `.tsx` pair, which reads Flow's types and
JSX; any other file by this grammar. Large repositories are sampled by
subdirectory with a sparse checkout. Minified files and build output,
`*.min.js` and anything under `dist/` or `build/`, are generated and not read:
seven files of lodash's `dist/` and two minified scheduler builds of React. The
script runs in a process group of its own, through
`tools/corpus/process-group.sh`, and shares `tools/corpus/jsts-common.sh` with
its TypeScript twin.

| Repository | Commit | Sampled | Kind | Files | Parsed | Excluded | Seconds |
|------------|--------|---------|------|------:|-------:|---------:|--------:|
| [facebook/react](https://github.com/facebook/react) | `278794d7dee9` | `/packages/` | Flow | 1816 | 1816 | 0 | 322.7 |
| [nodejs/node](https://github.com/nodejs/node) | `019e869ad3a3` | `/lib/` | JS | 429 | 429 | 0 | 64.7 |
| [lodash/lodash](https://github.com/lodash/lodash) | `2b5e6f7399a7` | all | JS | 48 | 48 | 0 | 23.6 |
| [expressjs/express](https://github.com/expressjs/express) | `7ef98448f8b3` | all | JS | 141 | 141 | 0 | 14.7 |
| [mrdoob/three.js](https://github.com/mrdoob/three.js) | `457581a08070` | `/src/` | JS | 755 | 755 | 0 | 77.3 |
| [vercel/next.js](https://github.com/vercel/next.js) | `263f6820b21d` | `/examples/`, `/packages/create-next-app/templates/` | JSX | 832 | 831 | 1 | 55.9 |
| [mui/material-ui](https://github.com/mui/material-ui) | `daaa525c3af0` | `/packages/mui-material/src/`, `/packages/mui-system/src/` | JSX | 473 | 473 | 0 | 53.9 |
| Total | | | | 4494 | 4493 | 1 | 612.8 |

Every file but one parses with the plain grammar and with the dialect. By kind
of file, a JSX file being a `.jsx` file or one that holds a closing tag: 1,821
Flow files, React's and five that say `@flow`, all parse; 777 JSX files, 776
parse; and 1,896 other JavaScript files all parse. The one file excluded,
next.js's `examples/with-custom-babel-config/pages/index.js`, writes the
pipeline operator `|>`, the syntax of a Babel proposal plugin, which no engine
reads. The seconds are the sum of each file's wall time, the `canon` process
included, with 10 files parsed at once. A file takes 0.08 seconds at the
median, 0.21 at the 90th percentile, 1.0 at the 99th, and at most 6.8,
lodash's `test/test.js`, 27,000 lines; the excluded file fails in 0.07
seconds. Through the dialect the slowest file is lodash's vendored
`firebug-lite-debug.js`, 31,000 lines, at 29 seconds, since each of its JSDoc
comments that no rule takes is a stray comment the file is read again without.

The corpus found these gaps, now fixed in the plain grammar and the dialect:
logical assignment, `||=` and `&&=`; a trailing comma after the last
parameter; a number with a dot and no fraction digits, `1.`; a private brand
check, `#x in o`; `using` and `await using` declarations; and, as in
TypeScript, exponential lexing of an identifier with many underscores. In the
dialect a JSDoc comment above a local binding or an expression statement, as
JSDoc writes above `this.x = x`, or before a method of an object literal, is an
orphan the grammar reads, so a file with many is not read again once for each.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/javascript.sh                      # clones into /tmp/corpus/javascript
CORPUS_SKIP_FETCH=1 tools/corpus/javascript.sh  # reuses the clones
```
