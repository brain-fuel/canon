# Open decisions

Waiting for: each item to be decided and recorded in its canonical place.

Date opened: 2026-09-12

- **Reference registry.** Canonical comments cite references by key into a
  registry. The registry has no home, file format, or rule yet. It is a
  canonical source alongside README.md and CHANGELOG.md and will need its own
  numbered rule.
- **ANTLR4 meta-grammar.** `canon` needs ANTLR's own grammar to read any `.g4`
  file. Vendoring `ANTLRv4Lexer.g4` and `ANTLRv4Parser.g4` into
  `grammars/antlr4/` is the first grammar to add, and it needs the same
  upstream plus `canonically_commented/` treatment as every other language.
- **Decision record format.** Decisions such as the parser choice currently
  sit in this directory as prose. The canonical form of a decision, and how it
  binds to code as a comment does, is undefined.
- **`canon.cabal` in version control.** It is currently ignored and
  regenerated from `package.yaml` by stack. Committing it would let plain
  cabal users build without hpack. Undecided.
- **Sample project README exception.** Rule 2 treats each directory under
  `sample_projects/` as its own project with its own README.md. This was an
  assumption made when the rule was written, not an explicit instruction.
