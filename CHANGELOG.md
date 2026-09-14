# Changelog for `canon`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

### Added
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

## 0.1.0.0 - 2026-09-12

### Added
- `canon` executable with a `version` subcommand
- Usage text printed when no recognised subcommand is given
- Root `README.md` stating the Canon documentation rules
- `to_be_removed/` and `sample_projects/` directories
