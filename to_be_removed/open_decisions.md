# Open decisions

Waiting for: each item to be decided and recorded in its canonical place.

Date opened: 2026-09-12

- **Content of `grammars/antlr4/canonically_commented/`.** The meta-grammar is
  vendored and read. What its canonically commented derivative looks like
  depends on the canonical comment format, which is undefined.
- **Precedence climbing.** The interpreter returns the first complete parse
  by alternative order. ANTLR rewrites a directly left-recursive rule into
  precedence levels, so `1*2+3` under `expr: expr '*' expr | expr '+' expr |
  INT` has `+` at the top for ANTLR and `*` at the top here. Implementing the
  rewrite is needed before expression grammars from grammars-v4 give ANTLR's
  trees.
- **Two notions of comment attachment.** The extractor binds a doc comment to
  the rule on the line directly below it; the canonical dialect grammar binds
  it to the next rule regardless of blank lines, because whitespace is off
  channel. One of them has to give.
- **Migrating prose decision records.** The canonical form of a decision now
  exists as the `Decision` type: a Why with cited registry keys, bound to unit
  ids. The prose records in this directory can become registry entries plus
  doc comments on the code they explain once the Haskell canonically commented
  grammar exists.
- **Comment attachment for other languages.** Grammars bind a doc comment to
  the rule on the line directly below it, with no blank line between. Whether
  the same rule holds for Haskell and other languages is for their
  canonically commented grammars to say.
- **Version duplication.** `canon.yaml` carries the project version that
  `package.yaml` also carries. A parity finding between the two is natural
  later work.
- **`canon.cabal` in version control.** It is currently ignored and
  regenerated from `package.yaml` by stack. Committing it would let plain
  cabal users build without hpack. Undecided.
- **Sample project README exception.** Rule 2 treats each directory under
  `sample_projects/` as its own project with its own README.md. This was an
  assumption made when the rule was written, not an explicit instruction.
