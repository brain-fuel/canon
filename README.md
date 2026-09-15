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
Javadoc comment after an annotation, and is reported. Alternative labels
without a `why`, such as the Java grammar's own expression labels, are
inert. `canon` generates the extraction parser from that grammar, so nothing
about a language's comment placement is written in Haskell. The ANTLR
meta-grammar and Java are the languages done this way.

### Vetting

When `canon` is introduced to an existing codebase, its comments were written
without `canon` and may or may not answer Why. Rule 7 says none of them
counts until a human has read it. The flow is:

1. `canon ingest` extracts the project and writes `canonical_vetting.yaml`,
   one entry per canonical comment, keyed by decision id, with the verdict
   `pending` and a digest of the comment's text. Running it again adds only
   comments that have no entry yet.
2. `canon vet` lists every comment that needs a verdict, with its location
   and its text, so a reviewer can work through them. It also lists verdicts
   that have gone stale because the comment changed, deferrals past their
   revisit version, and verdicts whose comment no longer exists.
3. The reviewer edits the entry's `verdict` to `good`, `bad`, or `deferred`,
   adds a `revisit` version to a deferral and optionally a `note`, and
   commits. Nothing in the file names the reviewer: `canon` reads the author
   of the commit that last touched the `verdict` line with `git blame`, and
   the model records that person, the time, and the commit as the decision's
   `vetting` answer with git evidence. An uncommitted verdict has no assessor
   yet, and `canon check` says so informationally.
4. `canon check` fails on every pending, stale, or bad comment and on a
   deferral without a revisit version or past it, reports a deferral within
   its window informationally, and ends with `report invalid: N canonical
   comments pending vetting` while any are pending.

A `bad` comment is a liar's comment: the fix is to rewrite it, which changes
its digest and makes it pending, so the rewrite is vetted in turn. Once the
file exists, a new comment without an entry is pending too, so the author of
a new comment adds its `good` entry in the same commit and is thereby its
assessor.

Until the canonical comment grammar exists for Haskell, this repository's own
code carries no comments at all. Languages whose dialect grammars do not exist
yet fall back to the provisional line-adjacency rule recorded in
`to_be_removed/provisional_canonical_comment_syntax.md`: a doc comment on the
line directly above a unit named by the language profile is its canonical
comment.

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
  requires a canonical comment on it.
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
name, with the file `extensions` it owns, the `grammar` file or the `lexer`
and `parser` pair, the `start` rule, the comment syntax (`line`, `blockOpen`,
`blockClose`, and the `strings` whose contents are not comments), and the
`units`: which parse-tree rules are code units, their `kind`, where their
`name` comes from (the nth token of a type, or the text of a child rule),
whether a canonical comment is `required`, and optionally a `firstToken`
constraint so that, for example, only Clojure lists beginning with `defn`
count. Unit ids are the language, the file path, and then kind and name at
each level of nesting; a repeated name in one scope gets an ordinal suffix.

A directory containing its own `canon.yaml` is a nested project. The walk
stops there, and `canon check` runs it with its own configuration, registry,
ledger, and ignore list, so one repository can hold many projects. A project
whose sources live elsewhere, such as a git submodule, sets `root` to that
directory.

`lang_samples/` holds real projects in other languages, each a nested project
whose sources are a submodule under `source` and whose canon files sit
beside it. Their grammars are vendored under `grammars/<lang>/` from
grammars-v4, with a `canonically_commented/` dialect where one exists and an
empty husk where it does not. Running
`canon check` from a sample's directory checks that project; running it from
the repository root includes every sample. The samples are upstream code that
is not canonically commented, so those checks fail, and that is the truth
they exist to show: every function without a canonical comment is a finding,
and every file the upstream grammar cannot parse is one too. Run
`git submodule update --init` after cloning to fetch them.

| Sample | Language | Grammar |
|--------|----------|---------|
| `lang_samples/erlang-recon` | Erlang | `grammars/erlang/Erlang.g4` |
| `lang_samples/clojure-hiccup` | Clojure | `grammars/clojure/Clojure.g4` |
| `lang_samples/prolog-marelle` | Prolog | `grammars/prolog/prolog.g4` |
| `lang_samples/haskell-tetris` | Haskell | `grammars/haskell/HaskellLexer.g4` and `HaskellParser.g4` |
| `lang_samples/java-commons-lang` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |
| `lang_samples/java-joda-time` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |
| `lang_samples/java-gson` | Java | `grammars/java/canonically_commented/JavaLexer.g4` and `JavaParser.g4` |

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
adaptor. Where the upstream base lexer gets layout wrong, the port does too,
and the file is reported as unparsable rather than parsed differently.

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
source it is derived from. Lexer actions that upstream grammars delegate to a
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
it. The plain Java grammar carries a canonical comment on every parser rule
and non-fragment lexer rule and cites its BSD license in the header, the
dialect carries the same comments extended where a rule gained unit labels,
and both are checked at the root like the meta-grammar.

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
`bower_components`, `vendor`, `third_party`, build outputs such as
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
