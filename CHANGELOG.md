# Changelog for `canon`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added
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
- Extraction was exponential in expression depth on the Java grammar because every labeled expression alternative was scanned as a possible unit; the check of one 170-line test file took minutes and now takes a fraction of a second
- `canon check` bounds the number of files extracted at once to the core count instead of starting every file concurrently
- Unit ids are relative to the project directory rather than the working directory, so verdicts and ledger unit names mean the same thing wherever `canon` is run
- An uncited decided decision is reported once per project, when no file in the project cites it, instead of per file that happens not to

### Changed
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
