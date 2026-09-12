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
3. **All other documentation is pending removal.** Any existing documentation
   for this repository that does not follow the `canon` layout goes into
   `to_be_removed/`. Nothing in that directory is authoritative. Its contents
   are to be folded into the `canon` structure and then deleted.
4. **Do not add new documentation to `to_be_removed/`.** It is a holding area
   for legacy material only. New documentation goes into the project's
   `README.md` or, for release history, its `CHANGELOG.md`.

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
│   └── Canon.hs           # library; argument dispatch and usage text
├── test/
│   └── Spec.hs            # test suite
├── grammars/              # language grammars canon uses to extract meaning from code
│   └── <lang>/
│       ├── <grammar files>
│       └── canonically_commented/
│           └── <grammar files>
├── to_be_removed/         # legacy documentation awaiting migration, then deletion
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

The first language directory is `grammars/haskell/`. It is currently a husk
with no grammar files in it.

### `to_be_removed/`

Holds every piece of pre-existing documentation about this repository that has
not yet been rewritten according to `canon`. It is currently empty because the
repository has no legacy documentation. When the migration is complete, this
directory is deleted.

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
stack exec canon -- version
```

`canon` is a command line tool. Running it with no arguments prints usage.
