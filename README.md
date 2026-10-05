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
2. **One `README.md` per project, at its root, and one `docs/` tree in the
   Folio.** Apart from `CHANGELOG.md` where rule 1 applies, the only markdown
   allowed outside `to_be_removed/` is `README.md` at the root of a given
   project and the pages under `docs/`, which Diátaxis splits into
   `docs/tutorials/`, `docs/how-to/`, `docs/reference/`, and
   `docs/explanation/`. A page is written in the Folio: front matter naming
   its `kind`, `id`, and `title`, prose that cites with `ref:KEY`, and fenced
   blocks that tangle to source with `canon tangle`, so a page can be the
   source of code and the code's Why at once. Every page is canonical
   material of kind `doc`, judged as a whole under `canonical_vetting/doc/`
   with the same words as a comment. A tutorial or how-to may name a video on
   the same topic, `video: KEY` against a registry entry of kind `video`; a
   video is a second medium for the same material, and nothing is raised when
   a page names none. For this repository, that is this file and `docs/`; for
   a sample project, `sample_projects/<project>/README.md`.
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
   `canon.yaml` is canon's configuration: the project version, the paths of
   the registry, the ledger, and the vetting directory, the languages, and
   the kinds of vetting rows other tools raise. `canonical_refs.yaml` is the reference registry, the single
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
7. **Existing comments are vetted before they count, in `canonical_vetting/`.**
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
   have an entry under `canonical_vetting/`, and none of them counts until
   its verdict is set. Whether the material says something true is not a
   question a program can decide, which is Rice's theorem applied to
   documentation, so the sign-off is the evidence. `canon` does not test who
   signed; it records it: the author of the commit that last touched the
   verdict line, from `git blame`, and the co-authors that commit names in
   its trailers. An edit to signed material makes its verdict stale, and the
   report is invalid while anything is pending.

10. **A subject may be exempt until a version, in `canonical_exemptions.yaml`.**
    A project just adopted owes more than anyone can pay at once. An entry
    names a subject, a path pattern in gitignore form or a key written in
    full, the kinds it covers, a reason, and the version to revisit by, and
    is signed by `git blame` like every row. `canon check` still raises the
    material and reports it as exempt rather than pending, so the debt is
    counted and not yet due, and fails once the project reaches the revisit
    version, as it does for an open decision.

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
reads to recognise tests. A unit found under an element labeled `inherited`
requires a comment when the unit around it does, unless its own node holds an
element labeled `optional`, which is how the items of a public Rust trait and
the members of a public C# interface require one. An element labeled
`optional` wins over one labeled `required` in the same node. An element
labeled `ordinal` stands for the `what` of a unit without a name, such as a
field of a Rust tuple struct, which is then named by its position among the
units of its kind in its parent. An element labeled `hidden` is a mark the
language uses to hide a unit from its documentation, such as Elixir's
`@doc false`: the unit and every unit inside it need no comment unless they
are tests, and the model records their requirement as `hidden`; a hidden mark
outside every unit hides the file. An element labeled `merge` makes adjacent
units of one rule, kind, and name a single unit, as the clauses of an Elixir
function are, unless a later one has a Why of its own. An element labeled
`file`, outside every unit, is part of the file's Why, and all of them are
joined, as Gleam joins its `////` comments. A unit's Why is the first `why`
element in its node outside the units nested in it, wherever the grammar puts
it, so an Elixir module's `@moduledoc` may sit among its statements; any
other `why` element is reported. An element labeled `arity` names the unit
`name/arity`, as Erlang names a function and Prolog a predicate: the arity is
the number of arguments when the element is a bracketed list, the number the
element holds, or else the number of rules among its children, and adjacent units so
named that share a kind and a name are one unit unless a later one has a Why of
its own, as the clauses of a predicate are one predicate. An `export` element
that holds a `what` and an `arity` element exports `name/arity`, as Prolog's
`name//N` exports the nonterminal named `name/N`. A `why` element that holds
`how` elements is the Why without them, the text on each side of one a
paragraph of its own, and a unit with several `how` elements has them all as
its How, as a Folio section's prose around its fenced blocks is its Why and the
blocks its How. A `why` element of
the start rule outside every unit is the file's Why, as Rust's `//!` at the top
of a file is. A unit's What is the text of its `what` element; when the
alternative itself holds several, they are joined with a dot, as a Terraform
resource is named `aws_vpc.main` by its type and name. An element labeled
`qualifier` on a node that is no unit is the first part of the name of every
unit below it, as the type of a resource in Terraform's JSON syntax is a key
above the resource's own. An element labeled `declarator` makes a unit of its
own of each name a declaration declares, named by the `what` element inside it,
with the declaration's kind, requirement, and Why, one decision binding them
all, as each name of a Groovy field is a field documented by the Groovydoc
above the declaration. A name written as one string literal, as a Spock
feature method's, is its contents without quotes or escapes, and a slash in it
is a division slash (∕), so the name stays one segment of the unit id; a test
is still told by the name as written. A `why` element inside an optional or repeated block
is optional. A `why` element that is data rather than a comment, such as the
`description` of a Terraform variable, is documentation written as data: its
prose is the string without its quotes, heredoc delimiters, or block scalar
header, and its citations are read from its text.
A doc comment may stand between any two tokens of a file its compiler
accepts, and no grammar can take it everywhere without reading every
expression differently, so a parser grammar names its comment rules in
`strayComment` options. Where a parse fails at a match of one of them, or
within three tokens after one ends, `canon` reads the file again without that
comment and reports it as an orphan, for as long as each round moves the
failure forward; a failure no such comment explains is reported where the
parse stopped. The Rust, C#, F#, Elixir, Gleam, Erlang, and Haskell dialects
name their comment rules, so a doc comment never fails their parse.
Alternative labels without a `why`, such as the Java grammar's own expression
labels, are inert. `canon` generates the extraction parser from that grammar,
so nothing about a language's comment placement is written in Haskell. The
ANTLR meta-grammar, Java, Haskell, Rust, C#, F#, Groovy, JavaScript,
TypeScript, Go, Python, Kotlin, Clojure, Prolog, Scala, Elixir, Gleam, Erlang,
HCL, Pulumi YAML, and the Folio have dialects.

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
| `erlang` | a function of arity 0 named `*_test` or `*_test_` (EUnit), as `name_test/0` |
| `clojure` | a `deftest` unit, or a definition named `*-test` |
| `prolog` | a clause named `test` (plunit), or a unit of kind `test`, which the Prolog dialect makes of a clause of `test/1` or `test/2` and names by the test's name |
| `haskell` | a function named `prop_*` or `test_*` |
| `rust` | a function marked `#[test]`, `#[tokio::test]`, `#[async_std::test]`, `#[rstest]`, or `#[quickcheck]` |
| `csharp` | a method marked `[Fact]` or `[Theory]` (xUnit), `[Test]`, `[TestCase]`, or `[TestCaseSource]` (NUnit), or `[TestMethod]` or `[DataTestMethod]` (MSTest), bare or qualified with its namespace, with or without arguments |
| `fsharp` | a function or member marked `[<Fact>]`, `[<Theory>]`, `[<Test>]`, `[<TestCase>]`, `[<TestCaseSource>]`, or `[<Property>]` (FsCheck), bare or qualified; or a function or value marked `[<Tests>]`, the test list Expecto runs, whose `testCase` and `testProperty` entries are expressions rather than declarations |
| `elixir` | a unit of kind `test`, which the Elixir profile makes of ExUnit's `test "name"` and StreamData's `property "name"` calls |
| `gleam` | a function named `*_test` (gleeunit) |
| `javascript`, `typescript` | any unit under a `test`, `tests`, or `__tests__` directory or in a `*.test.*` or `*.spec.*` file, since a test in these languages is a call rather than a declaration |
| `python` | a function named `test_*` or a class named `Test*` (pytest and unittest) |
| `go` | a function named `Test*`, `Benchmark*`, `Example*`, or `Fuzz*` in a `*_test.go` file |
| `kotlin` | a function marked `@Test`, `@kotlin.test.Test`, `@org.junit.Test`, or `@org.junit.jupiter.api.Test`, or any function under a `src/test` or `src/*Test` source set, since Kotlin test names are often backticked sentences |
| `groovy` | a method marked with one of the JUnit or jqwik annotations `java` lists, or a method named `test*` under a `src/test` directory (JUnit 3), as for `java`; or a method named by a string, as Spock writes a feature method such as `def 'adds two numbers'()`, under a `src/test` directory or in a `*Spec.groovy` file |
| `scala` | a method marked `@Test`, `@org.junit.Test`, `@org.junit.jupiter.api.Test`, `@ParameterizedTest`, `@RepeatedTest`, `@TestFactory`, or `@TestTemplate` (JUnit 4 and 5), with or without arguments; or any unit under a `src/test` or `test` directory or in a `*Suite.scala`, `*Spec.scala`, or `*Test.scala` file, since a munit, ScalaTest, or utest test is a `test("...")` call rather than a declaration |
| `hcl` | a `run` block of a Terraform test file (`terraform test`) |

Two findings fail `canon check`: a commented test whose comment cites no
requirement, and a requirement in the registry that no test in the project
cites. A test with no comment at all is reported as a missing canonical
comment, not twice.

### Vetting

When `canon` is introduced to an existing codebase, its comments were written
without `canon` and may or may not answer Why. Rule 7 says none of them
counts until a human has read it. The flow is:

1. `canon ingest` extracts the project and writes the `canonical_vetting/`
   directory, one entry per piece of canonical material, with the verdict
   `pending` and a digest of what it says: a comment is keyed by its decision
   id and digests its text, a ledger entry is keyed `ledger/KEY` and digests
   everything it says, and a registry entry is keyed `registry/KEY` and
   digests its kind, title, and locator. Running it again adds only entries
   that are missing.

   The directory holds a file per kind and subject, so a record sits beside
   the path it judges and a review tool can read and rewrite exactly the
   files `canon` checks. Comment verdicts mirror the source tree under
   `comment/`, so the comments of `src/Canon/Walk.hs` are judged in
   `canonical_vetting/comment/src/Canon/Walk.hs.yaml`; the ledger's verdicts
   are in `canonical_vetting/ledger/canonical_decisions.yaml` and the
   registry's in `canonical_vetting/registry/canonical_refs.yaml`. Every file
   keeps one key per line with the verdict on its own line, which is what
   `git blame` is asked about, and keys are written in full so a file reads
   alone. A `canonical_vetting.yaml` from before this layout is refused with
   the instruction to delete it and ingest again.

   Other tools raise other kinds of material, such as the surviving mutants
   that Rice's Tax asks a person to judge. A project declares each such kind
   in `canon.yaml` with its verdict words and what each does:

   ```yaml
   kinds:
     mutant:
       unreviewed: open
       logical-equivalency: closed
       inadequate-testing: work
       unnecessary-code: work
       needs-research: deferred
   ```

   `canon.yaml` may also carry a `runtime` section, which canon does not
   read, naming the test and mutation runtime whose artefacts the tax tools
   consume, and the `command` that produces them, so that every tool's
   parameters live in one file.

   A row of a declared kind is keyed `kind/id`, lives under
   `canonical_vetting/<kind>/`, and carries the kind's own word. `canon`
   counts a row whose word is `open` as pending, so the report is invalid
   while it stands, records the signer of the rest, and reports a kind or a
   word the declaration does not know. Raising the rows, keeping their
   digests fresh, and retiring the ones whose material is gone belong to the
   tool that owns the kind.
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
`name` comes from (the nth token of a type, the nth such token that is the
rule's own rather than a child rule's when `direct` is set, or the text of a
child rule),
whether a canonical comment is `required`, and optionally a `firstToken`
constraint so that, for example, only Clojure lists beginning with `defn`
count. A unit's `name` may also be `{ordinal: true}`, its position from zero
among the units of its rule in its parent, for a unit without a name of its
own, such as a field of a Rust tuple struct. A unit's name is its tokens run
together, with a hyphen where the source spaces a word from what follows, so a
unit id holds no space. A language that tells doc comments from plain ones lists their
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
where a comment binds to nothing and is no orphan. A file whose lexer reads
`#if`, as the C# and F# lexers do, is read once per build of a few that
together read every branch some build compiles: a build is an assignment of the
symbols the file's conditions name, and what each build reads is merged, units
and decisions by id, the first build's winning. A language that writes
documentation as code lists `docAttributes`: an attribute such as Elixir's
`@doc` followed by a string, or by a sigil and a string, is scanned as a
comment running to the end of the string, its body is the string's contents,
and its name is matched against `outerDoc` and `innerDoc` like any opener; a
string delimiter of three or more characters, such as a heredoc's, may span
lines. The string may follow an opening parenthesis, as in Erlang's
`-doc("...")`. Blank lines below a doc attribute do not part it from the unit
below, since Elixir and Erlang bind it to the next definition across them,
and a doc attribute directly above a unit marked hidden binds to nothing. A
language whose strings interpolate code names its `interpolation` opener and
closer, such as `["#{", "}"]`, so a quote inside an interpolation does not end
the string around it. With `joinAcrossBlankLines`, doc comments that open
alike and stand apart only by blank lines are one comment, and blank lines
below one do not part it from its unit. `hiddenTags`, such as EDoc's
`@private`, hide the unit a doc comment holding one documents. An element
labeled `arity` around a unit's arguments names the unit by name and arity,
such as Erlang's `info/2`. Several unit rules may name one parse rule, told apart by
`firstToken`, and a unit rule with `mergeClauses: true` makes adjacent matches
with one name a single unit, as the clauses of an Elixir function are one
function, unless a doc comment directly above a later clause starts a unit of
its own. A unit's rule may leave its comment optional and the grammar still
require it: a unit whose node holds an element labeled `required`, as the C#
grammar labels `public`, requires a comment, and a unit whose rule requires
one does not when its node holds an element labeled `optional`, as the F#
grammar labels `private`. A profile's `signatures` maps the extension of a
signature file to the extension of the implementation it declares, as F#'s
`.fsi` declares a `.fs`: when `canon check` reads both files of a name, a unit
of the implementation needs no comment, and a unit of the signature needs one
when the unit it declares would. Unit ids are the language, the file path, and then
kind and name at each level of nesting; a repeated name in one scope gets an
ordinal suffix.

A language named `calm` is read differently: its grammar is any JSON grammar,
and a CALM 1.2 architecture description parsed with it becomes a unit per
node, relationship, and flow, named by its `unique-id`, required, and with its
`description` as its Why, so an architecture is vetted like code. A
description with a repeated id, a dangling reference, an unknown node type,
or a schema other than CALM 1.2 is refused. Rice's Tax ships the JSON grammar;
canon ships none, since no language it targets is JSON.

A directory containing its own `canon.yaml` is a nested project. The walk
stops there: `canon check` in the enclosing project does not look inside it,
and `canon files` lists it as a nested project. Checking it is a separate
run from its own directory, with its own configuration, registry, ledger,
vetting file, and ignore list, so one repository can hold many projects and
each answers for itself. A project whose sources live elsewhere, such as a
git submodule, sets `root` to that directory.

`lang_samples/` holds real projects in other languages, each a nested project
whose sources are a submodule under `source` (vendored, for the small Rust,
C#, F#, Elixir, Gleam, Groovy, Scala, HCL, and Pulumi YAML samples) and whose canon files sit
beside it. Their grammars are vendored under `grammars/<lang>/` from
grammars-v4 or written for canon, each with a `canonically_commented/`
dialect. `canon check` at the repository root checks
canon itself and leaves the samples alone; checking a sample is its own run,
from its directory, or with `stack exec --cwd lang_samples/<sample> canon --
check` from the root. The samples are upstream code that is not canonically
commented, so those checks fail, and that is the truth they exist to show:
every function without a canonical comment is a finding, and every file the
upstream grammar cannot parse is one too. Run `git submodule update --init`
after cloning to fetch them.

The root `canon.yaml` pins the languages LawSpec targets under `parity`:
`current` for the targets LawSpec emits today and `planned` for those it is
to emit, among them the languages canon itself is written and documented in.
`canon` does not read the section; the `parity` group of the test suite holds
the repository to it. Every listed language has a grammar under `grammars/`,
a profile in the root `canon.yaml` or in a sample's, a `canonically_commented/`
dialect, and a sample: a project under `lang_samples/`, or canon itself for the
languages its own sources are written in. Every grammar directory belongs to a
listed language. A language whose missing pieces another branch delivers names
them under `pending`, and the suite fails both on a missing piece not named
there and on a named piece that exists, so the list says exactly what the
repository holds.

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
| `lang_samples/javascript-chalk` | JavaScript | `grammars/javascript/JavaScriptLexer.g4` and `JavaScriptParser.g4` |
| `lang_samples/typescript-ky` | TypeScript | `grammars/typescript/TypeScriptLexer.g4` and `TypeScriptParser.g4` |
| `lang_samples/python-itsdangerous` | Python | `grammars/python/Python3Lexer.g4` and `Python3Parser.g4` |
| `lang_samples/go-uuid` | Go | `grammars/golang/GoLexer.g4` and `GoParser.g4` |
| `lang_samples/kotlin-turbine` | Kotlin | `grammars/kotlin/KotlinLexer.g4`, `KotlinParser.g4`, and `UnicodeClasses.g4` |
| `lang_samples/groovy-spock-genesis` | Groovy | `grammars/groovy/GroovyLexer.g4` and `GroovyParser.g4` |
| `lang_samples/scala-iron` | Scala | `grammars/scala/ScalaLexer.g4` and `ScalaParser.g4` |
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
      - {rule: function_, kind: function, name: {rule: identifier}, required: false}
      - {rule: structStruct, kind: struct, name: {rule: identifier}, required: false}
      - {rule: tupleStruct, kind: struct, name: {rule: identifier}, required: false}
      - {rule: enumeration, kind: enum, name: {rule: identifier}, required: false}
      - {rule: union_, kind: union, name: {rule: identifier}, required: false}
      - {rule: trait_, kind: trait, name: {rule: identifier}, required: false}
      - {rule: macroRulesDefinition, kind: macro, name: {rule: identifier}, required: false}
      - {rule: typeAlias, kind: type, name: {rule: identifier}, required: false}
      - {rule: constantItem, kind: const, name: {rule: identifier}, required: false}
      - {rule: staticItem, kind: static, name: {rule: identifier}, required: false}
      - {rule: inherentImpl, kind: impl, name: {rule: type_}, required: false}
      - {rule: traitImpl, kind: impl, name: {rule: traitImplTarget}, required: false}
      - {rule: module, kind: module, name: {rule: identifier}, required: false}
      - {rule: enumItem, kind: variant, name: {rule: identifier}, required: false}
      - {rule: structField, kind: field, name: {rule: identifier}, required: false}
      - {rule: tupleField, kind: field, name: {ordinal: true}, required: false}
```

No Rust unit requires a comment by its rule. The grammar labels a bare `pub`
and `#[macro_export]` `required`, and the items of a trait and the variants of
an enum `inherited`, so what a crate exports requires a comment, as rustc's
`missing_docs` lint asks; `pub(crate)` items, private items, and the methods of
a trait impl, which the trait documents, may have one. A trait impl is named by
its trait and self type, as `Deref-for-ScopeGuard<T,F,S>`, and an inherent impl
by its self type. A tuple field is named by its position.

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

No C# unit requires a comment by its rule; the grammar labels `public`,
`protected`, and `protected internal` `required`, so a type or member visible
outside its assembly requires one, as the compiler's CS1591 warning asks, and a
test always does. The members of an interface and of an enum are as visible as
it is, so the grammar labels their bodies `inherited`; a member marked
`private`, `internal`, or `private protected` is labeled `optional` and never
requires one.

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
    signatures: {.fsi: .fs}
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
      - {rule: localAndFunctionDefinition, kind: function, name: {rule: bindingName}, required: false}
      - {rule: localAndValueDefinition, kind: value, name: {rule: bindingName}, required: false}
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
declarations, the `let` bindings of a class or of a body, modules, and
namespaces may have a comment. Where a `.fsi` signature file declares a `.fs`,
the comment is required on the signature, not the implementation.

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
      interpolation: ["#{", "}"]
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
comment and `defp` may have one. `@doc false` hides the definition below it
and `@moduledoc false` the module around it, so neither needs a comment. An
operator definition is named by its operator, and `def unquote(name)(args)`
by its `unquote` call. A test is named by its string, and its
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
      joinAcrossBlankLines: true
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

`@internal` hides an item, so it needs no comment. Gleam written before 1.0,
with `external fn` and `if erlang { ... }` groups, parses too. With
`joinAcrossBlankLines`, `///` lines stand together across blank lines, as
the Gleam compiler joins them.

The Erlang sample is recon, a git submodule. Its `canon.yaml` holds the Erlang
profile:

```yaml
languages:
  erlang:
    extensions: [.erl, .hrl, .escript]
    grammar: ../../grammars/erlang/Erlang.g4
    start: forms
    comments:
      line: "%"
      innerDoc: ["-moduledoc"]
      docAttributes: ["-moduledoc", "-doc"]
      hiddenTags: ["@private", "@hidden"]
      strings: ["\"\"\"\"", "\"\"\"", "\""]
    units:
      - {rule: functionDefinition, kind: function, name: {rule: definedName}, required: true}
      - {rule: typeAttribute, kind: type, name: {rule: definedName}, required: false, firstToken: {token: TokAtom, oneOf: [type, opaque, nominal]}}
      - {rule: recordAttribute, kind: record, name: {rule: definedName}, required: false, firstToken: {token: TokAtom, oneOf: [record]}}
      - {rule: callbackAttribute, kind: callback, name: {rule: specFun}, required: true}
```

Every `%` comment directly above a unit is its Why, so an EDoc comment above a
function's `-spec` documents the function. An OTP 27 `-doc` string documents
the function below it and `-moduledoc` the file, and `-doc false` hides the
function, as does an EDoc comment holding one of the `hiddenTags`. Functions,
types, and callbacks are named by name and arity, such as `info/2`, because
the grammar labels their arguments `arity`. A hook named by the grammar's
`superClass` expands the macros a file defines before parsing, as `epp` does.

The Prolog sample is marelle, read through the grammars-v4 Prolog grammar with
a profile that makes each clause and directive a unit. The grammar admits any
character outside ASCII inside quotes, as SWI-Prolog does, which marelle's check
mark needs; the change is marked `canon:` and recorded as
`DEC-prolog-grammar-fixes`. The canonically commented dialect under
`grammars/prolog/canonically_commented/` reads PlDoc: a `%!` or `%%` comment at
the start of a line, with the `%` lines that continue it, or a `/**` comment,
documents the clauses directly below it, and a `/** <module>` comment documents
the file, while a plain `%` comment, a `%%%` banner, and a `%!`, `%%`, or `/**`
anywhere inside a clause, on whatever line before its full stop, document
nothing. The clauses of a predicate are one unit of kind `predicate` named
`name/arity`, the arity being the number of the head's arguments, and a head
may be module-qualified, as `user:portray(X)` is; a declaration such as
`:- dynamic foo/1.` is one of its clauses, and one of several predicates,
`:- dynamic a/1, b/2.`, documents the first. A DCG rule is a `nonterminal` and a
clause of `test/1` or `test/2` a plunit `test` named by its first argument. The
module directive's export list labels each predicate indicator `export`, and
`name//N` exports the nonterminal `name/N`, so a module requires a comment on
what it exports, and a file without a module directive on every predicate, as
all of them are visible; a PlDoc comment where no predicate follows is an
orphan. A head written with an operator is no unit, since the grammar has no
operator table (`DEC-prolog-dialect`). marelle writes plain `%` comments,
so through the dialect it has 197 units, every one required, and no canonical
comment.

The Groovy sample is spock-genesis 0.6.0, six of its sources and two of its
Spock specifications, vendored under `source/` with its MIT license. Groovy
documents a declaration with a `/**` Groovydoc comment above its annotations.
Its `canon.yaml` holds the Groovy profile a Groovy project can copy:

```yaml
languages:
  groovy:
    extensions: [.groovy, .gvy, .gy, .gsh]
    lexer: ../../grammars/groovy/GroovyLexer.g4
    parser: ../../grammars/groovy/GroovyParser.g4
    start: compilationUnit
    comments:
      line: "//"
      blockOpen: "/*"
      blockClose: "*/"
      outerDoc: ["/**"]
      strings: ["\"\"\"", "'''", "\"", "'"]
    units:
      - {rule: normalClassDeclaration, kind: class, name: {rule: identifier}, required: true}
      - {rule: interfaceDeclaration, kind: interface, name: {rule: identifier}, required: true}
      - {rule: traitDeclaration, kind: trait, name: {rule: identifier}, required: true}
      - {rule: enumDeclaration, kind: enum, name: {rule: identifier}, required: true}
      - {rule: annotationTypeDeclaration, kind: annotation, name: {rule: identifier}, required: true}
      - {rule: recordDeclaration, kind: record, name: {rule: identifier}, required: true}
      - {rule: enumConstant, kind: constant, name: {rule: identifier}, required: true}
      - {rule: constructorDeclaration, kind: constructor, name: {rule: methodName}, required: true}
      - {rule: methodDeclaration, kind: method, name: {rule: methodName}, required: true}
      - {rule: fieldDeclaration, kind: field, name: {rule: variableDeclaratorId}, required: true}
```

Groovy declarations are public unless they say otherwise, so every unit
requires a comment by its rule, and the grammar labels `private` `optional`,
which lifts the requirement, as Groovydoc documents what is not private. A
field, which Groovy makes a property when it has no access modifier, is named
by its first declarator; the dialect makes each declarator a field. A Spock
feature method is named by its string without quotes, as `is finite`, and a
constructor by its class.

The Scala sample is Iron 3.3.2, its constraint core, its `any` and `char`
constraints, and two of its utest suites, vendored under `source/` with its
Apache-2.0 license. Scaladoc documents a definition with a `/**` comment above
its annotations and modifiers. Its `canon.yaml` holds the Scala profile a
Scala project can copy:

```yaml
languages:
  scala:
    extensions: [.scala, .sc]
    lexer: ../../grammars/scala/ScalaLexer.g4
    parser: ../../grammars/scala/ScalaParser.g4
    start: compilationUnit
    comments:
      line: "//"
      blockOpen: "/*"
      blockClose: "*/"
      outerDoc: ["/**"]
      strings: ["\"\"\"", "\""]
    units:
      - {rule: packageObject, kind: object, name: {rule: definitionName}, required: true}
      - {rule: objectDefinition, kind: object, name: {rule: definitionName}, required: true}
      - {rule: classDefinition, kind: class, name: {rule: definitionName}, required: true}
      - {rule: caseClassDefinition, kind: case_class, name: {rule: definitionName}, required: true}
      - {rule: traitDefinition, kind: trait, name: {rule: definitionName}, required: true}
      - {rule: enumDefinition, kind: enum, name: {rule: definitionName}, required: true}
      - {rule: enumCase, kind: case, name: {rule: definitionName}, required: false}
      - {rule: defDefinition, kind: def, name: {rule: definitionName}, required: true}
      - {rule: defDefinition, kind: def, name: {token: THIS, index: 1}, required: true}
      - {rule: valDefinition, kind: val, name: {rule: definitionName}, required: true}
      - {rule: varDefinition, kind: var, name: {rule: definitionName}, required: true}
      - {rule: givenDefinition, kind: given, name: {rule: givenName}, required: true}
      - {rule: givenDefinition, kind: given, name: {rule: givenType}, required: true}
      - {rule: extensionDefinition, kind: extension, name: {rule: extendedType}, required: false}
      - {rule: typeDefinition, kind: type, name: {rule: definitionName}, required: true}
```

Scala definitions are public unless they say otherwise, so every definition
requires a comment by its rule, and the grammar labels `private` and
`protected`, qualified or not, `optional`, which lifts the requirement, as
Scaladoc documents public members; it labels `override` `optional` too, since
an override inherits the documentation of what it overrides. An enum case is
labeled `inherited`, so it requires a comment when its enum does. Definitions
inside a block, such as the locals of a `def`, are not units. An anonymous
given is named by its type, as `Constraint[Char,Whitespace]`, an auxiliary
constructor by `this`, and an extension by the type it extends. The grammar is
canon's own, written from the Scala 3 syntax reference under canon's MIT
license, because the grammars-v4 Scala 3 grammar states no license. It reads
declarations and leaves bodies and expressions as runs of tokens, and Scala 3's
optional braces come from `Canon.Antlr4.Lex.Scala`, a lexer hook selected by
the grammar's `superClass` that inserts the indent, outdent, and newline tokens
the reference describes.

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
and the first ingested under rule 7: each carries a `canonical_vetting/`
directory in which every Javadoc comment is `pending`, so their reports are invalid
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
upstream port left open. The parse-error rule of the layout algorithm closes
an implicit block at a token the block cannot hold, which needs the parser to
tell the lexer a token was rejected, so the hook approximates it for the
tokens real code puts there: a closing bracket, and a comma of the brackets
or record braces around the block, close the blocks opened inside them, as
after a `case` in a tuple or a `let` in a comprehension, unless the comma
follows a guard's bar; `then` and `else` close the blocks opened since their
`if`; and a `let` in a function's guard ends at the equals sign that ends the
guard. A `let` in the guard of a `case` alternative, and any other token a
block cannot hold, stay out of reach.

JavaScript, TypeScript, Python, Go, and Kotlin are profile languages with
`units`, checked through their grammars-v4 grammars and the samples above:
chalk, ky, itsdangerous, google/uuid, and Turbine. Reading them needed four
general additions to the interpreter and three base lexer ports. Character
sets may name Unicode properties such as `\p{L}`, which Go and Kotlin use for
identifiers. A grammar may `import` another, read from beside it, and its own
rules win, which Kotlin's `UnicodeClasses` needs. A semantic predicate in a
lexer rule is decided where it sits, by the hooks, so a predicate inside one
alternative of a block gates only that alternative; a grammar without hooks
has every predicate hold, and a parser-side predicate holds unless a parser
hook answers it, as the C#, JavaScript, and TypeScript hooks do.
An empty lexer match is allowed when it changes mode, which Go's `OTHER` rule
relies on. `Canon.Antlr4.Lex.JavaScript` ports `JavaScriptLexerBase` and
`TypeScriptLexerBase`, which decide whether a slash starts a regular
expression, whether a closing brace ends a template expression, and whether
strict mode is on; `Canon.Antlr4.Lex.Python` ports `Python3LexerBase`, which
turns newlines into `NEWLINE`, `INDENT`, and `DEDENT` and skips blank and
comment lines and newlines inside brackets. The parser memoises its loops and
its precedence climbing by position, so a block of statements that can each
end two ways, as every TypeScript statement can, costs a table rather than a
power of two. The vendored grammars carry small patches marked `canon:` for
constructs newer than the grammars: Python's positional-only `/`,
JavaScript's `import.meta`, Kotlin's `when (val x = ...)`, and for TypeScript
`readonly` types, mapped and conditional types, `infer`, `as` before any type,
`#private` members, `readonly` parameters, optional calls, logical assignment,
ambient `module` declarations, and `is` and `infer` as property names.

The JavaScript and TypeScript dialects, under `canonically_commented/` beside
each grammar, read a `/**` comment as JSDoc and TSDoc do: it documents the
function, class, method, accessor, field, property, interface, type alias,
enum and enum member, namespace, module-level `var`, `let`, or `const`
binding, or `export default` below it, and in TypeScript the members of an
interface or object type, a call, construct, or index signature named by its
position. An accessor is named by `get` or `set` and its property, and
`export default` by `default`. A file's first `/**` documents the file when
it holds `@file`, `@fileoverview`, `@overview`, `@module`, `@license`, or
`@packageDocumentation`, or when a blank line or an import follows it, and
otherwise the declaration below it, a hashbang line above it changing
nothing. A `/**` that starts with `@type` or `@satisfies` is a type cast or
annotation and is hidden: neither a Why nor an orphan. Any other `/**` above
another statement, a local binding's included, inside an expression or a
type, or after the last member of a body is an orphan, through the grammar or
through the parser's `strayComment` option, so none fails the parse; `/**/`
and `/***` are plain comments. The properties, methods, and accessors of an
object literal an exported binding or `export default` holds directly are
units, and in TypeScript overload signatures and their implementation are one
unit, merged as Elixir's clauses are, and an ambient module is named without
quotes. The `export` keyword is part of the declaration it exports and is
labeled `required`, the bodies of classes, interfaces, and enums, exported
object literals, and the right side of a type alias are labeled `inherited`,
and `private`, `protected`, and `#private` names are labeled `optional`, so
what a module exports requires a comment, its members included. The parser
hook answers `JavaScriptParserBase`'s `n` and `p` predicates, which tell a
getter, a setter, or `static` from a member so named, and its line terminator
predicates from the lines of the code tokens on either side, so a statement
without a semicolon ends at a line break. On chalk the JavaScript dialect
parses all 16 files with no orphan, and on ky the TypeScript dialect parses
all 87, binding all 90 TSDoc comments, within the time the plain grammar takes.
A sample checks through either by naming the dialect's `lexer` and `parser`
in its profile with no `units`.

Go and Python also have canonically commented dialects. A Go doc comment is an
ordinary comment directly above a declaration, so the Go dialect's lexer hook,
`Canon.Antlr4.Lex.Go`, makes a comment a doc comment only when it starts its
line at the top level of a file, in a grouped `const`, `type`, or `var`, or in
a `struct` or `interface`, and never in a function body; a comment that a
blank line or the end of the file parts from what follows is no documentation,
so a license header or build constraint is neither a Why nor an orphan. Each
top-level function, method, type, const, and var, each spec of a group, each
field, and each interface element is a unit, a group is named by its position,
and the comment above the package clause is the file's Why. An exported name,
one with an upper-case initial, requires a comment, as revive's `exported`
rule asks, unless it is a method of an unexported type or a spec of a group
whose comment documents it; a spec requires one when any of its names is
exported, and fields and interface methods may have one. Comments with no
blank line between them are one doc comment, as go/doc groups them, and a
directive line such as `//go:generate`, `//nolint`, or `// +build` is left out
of it. The
sample's plain profile requires a comment on every function, method, and type.
A Python docstring is a string, so the Python dialect keeps the plain lexer and
labels the string that opens a module, class, or function body `why`, and
canon reads its prose and keys from the string's contents, adjacent strings
joined as Python joins them; a string elsewhere and a `#` comment are no
documentation. Decorators are markers. A public name at the top level of a
module, nested in no `def` or `class` though perhaps in a module-level `if` or
`try`, requires a docstring, a class body is
`inherited`, so the public methods of a public class need one, `__init__`
included, and a private name, a dunder other than `__init__`, and an
`@overload` stub need none, as PEP 257 and PEP 8 have it. A module's
docstring is never required, since no file unit requires a comment. The sample's plain
profile requires one on every function and class.

## Makefiles

A Makefile is a language of its own, `make`, through canon's own dialect under
`grammars/make/canonically_commented/`, since grammars-v4 has none. A canonical
comment opens with `# |` and continues on `#` lines above the unit, as the
Haskell dialect's opens with `-- |`. A rule with a plain target is a unit of
kind `rule` that requires the comment, its target the What and its recipe the
How; a special target, a pattern rule, and a variable are units whose comment
is optional; the `## text` after a rule's prerequisites stays as the one-line
What the `help` target prints. canon, Rice's Tax, and wavelet each have a
Makefile as their front door, checked like any other source, and `make` alone
lists what each can do (`DEC-make-dialect`).

## The Folio

The Folio is the literate form: Markdown with front matter, citations, and
fenced blocks that tangle. A project declares it in `canon.yaml` as a language
whose profile has `embeds`, one per language its blocks are written in, each
naming the profile that parses the blocks, the comment syntax a block must not
carry, the width a tangled line may have, and how a generated comment and
banner are spelled. canon reads a page with `grammars/folio/`, one token per
line, and scans the tree into headings, prose, and blocks; the prose between
a heading and a block is the block's rationale. `canon tangle` assembles every
file the blocks name, byte for byte as wavelet's tangler wrote them, with the
prose as a generated documentation comment ending in its section's address,
and `canon tangle --check` reports what is stale. `canon check` parses what
the pages tangle to with the embedded language's grammar, so every rule
applies unchanged, then relocates every unit and decision into the pages, so
a finding points at what a person edits and a unit's Why is the prose of its
section as authored; a tangled file that differs from its pages is a finding,
and a block that declares a `def=` it does not define, or carries a comment,
is one too. `canon site <dir>` renders `docs/` to a static site with canon's
own renderer, deterministically, its fenced blocks highlighted by the
language's own lexer: tokens are classified from the grammar's shape, and a
profile's `highlight` key names, per class, the token names the shape does not
classify (`DEC-highlight-by-lexer`). This repository's own pages are
`docs/explanation/folio.md` and `docs/how-to/tangle.md`; its sources stay
hand-written Haskell until `DEC-canon-self-folio` is decided.

`grammars/folio/canonically_commented/` is a dialect of the Folio that reads a
page as units by labels, as every dialect reads its language: a page's front
matter is the Why of a unit of kind `doc` named by its id, the id canon's page
extraction gives it, with its `video` cited as a reference; each section whose
heading is followed by prose is a unit of kind `section` named by its title,
its Why all of its prose, before and after its fenced blocks, and its How the
blocks; and a `---` line below the top of a page is a thematic break, as in
Markdown. A thematic break inside a section's prose stays in the Why's text. The root
`canon.yaml` keeps reading `docs/` through the plain grammar, whose line tokens
the page extraction, the tangler, and the site read (`DEC-folio-dialect`).

Haskell is checked through its dialect in this repository's own `canon.yaml`,
so `canon check` at the root checks canon itself: `src`, `app`, `test`, and
the four grammars that carry canonical comments. Every one of canon's own
comments is recorded as pending under `canonical_vetting/` until a human
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
├── Makefile               # the front door: make and a verb runs the Stack commands below
├── docs/                  # Folio pages split by Diátaxis: tutorials, how-to, reference, explanation
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
│   ├── Canon/Exemptions.hs # canonical_exemptions.yaml: subjects not owed until a version
│   ├── Canon/Vetting.hs   # canonical_vetting/: verdicts per kind and subject, digests, assessors from git blame
│   ├── Canon/Version.hs   # semantic versions and their precedence
│   ├── Canon/Ignore.hs    # gitignore-style patterns
│   ├── Canon/Walk.hs      # finds supported files and nested projects under a directory
│   ├── Canon/Project.hs   # a project: its config, registry, ledger, files, and checks
│   ├── Canon/Cache.hs     # content-addressed cache of extractions under .canon-cache/
│   ├── Canon/Git/Fill.hs  # Who and When from one git blame per file
│   ├── Canon/Profile.hs   # language profiles declared in canon.yaml
│   ├── Canon/CommentScan.hs  # comments by a profile's syntax
│   ├── Canon/Preprocessor.hs  # the builds a file is read under and the #if branches each reads, for C# and F#
│   ├── Canon/Signature.hs # ties a signature file's comments to its implementation, for F#
│   ├── Canon/Extract/Grammar.hs  # builds the model of any file through its language profile
│   ├── Canon/Extract/Folio.hs    # relocates the units of tangled files into the Folio pages
│   ├── Canon/Extract/Calm.hs     # reads a CALM architecture description as units
│   ├── Canon/Folio.hs     # a Folio page: front matter, sections, and fenced blocks
│   ├── Canon/Tangle.hs    # writes the sources a page's blocks tangle to
│   ├── Canon/Weave.hs     # renders the pages to a static site
│   ├── Canon/Highlight.hs # colours code by the language's own lexer
│   ├── Canon/Testing.hs   # the built-in table of test markers and name patterns per language
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
│       ├── Predicate.hs   # semantic predicates answered for a parser's base class
│       ├── Lex.hs         # the interpreted lexer and its hook interface
│       ├── Lex/           # lexer hooks ported from grammars' base classes, one per superClass
│       ├── Parse.hs       # the interpreted parser
│       ├── Interpret.hs   # loads a grammar pair and runs lexer and parser over a file
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
first hook implementation. Semantic predicates that a parser grammar
delegates to its base class are answered the same way, by a parser hook keyed
by the parser grammar's `superClass`; `CSharpParserBase` is the first.

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
pragma names accepted as identifiers, and the layout cases above. Under
`canonically_commented/` the dialect sends `-- |` and `{-|` into `DocLine`
and `DocBlock` lexer modes, keeps the line break that ends a doc line as a
`NEWLINE` carrying the layout action, inlines each unit-bearing top-level
form as a labeled alternative, labels export-list entries `export`, and
absorbs a doc comment on a local binding, instance method, or constructor as
an `orphan`. A doc comment anywhere else the grammar takes none, as inside
an expression, is read out of the file and reported as an `orphan`, since the
parser's `strayComment` option names `canonicalComment`. Two `-- |` comments
on consecutive lines merge, as Haddock also reads them.

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

`grammars/rust/` holds the Rust grammar from grammars-v4 and its dialect. canon has no port of its base classes, so the
predicates that called into them are replaced in the grammar itself; outer
attributes and visibility move into each kind of item, so an item's node
starts at its first attribute and the doc comment above binds to it, with
each attribute labeled `marker`; and macro token trees take one token at a
time, which keeps macro bodies from parsing in exponential time. A bare `pub`
and `#[macro_export]` are labeled `required`, and trait items and enum
variants `inherited`. Under `canonically_commented/` the dialect sends `///`
and `/**` into `DocLine` and `DocBlock` lexer modes and `//!` and `/*!` into
`InnerDocLine` and `DocBlock`, labels each item, field, and variant as a unit
alternative, binds `//!` to the module or file around it, and takes a doc
comment after an attribute or above a statement as an `orphan`. Each change
is marked `// canon:` in the grammar, listed in `grammars/rust/README.md`,
and recorded in the ledger.

`grammars/csharp/` holds the C# 7 grammar from grammars-v4 and its dialect.
Upstream leaves interpolated strings and the
preprocessor to a `CSharpLexerBase` class, which canon ports as a lexer hook
selected by the grammar's `superClass` option: the hook tracks the braces of
each interpolation hole, raw ones included, and reads the branches of each
`#if` that a build selects, so the code canon reads is code some build
compiles, and every branch some build compiles is read in one of a few builds.
The parser's predicates go through a `CSharpParserBase` hook. Attributes and modifiers
move into each kind of type and member, as Rust's do, with `public` and
`protected` labeled `required`, `private` and `internal` `optional`, interface
and enum bodies `inherited`, and each attribute labeled `marker`, and C# 8 to 14
syntax is added. Under `canonically_commented/` the dialect sends `///` and
`/**` into `DocLine` and `DocBlock` lexer modes, labels each namespace, type,
member, and enum member as a unit alternative, and takes a doc comment the
compiler warns is on no valid element, such as one after an attribute or
before a statement, as an `orphan`. Each change is marked `// canon:` in the
grammar, listed in `grammars/csharp/README.md`, and recorded in the ledger.

`grammars/fsharp/` holds an F# grammar written for canon, since grammars-v4
has none, and its dialect. It parses the
declarations that carry documentation and reads expressions, patterns, and
types as runs of tokens. F# ends a declaration by indentation, so the
grammar's `superClass` selects a lexer hook that turns the offside rule into
`INDENT`, `DEDENT`, and `NEWLINE` tokens outside brackets, as Python's
tokenizer does, and reads `#if` as the C# hook does. Under
`canonically_commented/` the dialect sends `///` into a `DocLine` lexer mode,
the hook holds a doc comment's tokens until the next code token has produced
its layout tokens, as the Haskell port does, and each declaration is a unit
alternative, with what is public by default labeled `required` and `private`
and `internal` `optional`. What it reads and what it leaves out is listed in
`grammars/fsharp/README.md` and recorded in the ledger.

`grammars/kotlin/` holds the Kotlin grammar from grammars-v4, with each
annotation labeled `marker`, and its dialect. Under `canonically_commented/`
the dialect sends `/**` into a `DocBlock` lexer mode from the default and the
parenthesised modes, and labels each top-level declaration, member, companion
object, secondary constructor, enum entry, and constructor property as a unit
alternative whose Why is the KDoc comment above its annotations and modifiers;
the comment above the package directive is the file's. A Kotlin declaration is
public unless it says otherwise, so a top-level declaration holds the empty
rule `publicByDefault`, labeled `required`, class bodies are `inherited`, and
`private`, `internal`, `override`, and `actual` are `optional`, which is the
API that explicit API mode and Dokka document. A KDoc comment after an
annotation, before a statement, on a parameter, or on an accessor is an
`orphan`. What it reads is listed in `grammars/kotlin/README.md` and recorded
in the ledger as `DEC-kotlin-dialect`.

`grammars/clojure/` holds the Clojure grammar from grammars-v4, which read a
keyword as a colon and a symbol and so failed on `:1.8` and `:div#id`; a
keyword is one token there, as the reader reads it, and a backslash in a
string always escapes (`DEC-clojure-grammar-fixes`). Under
`canonically_commented/` the dialect tries a definition form before the
generic list: `defn`, `defn-`, `defmacro`, `defmulti`, `defprotocol` and its
method signatures, `defrecord`, `deftype`, `def`, and `deftest` are unit
alternatives whose What is the name and whose Why is the docstring after it or
the `:doc` metadata on it, and the docstring of the leading `ns` form is the
file's Why. A docstring is a string told from others only by where it stands,
so the string is labeled `why` and canon reads a Why that is one string literal
without its quotes and escapes. `defn`, `defmacro`, `defmulti`, and
`defprotocol` are `required`, protocol methods `inherited`, and `^:private`
and `^:no-doc` `optional`; a string after a function's parameters with more
body after it is a misplaced docstring and an `orphan`. Any other head that
starts with `def`, as hiccup's `defelem` does, followed by a symbol is a unit
of kind `def` with an optional docstring, except `default`, `defer`, their
longer forms, and `defproject`; a `defmethod` is a unit of kind `method` named
by its multimethod and dispatch value, as `render.:circle`; and a definition
inside `(comment ...)` is no unit. A `;` comment is not documentation
(`DEC-clojure-dialect`).

The Rust, C#, F#, Kotlin, and Clojure samples keep the profiles above, and the
test suite reads their sources through the dialects too. The dialects bind a doc comment across
a blank line and read no plain comment as a file's Why, as every dialect does
under the open `DEC-comment-attachment`, while the profiles part a doc comment
from its unit at a blank line and bind a plain comment on a file's first line
to the file.

`grammars/groovy/` holds Apache Groovy's own ANTLR 4 grammar, which the Groovy
compiler parses with, since grammars-v4 has none, and its dialect. Its lexer
and parser lean on Java superclasses, `AbstractLexer` and `AbstractParser`,
renamed `GroovyLexerBase` and `GroovyParserBase` so the names select only
Groovy's hooks, which canon ports as a lexer hook that decides whether a slash starts a
slashy string and which brackets hide newlines, and as a parser hook that
answers whether a line declares a method or a variable or calls one. The
lexer predicates that looked ahead in the characters are written as the
characters they allowed, comments are hidden, each kind of type is a rule of
its own that starts with its annotations, and a constructor is a rule of its
own, with `private` labeled `optional` and each annotation `marker`. Under
`canonically_commented/` the dialect sends `/**` into a `DocBlock` lexer mode,
labels each type, constructor, method, field, and enum constant as a unit
alternative that holds the empty rule `publicByDefault` labeled `required`,
makes each name a field declaration declares a field labeled `declarator`,
and takes a Groovydoc comment after an annotation, above a statement, or
anywhere else no rule names, as inside an expression, as an `orphan`. The Groovy sample keeps the profile above, and the test suite reads
its sources through the dialect too. Each change is marked `// canon:` in the
grammar, listed in `grammars/groovy/README.md`, and recorded in the ledger.

`grammars/scala/` holds a Scala grammar written for canon from the Scala 3
syntax reference, under canon's MIT license, and its dialect. canon does not
vendor the grammars-v4 Scala 3 grammar, because it states no license. It
parses the declarations that carry documentation, packages, imports, objects,
classes, case classes, traits, enums and their cases, defs, vals, vars, type
aliases, givens, and extensions with their annotations and modifiers, and reads
bodies and expressions as runs of tokens. The grammar's `superClass` selects a
lexer hook that inserts `INDENT`, `OUTDENT`, and `NEWLINE` where the reference's
Optional Braces section does, outside parentheses and brackets, so braces and
significant indentation read alike. Each annotation is labeled `marker`, and
`private`, `protected`, and `override` `optional`. Under
`canonically_commented/` the dialect sends `/**` into a `DocBlock` lexer mode,
the hook holds a Scaladoc comment's tokens until the next code token has
produced its layout tokens, each definition is a unit alternative that holds
the empty rule `publicByDefault` labeled `required`, enum cases are
`inherited`, and a Scaladoc comment after an annotation or above a statement
is an `orphan`. What it reads and what it leaves out is listed in
`grammars/scala/README.md` and recorded in the ledger.

`grammars/elixir/` and `grammars/gleam/` hold grammars written for canon, each
with a canonically commented dialect. The grammars-v4 Elixir grammar parsed
71 of 308 files from Jason, Plug, and Phoenix in canon's interpreter, and no
ANTLR grammar for Gleam exists. The Elixir grammar is structural: statements
end at newlines unless an operator continues them, expressions are chains of
operands without precedence, strings and heredocs have lexer modes whose
interpolations nest, and each kind of definition takes the module attributes
directly above it, labeled `marker`. The Gleam grammar reads a module's items
with their attributes, labeled `marker`, and reads function bodies as
balanced brackets. Both parse every file of their test corpora: the 308
Elixir files, and the 116 modules of the Gleam stdlib, gleam_json, gleam_otp,
and wisp, plus 182 pre-1.0 Gleam stdlib modules. Each directory's `README.md`
gives the design, the dialect, and the known limitations, and the ledger
records them as `DEC-elixir-grammar`, `DEC-gleam-grammar`,
`DEC-elixir-dialect`, and `DEC-gleam-dialect`. In the dialects `@doc` and
`@moduledoc` strings, and `///` and `////` lines, are tokenized as canonical
comments, and the last `@doc` before an Elixir definition wins.

`grammars/erlang/` holds the grammars-v4 Erlang grammar, changed for OTP 24 to
28 and for the preprocessor, which it reads without running, and its dialect.
Each change is marked `// canon:` and listed in `grammars/erlang/README.md`,
and the ledger records them as `DEC-erlang-grammar`. Every file of recon and of
OTP's stdlib, kernel, and eunit parses. The dialect, split into a lexer and a
parser, reads `-doc` strings and EDoc comments as canonical comments and labels
export entries `export`, so an exported unit requires a comment
(`DEC-erlang-dialect`).

`grammars/prolog/` holds the grammars-v4 Prolog grammar, `prolog.g4`, with
one change marked `canon:`, and under `canonically_commented/` its dialect,
split into `PrologLexer.g4` and `PrologParser.g4` because a combined grammar
may not hold modes. The default mode is the start of a line, where `%!` or
`%%` opens a `DocLine` mode; the code of a line is lexed in a `Code` mode that
a line break leaves, so a `%%` inside a clause body stays plain. `/**` opens a
`DocBlock` mode. A comma is no operator in the dialect, so the arguments of a
head are counted right, and each clause, declaration, DCG rule, and plunit test
is a labeled unit alternative. The marelle sample keeps its profile, and
the test suite reads it through the dialect too (`DEC-prolog-dialect`).

`grammars/folio/canonically_commented/` holds a dialect of the Folio grammar
whose every rule carries a canonical comment, as the plain grammar's do, so the
root `canon.yaml` checks it; the root profile still reads `docs/` through the
plain grammar (`DEC-folio-dialect`).

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
stack exec canon -- tangle --check
stack exec canon -- site _site
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
ignores `grammars/*/*.g4` except the ANTLR meta-grammar and the Java and
Haskell grammars, and the Rust, C#, and F# dialects, so that only grammars
carrying canonical comments are checked.

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
