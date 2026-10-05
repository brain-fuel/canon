# Folio Grammar

`FolioLexer.g4` and `FolioParser.g4` are canon's own grammar of the Folio, the
literate form of Markdown with front matter, citations, and fenced blocks that
tangle, under canon's MIT license. The plain grammar reads a page one token per
line, and the page extraction, the tangler, and the site read its tree
(`DEC-folio-language`). `canonically_commented/` holds the dialect, which reads
a page as units by labels: the page a unit of kind `doc` whose Why is its front
matter, and each section with prose a unit of kind `section` whose Why is its
prose and whose How is its fenced blocks (`DEC-folio-dialect`).

## Changes in canon

- The dialect's prose is a run of words to the next fenced block or heading,
  and two runs never stand side by side; a front-matter field's value takes
  every line up to the next field. Before, a section of `n` lines could be split
  into runs in every way and a field's value into lines, and canon's parser
  tried them, so a section of forty lines of Rice's Tax's documentation took
  six seconds and one of eighty more than thirty. Each page now has one parse.

## Corpus

The Folio has no public corpus, so the corpus is the projects written in it,
read in place and never modified. A Folio page is a Markdown file under a
`docs/` tree, where canon's README rule 2 places pages; a project's other
Markdown, such as its `README.md` and `CHANGELOG.md`, is no page. The copies a
mutation-testing run leaves under `.mut/` are not pages either.
`tools/corpus/folio.sh [dir]` parses every page with the plain grammar under a
limit of 10 CPU seconds, then every page that parsed with the dialect, and prints each
repository's counts, failures, and slowest files, writing its results under
`dir` (default `/tmp/corpus/folio`). `CORPUS_PROJECTS` names the directory that
holds the other projects (default `/Users/mattlaine/para/projects`); a project
that is absent is skipped.

| Repository | Pages | Parsed (plain) | Parsed (dialect) | Excluded | CPU time (plain) |
|------------|-------|----------------|------------------|----------|---------------|
| canon `docs/` | 2 | 2 | 2 | 0 | 0.1 s |
| Rice's Tax `docs/` | 50 | 50 | 50 | 0 | 2.2 s |
| Rice's Tax `examples/*/docs/` | 9 | 9 | 9 | 0 | 0.4 s |
| wavelet `docs/` | absent | | | | |

With 8 parses in parallel, every page parses through the plain grammar in under
half a second, the slowest Rice's Tax's `docs/reference/wire.md` at 0.27 s, and
through the dialect in under a second, the slowest
`docs/explanation/mutant-decision-lifecycle.md` at 0.58 s. A page that
fails, as one with a fence left open, fails in a twentieth of a second.

## Known limitations

- The dialect tokenizes prose into words, and canon's parser takes time
  quadratic in the tokens of one run of prose: a section of 400 lines of prose
  without a fenced block takes about six seconds through the dialect, where the
  plain grammar, one token per line, takes a tenth of a second. No page of
  the corpus comes near it. Making the loop
  linear is a change to `src/Canon/Antlr4/Parse.hs`.
