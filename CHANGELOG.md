# Changelog for `canon`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Changed
- The parser memoises each repeated element by position, so a file that does not parse fails as fast as one that does parses, instead of taking minutes
- HCL templates must pair `%{ if }` with `%{ endif }` and `%{ for }` with `%{ endfor }`
- A quoted YAML key is named without its quotes; flow collections read JSON-like pairs such as `{"a":1}` and Pulumi interpolations such as `[${a}]`
- A `why` element inside an optional or repeated block is optional

### Added
- Terraform's JSON syntax, `.tf.json` and `.tfvars.json`, read by the HCL dialect into the same units with the same names, with a `//` property as a block's Why; the HCL profile owns them by name
- The `qualifier` label: a key on a node that is no unit becomes the first part of the name of every unit below it
- HCL blocks named by what tells them apart: an aliased provider as `provider/aws.west`, `moved` and `removed` blocks by the address they move from, `import` blocks by the address they import to; only blocks that nothing tells apart are numbered
- Pulumi `template` config entries as units of kind `templateConfig`
- HCL as a language: an HCL grammar written for canon under `grammars/hcl/`, from the HCL native syntax specification, with a lexer hook that hides line breaks inside brackets and closes heredocs at their delimiter, and a canonically commented dialect in which every top-level Terraform block is a unit named by its labels joined with a dot, each `locals` entry is a unit, a comment directly above a block is its Why, and the `description` of a variable or an output is a Why too; variables and outputs require one; `run` blocks of Terraform test files in the test table; Terraform's `.terraform` directory skipped by default; and `lang_samples/hcl-terraform-aws-key-pair`, terraform-aws-key-pair vendored with its license
- Pulumi YAML as a language: a grammar of the block structure of YAML 1.2 written for canon under `grammars/yaml/`, with a lexer hook that turns indentation into layout tokens and ends block scalars, and a canonically commented dialect in which each resource, variable, output, and config key of a Pulumi program is a unit named by its key, with the comment directly above it, or a config key's `description`, as its Why; outputs and declared config keys require one; and `lang_samples/pulumi-yaml-examples`, three Pulumi examples vendored with their license
- `files` in a profile: file name patterns such as `Pulumi.*.yaml`, matched before any profile's extensions, so a profile can own some YAML files without owning all of them
- A unit whose alternative holds several `what` elements is named by their texts joined with a dot, and a `why` element that is a string rather than a `canonicalComment` is documentation written as data, read without its quotes or heredoc delimiters and with its citations taken from its text
- C# as a language: the grammars-v4 C# 7 grammar under `grammars/csharp/`, with its `CSharpLexerBase` ported as a lexer hook that tracks interpolation holes and reads one branch of each `#if`, attributes and modifiers moved into each kind of type and member so a doc comment above the attributes binds, `public` and `protected` labeled `required`, and C# 8 to 14 syntax added, from records and patterns to raw strings and extension blocks; a C# profile with namespaces, types, and members as units; xUnit, NUnit, and MSTest attributes in the test table; and `lang_samples/csharp-guardclauses`, Ardalis.GuardClauses vendored with its license
- F# as a language: an F# grammar written for canon under `grammars/fsharp/`, which parses namespaces, modules, bindings, types, members, fields, and cases and reads expressions as runs of tokens, with a lexer hook that turns the offside rule into layout tokens; an F# profile in which `private` and `internal` are labeled `optional`; xUnit, NUnit, FsCheck, and Expecto attributes in the test table; and `lang_samples/fsharp-giraffe-viewengine`, Giraffe.ViewEngine vendored with its license
- `directives` in a profile's comment syntax: a directive line, and where outer doc openers are given a plain comment line, does not part a doc comment from its unit, and a comment in an `#if` branch canon does not read binds to nothing and is no orphan
- A profile unit is required when its node holds an element labeled `required`, and not required by its rule when its node holds one labeled `optional`
- Elixir as a language: a structural Elixir grammar written for canon under `grammars/elixir/`, since the grammars-v4 Elixir grammar parsed 71 of 308 real files, reading statements, interpolating strings and heredocs, sigils, and every kind of definition with the attributes above it; an Elixir profile with modules, protocols, implementations, functions, macros, guards, delegates, callbacks, types, structs, exceptions, and ExUnit tests and describe blocks as units; ExUnit and StreamData tests in the test table; and `lang_samples/elixir-jason`, Jason 1.4.5's formatter and its tests vendored with Jason's license
- Gleam as a language: a grammar of Gleam's module level written for canon under `grammars/gleam/`, reading imports, functions, types with constructors and labelled fields, and constants with their attributes; a Gleam profile that requires a comment on public items; gleeunit's `*_test` functions in the test table; and `lang_samples/gleam-stdlib`, two stdlib modules and a test module vendored with the stdlib's licence
- `docAttributes` in a profile's comment syntax: an attribute such as Elixir's `@doc` followed by a string is scanned as a comment whose body is the string's contents, and a string delimiter of three or more characters may span lines
- `mergeClauses` on a unit rule, which makes adjacent matches with one name a single unit unless a doc comment above a later one starts a new unit, and several unit rules naming one parse rule, told apart by `firstToken`
- Rust as a language: the grammars-v4 Rust grammar under `grammars/rust/`, with its base-class predicates replaced in the grammar, attributes and visibility moved into each kind of item so a doc comment above the attributes binds, macro token trees parsed one token at a time, and seven fixes where upstream rejected stable Rust, among them a string ending in an escaped backslash; a Rust profile with functions, structs, enums, unions, traits, macros, type aliases, constants, statics, impls, and modules as units; `#[test]` and four other test attributes in the test table; and `lang_samples/rust-scopeguard`, scopeguard 1.2.0 vendored with its licenses
- `outerDoc` and `innerDoc` openers in a profile's comment syntax: with outer openers given, only a doc comment binds to the unit below and a plain comment is neither a Why nor an orphan, and an inner doc comment such as Rust's `//!` binds to the unit that encloses it or to the file; adjacent line comments merge only when they open alike
- Unicode property classes such as `\p{L}` and `\p{Zs}` in lexer character sets, matched by general category
- Rule 9: every piece of canonical material is signed off by whoever did it. Ledger entries and registry entries join comments in `canonical_vetting.yaml`, keyed `ledger/KEY` and `registry/KEY`, pending until a verdict is set and stale when edited; the sign-off records the verdict line's committer and the commit's co-authors, and `canon decisions` shows it after each entry
- Haskell as a dialect language: `grammars/haskell/canonically_commented/` tokenizes Haddock `-- |` and `{-| -}` comments, labels unit alternatives and export-list entries, and the layout port holds doc tokens until the next code token; the root `canon.yaml` checks canon's own `src`, `app`, and `test` through it
- The export rule: a dialect that labels export entries requires a comment on exactly the exported units, or on every named unit when a module has no export list
- Canonical comments on every rule of the plain Haskell grammar and on every exported unit and module of canon's own source, ingested as pending for a human to vet
- Four fixes to the vendored Haskell grammar and its layout port, so all seventy-seven Haskell files in the repository parse: standard literals with escapes, contextual keywords and pragma names as identifiers, block closing on a dedented `where` or brace, and doc-comment holding
- Rule 8: the name says what and the comment says why, so a comment that restates the name is vetted bad; applied to one Gson test as the worked example, with its requirement recorded in the sample's registry
- Test recognition: the `marker` element label on annotations in the Java dialect, a built-in table per language of test markers and name patterns (JUnit 3, 4, and 5, jqwik, EUnit, plunit, and naming conventions for Clojure and Haskell), `test` on every unit in the model, a required comment on every test, and two failing checks: a commented test that cites no `requirement` and a requirement no test in the project cites
- Canonical comments on every rule of the plain Java grammar and its dialect, with the BSD header citing its license, so both are checked at the root; test sources are not exempt from canonical comments, since a test's Why is the requirement it verifies
- Java as a language: the grammars-v4 Java grammar under `grammars/java/` and its canonically commented dialect, with `required = PUBLIC` making a public member's comment required, interface members required outright, and misplaced Javadoc comments accepted as `orphan` and reported
- Three Java sample projects as submodules, Apache Commons Lang, Joda-Time, and Gson, each ingested with every Javadoc comment pending
- Rule 7 and `canonical_vetting.yaml`: `canon ingest` records every canonical comment as pending with a digest of its text, `canon vet` lists what needs a verdict with its text, a human sets `good`, `bad`, or `deferred` with a revisit version and commits, the assessor is the author of that commit from `git blame`, the model carries the verdict, assessor, time, and commit on each decision, and `canon check` fails on pending, stale, bad, and overdue comments and ends with `report invalid` while any are pending
- The `required` and `orphan` element labels in canonically commented grammars, and the rule that only a labeled alternative containing a `why` element is a unit, so upstream alternative labels stay inert

### Fixed
- Lexing a long literal is linear rather than quadratic in its length: a 20 KB string in a Plug module took seconds, because each iteration of a loop copied the ends of the iterations after it
- Extraction was exponential in expression depth on the Java grammar because every labeled expression alternative was scanned as a possible unit; the check of one 170-line test file took minutes and now takes a fraction of a second
- `canon check` bounds the number of files extracted at once to the core count instead of starting every file concurrently
- Unit ids are relative to the project directory rather than the working directory, so verdicts and ledger unit names mean the same thing wherever `canon` is run
- An uncited decided decision is reported once per project, when no file in the project cites it, instead of per file that happens not to

### Changed
- A doc-comment opener followed by a slash, or one ending in a star followed by another, opens a plain comment, so `////`, `/**/`, and `/***` banners are not documentation in Rust, C#, or F#; and a `ref:` key ends where markup starts, so `ref:KEY</summary>` in an XML doc comment cites `KEY`
- Where plain comment lines, directive lines, and unread `#if` branches stand between a doc comment and its unit, one rule now applies: the unit is taken to start above those lines, a plain comment line being one held by a scanned plain comment that starts its line; it replaces both the C# and F# text-prefix check and the Elixir stretching of a doc comment over the comments below it
- Where a profile gives outer doc openers, full-line plain comments directly below a doc comment no longer separate it from its unit, and an outer doc comment on a file's first line documents the item below it rather than the file
- The decree of no comments in canon's own code ends: the standard is canonical comments in Haddock form on exported units and module headers, and nothing else
- The tetris sample is checked through the Haskell dialect instead of a profile with `units`, which brought its findings from 92 to 25 missing comments and no parse failures
- `canon check` stops at nested projects instead of checking them too, so the root check reports canon's own state and each sample is checked from its own directory
- The canonically commented grammar carries the extraction rules: a `DocComment` lexer mode tokenizes canonical comments, and labeled alternatives with `why`, `what`, and `how` elements name unit kinds and locate the answers, so `canon` generates the parser that slurps the five W's and the H from the grammar instead of a hand-written extractor; the plain meta-grammar files are now the language's own grammar with canonical comments on every unit, the `canonical` entry in `canon.yaml` and the hand-written ANTLR extractor are gone, `canon model` goes through the language profile, and unit ids for grammars are file-path based like every other language
- Versions follow Semantic Versioning 2.0.0 rather than the Haskell Package Versioning Policy; the released version is 0.1.0, decision entries and `canon.yaml` use three-part versions, and pre-release labels order as the specification says

### Changed
- The lexer compiles a grammar once into decoded literals, character predicates, and first-character filters, and the parser compiles a grammar once into FIRST sets that prune alternatives, vector memo tables, and difference-list children; the largest Haskell sample module went from 10.6 seconds to 1.3, and profiling shows the parser at under one percent of the remaining time
- `canon check` parses files concurrently, caches extractions under `.canon-cache/` keyed by content, grammar, profile, and git revision, and derives Who and When from one `git blame` per file; the Haskell sample check went from 26 seconds to 1.4 cold and 0.2 warm with identical findings

### Added
- License as the third reason for a canonical comment, cited as `license:KEY` against registry entries of kind `license`; a comment that reads like a license notice without a key is reported informationally, and a key that is not a license fails
- A doc comment on a file's first non-blank line binds to the file unit; the canonically commented meta-grammar allows one before the grammar declaration and carries its BSD notice there
- A Haskell sample project, with the Haskell grammar vendored and its layout base lexer ported to a lexer hook that injects the virtual braces and semicolons the grammar expects
- The parser keeps one tree per rule and span, chosen in preference order, so large ambiguous grammars parse in polynomial time and memory instead of enumerating every derivation
- Language profiles in `canon.yaml`: any interpretable grammar becomes a modelled language, with units taken from named parse-tree rules and comments scanned by the profile's syntax
- Nested projects: a directory with its own `canon.yaml` is checked with its own configuration, and `root` points a project at sources kept elsewhere, such as a submodule
- `lang_samples/` with Erlang, Clojure, and Prolog projects as submodules, and their grammars vendored under `grammars/`
- Precedence climbing for directly left-recursive rules, giving ANTLR's trees for expression grammars, and the `caseInsensitive` grammar option
- `canon check` with no path, or with a directory, checks every supported file under it, skipping version control, dependency, build, and editor directories by default and whatever `canon.yaml` lists under `ignore` in gitignore syntax; `canon files` lists what the walk visits
- `canonical_decisions.yaml`, the decision ledger, with rule 6; `canon decisions` to list it; and checks that fail on an open decision past its revisit version, a superseded decision without a decided successor, a key shared with the registry, or a missing named unit, and inform on an uncited decided decision or a comment citing an open one
- A lexer and parser interpreter that turns any grammar value into a running lexer and parser: longest match with non-greedy loops, modes, channels and commands, implicit literal tokens, a hook interface for target-language lexer actions, and an all-parses parser with left recursion
- `grammars/antlr4/canonically_commented/`, the canonically commented dialect of the meta-grammar, with a doc comment on every rule so it parses itself
- `canon parse` for parsing a file with an interpreted grammar, and `canonical` grammar entries in `canon.yaml` that `canon check` uses to report the first token a dialect refuses
- The canonical model: code units with stable path-based ids answering What, How, Where, Who, and When; decisions binding a Why to units; evidence on every answer; emitted as YAML with alphabetical keys and a schema version
- `canonical_refs.yaml`, the reference registry, and `canon.yaml`, the configuration file, with their readers
- A git provider that fills Who and When from `git log`, with a static implementation for tests and pure parsers for log and blame output
- The first extractor, over ANTLR grammar files, binding doc comments to the rule directly below them under a provisional `ref:KEY` citation syntax
- `canon model <grammar.g4>` and `canon check <grammar.g4>` subcommands; checks report unresolved keys, dangling decisions, missing required comments, orphan doc comments, and unavailable git
- `Canon.Antlr4` library that reads an ANTLR4 `.g4` file into a grammar value with source spans, scans its comments, prints it back to `.g4` text, and answers the questions ANTLR's Java `Grammar` object answers: rules by name, token vocabulary, literal aliases, modes, lexer commands, actions and predicates, references and undefined references, nullability, left recursion, and reachability
- `grammars/antlr4/` with the vendored ANTLR4 meta-grammar and an empty `canonically_commented/` husk
- Test suite on tasty and tasty-hedgehog, with generators for whole grammars, a round-trip property from pretty-printing to parsing, and fixture checks that both vendored meta-grammar files read with their known structure
- `grammars/` directory with the `grammars/<lang>/canonically_commented/` structure, seeded with an empty `haskell` language directory
- README section stating the six questions a codebase must answer and where each is answered

## 0.1.0 - 2026-09-12

### Added
- `canon` executable with a `version` subcommand
- Usage text printed when no recognised subcommand is given
- Root `README.md` stating the Canon documentation rules
- `to_be_removed/` and `sample_projects/` directories
