# Groovy grammar

## Provenance in canon

`GroovyLexer.g4` and `GroovyParser.g4` are Apache Groovy's own ANTLR 4
grammar, `src/antlr/GroovyLexer.g4` and `src/antlr/GroovyParser.g4` from
[apache/groovy](https://github.com/apache/groovy/tree/84b0d5072e2d8d02d10720b8a337493af1bda9fe/src/antlr)
at commit `84b0d5072e2d8d02d10720b8a337493af1bda9fe`, under the Apache License
2.0 in their headers, with the BSD licence of the Java grammar by Terence Parr
and Sam Harwell they were adapted from. grammars-v4 has no Groovy grammar, at
`7df52be94698550d219d299d04105c6bafadd9c3` or in its history, and this is the
grammar the Groovy compiler itself parses with, so it reads what Groovy reads.

The grammar leans on Java: the lexer's superclass `AbstractLexer` and its
`@members`, the parser's superclass `AbstractParser`, and the
`SemanticPredicates` class. canon interprets the grammar and has no port of
those classes, so the lexer's members are ported as the
`Canon.Antlr4.Lex.Groovy` hook, selected by `superClass = AbstractLexer`, the
parser's predicates as the `Canon.Antlr4.Predicate.Groovy` hook, selected by
`superClass = AbstractParser`, and what neither can express is rewritten in
the grammar. Every change is marked `// canon:` in the grammar and recorded as
`DEC-groovy-grammar` in canon's `canonical_decisions.yaml`:

- The lexer hook keeps the type of the last token on the default channel, so
  `isRegexAllowed` tells a slashy string from a division as upstream's
  `REGEX_CHECK_SET` does, and the stack of open brackets that `enterParen` and
  `exitParen` keep, so a newline inside parentheses or square brackets, but
  not braces or `try (...)`, goes to the hidden channel. It decides the
  identifier predicates on the character just matched, as `_input.LA(-1)`
  does; canon reads code points, so the surrogate-pair alternatives never
  apply.
- canon's lexer predicates see the characters matched, not the ones ahead, so
  each predicate that looked ahead is written as the characters it allowed:
  one or two quotes inside a triple-quoted string are a character when a
  character other than a quote follows them, and may stand before the closing
  quotes or a dollar; a dollar in a slashy or dollar slashy string is a
  character when what follows it cannot start a GString value, read together
  with that character, so the `isFollowedByJavaLetterInGString` predicates
  are dropped; a slashy string's first character is not a star; a slash in a
  dollar slashy string is a character when anything but a dollar follows it.
  `DollarSlashDollarEscape` keeps its predicate, which looks behind.
- `NOT_IN` takes the letters after `!in`, and the hook splits `!internal`
  back into `!` and an identifier, which upstream's `isFollowedBy` predicates
  decided; `!instanceof` needs no predicate, since a longer word is split the
  same way.
- `RollBackOne` consumed the character after a GString path and rolled the
  lexer back over it; canon's lexer cannot roll back, so it is an empty match
  that pops the mode and the character is read again in the string's mode.
- The string modes move to the end of the lexer, and `mode DEFAULT_MODE;` no
  longer reopens the default mode, since canon reads each mode section as the
  whole mode.
- Comments go to the hidden channel. Upstream made a comment a newline unless
  it was inside brackets or code followed it on its line; a comment that ends
  its line is followed by the newline token itself, so the parser sees the
  same separators.
- Each kind of type is a rule of its own, `normalClassDeclaration`,
  `interfaceDeclaration`, `enumDeclaration`, `annotationTypeDeclaration`,
  `traitDeclaration`, and `recordDeclaration`, which starts with the type's
  modifiers and annotations, so its node starts at its first annotation and
  the Groovydoc above binds to it. The header between the name and the body
  is `classHeader`. An enum's body is `enumBody`, which upstream chose inside
  `classBody` with the predicate `$t == 2` on a rule argument canon's
  predicates do not see.
- A constructor is `constructorDeclaration`, a member without a return type
  named for its class, which the `isConstructorName` predicate added for
  canon decides; upstream's AST builder told a constructor from a method.
- An annotation is labeled `marker`, so a test is told by its annotation, and
  `private` is labeled `optional`, since Groovy declarations are public unless
  they say otherwise.

The parser hook answers upstream's predicates on the visible tokens:
`isInvalidMethodDeclaration`, so `foo(1) { }` at the top of a script is a
call; `isInvalidLocalVariableDeclaration` and `isAnnotatedLoopStatement`, so
`println x` is a command and `String s` a declaration; `isIdentifierAssign`
for annotation arguments; `static.` as a name; and
`isFollowingArgumentsOrClosure`, which upstream read from the parse of the
expression before a command's arguments and the hook reads from its tokens.
The counters of switch expressions and async closures are not tracked, so
`yield` and `defer` statements are admitted anywhere.

## Canonically commented dialect

`canonically_commented/GroovyLexer.g4` and `GroovyParser.g4` are the grammar
above with Groovydoc comments as canonical comments, recorded as
`DEC-groovy-dialect`. Each change is marked `// canon:`:

- `/**` opens a Groovydoc comment on the default channel, in the `DocBlock`
  mode, which tokenizes prose, punctuation, `ref:KEY`, and `license:KEY`, and
  drops the stars that decorate its lines. A plain comment may not start with
  two stars, so `/**/` and `/***` stay plain by the longest match.
- `canonicalComment`, which takes the newlines after the comment, and
  `docPart` are the comment rules.
- Each type, constructor, method, field, and enum constant is a labeled unit
  alternative: `# class`, `# interface`, `# enum`, `# annotation`, `# trait`,
  `# record`, `# constructor`, `# method`, `# field`, and `# constant`. The
  Groovydoc above the annotations is the `why`, and of several in a row the
  last binds. A field is named by its first declarator.
- Each unit holds the empty rule `publicByDefault`, labeled `required`, and
  `private` is labeled `optional`, which wins, so a declaration requires a
  comment unless it is private.
- A Groovydoc comment the grammar accepts but binds to nothing is an
  `orphan`: after an annotation or a modifier, before a statement, a package,
  an import, or an initializer block, and after the last member of a body, a
  block, a closure, or a file.

A Groovydoc comment inside an expression or between brackets fails the parse.
