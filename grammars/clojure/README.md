# Clojure grammar

`Clojure.g4` is the grammars-v4 Clojure grammar, a reader of s-expressions, with the changes marked
`// canon:` in it and recorded as `DEC-clojure-grammar-fixes`. `canonically_commented/Clojure.g4` is
its canonically commented dialect, the same grammar with definition forms as labeled units
(`DEC-clojure-dialect`). Every change to the plain grammar is mirrored in the dialect.

## Changes from grammars-v4

- A keyword is one token, `KEYWORD` for `:name` and `MACRO_KEYWORD` for `::name`, of every character
  up to whitespace, a comma, or a character that ends a token for the reader, so `:1.8` and
  `:div#foo.bar` are keywords.
- A backslash in a string always starts an escape, so `"\\"` ends at its second quote.
- A quote may follow the first character of a symbol, as `x'` and `db'` name the next value of `x`
  and `db`.
- `##Inf`, `##-Inf`, and `##NaN` are numbers, `SYMBOLIC_VALUE`.
- A namespaced map, `#:ns{...}`, `#::{...}`, or `#::alias{...}`, is `ns_map`: a `#`, a keyword,
  and a map.
- A var quote quotes any form, so `#'~name` inside a syntax quote parses.
- A map is any run of forms, since a discarded `#_x` may stand among its entries; the reader, not
  the grammar, checks that keys and values pair.

## Corpus

`tools/corpus/clojure.sh` clones the projects below, each pinned to a commit, shallow and
blob-filtered, parses every `.clj`, `.cljc`, and `.cljs` file with `Clojure.g4` under a limit of
10 CPU seconds per file, and then parses every file the plain grammar accepted with the dialect, which
must accept it too. Rerun it with:

```
tools/corpus/clojure.sh [clone-dir]   # default /tmp/corpus/clojure
```

`CORPUS_TIMEOUT`, `CORPUS_JOBS`, `CORPUS_CANON`, and `CORPUS_CLONE_ONLY` adjust the timeout, the
parallel parses, the binary, and whether to parse at all.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Dialect | CPU time |
|---|---|---|---|---|---|---|---|
| clojure/clojure | `a10f778f31fb` | `src/clj/` | 49 | 49 | 0 | 49 | 6.9 s |
| ring-clojure/ring | `f14beaf7d7e2` | whole | 81 | 81 | 0 | 81 | 5.2 s |
| weavejester/compojure | `8a4758d28e8f` | whole | 12 | 12 | 0 | 12 | 0.9 s |
| tonsky/datascript | `34915cf673c0` | whole | 68 | 68 | 0 | 68 | 6.9 s |
| metabase/metabase | `0e58a35cea0e` | `src/` | 1,764 | 1,764 | 0 | 1,764 | 145.7 s |

Every file parses with both grammars, and nothing is excluded. Time is the plain grammar's CPU
seconds summed over a repository's files. Of 1,974 files, 1,967 took less than half a second, 6 from
half a second to one, and 1 from one to two; the slowest are clojure's `core.clj` (1.7 s, 8,000
lines), metabase's `custom_migrations.clj` (0.70 s), and datascript's `db.cljc` (0.64 s).

Before the changes above, 84 files failed, most on primed symbols such as `db'` and the rest on
`##NaN` and `##Inf`, namespaced maps, `#'~typ`, and a discarded form inside a map.

## Limitations

- The grammar reads every form a Clojure reader reads, and some it rejects: a map with an odd
  number of forms parses.
- A tagged literal, `#inst "..."`, is a dispatch on a symbol, and a reader conditional, `#?(...)`,
  a dispatch on `?`; both parse, and neither is interpreted.
