# canon

`canon` exists so that humans and LLMs can keep every decision in a codebase
evergreen: the who, what, when, where, why, and how of each decision has a
single canonical source that does not drift from its intended meaning. A
decision is a comment plus the code it attaches to, in the same way an
architecture decision record pairs with the architecture it describes.

No liar's comments and no liar's architecture are allowed. The compiler,
property-based testing, mutation testing, and decision coverage verify what
they can. Everything they cannot decide, which by Rice's theorem is every
non-trivial semantic property, must be explained by a human, and `canon` makes
it tractable for humans to review that explanation. A typical example is a
comment recording that a function exists because of a particular business
requirement.

This repository is the reference implementation of these rules, applied to
itself.

## Documentation rules

1. **`CHANGELOG.md` is required for any project that can be published to
   Hackage.** It lives at the root of the project, follows the
   [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format, and
   versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
   major, minor, and patch numbers, with optional pre-release and build
   metadata. Cabal accepts only the numeric part, so `package.yaml` carries
   the numbers and any pre-release label lives in `canon.yaml`.
   It is listed under `extra-source-files` so Hackage renders it.
2. **One `README.md` per project, at its root.** Apart from `CHANGELOG.md`
   where rule 1 applies, the only markdown file allowed outside
   `to_be_removed/` is `README.md` at the root of a given project. For this
   repository, that is this file. For a sample project, that is
   `sample_projects/<project>/README.md`.
3. **Anything without a canonical place goes in `to_be_removed/`.** Any
   documentation, decision, or record that does not yet have a canonical home
   under these rules lives in `to_be_removed/`, whether it predates `canon` or
   was written yesterday. Nothing in that directory is authoritative. Each item
   is folded into canonical form once a place for it exists, and then deleted.
4. **Nothing outside the repository is trusted.** If a fact about this project
   is not written down in canonical form, or in `to_be_removed/` pending a
   canonical place, it cannot be trusted. Tool memory, chat history, and
   recollection do not count.
5. **`canon.yaml` and `canonical_refs.yaml` live at the project root.**
   `canon.yaml` is canon's configuration: the project version and the path of
   the registry. `canonical_refs.yaml` is the reference registry, the single
   canonical source for every article, paper, ticket, requirement, package, or
   discussion that a comment cites. Each entry maps a key to a kind, a title,
   and a locator. Comments cite keys only. Neither file carries comments.
6. **Decisions live in `canonical_decisions.yaml` at the project root.** Every
   decision, open or closed, is an entry keyed like a reference, so a comment
   cites it with the same `ref:KEY` form. An entry is never deleted; its
   status moves from `open` to `decided`, or to `superseded` by another key.
   An open entry names the version by which it must be revisited, and
   `canon check` fails once the project version reaches it. A decided entry
   that no canonical comment cites is reported. Git supplies who opened and
   closed each decision and when.
7. **Existing comments are vetted before they count, in `canonical_vetting.yaml`.**
   A comment that predates `canon`, or that nobody has yet judged, is not
   known to fulfil its purpose. `canon ingest` records every canonical comment
   of a project as `pending`, keyed by its decision id together with a digest
   of its text. A human reads each one and sets its verdict to `good`, `bad`,
   or `deferred` with a `revisit` version, then commits. The assessor is the
   author of the commit that wrote the verdict, taken from `git blame`, never
   from the file itself. While any comment is pending, the report is invalid
   and `canon check` says so. A comment whose text changes after its verdict
   is pending again.
8. **The name says what; the comment says why.** A unit's name is its What
   and states the fact it establishes or the thing it does, in full words:
   a test is named for the property it verifies, such as
   `verifyThatGsonPackagesAreOnlyExportedButNotOpenedForReflection`, not
   `testReflectionInternalField`. Its canonical comment is its Why and says
   why that fact must hold, citing the requirement or decision that records
   the reason. A comment that restates the name, such as "Verifies that X"
   above a unit that verifies X, fulfils no purpose the name does not, and is
   vetted `bad`. `canon` cannot judge this; the vetting human does.
9. **Canonical material is signed off by whoever did it.** A canonical
   comment, a decision in the ledger, and a reference in the registry each
   have an entry in `canonical_vetting.yaml`, and none of them counts until
   its verdict is set. Whether the material says something true is not a
   question a program can decide, which is Rice's theorem applied to
   documentation, so the sign-off is the evidence. `canon` does not test who
   signed; it records it: the author of the commit that last touched the
   verdict line, from `git blame`, and the co-authors that commit names in
   its trailers. An edit to signed material makes its verdict stale, and the
   report is invalid while anything is pending.

## What documentation must answer

Canon treats a codebase as having to answer six questions. Each has one
designated home. `canon` extracts the answers from code, emits them as a
structured machine-readable model, generates documentation from that model,
checks that code and documentation agree, and enforces the standard.

| Question | Answered by |
|----------|-------------|
| Why?     | Comments. A comment gives a reason or points at resource material such as an article or reference paper. |
| Who?     | Git. |
| What?    | Names in the code or architecture, following the CALM architecture. |
| When?    | Git together with increasing version numbers. |
| How?     | Bodies in the code or architecture. |
| Where?   | Package, namespace, file, and similar location markers. |

## Canonical comments

A canonical comment is a comment whose structure a grammar recognises, so that
`canon` can parse out the "Why?" and its references from the comment, the
"What?" from the name of the code it attaches to, and the "How?" from the body.

There are three reasons for a canonical comment to exist, and a comment may
serve any of them at once:

- **Why.** A reason, in prose.
- **Ref.** A pointer into the registry, written `ref:KEY`, so that each
  article, paper, ticket, or requirement has a single canonical source.
- **License.** A pointer to a registry entry of kind `license`, written
  `license:KEY`. A comment that reads like a license or copyright notice but
  cites no license key is reported.

- A canonical comment is required on every public API, on anything used across
  modules, and on any non-trivial semantic property of the code that becomes
  part of the domain language. Elsewhere it is optional.
- A doc comment at the top of a file, on its first non-blank line, is the
  file's canonical comment and binds to the file unit. That is where a
  license notice lives.
- Where a comment may attach, and at what granularity, is defined by the
  canonically commented grammar of each language.

A canonically commented grammar says all of this in grammar form. A lexer
mode tokenizes the inside of a canonical comment into prose, `ref:KEY`, and
`license:KEY`; a parser rule alternative labeled `# kind` that contains a
`why` element makes each match of it a unit of that kind; and element labels
`why`, `what`, and `how` mark the comment, the name, and the body. The
comment is required when every `why` element of the alternative is
mandatory, or when the match contains an element labeled `required`, which
is how `public` makes a Java member's comment required. An element labeled
`orphan` is a comment the grammar accepts but binds to nothing, such as a
Javadoc comment after an annotation, and is reported. An element labeled
`marker` is an annotation or similar mark on the unit, whose text `canon`
reads to recognise tests. Alternative labels without a `why`, such as the
Java grammar's own expression labels, are inert. A unit's What is the text
of its `what` element; when the alternative itself holds several, they are
joined with a dot, as a Terraform resource is named `aws_vpc.main` by its
type and name. An element labeled `qualifier` on a node that is no unit is
the first part of the name of every unit below it, as the type of a resource
in Terraform's JSON syntax is a key above the resource's own. A `why`
element inside an optional or repeated block is optional. A `why` element that is a string rather than a
`canonicalComment`, such as the `description` of a Terraform variable, is
documentation written as data: its prose is the string without its quotes,
heredoc delimiters, or block scalar header, and its citations are read from
its text. `canon` generates the extraction parser from that grammar, so nothing
about a language's comment placement is written in Haskell. The ANTLR
meta-grammar, Java, Haskell, HCL, and Pulumi YAML are the languages done this
way.

### Tests

A test exists because of a requirement, so its Why is that requirement:
the canonical comment on a test cites it with `ref:KEY` against a registry
entry of kind `requirement`. `canon` recognises test units from the grammar's
`marker` labels together with a fixed table per language name, and marks them
`test: true` in the model. A test unit always requires a canonical comment,
whatever its visibility.

| Language | Recognised as a test |
|----------|----------------------|
| `java` | a method marked `@Test`, `@org.junit.Test`, `@org.junit.jupiter.api.Test`, `@ParameterizedTest`, `@RepeatedTest`, `@TestFactory`, or `@TestTemplate` (JUnit 4 and 5), or `@Property`, `@Example`, `@net.jqwik.api.Property`, or `@net.jqwik.api.Example` (jqwik), with or without arguments; or a method named `test*` under a `src/test` directory (JUnit 3). jetCheck has no annotations of its own, so its checks are recognised through the JUnit method they run in. |
| `erlang` | a function named `*_test` or `*_test_` (EUnit) |
| `clojure` | a `deftest` unit, or a definition named `*-test` |
| `prolog` | a clause named `test` (plunit) |
| `haskell` | a function named `prop_*` or `test_*` |
| `rust` | a function marked `#[test]`, `#[tokio::test]`, `#[async_std::test]`, `#[rstest]`, or `#[quickcheck]` |
| `csharp` | a method marked `[Fact]` or `[Theory]` (xUnit), `[Test]`, `[TestCase]`, or `[TestCaseSource]` (NUnit), or `[TestMethod]` or `[DataTestMethod]` (MSTest), bare or qualified with its namespace, with or without arguments |
| `fsharp` | a function or member marked `[<Fact>]`, `[<Theory>]`, `[<Test>]`, `[<TestCase>]`, `[<TestCaseSource>]`, or `[<Property>]` (FsCheck), bare or qualified; or a function or value marked `[<Tests>]`, the test list Expecto runs, whose `testCase` and `testProperty` entries are expressions rather than declarations |
| `elixir` | a unit of kind `test`, which the Elixir profile makes of ExUnit's `test "name"` and StreamData's `property "name"` calls |
| `gleam` | a function named `*_test` (gleeunit) |
| `hcl` | a `run` block of a Terraform test file (`terraform test`) |

Two findings fail `canon check`: a commented test whose comment cites no
requirement, and a requirement in the registry that no test in the project
cites. A test with no comment at all is reported as a missing canonical
comment, not twice.

### Vetting

When `canon` is introduced to an existing codebase, its comments were written
without `canon` and may or may not answer Why. Rule 7 says none of them
counts until a human has read it. The flow is:

1. `canon ingest` extracts the project and writes `canonical_vetting.yaml`,
   one entry per piece of canonical material, with the verdict `pending` and
   a digest of what it says: a comment is keyed by its decision id and
   digests its text, a ledger entry is keyed `ledger/KEY` and digests
   everything it says, and a registry entry is keyed `registry/KEY` and
   digests its kind, title, and locator. Running it again adds only entries
   that are missing.
2. `canon vet` lists every comment that needs a verdict, with its location
   and its text, so a reviewer can work through them. It also lists verdicts
   that have gone stale because the comment changed, deferrals past their
   revisit version, and verdicts whose comment no longer exists.
3. The reviewer edits the entry's `verdict` to `good`, `bad`, or `deferred`,
   adds a `revisit` version to a deferral and optionally a `note`, and
   commits. Nothing in the file names the reviewer: `canon` reads the author
   of the commit that last touched the `verdict` line with `git blame`, and
   the model records that person, the time, the commit, and the commit's
   co-authors as the decision's `vetting` answer with git evidence.
   `canon decisions` shows the same sign-off after each ledger entry. An
   uncommitted verdict has no signer yet, and `canon check` says so
   informationally.
4. `canon check` fails on every pending, stale, or bad comment, decision, or
   reference and on a deferral without a revisit version or past it, reports
   a deferral within its window informationally, and ends with `report
   invalid: N pieces of canonical material pending sign-off` while any are
   pending.

A `bad` comment is a liar's comment: the fix is to rewrite it, which changes
its digest and makes it pending, so the rewrite is vetted in turn. Once the
file exists, a new comment without an entry is pending too, so the author of
a new comment adds its `good` entry in the same commit and is thereby its
assessor.

This repository's own Haskell code follows the same rule through the Haskell
dialect: a Haddock comment in `-- |` or `{-| -}` form before every exported
unit and before every `module` keyword, and no other comments. Languages whose
dialect grammars do not exist yet fall back to the provisional line-adjacency
rule recorded in `to_be_removed/provisional_canonical_comment_syntax.md`: a
doc comment on the line directly above a unit named by the language profile
is its canonical comment.

An element labeled `export` marks an entry of a module's export list. A
dialect that labels exports opts into the export rule: a named unit requires
a comment when its name is exported, is listed under its parent's entry, or
its parent is exported with `(..)`; when the file has no export list, every
unit with a plain name requires one. An instance's What is its head, not a
name, so an instance never requires a comment by this rule.

## The model

`canon` emits a model of a codebase as YAML with alphabetically ordered keys
and a `schemaVersion`. The model has two kinds of entity, linked by identity:

- A **code unit** is a node in a tree of facts derived from the code. It has a
  stable, path-based id such as
  `antlr4/grammars/antlr4/ANTLRv4Parser.g4/grammarDefinition/ANTLRv4Parser/parserRule/grammarSpec`, and
  answers What (name and kind), How (body), and Where (path, span, and the
  chain of enclosing units). When git is available it also answers Who
  (authors and committers with their commits) and When (first and last change,
  and the version that introduced it). Each unit records whether the language
  requires a canonical comment on it and whether it is a test.
- A **decision** is a Why bound to one or more code units by id. Its text and
  cited reference keys come from the canonical comment, and its Where is the
  comment's own location. One Why can cover several units, and one unit can
  serve several decisions. A decision is to code what an architecture decision
  record is to architecture.

Every answer carries **evidence** of how it is known: derived from git,
derived from the parse, verified by a named property, test, mutation run, or
decision coverage, or asserted by a human in a comment. Checks compare what is
asserted against what is derived.

`canon check` reports findings: a cited key missing from the registry, a
decision naming a unit that no longer exists, a required unit with no
canonical comment, a doc comment attached to nothing, and git being
unavailable.

## Decisions

`canonical_decisions.yaml` is the ledger of decisions. Each entry has a
`status`, a `question`, the version it was `opened` in, and then either a
`revisit` version while open, an `answer` and a `decided` version once
decided, or the key it is superseded `by`. It may cite registry `refs` and
name the code `units` it concerns. `canon decisions` prints the ledger with
open entries first, ordered by revisit version, so the next review is always
at the top.

`canon check` cannot decide whether a question is still open, so it checks
what it can and forces the review at the right moment: an open decision at or
past its revisit version fails the check; a superseded decision whose
successor is not decided fails; a decision key that is also a registry key
fails; a unit named by a decision that the model does not contain fails. Two
findings are informational and do not fail the check: a decided decision that
no comment cites, which stays informational until Haskell code units exist,
and a comment citing a decision that is still open, which is how code is tied
to the ambiguity it depends on.

## Languages and sample projects

Any language with a grammar `canon` can interpret becomes a language `canon`
models. A project's `canon.yaml` declares one under `languages`, keyed by
name, with the file `extensions` it owns or the `files` it owns by name
pattern, such as `Pulumi.*.yaml`, which win over any profile's extensions,
the `grammar` file or the `lexer`
and `parser` pair, the `start` rule, the comment syntax (`line`, `blockOpen`,
`blockClose`, and the `strings` whose contents are not comments), and the
`units`: which parse-tree rules are code units, their `kind`, where their
`name` comes from (the nth token of a type, or the text of a child rule),
whether a canonical comment is `required`, and optionally a `firstToken`
constraint so that, for example, only Clojure lists beginning with `defn`
count. A language that tells doc comments from plain ones lists their
openers under `comments`: with `outerDoc` given, only a comment opening with
one binds to the unit below it, and a plain comment is neither a Why nor an
orphan; a comment opening with one of `innerDoc` binds to the innermost unit
that encloses it, or to the file, as Rust's `//!` documents its module. An
opener followed by a slash, or one ending in a star followed by another, opens
a plain comment, so `////` is not documentation unless a profile names it as
an opener, as Gleam's does. With outer openers given, an outer doc comment on
the first line of a file documents the item below it rather than the file. A
unit is taken to start above the lines directly over it that hold nothing a
reader of the documentation sees, so they do not part a doc comment from its
unit: with outer openers given, lines held by a plain comment that starts its
line; lines opening with one of `directives`, such as C#'s and F#'s `#`; and,
with `directives` given, the lines of an `#if` branch canon does not read,
where a comment binds to nothing and is no orphan. A language that writes
documentation as code lists `docAttributes`: an attribute such as Elixir's
`@doc` followed by a string, or by a sigil and a string, is scanned as a
comment running to the end of the string, its body is the string's contents,
and its name is matched against `outerDoc` and `innerDoc` like any opener; a
string delimiter of three or more characters, such as a heredoc's, may span
lines. Several unit rules may name one parse rule, told apart by
`firstToken`, and a unit rule with `mergeClauses: true` makes adjacent matches
with one name a single unit, as the clauses of an Elixir function are one
function, unless a doc comment directly above a later clause starts a unit of
its own. A unit's rule may leave its comment optional and the grammar still
require it: a unit whose node holds an element labeled `required`, as the C#
grammar labels `public`, requires a comment, and a unit whose rule requires
one does not when its node holds an element labeled `optional`, as the F#
grammar labels `private`. Unit ids are the language, the file path, and then
kind and name at each level of nesting; a repeated name in one scope gets an
ordinal suffix.

A directory containing its own `canon.yaml` is a nested project. The walk
stops there: `canon check` in the enclosing project does not look inside it,
and `canon files` lists it as a nested project. Checking it is a separate
run from its own directory, with its own configuration, registry, ledger,
vetting file, and ignore list, so one repository can hold many projects and
each answers for itself. A project whose sources live elsewhere, such as a
git submodule, sets `root` to that directory.

`lang_samples/` holds real projects in other languages, each a nested project
whose sources are a submodule under `source` (vendored, for the small Rust,
C#, F#, Elixir, Gleam, HCL, and Pulumi YAML samples) and whose canon files sit
beside it. Their grammars are vendored under `grammars/<lang>/` from
grammars-v4, with a `canonically_commented/` dialect where one exists and an
empty husk where it does not. `canon check` at the repository root checks
canon itself and leaves the samples alone; checking a sample is its own run,
from its directory, or with `stack exec --cwd lang_samples/<sample> canon --
check` from the root. The samples are upstream code that is not canonically
commented, so those checks fail, and that is the truth they exist to show:
every function without a canonical comment is a finding, and every file the
upstream grammar cannot parse is one too. Run `git submodule update --init`
after cloning to fetch them.

| Sample | Language | Grammar |
|--------|----------|---------|
| `lang_samples/erlang-recon` | Erlang | `grammars/erlang/Erlang.g4` |
| `lang_samples/clojure-hiccup` | Clojure | `grammars/clojure/Clojure.g4` |
| `lang_samples/prolog-marelle` | Prolog | `grammars/prolog/prolog.g4` |
| `lang_samples/haskell-tetris` | Haskell | `grammars/haskell/canonically_commented/HaskellLexer.g4` and `HaskellParser.g4` |
| `lang_samples/java-commons-lang` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |
| `lang_samples/java-joda-time` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |
| `lang_samples/java-gson` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |
| `lang_samples/rust-scopeguard` | Rust | `grammars/rust/RustLexer.g4` and `RustParser.g4` |
| `lang_samples/csharp-guardclauses` | C# | `grammars/csharp/CSharpLexer.g4` and `CSharpParser.g4` |
| `lang_samples/fsharp-giraffe-viewengine` | F# | `grammars/fsharp/FSharpLexer.g4` and `FSharpParser.g4` |
| `lang_samples/elixir-jason` | Elixir | `grammars/elixir/ElixirLexer.g4` and `ElixirParser.g4` |
| `lang_samples/gleam-stdlib` | Gleam | `grammars/gleam/GleamLexer.g4` and `GleamParser.g4` |
| `lang_samples/hcl-terraform-aws-key-pair` | HCL | `grammars/hcl/canonically_commented/HCLLexer.g4` and `HCLParser.g4` |
| `lang_samples/pulumi-yaml-examples` | Pulumi YAML | `grammars/yaml/canonically_commented/YAMLLexer.g4` and `YAMLParser.g4` |

The Rust sample is scopeguard 1.2.0, one source file, vendored under
`source/` with its MIT and Apache-2.0 licenses instead of a submodule. Its
`canon.yaml` holds the Rust profile a Rust project can copy, with the
`lexer` and `parser` paths pointing at wherever the Rust grammar lives:

```yaml
languages:
  rust:
    extensions: [.rs]
    lexer: ../../grammars/rust/RustLexer.g4
    parser: ../../grammars/rust/RustParser.g4
    start: crate
    comments:
      line: "//"
      blockOpen: "/*"
      blockClose: "*/"
      outerDoc: ["///", "/**"]
      innerDoc: ["//!", "/*!"]
      strings: ["\""]
    units:
      - {rule: function_, kind: function, name: {rule: identifier}, required: true}
      - {rule: structStruct, kind: struct, name: {rule: identifier}, required: true}
      - {rule: tupleStruct, kind: struct, name: {rule: identifier}, required: true}
      - {rule: enumeration, kind: enum, name: {rule: identifier}, required: true}
      - {rule: union_, kind: union, name: {rule: identifier}, required: true}
      - {rule: trait_, kind: trait, name: {rule: identifier}, required: true}
      - {rule: macroRulesDefinition, kind: macro, name: {rule: identifier}, required: true}
      - {rule: typeAlias, kind: type, name: {rule: identifier}, required: false}
      - {rule: constantItem, kind: const, name: {rule: identifier}, required: false}
      - {rule: staticItem, kind: static, name: {rule: identifier}, required: false}
      - {rule: inherentImpl, kind: impl, name: {rule: type_}, required: false}
      - {rule: traitImpl, kind: impl, name: {rule: type_}, required: false}
      - {rule: module, kind: module, name: {rule: identifier}, required: false}
```

The profile cannot see visibility, so functions, structs, enums, unions,
traits, and macros require a comment whether or not they are `pub`, and the
other kinds may have one. An impl is named by its self type, so the impls of
one type are told apart by ordinal.

The C# sample is Ardalis.GuardClauses, its library sources (without the
vendored JetBrains annotations) and one xUnit test file, vendored under
`source/` with its MIT license. Its `canon.yaml` holds the C# profile a C#
project can copy:

```yaml
languages:
  csharp:
    extensions: [.cs]
    lexer: ../../grammars/csharp/CSharpLexer.g4
    parser: ../../grammars/csharp/CSharpParser.g4
    start: compilation_unit
    comments:
      line: "//"
      blockOpen: "/*"
      blockClose: "*/"
      outerDoc: ["///", "/**"]
      directives: ["#"]
      strings: ["\""]
    units:
      - {rule: namespace_declaration, kind: namespace, name: {rule: qualified_identifier}, required: false}
      - {rule: file_scoped_namespace_declaration, kind: namespace, name: {rule: qualified_identifier}, required: false}
      - {rule: class_definition, kind: class, name: {rule: identifier}, required: false}
      - {rule: struct_definition, kind: struct, name: {rule: identifier}, required: false}
      - {rule: interface_definition, kind: interface, name: {rule: identifier}, required: false}
      - {rule: enum_definition, kind: enum, name: {rule: identifier}, required: false}
      - {rule: record_definition, kind: record, name: {rule: identifier}, required: false}
      - {rule: delegate_definition, kind: delegate, name: {rule: identifier}, required: false}
      - {rule: method_declaration, kind: method, name: {rule: method_member_name}, required: false}
      - {rule: constructor_declaration, kind: constructor, name: {rule: identifier}, required: false}
      - {rule: destructor_definition, kind: destructor, name: {rule: identifier}, required: false}
      - {rule: property_declaration, kind: property, name: {rule: member_name}, required: false}
      - {rule: indexer_declaration, kind: indexer, name: {token: THIS, index: 1}, required: false}
      - {rule: event_declaration, kind: event, name: {rule: member_name}, required: false}
      - {rule: operator_declaration, kind: operator, name: {rule: overloadable_operator}, required: false}
      - {rule: conversion_operator_declaration, kind: operator, name: {rule: type_}, required: false}
      - {rule: field_declaration, kind: field, name: {rule: identifier}, required: false}
      - {rule: constant_declaration, kind: constant, name: {rule: identifier}, required: false}
      - {rule: enum_member_declaration, kind: member, name: {rule: identifier}, required: false}
      - {rule: extension_declaration, kind: extension, name: {rule: type_}, required: false}
```

No C# unit requires a comment by its rule; the grammar labels `public` and
`protected` `required`, so a type or member visible outside its assembly
requires one, as the compiler's CS1591 warning asks, and a test always does.
A member of an interface is public without saying so, and requires a comment
only when it says so.

The F# sample is Giraffe.ViewEngine, its two source files and its xUnit test
file, vendored under `source/` with its Apache-2.0 license. Its `canon.yaml`
holds the F# profile an F# project can copy:

```yaml
languages:
  fsharp:
    extensions: [.fs, .fsi, .fsx]
    lexer: ../../grammars/fsharp/FSharpLexer.g4
    parser: ../../grammars/fsharp/FSharpParser.g4
    start: file
    comments:
      line: "//"
      blockOpen: "(*"
      blockClose: "*)"
      outerDoc: ["///"]
      directives: ["#"]
      strings: ["\""]
    units:
      - {rule: namespaceDeclaration, kind: namespace, name: {rule: longIdentifier}, required: false}
      - {rule: topModule, kind: module, name: {rule: longIdentifier}, required: false}
      - {rule: nestedModule, kind: module, name: {rule: identifier}, required: false}
      - {rule: functionDefinition, kind: function, name: {rule: bindingName}, required: true}
      - {rule: andFunctionDefinition, kind: function, name: {rule: bindingName}, required: true}
      - {rule: valueDefinition, kind: value, name: {rule: bindingName}, required: false}
      - {rule: andValueDefinition, kind: value, name: {rule: bindingName}, required: false}
      - {rule: localFunctionDefinition, kind: function, name: {rule: bindingName}, required: false}
      - {rule: localValueDefinition, kind: value, name: {rule: bindingName}, required: false}
      - {rule: recordType, kind: record, name: {rule: typeName}, required: true}
      - {rule: unionType, kind: union, name: {rule: typeName}, required: true}
      - {rule: enumType, kind: enum, name: {rule: typeName}, required: true}
      - {rule: classType, kind: class, name: {rule: typeName}, required: true}
      - {rule: interfaceType, kind: interface, name: {rule: typeName}, required: true}
      - {rule: delegateType, kind: delegate, name: {rule: typeName}, required: true}
      - {rule: exceptionDefinition, kind: exception, name: {rule: identifier}, required: true}
      - {rule: abbreviationType, kind: abbreviation, name: {rule: typeName}, required: false}
      - {rule: typeExtension, kind: extension, name: {rule: typeName}, required: false}
      - {rule: abstractType, kind: type, name: {rule: typeName}, required: false}
      - {rule: memberDefinition, kind: member, name: {rule: memberName}, required: true}
      - {rule: abstractMemberDefinition, kind: member, name: {rule: memberName}, required: true}
      - {rule: constructorDefinition, kind: constructor, name: {token: NEW, index: 1}, required: false}
      - {rule: valDeclaration, kind: val, name: {rule: bindingName}, required: false}
      - {rule: recordField, kind: field, name: {rule: identifier}, required: false}
      - {rule: unionCase, kind: case, name: {rule: identifier}, required: false}
      - {rule: unionCaseOf, kind: case, name: {rule: identifier}, required: false}
      - {rule: enumCase, kind: case, name: {rule: identifier}, required: false}
```

F# declarations are public unless they say otherwise, so functions, types,
exceptions, and members require a comment by their rule, and the grammar
labels `private` and `internal` `optional`, which lifts the requirement from
what a file does not export. Values, abbreviations, fields, cases, `val`
declarations, the `let` bindings of a class, modules, and namespaces may have
a comment.

The Elixir sample is Jason 1.4.5's formatter and its tests, vendored under
`source/` with Jason's Apache-2.0 license. Elixir documents with attributes,
not comments: `@doc` and `@typedoc` document the definition below them and
its other attributes, such as `@spec`, and `@moduledoc` documents the module
around it, while a `#` comment documents nothing. Its `canon.yaml` holds the
Elixir profile:

```yaml
languages:
  elixir:
    extensions: [.ex, .exs]
    lexer: ../../grammars/elixir/ElixirLexer.g4
    parser: ../../grammars/elixir/ElixirParser.g4
    start: file
    comments:
      line: "#"
      outerDoc: ["@doc", "@typedoc"]
      innerDoc: ["@moduledoc"]
      docAttributes: ["@moduledoc", "@doc", "@typedoc"]
      strings: ["\"\"\"", "'''", "\"", "'"]
    units:
      - {rule: moduleDefinition, kind: module, name: {rule: moduleName}, required: true}
      - {rule: protocolDefinition, kind: protocol, name: {rule: moduleName}, required: true}
      - {rule: implementationDefinition, kind: impl, name: {rule: moduleName}, required: false}
      - {rule: publicFunction, kind: function, name: {rule: definitionName}, required: true, mergeClauses: true}
      - {rule: privateFunction, kind: function, name: {rule: definitionName}, required: false, mergeClauses: true}
      - {rule: publicMacro, kind: macro, name: {rule: definitionName}, required: true, mergeClauses: true}
      - {rule: privateMacro, kind: macro, name: {rule: definitionName}, required: false, mergeClauses: true}
      - {rule: publicGuard, kind: guard, name: {rule: definitionName}, required: true, mergeClauses: true}
      - {rule: privateGuard, kind: guard, name: {rule: definitionName}, required: false, mergeClauses: true}
      - {rule: delegateDefinition, kind: function, name: {rule: definitionName}, required: true, mergeClauses: true}
      - {rule: callbackDefinition, kind: callback, name: {rule: definitionName}, required: true, mergeClauses: true}
      - {rule: typeDefinition, kind: type, name: {rule: definitionName}, required: false}
      - {rule: structDefinition, kind: struct, name: {token: DEFSTRUCT}, required: false}
      - {rule: exceptionDefinition, kind: exception, name: {token: DEFEXCEPTION}, required: false}
      - {rule: namedBlock, kind: test, name: {rule: blockName}, firstToken: {token: TEST_MACRO, oneOf: [test, property]}}
      - {rule: namedBlock, kind: describe, name: {rule: blockName}, required: false, firstToken: {token: TEST_MACRO, oneOf: [describe]}}
```

Private definitions are told apart by their keyword, so `def` requires a
comment and `defp` may have one. A test is named by its string, and its
canonical comment is a `@doc` above it, which ExUnit compiles without
warning.

The Gleam sample is the standard library's `order` and `bytes_tree` modules
and `order`'s tests, vendored under `source/` with the library's Apache-2.0
licence. `///` documents the item below its attributes and `////` documents
the module. Its `canon.yaml` holds the Gleam profile:

```yaml
languages:
  gleam:
    extensions: [.gleam]
    lexer: ../../grammars/gleam/GleamLexer.g4
    parser: ../../grammars/gleam/GleamParser.g4
    start: module
    comments:
      line: "//"
      outerDoc: ["///"]
      innerDoc: ["////"]
      strings: ["\""]
    units:
      - {rule: publicFunction, kind: function, name: {rule: definitionName}, required: true}
      - {rule: privateFunction, kind: function, name: {rule: definitionName}, required: false}
      - {rule: publicType, kind: type, name: {rule: typeName}, required: true}
      - {rule: privateType, kind: type, name: {rule: typeName}, required: false}
      - {rule: constructor, kind: constructor, name: {rule: constructorName}, required: false}
      - {rule: publicConstant, kind: const, name: {rule: definitionName}, required: true}
      - {rule: privateConstant, kind: const, name: {rule: definitionName}, required: false}
      - {rule: field, kind: field, name: {rule: fieldName}, required: false}
```

The HCL sample is terraform-aws-key-pair 3.0.1, its root module, complete
example, and wrappers, vendored under `source/` with its Apache-2.0 license.
It is checked through the HCL dialect, which needs no `units` or `comments`,
since the grammar carries them. Its `canon.yaml` holds the profile a
Terraform project can copy:

```yaml
languages:
  hcl:
    extensions: [.tf, .tfvars, .hcl]
    files: ["*.tf.json", "*.tfvars.json"]
    lexer: ../../grammars/hcl/canonically_commented/HCLLexer.g4
    parser: ../../grammars/hcl/canonically_commented/HCLParser.g4
    start: configFile
```

Each top-level block is a unit named as Terraform addresses it, such as
`resource/aws_key_pair.this`, and each entry of a `locals` block is a unit of
kind `local`. An aliased provider is named by its alias too, as
`provider/aws.west`, and `moved`, `removed`, and `import` blocks by the
addresses they name. A comment directly above a block is its Why, and so is
the `description` of a variable or an output, which is how this module
documents every one of them. Variables and outputs require a Why; other blocks
may have one. A `.tf.json` file gives the same units with the same names,
with a `//` property as a block's Why.

The Pulumi YAML sample is the `Pulumi.yaml` programs of three Pulumi
examples, vendored under `source/` with the repository's Apache-2.0 license.
A Pulumi program is YAML, but not every YAML file is a Pulumi program, so the
profile owns its files by name:

```yaml
languages:
  pulumi:
    files: [Pulumi.yaml, Pulumi.yml, "Pulumi.*.yaml", "Pulumi.*.yml", Main.yaml, Main.yml]
    lexer: ../../grammars/yaml/canonically_commented/YAMLLexer.g4
    parser: ../../grammars/yaml/canonically_commented/YAMLParser.g4
    start: yamlFile
```

Each entry of a program's `resources`, `variables`, `outputs`, and `config`,
and of its `template` section's `config`, is a unit named by its key, without
quotes. A comment directly above an entry is its Why, and
so is the `description` of a config key. Outputs require a Why, and so does a
config key that declares a `type` or a `default`; the keys of a stack file,
which only set values, may have one. Pulumi programs in TypeScript, Python,
Go, C#, or Java are read through those languages' profiles.

The three Java samples are projects with a reputation for thorough Javadoc:
Apache Commons Lang, Joda-Time, and Gson. They are the first samples checked
through a canonically commented dialect rather than a profile with `units`,
and the first ingested under rule 7: each carries a `canonical_vetting.yaml`
in which every Javadoc comment is `pending`, so their reports are invalid
until a human has vetted them. Public members of classes and all members of
interfaces require a comment; non-public members may have one. Test methods
are public, so they count, and each sample's ledger records why they are
not exempt: a test exists because of a requirement, and its canonical
comment cites that requirement with `ref:KEY` against a registry entry of
kind `requirement`.

The Haskell grammar needs the layout rule, which upstream implements in a
Java base lexer that injects virtual braces and semicolons into the token
stream. `Canon.Antlr4.Lex.Haskell` is that base lexer ported to a lexer hook,
selected by the grammar's `superClass` option like the meta-grammar's own
adaptor. The port holds doc-comment tokens until the next code token has
produced its virtual braces and semicolons, so a comment never counts as the
first token of a line, and it closes implicit blocks when a `where` or a
closing brace starts a line at or left of the block's indentation, which the
upstream port left open. Two constructs stay out of reach because they need
the parse-error rule of the layout algorithm: a `case` whose alternatives end
at a closing bracket on the same line, and a `let` inside a comprehension.

Haskell is checked through its dialect in this repository's own `canon.yaml`,
so `canon check` at the root checks canon itself: `src`, `app`, `test`, and
the four grammars that carry canonical comments. Every one of canon's own
comments is recorded as pending in `canonical_vetting.yaml` until a human
vets it.

ANTLR grammar files are the first language `canon` models, through the
`antlr4` profile in this repository's `canon.yaml`, which names the
canonically commented meta-grammar. Each grammar definition is a unit, each
rule is a child unit, and each lexer mode groups its rules. Every parser rule
and every non-fragment lexer rule requires a canonical comment.

## Directory layout

```
canon/
├── README.md              # this file
├── CHANGELOG.md           # release history; required for Hackage-publishable projects
├── canon.yaml             # canon configuration
├── canonical_refs.yaml    # the reference registry
├── canonical_decisions.yaml  # the decision ledger
├── LICENSE
├── install_toolchain.sh   # installs the build toolchain
├── package.yaml           # hpack package definition; generates canon.cabal
├── stack.yaml             # stack snapshot and package list
├── Setup.hs
├── app/
│   └── Main.hs            # executable entry point
├── src/
│   ├── Canon.hs           # command line: version, model, check
│   ├── Canon/Span.hs      # positions and spans shared by every language
│   ├── Canon/Model.hs     # the canonical model root and its parts under Canon/Model/
│   ├── Canon/Model/       # ids, evidence, answers, units, decisions, YAML, findings, checks
│   ├── Canon/Git/         # commits, log and blame parsing, the git provider and its shell implementation
│   ├── Canon/Registry.hs  # canonical_refs.yaml
│   ├── Canon/Decisions.hs # canonical_decisions.yaml
│   ├── Canon/Vetting.hs   # canonical_vetting.yaml: verdicts, digests, assessors from git blame
│   ├── Canon/Version.hs   # semantic versions and their precedence
│   ├── Canon/Ignore.hs    # gitignore-style patterns
│   ├── Canon/Walk.hs      # finds supported files and nested projects under a directory
│   ├── Canon/Project.hs   # a project: its config, registry, ledger, files, and checks
│   ├── Canon/Cache.hs     # content-addressed cache of extractions under .canon-cache/
│   ├── Canon/Git/Fill.hs  # Who and When from one git blame per file
│   ├── Canon/Profile.hs   # language profiles declared in canon.yaml
│   ├── Canon/CommentScan.hs  # comments by a profile's syntax
│   ├── Canon/Preprocessor.hs  # the branch of each #if canon reads, for C# and F#
│   ├── Canon/Extract/Grammar.hs  # builds the model of any file through its language profile
│   ├── Canon/Config.hs    # canon.yaml
│   ├── Canon/Attach.hs    # binds a comment to the unit directly below it
│   ├── Canon/CanonicalComment.hs  # comment body normalisation and key extraction
│   └── Canon/Antlr4/      # reads .g4 grammars into a queryable representation
│       ├── Syntax.hs      # the grammar representation
│       ├── Lexical.hs     # scanners for literals, actions, arguments, char sets, comments
│       ├── Escape.hs      # decoding and encoding of literal escapes
│       ├── Grammar.hs     # the scannerless grammar record on grammatical-parsers
│       ├── Comment.hs     # comments with their spans
│       ├── Read.hs        # reads a file into a grammar plus its comments
│       ├── Pretty.hs      # prints a grammar back to .g4 text
│       ├── Query.hs       # rules, tokens, modes, references, and well-formedness
│       └── RuleGraph.hs   # reference graph, nullability, left recursion, reachability
├── test/
│   ├── Spec.hs            # tasty entry point
│   └── Canon/Antlr4/      # hedgehog generators and properties per module
├── lang_samples/          # nested sample projects in other languages, sources as submodules
│   └── <sample>/
│       ├── canon.yaml     # root: source, plus the language profile
│       ├── canonical_refs.yaml
│       ├── canonical_decisions.yaml
│       └── source/        # the upstream project, a git submodule
├── grammars/              # language grammars canon uses to extract meaning from code
│   ├── antlr4/            # ANTLR's own meta-grammar, which canon reads first
│   └── <lang>/
│       ├── <grammar files>
│       └── canonically_commented/
│           └── <grammar files>
├── to_be_removed/         # records without a canonical place yet, then deletion
└── sample_projects/       # sample projects, each with its own README.md
    └── <project>/
        └── README.md      # the only markdown file in that project
```

### `grammars/`

Holds one subdirectory per language that `canon` can read. Each language
directory contains two grammars:

- The grammar files at the top of the directory are the grammar of the
  language itself, with its rules as
  [grammars-v4](https://github.com/antlr/grammars-v4) publishes them, and
  with a canonical comment on every unit the language requires one on. They
  are canonically commented code in the language of ANTLR grammars.
- `canonically_commented/` contains the plain grammar plus the rules that
  define canonical comments and locate the answers: the comment lexer mode,
  the `canonicalComment` rule, and the labeled alternatives that name unit
  kinds and mark `why`, `what`, and `how`. `canon` generates the parser that
  slurps the five W's and the H out of a file from this grammar. Code that is
  valid in the language may not be valid canonically commented code.

`canon` consumes the canonically commented grammar by interpreting it: the
`Canon.Antlr4.Lex` and `Canon.Antlr4.Parse` modules turn any grammar value
into a running lexer and parser, so a `.g4` file under `grammars/` becomes a
parser without code generation. The upstream grammar is kept beside it as the
source it is derived from. The parser memoises each rule and each repeated
element by position, so a file that does not parse fails as fast as one that
does parses. Lexer actions that upstream grammars delegate to a
target-language base class are resolved through a hook interface keyed by the
grammar's `superClass` option; the ANTLR meta-grammar's own adaptor is the
first hook implementation.

`grammars/antlr4/` holds ANTLR's own meta-grammar, `ANTLRv4Lexer.g4` and
`ANTLRv4Parser.g4`, with the rules as grammars-v4 publishes them and a
canonical comment on every parser rule and non-fragment lexer rule, plus the
BSD notice as the file-level comment. The `Canon.Antlr4` modules read any
`.g4` file into a grammar value, and the test suite checks that both of these
files read with their known structure.

`grammars/antlr4/canonically_commented/` holds the same grammar plus the
extraction rules. The lexer turns `/**` into a `DocOpen` token that enters a
`DocComment` mode, where `ref:KEY` and `license:KEY` are their own tokens and
prose is words and punctuation, until `*/` leaves the mode. The parser adds
`canonicalComment` and `docPart`, and labels the unit alternatives:
`grammarSpec` is a `grammarDefinition`, `parserRuleSpec` a `parserRule`,
`lexerRuleSpec` a `fragmentRule` or a `lexerRule`, and `modeSpec` a
`lexerMode`, each with `why`, `what`, and where it differs from the whole
node `how` marked on its elements. A `parserRule` and a `lexerRule` require
the comment; the others allow it. Every rule in both files carries its own
comment, so the dialect parses its own grammars, and the test suite checks
that it does and that it rejects a grammar without canonical comments.

`grammars/haskell/` holds the Haskell grammar from grammars-v4 with a
canonical comment on every rule and four fixes, each cited in the ledger:
standard character and string literals with escapes, contextual keywords and
pragma names accepted as identifiers, and the two layout cases above. Under
`canonically_commented/` the dialect sends `-- |` and `{-|` into `DocLine`
and `DocBlock` lexer modes, keeps the line break that ends a doc line as a
`NEWLINE` carrying the layout action, inlines each unit-bearing top-level
form as a labeled alternative, labels export-list entries `export`, and
absorbs a doc comment on a local binding, instance method, or constructor as
an `orphan`. Two `-- |` comments on consecutive lines merge, as Haddock also
reads them.

`grammars/java/` holds the Java grammar from grammars-v4 and, under
`canonically_commented/`, its dialect: the same `DocComment` lexer mode,
`canonicalComment` and `docPart` rules, and labeled alternatives on
`compilationUnit` (`# package`), `typeDeclaration`, `classBodyDeclaration`,
`interfaceBodyDeclaration`, `annotationTypeElementDeclaration`,
`enumConstant`, and `compactConstructorDeclaration` with `why`, `what`, and
`how` elements. `required = PUBLIC` among a member's modifiers makes its
comment required, interface members are `required` outright, and the
`orphan` label accepts a doc comment after an annotation, before an
initializer, before a local declaration, or one of two in a row, and reports
it, and the `marker` label on annotations lets `canon` recognise tests. The plain Java grammar carries a canonical comment on every parser rule
and non-fragment lexer rule and cites its BSD license in the header, the
dialect carries the same comments extended where a rule gained unit labels,
and both are checked at the root like the meta-grammar.

`grammars/rust/` holds the Rust grammar from grammars-v4 with an empty
`canonically_commented/` husk. canon has no port of its base classes, so the
predicates that called into them are replaced in the grammar itself; outer
attributes and visibility move into each kind of item, so an item's node
starts at its first attribute and the doc comment above binds to it, with
each attribute labeled `marker`; and macro token trees take one token at a
time, which keeps macro bodies from parsing in exponential time. Each change
is marked `// canon:` in the grammar, listed in `grammars/rust/README.md`,
and recorded in the ledger.

`grammars/csharp/` holds the C# 7 grammar from grammars-v4 with an empty
`canonically_commented/` husk. Upstream leaves interpolated strings and the
preprocessor to a `CSharpLexerBase` class, which canon ports as a lexer hook
selected by the grammar's `superClass` option: the hook tracks the braces of
each interpolation hole, and reads one branch of each `#if`, the first whose
condition holds for some choice of the symbols the file does not define, so
the code canon reads is code some build compiles. Attributes and modifiers
move into each kind of type and member, as Rust's do, with `public` and
`protected` labeled `required` and each attribute labeled `marker`, and C# 8 to
14 syntax is added. Each change is marked `// canon:` in the grammar, listed in
`grammars/csharp/README.md`, and recorded in the ledger.

`grammars/fsharp/` holds an F# grammar written for canon, since grammars-v4
has none, with an empty `canonically_commented/` husk. It parses the
declarations that carry documentation and reads expressions, patterns, and
types as runs of tokens. F# ends a declaration by indentation, so the
grammar's `superClass` selects a lexer hook that turns the offside rule into
`INDENT`, `DEDENT`, and `NEWLINE` tokens outside brackets, as Python's
tokenizer does, and reads `#if` as the C# hook does. What it reads and what it
leaves out is listed in `grammars/fsharp/README.md` and recorded in the
ledger.

`grammars/elixir/` and `grammars/gleam/` hold grammars written for canon, with
empty `canonically_commented/` husks. The grammars-v4 Elixir grammar parsed
71 of 308 files from Jason, Plug, and Phoenix in canon's interpreter, and no
ANTLR grammar for Gleam exists. The Elixir grammar is structural: statements
end at newlines unless an operator continues them, expressions are chains of
operands without precedence, strings and heredocs have lexer modes whose
interpolations nest, and each kind of definition takes the module attributes
directly above it, labeled `marker`. The Gleam grammar reads a module's items
with their attributes, labeled `marker`, and reads function bodies as
balanced brackets. Both parse every file of their test corpora: the 308
Elixir files, and the 116 modules of the Gleam stdlib, gleam_json, gleam_otp,
and wisp. Each directory's `README.md` gives the design and the known
limitations, and the ledger records them as `DEC-elixir-grammar` and
`DEC-gleam-grammar`.

`grammars/hcl/` holds an HCL grammar written for canon from the HCL native
syntax specification, since the grammars-v4 Terraform grammar parsed 344 of
554 real Terraform files and no `.tfvars` or `.hcl` file. HCL ends an
attribute at a line break except inside brackets, so the grammar's
`superClass` selects a lexer hook that hides line breaks there and closes each
heredoc at its delimiter line. Under `canonically_commented/` every comment is
a canonical comment, because HCL has no other kind, and the hook hides a
comment after code or inside brackets and joins a comment to the line
directly below it, so only a comment directly above a block binds to it. The
dialect labels each top-level block a unit, joins its labels into its What,
reads the `description` of a variable or an output as a Why, and labels
`variable` and `output` `required`. A file in Terraform's JSON syntax gives the
same units, with its `//` properties as Whys. `grammars/hcl/README.md` gives the design
and the known limitations, and the ledger records them as `DEC-hcl-grammar`.

`grammars/yaml/` holds a grammar of the block structure of YAML 1.2 written
for canon, since grammars-v4 has none. A lexer hook turns indentation into
`INDENT`, `DEDENT`, and `NEWLINE` tokens as the F# hook does and ends each
block scalar where its lines stop being indented past its key. Under
`canonically_commented/` the dialect reads a Pulumi program: the hook emits
each comment just before the code directly below it, and each entry of the
`resources`, `variables`, `outputs`, and `config` sections, and of the
`template` section's `config`, is a unit with that comment, or a config key's
`description`, as its Why.
`grammars/yaml/README.md` gives the design and the known limitations, and the
ledger records them as `DEC-pulumi-yaml-grammar`.

The other language directories hold their upstream grammars with an empty
`canonically_commented/` husk, and their samples use the line-adjacency
profile path until a dialect exists.

### `to_be_removed/`

Holds every record about this repository that does not yet have a canonical
place: legacy documentation, decisions and their reasoning, and raw source
material such as interview answers. Each file names what it is waiting for.
When every item has been folded into canonical form, this directory is
deleted.

### `sample_projects/`

Holds sample projects that demonstrate the `canon` layout. Each sample project
is a subdirectory with its own `README.md` at its root, plus a `CHANGELOG.md`
if it can be published to Hackage, and no other markdown files. This directory is currently a husk with no sample projects in it.

## Toolchain

```
./install_toolchain.sh
```

Installs the Xcode command-line tools and Haskell Stack.

## Building and running

```
stack build
stack test
stack test --ta '-p property'
stack exec canon -- version
stack exec canon -- model grammars/antlr4/ANTLRv4Parser.g4
stack exec canon -- check grammars/antlr4/ANTLRv4Parser.g4
stack exec canon -- parse grammars/antlr4/canonically_commented/ANTLRv4Lexer.g4 grammars/antlr4/canonically_commented/ANTLRv4Parser.g4 grammarSpec grammars/antlr4/canonically_commented/ANTLRv4Parser.g4
stack exec --cwd lang_samples/java-gson canon -- ingest
stack exec --cwd lang_samples/java-gson canon -- vet
```

`canon` is a command line tool. Running it with no arguments prints usage.
`canon model` writes the model of a file to standard output as YAML
and any extraction findings to standard error, using the language profile
that owns the file's extension and the project's vetting verdicts. `canon check` prints every
finding, one per line, and exits with status 1 if there are any. Both read
`canon.yaml` from the current directory when it exists. Who and When come from
`git` on the path; without a repository the model is still emitted, with those
answers empty and one finding saying so. `canon parse` interprets a lexer and
parser grammar pair, or one combined grammar, and prints the parse tree of a
file or the position where parsing fails.

Run with no path, or with a directory, `canon check` walks the tree and checks
every file of a supported type it finds, and `canon files` lists what that
walk would visit. Directories that never hold a project's own sources are
skipped by default: version control metadata, `node_modules`,
`bower_components`, `vendor`, `third_party`, Terraform's `.terraform` cache of
downloaded modules and providers, build outputs such as
`.stack-work`, `dist`, `dist-newstyle`, `target`, `build`, and `out`, Python
environments, and editor folders. `canon.yaml` adds patterns under `ignore`
in gitignore syntax: a bare name matches at any depth, a pattern containing a
slash is anchored at the project root, a trailing slash matches directories
only, `*` stays within one path segment, `**` spans segments, `?` and `[...]`
match single characters, and a later `!` pattern re-includes what an earlier
pattern excluded, unless a parent directory is excluded. This repository
ignores `grammars/*/*.g4` except the ANTLR meta-grammar and the Java grammar,
so that only grammars carrying canonical comments are checked.

`canon check` parses files concurrently, and caches each file's extraction
under `.canon-cache/` in the project directory, keyed by the file's content,
the grammar and profile it was parsed with, the git revision, the file's
own dirty state, the project's `git describe` output and tag list, the
version in `canon.yaml`, and canon's own version, so a second run re-reads
only what changed and nothing that reaches the model is left out of the key. The directory is ignored by the walk and by
git, and can be deleted at any time. Who and When come from one `git blame`
per file rather than one `git log` per unit.

`canon.yaml` names the registry under `registry` and the decision ledger
under `decisions`, both defaulting to the files at the project root. It may
name canonical dialect grammars under `canonical`, keyed by
language, each with a `lexer`, a `parser`, and a `start` rule. `canon check`
parses the checked file with the dialect named for its language and reports a
finding at the first token the dialect refuses.

Tests use tasty with hedgehog. Property-based tests are the primary tests and
live under the `property` group. Fixture checks against the vendored grammars
live under the `unit` group.
