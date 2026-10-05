# ANTLR 4 Meta-Grammar

`ANTLRv4Lexer.g4` and `ANTLRv4Parser.g4` are ANTLR's own grammar of ANTLR 4
grammars, as [antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/master/antlr/antlr4)
publishes it, under the BSD license in their headers. The `LexerAdaptor` hook in
`src/Canon/Antlr4/Lex/Adaptor.hs` ports the Java adaptor the lexer names as its
`superClass`. `canonically_commented/` holds the dialect canon reads its own
grammars through (`DEC-grammar-carries-extraction-rules`).

## Changes in canon

Every change is marked `// canon:` in the grammar.

- canon's lexer interpreter backtracks where ANTLR's simulates every
  alternative at once, so a text with two readings is read twice, and the
  readings multiply. Inside an action (`NESTED_ACTION`), a line comment runs to
  its line break, a slash that opens no comment is an alternative of its own,
  and the catch-all character takes no slash, so each comment has one reading.
  An escape (`ESC_SEQUENCE`) is a backslash and the one character after it; the
  hex digits of a Unicode escape are ordinary characters of the literal, which
  matches the same text. Before, the action of grammars-v4's `ECMAScript.g4`,
  with about twenty comments, and a literal of forty escapes each lexed for
  minutes.
- A quoted string inside an action may span lines, as the ANTLR tool's own
  `ACTION_STRING_LITERAL` and `ACTION_CHAR_LITERAL` do, so an apostrophe in a
  target comment that ANTLR does not know as one, such as Python's `#`, pairs
  with the next apostrophe as the tool pairs it. A triple-quoted string is then
  three strings, so its alternative is gone.

The dialect carries the same changes, and these of its own:

- A parser rule and a non-fragment lexer rule take an optional canonical
  comment and hold the empty rule `documentedRule`, labeled `required`, so a
  rule without one parses and is reported as missing its comment, as every
  other dialect reports it. Before, a grammar without a comment on every rule
  did not parse, which was 1,127 of the 1,135 grammars of grammars-v4 the plain
  grammar then read.
- Of several canonical comments in a row before the grammar, a mode, or a
  rule, the last binds and the others are orphans.
- `/**/` is an empty plain comment, not the opener of a canonical comment.
- The parser names `canonicalComment` in a `strayComment` option, so a `/**`
  comment inside a rule's alternatives, after the declaration, or after the last
  rule is read as an orphan (`DEC-stray-comments`).

## Corpus

`tools/corpus/antlr4.sh [dir]` clones grammars-v4 shallow and blob-filtered
into `dir` (default `/tmp/corpus/antlr4`), parses every `.g4` file with the
plain meta-grammar under a limit of 10 CPU seconds, then every file that parsed with
the dialect, and prints each repository's counts, failures, and slowest files.
canon's own `grammars/` is the second repository. `CORPUS_TIMEOUT` and
`CORPUS_JOBS` set the timeout and the parallel parses.

| Repository | Commit | Files | Parsed (plain) | Parsed (dialect) | Excluded | CPU time (plain) |
|------------|--------|-------|----------------|------------------|----------|---------------|
| antlr/grammars-v4 | `7df52be94698550d219d299d04105c6bafadd9c3` | 1,154 | 1,152 | 1,152 | 2 | 134 s |
| canon `grammars/` | the working tree | 84 | 84 | 84 | 0 | 9.6 s |

The two exclusions are negative fixtures of grammars-v4's own meta-grammar
test, each with a `.errors` file beside it holding the errors the
meta-grammar must report:

- `antlr/antlr4/examples/LexerElementLabel.g4`: an element label in a lexer
  rule, which ANTLR rejects.
- `antlr/antlr4/examples/three.g4`: `/**/` opens a comment that runs to the
  end of the file, so the grammar has no rules.

Plain-grammar CPU time per file over both repositories: 1,206 files under half
a second, 24 from half a second to one, 4 from one to two, and 2 from two to
five. The slowest are grammars-v4's `sql/plsql/PlSqlParser.g4`, 10,108 lines
(2.2 s), its copy under `antlr/antlr4/examples/` (2.0 s), and
`sql/tsql/TSqlParser.g4` and `asm/nasm/nasm_x86_64_Parser.g4` (1.2 s). A file that fails, fails within a
quarter of a second: a syntax error at the end of `PlSqlParser.g4` is reported
at once, and an action left open lexes no further at once rather than after
minutes.

## Known limitations

- A slash directly before the `}` that closes an action does not lex; no
  grammar of the corpus has one.
