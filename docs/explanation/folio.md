---
id: canon.folio
kind: explanation
title: The Folio, or why a page can be the source of its code
---
# The Folio

A Folio page is Markdown with three rules on top: it begins with front matter naming its `id`, its
`kind`, and its `title`; its prose cites with `ref:KEY` like a canonical comment; and a fenced block
whose info string names a `file=` tangles into that file, declaring with `def=` the unit it defines or
with `part=` that it is scaffolding. Everything else on the page is prose. ref:DEC-folio-language

## The section is the Why

The prose between the heading above a block and the block itself is the block's rationale. When
canon tangles, that prose becomes the generated documentation comment above the code, ending with the
address of its section; when canon checks, that same prose is the canonical comment of every unit the
block holds, and its digest is of the page rather than of the projection. A comment inside a block is
refused: prose has one home, and it is the page. ref:DEC-section-prose-is-why

## The units keep the tangled path

A unit found in a tangled file keeps that file in its id, because the tangled module is where the
export rule and name uniqueness are decided and because a page may tangle into several files and a
file may be tangled from several pages. Its Where names the page and the line, so every finding points
at what a person edits. A verdict on a comment keeps its key across the move from a source tree to
pages; only the file the verdict sits in changes. ref:DEC-units-by-tangled-path

## The four quadrants

Pages live under `docs/tutorials/`, `docs/how-to/`, `docs/reference/`, and `docs/explanation/`,
after Diátaxis, and a page's `kind` must match its directory. Each page is canonical material of the
kind `doc`, judged as a whole with the same four words as a comment, so a page that drifts from the
project it describes is pending again. A tutorial or a how-to may name a `video:` on the same topic, a
second medium for the same material; nothing is owed when it names none. ref:DEC-docs-tree
ref:DEC-doc-kind ref:DEC-video-reference ref:diataxis
