# Rust Grammar

This grammar is based on official language reference
at https://doc.rust-lang.org/reference/.

## Reference
* [pldb](http://pldb.info/concepts/rust)


## License
MIT

## Comments
Last updated for rust v1.60.0.

## Known limitations
- Only v2018+ stable feature is implemented.
- Checks about isolated `\r` are not implemented. 

## Provenance in canon

`RustLexer.g4` and `RustParser.g4` are from
[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/8af0d4c26c796ea27c15c3d85418f2d0f77c3adb/rust)
at commit `8af0d4c26c796ea27c15c3d85418f2d0f77c3adb`, under the MIT license in
their headers (Copyright (c) 2010 The Rust Project Developers, Copyright (c)
2020-2022 Student Main). The README above is upstream's. canon interprets the
grammar itself and has no port of the `RustLexerBase` and `RustParserBase`
classes, so every change is marked `// canon:` in the grammar and recorded as
`DEC-rust-grammar` in canon's `canonical_decisions.yaml`:

- `SHEBANG` loses its start-of-file predicate and may not continue with `[`,
  so `#![no_std]` stays an inner attribute.
- `FLOAT_LITERAL` loses its two predicates and its bare-dot form (`1.`), so
  `1..2` and `1.max(2)` lex as integers; `tupleIndex` accepts the float that
  `x.0.1` then lexes to.
- `shl` and `shr` lose the predicates that required touching brackets.
- A backslash in a string or byte string always starts an escape, and a line
  continuation may end in `\r\n`.
- Outer attributes and visibility move from `item`, `associatedItem`, and
  `externalItem` into each kind of item through `itemPrefix`, so an item's
  node starts at its first attribute and the doc comment above binds to it;
  each attribute is labeled `marker` for test recognition.
- `tokenTree` and `macroMatch` take one token each instead of runs, which made
  macro bodies exponential to parse; the language is the same.
- Fixes for Rust upstream rejects: bounds on associated types, `union` as an
  identifier, `&&` before a type, keywords as macro metavariable names, the
  `~` token, and the underscore expression `_ = x;`.
- `LINE_COMMENT` and `OUTER_LINE_DOC` may not continue with a line break
  after `//` or `///`. Upstream's let an empty comment run on through the next
  line, which hid the code there.
- A bare `pub` is labeled `required`; `pub(crate)`, `pub(super)`, `pub(self)`,
  and `pub(in path)` are not. `#[macro_export]` is labeled `required`. The
  items of a trait and the variants of an enum are labeled `inherited`, so they
  need a comment when their trait or enum does. This is what rustc's
  `missing_docs` lint asks for, recorded as `DEC-rust-visibility`.
- A trait impl's trait and self type are one rule, `traitImplTarget`, which
  names the impl, so `impl Deref for Guard<T>` is `Deref-for-Guard<T>`.

Unstable syntax, such as `default fn` under specialization, is not accepted.
