# Makefile grammar

`canonically_commented/MakefileLexer.g4` and `canonically_commented/MakefileParser.g4` are canon's
own grammar of GNU make, written canonically commented from the start, since grammars-v4 has no
Makefile grammar (`DEC-make-dialect`). A canonical comment opens with `# |` and continues on the
`#` lines below it; a rule with a plain target is a unit of kind `rule` that requires the comment,
its target the What and its recipe the How; a special target, a pattern rule, and a variable are
units whose comment is optional; `## text` after a rule's prerequisites is the one-line What the
`help` target prints.

## No plain sibling

The dialect is the reader: there is no plain `grammars/make/MakefileLexer.g4`. Every other language
keeps a plain grammar because it is vendored from grammars-v4 or the language's own project and is
kept as published; canon's Makefile grammar has no upstream, so a plain copy would be the dialect
without its labels and its `DocLine` mode, and would only have to be kept in step with it. What a
plain grammar would add, reading a makefile whose `# |` comments sit where no unit follows, the
dialect does itself: its `strayComment` option reads the file without such a comment and reports it
as an orphan (`DEC-stray-comments`). `tools/corpus/make.sh` therefore runs the same grammar for its
plain pass and its dialect pass.

## How it reads make

- The default lexer mode is the start of a line, where make looks for directives (`ifeq`, `ifdef`,
  `else`, `endif`, `define`, `include`, `undefine`, `vpath`, `load`), modifiers (`export`,
  `override`, `private`), and recipe lines. The first name or separator of a line moves to the
  `Body` mode, where those words are names, as in `all: define include` or `define = define`; the
  line break returns. `export = 1` assigns a variable named `export`, as make reads it.
- A name carries its references whole: `$(...)` and `${...}` nest to any depth and may hold colons,
  commas, equals signs, spaces, and hashes; `$\` before a line break joins two lines without a space.
- A backslash line break joins lines everywhere: in names, values, directives, comments, and recipe
  lines, so a continued recipe line need not start with a tab.
- An assignment takes any of make's operators (`=`, `:=`, `::=`, `:::=`, `?=`, `?:=`, `+=`, `!=`),
  with `override`, `private`, and `export` before the name; its value is one token to the end of the
  line. `define` takes a flavour after its name, and a `define` nested in a `define` is counted.
- A rule may be grouped (`&:`), double-colon, a static pattern rule (`targets: pattern: prereqs`),
  have order-only prerequisites, a target-specific assignment or export, and a recipe after `;`. Its
  recipe continues across blank lines, help lines, and conditionals between its recipe lines.
- A line of names with no separator, such as `$(eval $(call tpl,x))`, is an expansion statement;
  a tab-indented line that follows no rule is a statement too, since make reads it as an ordinary
  line; a line written with the prefix `.RECIPEPREFIX` sets reads as an expansion or a rule.

## Known limitations

- The lexer does not track whether a tab-indented line follows a rule, as make does. A tab-indented
  line outside a rule, which make reads as an ordinary line, is read as a stray recipe line: an
  assignment written so is no variable unit, and an `ifeq` indented with a tab whose `endif` is not
  would not balance. git's `Makefile` indents a whole conditional with tabs, which balances; no
  makefile of the corpus indents only one end.
- A name ending in `+`, `?`, `!`, or `&`, such as a target `c++`, is read as two names, which the
  parser accepts in every place a name may stand; the unit name is then the part before the symbol.
- `.RECIPEPREFIX` is not tracked: a recipe line written with another prefix is parsed as an
  expansion or a rule line and is not part of its rule's How.

## Corpus

`tools/corpus/make.sh [clone-dir]` (default `/tmp/corpus/make`) clones each repository below pinned to
a commit, shallow, blob-filtered, and sparse to its makefiles; extracts GNU make's test makefiles;
parses every makefile under a limit of 10 CPU seconds (`CORPUS_TIMEOUT`), eight at a time (`CORPUS_JOBS`);
and prints, per repository, the files parsed out of the files, the failures, the exclusions with
their reasons, and the slowest files. A makefile is a file named `Makefile`, `makefile`,
`GNUmakefile`, `Makefile.*`, `Kbuild`, `*.mk`, `*.mak`, or `config.mak.*`.

| Repository | Commit | Sampled |
|------------|--------|---------|
| torvalds/linux | `67f0943b394d920b6c142aad8c6af94340342ae7` | `Makefile`, `Kbuild`, `scripts/Makefile.*`, `scripts/Kbuild.include`, and the Makefiles of `kernel`, `mm`, `fs`, `fs/ext4`, `net`, `net/ipv4`, `drivers`, `drivers/net`, `arch/x86` (with `Makefile_32.cpu` and `boot`), `arch/arm64`, `tools/scripts/Makefile.include`, `tools/build/Makefile.build`, `tools/perf/Makefile.perf` and `Makefile.config` |
| python/cpython | `3f9118f1d17ae2ff0e25bd07fce9940ba13afdff` | `Makefile.pre.in` and every `Makefile` and `*.mk` |
| git/git | `8103b446517e0c44e67561b9d0ccce56efa60a71` | every `Makefile`, `*.mak`, `*.mk`, and `config.mak.*` |
| GNU make (mirror/make) | `c63a5bc6a2881d515bb3020ed477fcba08fb2f3d` | `tests/scripts`, whose makefiles are extracted |
| canon | this tree | its `Makefile` and the samples' |

GNU make's tests embed their makefiles in Perl: the script extracts the first argument of each
`run_make_test` call and each `print MAKEFILE` text that is a string literal or here-document,
evaluating only the literal, in a `Safe` compartment, into `<clone>/gnumake-tests/extracted/`. A
call whose makefile is `undef` reuses the previous one and adds no file; the 17 calls whose makefile
is built by a variable or `sprintf` are not extracted. A fixture whose expected output shows make
stopping on a syntax error is an invalid-code fixture, a documented exclusion.

| Repository | Files | Parsed | Excluded | Failing | CPU time |
|------------|------:|-------:|---------:|--------:|-----:|
| linux | 52 | 52 | 0 | 0 | 4.1 s |
| cpython | 5 | 5 | 0 | 0 | 0.7 s |
| git | 21 | 21 | 0 | 0 | 3.4 s |
| GNU make tests | 995 | 974 | 21 | 0 | 44.4 s |
| canon | 3 | 3 | 0 | 0 | 0.2 s |

Every file the grammar parses, it parses through the canonically commented dialect too, being the
same grammar. The 21 exclusions are fixtures make itself rejects, by the message their test
expects: `missing separator` (7), `unterminated variable reference` (3), `unterminated call to
function` (3), `empty variable name` (2), `invalid syntax in conditional` (2), `prerequisites cannot
be defined in recipes` (2), `missing 'endef'` (1), and `grouped targets must provide a recipe` (1).

Times are CPU seconds, the sum over a repository's files. Of the 1,055 files parsed, 1,054 parse in
under half a second; the slowest are git's 4,143-line `Makefile` (2.1 s), CPython's
`Makefile.pre.in` (0.45 s), and Linux's top `Makefile` (0.41 s). No file failed; a syntax
error on the last line of git's `Makefile` is reported in under 3 seconds.
