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

- A canonical comment is required on every public API, on anything used across
  modules, and on any non-trivial semantic property of the code that becomes
  part of the domain language. Elsewhere it is optional.
- References are pointers into a registry, so that each reference has a single
  canonical source. The comment carries a key and the registry maps the key to
  the article, paper, ticket, or requirement.
- Where a comment may attach, and at what granularity, is defined by the
  canonically commented grammar of each language.

Until the canonical comment grammar exists for Haskell, this repository's own
code carries no comments at all. A provisional syntax, recorded in
`to_be_removed/provisional_canonical_comment_syntax.md`, is used for ANTLR
grammar files in the meantime: a doc comment on the line directly above a rule
is its canonical comment, its body is the "Why?", and tokens of the form
`ref:KEY` cite the registry.

## The model

`canon` emits a model of a codebase as YAML with alphabetically ordered keys
and a `schemaVersion`. The model has two kinds of entity, linked by identity:

- A **code unit** is a node in a tree of facts derived from the code. It has a
  stable, path-based id such as `grammar/ANTLRv4Parser/rule/grammarSpec`, and
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

ANTLR grammar files are the first language `canon` models. Each grammar is a
unit, each rule is a child unit, and each mode groups its rules. Every parser
rule and every non-fragment lexer rule requires a canonical comment.

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
│   ├── Canon/Version.hs   # semantic versions and their precedence
│   ├── Canon/Config.hs    # canon.yaml
│   ├── Canon/Attach.hs    # binds a comment to the unit directly below it
│   ├── Canon/CanonicalComment.hs  # provisional canonical comment syntax
│   ├── Canon/Extract/Antlr4.hs    # builds the model of a grammar file
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

- The grammar files at the top of the directory are the official ANTLR4
  grammar for the language, taken from
  [grammars-v4](https://github.com/antlr/grammars-v4) and kept as upstream
  publishes it.
- `canonically_commented/` contains the grammar of the canonically commented
  dialect of that language. It is derived from the upstream grammar and
  modified to add canonical comment structure and attachment rules. Code that
  is valid in the language may not be valid canonically commented code.

`canon` consumes the canonically commented grammar by interpreting it: the
`Canon.Antlr4.Lex` and `Canon.Antlr4.Parse` modules turn any grammar value
into a running lexer and parser, so a `.g4` file under `grammars/` becomes a
parser without code generation. The upstream grammar is kept beside it as the
source it is derived from. Lexer actions that upstream grammars delegate to a
target-language base class are resolved through a hook interface keyed by the
grammar's `superClass` option; the ANTLR meta-grammar's own adaptor is the
first hook implementation.

`grammars/antlr4/` holds ANTLR's own meta-grammar, `ANTLRv4Lexer.g4` and
`ANTLRv4Parser.g4`, vendored unmodified from grammars-v4. The `Canon.Antlr4`
modules read any `.g4` file into a grammar value, and the test suite checks
that both of these files read with their known structure.

`grammars/antlr4/canonically_commented/` holds the canonically commented
dialect of the meta-grammar. It differs from upstream in three ways: doc
comments stay on the default channel, a parser rule must be preceded by a doc
comment, and a non-fragment lexer rule must be preceded by one while a
fragment may be. Every rule in both files carries its own doc comment, so the
dialect parses its own grammars, and the test suite checks that it does and
that it rejects the upstream file. `canon check` runs this dialect over every
grammar it checks and reports the first token the dialect refuses.

`grammars/haskell/` is the first language directory. It is currently a husk
with no grammar files in it.

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
```

`canon` is a command line tool. Running it with no arguments prints usage.
`canon model` writes the model of a grammar file to standard output as YAML
and any extraction findings to standard error. `canon check` prints every
finding, one per line, and exits with status 1 if there are any. Both read
`canon.yaml` from the current directory when it exists. Who and When come from
`git` on the path; without a repository the model is still emitted, with those
answers empty and one finding saying so. `canon parse` interprets a lexer and
parser grammar pair, or one combined grammar, and prints the parse tree of a
file or the position where parsing fails.

`canon.yaml` names the registry under `registry` and the decision ledger
under `decisions`, both defaulting to the files at the project root. It may
name canonical dialect grammars under `canonical`, keyed by
language, each with a `lexer`, a `parser`, and a `start` rule. `canon check`
parses the checked file with the dialect named for its language and reports a
finding at the first token the dialect refuses.

Tests use tasty with hedgehog. Property-based tests are the primary tests and
live under the `property` group. Fixture checks against the vendored grammars
live under the `unit` group.
