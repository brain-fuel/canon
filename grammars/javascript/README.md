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
- The first `/**` of a file, before any code, opens `FILE_DOC_OPEN` through
  the base lexer's `IsStartOfFile` predicate, in the `FileDocBlock` mode,
  which reads `@file`, `@fileoverview`, `@overview`, `@module`, `@license`,
  and `@packageDocumentation` as `DOC_FILE_TAG`; the `FileDocAfter` mode
  marks a blank line below it with `DOC_BLANK_LINE`. `program` makes it the
  file's Why when it holds a file tag or a blank line or an import follows
  it, and otherwise it documents the declaration below.
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
- `export` is part of the declaration it exports and is labeled `required`; a
  class's tail is labeled `inherited`, and a `#private` name `optional`.
- A doc comment before any other statement, a parameter, an argument, a
  property of an object literal, or a case, after the last statement or
  member of a body or file, or inside an expression, as a `@type` cast is, is
  an `orphan`. A named function expression is an expression and no unit, and
  `exportStatement` keeps only lists of exports and `export default`.
