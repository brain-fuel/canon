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
  braces as an object literal does not take it. Anywhere else the grammar
  does not take one, as above a statement that declares nothing, a local
  binding included, inside an expression, before an argument, or before a
  parameter, the parser's `strayComment` option reads the file without it and
  reports it as an orphan (`DEC-stray-comments`). A named function expression
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
