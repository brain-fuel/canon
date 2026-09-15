# Provisional canonical comment syntax

Waiting for: the canonically commented grammars per language, which define
comment structure and attachment. The ANTLR meta-grammar has one since
2026-09-14 (ref DEC-grammar-carries-extraction-rules in the ledger), so
nothing here applies to `.g4` files any more. Everything here is provisional
and applies only to languages checked through a profile with `units`, which
today are the sample languages Erlang, Clojure, Prolog, and Haskell.

Date: 2026-09-14

## Rules

- Only doc comments, `/** ... */` or the profile's comment syntax, are
  canonical. Line comments and plain block comments are ignored.
- A doc comment binds to the unit whose first line is directly below the
  comment's last line. A blank line between them breaks the binding, because a
  blank line is the universal signal that a comment stands alone. A doc
  comment that binds to nothing is reported as an orphan.
- The comment body, with the delimiters and leading stars removed, is the
  "Why?".
- A reference is cited as a token `ref:KEY` anywhere in the body, and a
  license as `license:KEY`, whose registry entry must be of kind `license`.
  `KEY` must exist in `canonical_refs.yaml`. Keys start and end with an ASCII
  letter or digit and may contain `.`, `_`, and `-` in between, so sentence
  punctuation after a key is not part of it.
- A doc comment starting on the file's first non-blank line is the file-level
  comment and binds to the file unit. It is not considered for line adjacency
  to the first unit.
- Which parse-tree rules are units, and whether each requires a comment, comes
  from the profile's `units` list.

## What replaced this for ANTLR

`grammars/antlr4/canonically_commented/` expresses all of the above as
grammar: a `DocComment` lexer mode, a `canonicalComment` parser rule, and
labeled alternatives with `why`, `what`, and `how` elements. Attachment is
then a matter of where the grammar allows `canonicalComment`, which is
directly before the unit, with no adjacency rule needed. Doing the same for
each sample language is what retires this record.

## Example

```
/** Match stuff like @init {int i;}; required by ref:grammars-v4 */
ruleAction
    : AT identifier actionBlock
    ;
```
