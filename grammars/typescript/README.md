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
described in `grammars/javascript/README.md`, and the parser as follows, each
change marked `// canon:`:

- `canonicalComment`, `fileComment`, `taggedFileComment`, and `docPart` are
  the comment rules; `program` makes a file's first doc comment its Why when
  it holds a file tag such as `@packageDocumentation`, or a blank line or an
  import follows it. `moduleItem` and `declaredVariable` read a statement at
  the top of a module or namespace, where a variable statement is a unit.
- Functions, each overload a unit of its own, classes, interfaces, type
  aliases, enums, enum members, namespaces, ambient modules, module-level
  bindings, `export default`, constructors, class properties, methods,
  accessors, abstract members, and index signatures, and the members of an
  object type are labeled unit alternatives: `# function`, `# class`,
  `# interface`, `# type`, `# enum`, `# member`, `# namespace`, `# module`,
  `# variable`, `# export`, `# constructor`, `# property`, `# method`,
  `# accessor`, `# index`, `# call`, and `# new`. A call, construct, or index
  signature is named by its position through `ordinal`, and an accessor by
  `get` or `set` and its property, through `classGetAccessor` and
  `classSetAccessor`. Decorators follow a member's doc comment.
- `export` is part of the declaration it exports and is labeled `required`.
  An interface's body, an enum's body, a class's tail, and an object type
  alone on the right of a type alias are labeled `inherited`; `private`,
  `protected`, and a `#private` name are labeled `optional`.
- A doc comment before any other statement, a parameter, an argument, a
  property of an object literal, a case, or a mapped type's member, after the
  last statement or member of a body or file, or inside an expression is an
  `orphan`. A named function expression is an expression and no unit.
- `import type`, `export type`, and an inline `type` modifier in an import or
  export list are read, which the plain grammar reads as an expression.
