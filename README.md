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
   uses the [Haskell Package Versioning Policy](https://pvp.haskell.org/).
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
code carries no comments at all.

## Directory layout

```
canon/
├── README.md              # this file
├── CHANGELOG.md           # release history; required for Hackage-publishable projects
├── LICENSE
├── install_toolchain.sh   # installs the build toolchain
├── package.yaml           # hpack package definition; generates canon.cabal
├── stack.yaml             # stack snapshot and package list
├── Setup.hs
├── app/
│   └── Main.hs            # executable entry point
├── src/
│   ├── Canon.hs           # argument dispatch and usage text
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

`canon` consumes the canonically commented grammar. The upstream grammar is
kept beside it as the source it is derived from.

`grammars/antlr4/` holds ANTLR's own meta-grammar, `ANTLRv4Lexer.g4` and
`ANTLRv4Parser.g4`, vendored unmodified from grammars-v4. The `Canon.Antlr4`
modules read any `.g4` file into a grammar value, and the test suite checks
that both of these files read with their known structure. Its
`canonically_commented/` directory is still a husk.

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
```

`canon` is a command line tool. Running it with no arguments prints usage.
The `Canon.Antlr4` library is not reachable from the command line yet.

Tests use tasty with hedgehog. Property-based tests are the primary tests and
live under the `property` group. Fixture checks against the vendored grammars
live under the `unit` group.
