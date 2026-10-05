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
  before a property of an object literal that `propertyAhead` sees, as in the
  JavaScript dialect, is an `orphan` the grammar reads. Anywhere else the
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
