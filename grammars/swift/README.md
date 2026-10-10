# Swift Grammar

`SwiftLexer.g4` and `SwiftParser.g4` are written for canon, under canon's MIT
license. The parser follows the
[grammar summary](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/summaryofthegrammar/)
of The Swift Programming Language production by production, under the
summary's names in lower camel case (`functionDeclaration` for
`function-declaration`), and takes the Swift compiler's parser,
[swift-syntax's `SwiftParser`](https://github.com/swiftlang/swift-syntax/tree/09b1d91451c5a0277600cee849fd968d5302460b/Sources/SwiftParser)
(Apache-2.0 with the Runtime Library Exception), as the authority where the
two differ. The lexer follows the
[Lexical Structure](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/)
chapter and the compiler's lexer, and the `#if` reading follows the
[Compiler Control Statements](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/#Compiler-Control-Statements)
section. The grammar, its hook, and the profile are recorded as
`DEC-swift-grammar` and the dialect as `DEC-swift-dialect` in canon's
`canonical_decisions.yaml`, and these sources as `swift-grammar-summary`,
`swift-lexical-structure`, `swift-statements`, `swift-compiler-control`,
`swift-access-control`, `swift-regex-literals`, `swift-syntax-parser`, and
`docc` in its registry.

## Provenance

grammars-v4 has a Swift 5 grammar,
[`swift/swift5`](https://github.com/antlr/grammars-v4/tree/89fd36482e8cb68a4e55df021a8adbc7541b52f2/swift/swift5),
with a `SwiftSupport` base class in Java, C#, and C++. grammars-v4 has no
single license: its house rules leave each grammar to state its own, and the
Swift 5 grammar states none in its files, its readme, or its build files,
while the older Swift 2 and Swift 3 grammars beside it carry Terence Parr's
BSD notice. canon does not vendor unlicensed code, so it does not vendor the
Swift 5 grammar or port its base class; its files were opened only to look for
a license, as `grammars-v4-swift-license` records. This grammar and its hook
were written for canon from the Swift reference and the compiler's sources.
The old Swift 3 grammar, though licensed, reads Swift 3 and is not used.

## Rules and the grammar summary

Each production the grammar reads has a rule of the same name, its EBNF quoted
above it: `topLevel` (top-level-declaration), `statement`, `declaration`,
`importDeclaration`, `constantDeclaration`, `variableDeclaration`,
`patternInitializerList`, `typealiasDeclaration`, `functionDeclaration`,
`functionName`, `enumDeclaration`, `enumCaseDeclaration`,
`structDeclaration`, `structBody`, `classDeclaration`, `classBody`,
`actorDeclaration`, `actorBody`, `protocolDeclaration`, `protocolBody`,
`initializerDeclaration`, `deinitializerDeclaration`,
`extensionDeclaration`, `extensionBody`, `subscriptDeclaration`,
`macroDeclaration`, `operatorDeclaration`, `precedenceGroupDeclaration`,
`attribute`, `attributeName`, `attributeArgumentClause`,
`genericArgumentClause`, `declarationModifier`, `accessLevelModifier`,
`mutationModifier`, `actorIsolationModifier`, `codeBlock`, and
`identifier`. canon adds rules of its own, each said so where it stands:

- `declarationPrefix`, the `attributes? declaration-modifiers?` every
  declaration rule starts with, so a declaration's node starts at its first
  attribute and the doc comment above it belongs to it; `attributeOrSpi`,
  which tells `@_spi` from the other attributes; and `declarationName`,
  `variableName`, `operatorName`, and `extendedType`, the names a declaration
  declares.
- `associatedtypeDeclaration` (protocol-associated-type-declaration) and
  `macroExpansionDeclaration`, read wherever a declaration stands, as the
  compiler reads a protocol's associated type and a freestanding macro such
  as `#warning` or `#Preview`.
- The statements of the file and of each body are written out where they are
  enclosed rather than as a rule of their own: the parser keeps one tree for
  every end a rule reaches, and a rule holding a body's statements reaches one
  end per statement.
- Expressions, statements, types, patterns, generic clauses, parameter
  clauses, effects, result types, where clauses, and code blocks are read
  structurally, as runs of tokens: `importPart`, `bindingPart`,
  `signaturePart`, `headerPart`, `typeHeader`, `exprPart`, `group`,
  `bracketGroup`, `groupItem`, and `genericArgument` keep brackets balanced
  without typing what is inside them, so a local declaration is part of its
  block. A top-level statement that declares nothing, as `main.swift`, a
  script, or a playground holds, is `expressionStatement`, which starts with
  no attribute, keyword, or modifier that begins a declaration, so a
  declaration the grammar cannot read fails the file rather than reading as an
  expression; a contextual keyword starts one only where a dot, an operator,
  or a bracket follows it, as `package.targets` does in a `Package.swift`. A
  member of a type is always a declaration, as the compiler requires.

Where the summary and the compiler differ, the grammar follows the compiler:

| Production | The grammar summary says | The compiler does | canon follows |
|---|---|---|---|
| declaration | attributes, then modifiers | either order, and a line break after either | the compiler |
| attribute | an attribute name and arguments | also a custom attribute's generic arguments, `@ReducerBuilder<State, Action>` | the compiler |
| declaration-modifier | the documented modifiers | also `nonisolated(unsafe)`, `__consuming`, and `@_spi(name)`, which hides a declaration from its module's public interface | the compiler |
| declaration | the declarations | also a freestanding macro expansion where a declaration stands | the compiler |
| extension-declaration | a type identifier | also array and dictionary sugar, `extension [Int]` | the compiler |
| operator-declaration | `prefix`, `postfix`, or `infix operator` with a precedence group | also the Swift 2 form with a body, which the compiler parses and rejects with a fix-it | both, so such a file parses |
| generic-parameter-clause | type parameters | also value generics, `<let count: Int>`, and `~Copyable` requirements | read as a run of tokens |
| function-declaration | the signature on its line | a generic clause, parameters, effects, result, and where clause over several lines, and the body's brace on the next | the compiler |
| enum-case-clause | a list of cases | the same | one unit, named by the first case |

## The lexer

The lexer reads every Swift token. A block comment nests. A string literal is
one token, its interpolations and the strings nested in them included: a
single-line string holds escapes and no line break outside an interpolation,
a multi-line string's opening quotes end their line and it runs to the first
`"""` outside an interpolation, and a raw string, delimited by one to seven
number signs, single-line or multi-line, runs to its closing quotes followed
by as many number signs. An extended regex literal runs from `#/` to `/#`, and
a bare one between slashes, where the hook says an expression may start and
no space follows the opening slash, as SE-0354 decides. Declaration keywords
and the contextual keywords that declare or modify a declaration are tokens of
their own, which `identifier` also reads as names; the other keywords are
names to the parser, which reads statements and expressions as runs of
tokens. A lone `<` or `>` is a token of its own, for a custom attribute's
generic arguments; every other operator, `=`, `->`, `?`, and `!` among them,
is `OP`. An operator is a run of operator characters, Unicode's included, or
a dot followed by dots and operator characters. `_` and `_spi` are tokens of
their own, the wildcard naming no declaration. A conditional compilation
directive is one hidden token running to the end of its line.

## Statements and line breaks

Swift ends a statement at a line break unless the tokens around it continue
it, which no context-free grammar sees. The lexer's `superClass` option,
`SwiftLexerBase`, selects the `Canon.Antlr4.Lex.Swift` hook in canon, which
emits an empty `NEWLINE` token, placed where the last code token ends, before
the first code token of a line that starts a new statement:

- Line breaks separate statements in braces and at the top level, and mean
  nothing inside parentheses or brackets.
- The last token must be able to end a statement: not an opening bracket, a
  comma, a colon, a semicolon, a dot, `@`, `#`, or `\`; not a keyword that
  something must follow, such as `func`, `case`, `if`, `else`, `in`, `where`,
  `as`, `try`, or `await`, unless it is a member name after a dot or a name
  after a declaration's introducer, as in `case await`; not an operator with
  whitespace before it, `=`, `->`, or `<`, while a postfix operator such as
  `!` and a closing `>` end one; and not the closing parenthesis of an
  attribute's arguments, after which the declaration or type it applies to
  may follow on the next line, as `@convention(thin)` and a function type do.
- The next token must be able to start one: not a closing bracket, an opening
  brace, which after a line break begins a body or a trailing closure, a
  comma, a colon, or a dot; not `else`, `catch`, `where`, `in`, `is`, `as`,
  `throws`, `rethrows`, or `async`; not a binary operator, which has
  whitespace on both sides, `=`, `->`, or a closing `>`; and not a parameter
  clause after a generic clause's `>`, after `init`, or after a function's
  name. An operator that starts a line is held until the next token shows
  whether whitespace follows it.
- A keyword token after a dot is retyped as a name, as `.init`, `.default`,
  and `Foo.self` are names.

## Conditional compilation

Swift compiles one branch of each `#if`, `#elseif`, `#else`, and `#endif`,
chosen by its compilation conditions. The hook reads each directive and hides
the tokens of the branches a build does not compile, as the C# and F# hooks
do, by the policy of `Canon.Preprocessor`, which reads Swift's directives
through `swiftDirectiveOf`: a platform condition such as `os(Linux)`,
`canImport(Darwin)`, `swift(>=5.9)`, `compiler(>=6)`, `hasFeature(X)`, or
`targetEnvironment(simulator)` is one symbol, decided as a whole, and so is a
name such as `DEBUG` or `$Macros`; `true` and `false` are constants. By
default the first branch whose condition some build satisfies is read, and
`canon check` reads each file once per build of the few that together read
every branch some build compiles, as `DEC-preprocessor-builds` has it. So a
postfix `#if` around a member chain, an `#if` among attributes or switch
cases, and an `#if` between a declaration's members all read as the
compiler reads them.

## Coverage

`tools/corpus/swift.sh` clones each repository below at its commit, parses
every `.swift` file with the plain grammar and with the dialect, in the build
canon reads by default, and prints the files parsed per repository. The
excluded file, listed in the script, is a tutorial step whose code is elided
and which `swiftc -parse` rejects. Swift's own repository is sampled to its
standard library, whose `.swift.gyb` templates are not Swift.

Every file outside the excluded one parses with the plain grammar and with the
dialect, 5,605 files in all, as do the 12 files of the Argument Parser sample.
Parsed under every build canon reads, every file of the corpus but the
excluded one, 6,036 files with the sources RxSwift links into a second
directory counted twice, parses in each of its builds, 7,468 in all, 989 files
being read in more than one.

| Repository | Commit | Files | Parsed | Excluded | Dialect parsed |
|---|---|---|---|---|---|
| [apple/swift-nio](https://github.com/apple/swift-nio) | `e12881f2a691` | 555 | 555 (100%) | 0 | 555 |
| [apple/swift-collections](https://github.com/apple/swift-collections) | `935f696a549a` | 734 | 734 (100%) | 0 | 734 |
| [apple/swift-algorithms](https://github.com/apple/swift-algorithms) | `5b7143f8e291` | 57 | 57 (100%) | 0 | 57 |
| [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) | `efd239f0055b` | 170 | 170 (100%) | 0 | 170 |
| [Alamofire/Alamofire](https://github.com/Alamofire/Alamofire) | `bda9ed57d729` | 101 | 101 (100%) | 0 | 101 |
| [vapor/vapor](https://github.com/vapor/vapor) | `bf77fc69b142` | 268 | 268 (100%) | 0 | 268 |
| [swiftlang/swift-syntax](https://github.com/swiftlang/swift-syntax) | `09b1d91451c5` | 767 | 767 (100%) | 0 | 767 |
| [swiftlang/swift-format](https://github.com/swiftlang/swift-format) | `b15dd59fad21` | 263 | 263 (100%) | 0 | 263 |
| [onevcat/Kingfisher](https://github.com/onevcat/Kingfisher) | `08557202ba5a` | 175 | 175 (100%) | 0 | 175 |
| [SnapKit/SnapKit](https://github.com/SnapKit/SnapKit) | `250529bec615` | 43 | 43 (100%) | 0 | 43 |
| [pointfreeco/swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) | `bc2db5ba8ad3` | 797 | 797 (100%) | 1 | 797 |
| [swiftlang/swift](https://github.com/swiftlang/swift), `stdlib/public` | `fd5346677872` | 472 | 472 (100%) | 0 | 472 |
| [ReactiveX/RxSwift](https://github.com/ReactiveX/RxSwift) | `3e33f90c1bcd` | 588 | 588 (100%) | 0 | 588 |
| [SwiftyJSON/SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) | `3d2544101a03` | 23 | 23 (100%) | 0 | 23 |
| [ChartsOrg/Charts](https://github.com/ChartsOrg/Charts) | `1bad5469f576` | 205 | 205 (100%) | 0 | 205 |
| [airbnb/lottie-ios](https://github.com/airbnb/lottie-ios) | `1fb4d7d5b45b` | 323 | 323 (100%) | 0 | 323 |
| [Moya/Moya](https://github.com/Moya/Moya) | `24c26671a2f0` | 64 | 64 (100%) | 0 | 64 |
| all | | 5605 | 5605 | 1 | 5605 |

Over the corpus no declaration keyword is read inside another declaration's
run of tokens, other than the import kinds, value generics, and the `let` of
`if let` in a script, and no member of a type is read as anything but a
declaration. Parsing is linear in the length of a file and failing files fail
fast: run fourteen at a time, the median file took 0.01 seconds of CPU, the
99th percentile 0.07 with the plain grammar and 0.09 with the dialect, and the
slowest, swift-syntax's generated `RawSyntaxValidation.swift` and the standard
library's `Codable.swift`, 0.27 and 0.35; the excluded file fails in 0.02.

## Canonically commented dialect

`canonically_commented/SwiftLexer.g4` and `SwiftParser.g4` are the grammar
with `///` and `/**` doc comments as canonical comments, as DocC reads them,
recorded as `DEC-swift-dialect`. Each change is marked `// canon:`:

- `///` opens a doc comment on the default channel in the `DocLine` mode, and
  a following line that starts with `///` continues it; `/**` opens one in the
  `DocBlock` mode, which drops the stars that decorate its lines and skips a
  comment nested in it, since Swift comments nest. Both tokenize prose,
  DocC markup, `ref:KEY`, and `license:KEY`. `////`, `/**/`, and `/***` stay
  plain comments by the longest match.
- The hook ends a `///` comment with an empty `DOC_END` token where its line
  ends, and holds a doc comment's tokens until the next code token, emitting
  them after the `NEWLINE` the line break before that token needs, so a line
  holding only a comment is blank to the statement rules.
- `canonicalComment` and `docPart` are the comment rules, and the
  `strayComment` option names `canonicalComment`, so a doc comment where the
  grammar accepts none is read as an orphan rather than failing the file.
- Each declaration DocC documents is a labeled unit alternative whose `why` is
  the doc comment above its attributes and modifiers and whose `what` is its
  name: `# let`, `# var`, `# typealias`, `# associatedtype`, `# func`,
  `# enum`, `# case`, `# struct`, `# class`, `# actor`, `# protocol`,
  `# init`, `# deinit`, `# extension`, `# subscript`, `# macro`,
  `# operator`, and `# precedencegroup`. A `let` or `var` that binds a tuple
  or wildcard pattern is no unit.
- A doc comment after an attribute or a modifier, inside a modifier's
  parentheses, above an import, a freestanding macro expansion, or a
  statement, inside a run of tokens, at the end of a body, or at the end of
  the file is an `orphan`.
- A doc comment above a declaration marked `private`, `fileprivate`, or
  `@_spi` is its Why, as the Gleam dialect binds one above `@internal`; the
  profile, which reads the plain grammar, reports it as an orphan under
  `DEC-hidden-label`.

The dialect parses the Argument Parser sample, binding the doc comments the
profile binds and those on hidden declarations, and finding the units and
requirements the profile finds; 327 sample and corpus files holding no
multi-line string or regex literal with a doc comment inserted at the start of
every line and after every opening parenthesis, comma, and equals sign,
without the `strayComment` recovery; and every corpus file the plain grammar
parses, no more and no fewer.

## Known limits

- An enum case clause listing several cases, `case a, b`, is one unit named by
  the first.
- An operator written right against a following comment, as `x+//`, takes the
  comment's first slash, as the compiler's lexer does not.
- A bare regex literal after a token the hook does not list, or containing an
  unescaped slash inside a character class, is read as operators; the
  extended `#/.../#` form always reads.
- A raw string's interpolation is text to the lexer, so a raw string holding a
  string with its own closing delimiter inside an interpolation ends early.
- A condition of `#if` that continues onto the next line is read to the end of
  its first line.
- A `#if` inside a multi-line string literal is text to the lexer but a
  directive to the line-based reading that chooses builds and the lines a
  build leaves unread, so it may add a build or leave a doc comment in that
  string's lines unbound.
