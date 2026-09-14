# Provisional canonical comment syntax

Waiting for: the canonically commented grammars per language, which will
define comment structure and attachment. Everything here is provisional and
applies only to ANTLR grammar files.

Date: 2026-09-14

## Rules

- Only doc comments, `/** ... */`, are canonical. Line comments and plain block
  comments are ignored.
- A doc comment binds to the rule whose first line is directly below the
  comment's last line. A blank line between them breaks the binding, because a
  blank line is the universal signal that a comment stands alone, and because
  the upstream grammars use exactly that layout for section headers. A doc
  comment that binds to nothing is reported as an orphan.
- The comment body, with the delimiters and leading stars removed, is the
  "Why?".
- A reference is cited as a token `ref:KEY` anywhere in the body. `KEY` must
  exist in `canonical_refs.yaml`. Keys start and end with an ASCII letter or
  digit and may contain `.`, `_`, and `-` in between, so sentence punctuation
  after a key is not part of it.
- Every parser rule and every non-fragment lexer rule requires a canonical
  comment. Fragments are optional. Parser rules are the public methods of the
  generated parser and token rules are the vocabulary another grammar imports,
  which are the "public API" and "used across modules" cases of the README.

## Example

```
/** Match stuff like @init {int i;}; required by ref:grammars-v4 */
ruleAction
    : AT identifier actionBlock
    ;
```
