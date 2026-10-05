---
id: canon.how-to.tangle
kind: how-to
title: Tangle a project's pages into its sources
---
# Tangle a project's pages into its sources

Declare the Folio in `canon.yaml` as a language whose profile embeds the languages its blocks are
written in. The embedding names the profile that parses the blocks, the comment syntax a block must
not carry, the width a tangled line may have, and how a generated comment is spelled:

```yaml
languages:
  folio:
    extensions: [.md]
    lexer: grammars/folio/FolioLexer.g4
    parser: grammars/folio/FolioParser.g4
    start: document
    embeds:
      haskell:
        language: haskell
        comments: {line: "--", blockOpen: "{-", blockClose: "-}", strings: ["\""]}
        width: 98
        doc: {open: "-- | ", continue: "-- ", blank: "--", banner: "-- ", markup: haddock}
```

Then write every tangled source, or only check that the tree is current:

```
canon tangle
canon tangle --check
canon tangle --manifest
```

`canon tangle` writes each file its pages tangle to and says whether it was unchanged or written.
With `--check` it writes nothing and reports each stale file, exiting with failure, which is what a
build step wants. With `--manifest` it lists every block with its page, line, name, and the lines it
occupies in the tangled file. `canon check` reports a stale tangled file as a finding of its own, so a
project that forgets to tangle fails its check. ref:DEC-tangle-in-canon

To publish the pages, render them to a directory:

```
canon site _site
```

The site is one HTML page per document under its quadrant and an index of the four, written the same
way every time, so it can be built and compared in a pipeline. ref:DEC-site-renderer
