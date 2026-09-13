# Open decisions

Waiting for: each item to be decided and recorded in its canonical place.

Date opened: 2026-09-12

- **Reference registry.** Canonical comments cite references by key into a
  registry. The registry has no home, file format, or rule yet. It is a
  canonical source alongside README.md and CHANGELOG.md and will need its own
  numbered rule.
- **Content of `grammars/antlr4/canonically_commented/`.** The meta-grammar is
  vendored and read. What its canonically commented derivative looks like
  depends on the canonical comment format, which is undefined.
- **Attaching comments to rules.** `Canon.Antlr4.Read` returns comments with
  spans beside the grammar. The rule for binding a doc comment to the rule it
  precedes is not defined and is needed before canonical comments can be
  extracted from grammars.
- **Meaning of left recursion when interpreting grammars.** ANTLR resolves
  left-recursive alternatives by precedence climbing over ordered
  alternatives; grammatical-parsers' context-free backends return every
  parse. The interpretation stage must choose.
- **Decision record format.** Decisions such as the parser choice currently
  sit in this directory as prose. The canonical form of a decision, and how it
  binds to code as a comment does, is undefined.
- **`canon.cabal` in version control.** It is currently ignored and
  regenerated from `package.yaml` by stack. Committing it would let plain
  cabal users build without hpack. Undecided.
- **Sample project README exception.** Rule 2 treats each directory under
  `sample_projects/` as its own project with its own README.md. This was an
  assumption made when the rule was written, not an explicit instruction.
