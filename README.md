# canon

`canon` defines how a project's documentation is structured and where it lives.
This repository is the reference implementation of those rules, applied to itself.

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
designated home, and `canon` exists to extract meaning from code and check
that the code and its documentation agree.

| Question | Answered by |
|----------|-------------|
| Why?     | Comments. A comment gives a reason or points at resource material such as an article or reference paper. |
| Who?     | Git. |
| What?    | Names in the code or architecture, following the CALM architecture. |
| When?    | Git together with increasing version numbers. |
| How?     | Bodies in the code or architecture. |
| Where?   | Package, namespace, file, and similar location markers. |

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
│       └── commented/
│           └── <grammar files>
├── to_be_removed/         # legacy documentation awaiting migration, then deletion
└── sample_projects/       # sample projects, each with its own README.md
    └── <project>/
        └── README.md      # the only markdown file in that project
```

### `grammars/`

Holds one subdirectory per language that `canon` can read. Each language
directory contains the grammar files for that language, and a `commented/`
subdirectory containing the same grammar files annotated with comments that
explain why the grammar is shaped as it is. The uncommented files are what
`canon` consumes. The commented files are the human reference and are the one
place in this repository where comments are expected.

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
