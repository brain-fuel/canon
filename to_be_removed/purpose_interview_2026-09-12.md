# Source material: the project owner's answers on the purpose of canon

Waiting for: confirmation that README.md captures every statement below, after
which this file is deleted.

Date: 2026-09-12. Answers are quoted verbatim from the project owner. The
questions are paraphrased.

## What lives in `grammars/<lang>/canonically_commented/`?

> A grammar for canonically commented code of the specified language; valid
> language code might not be valid, canonically-commented code.

## What does canon do with what it extracts?

Selected: generate documentation, check parity, emit a structured model,
enforce the standard.

> Canon, in addition to emitting a structured, machine-readable model, ought to
> also help us ensure that every single Who, What, When, Where, Why, and How
> has a single canonical source that does not drift away from its intended
> meaning; this corresponds with Rice's Theorem and ensuring that everything
> that is not decideable by a compiler is explained by a human. There are many
> examples, but one that immediately comes to mind is "Such-and-such a function
> exists because of business requirement XYZ".

## Must every code unit carry a canonical comment?

> Not every code unit requires commenting; only the public apis, or things used
> across modules, or steps in programs that are being run require them;
> otherwise it's optional

## Where does a canonical comment attach?

> Defined by the grammar per language

## How do the upstream grammar and the canonical grammar relate?

> The regular grammar is the official one kept by the ANTLR folks; The
> canonical one is one we modify in order to keep this whole canonical project
> working. The entire point of this project is to make humans and LLMs be able
> to keep every decision (for example, an ADR + architect ~ a comment + code)
> and who, what, when, where, why, how, evergreen. No liar's comments; no
> liar's architecture; no lies are allowed in general and the tooling makes it
> tractable for humans to conduct human review, and the compiler + PBT +
> Mutation Testing + Decision Coverage to verify what it all can.

## What are "steps in programs that are being run"?

> Any non-trivial semantic property of the code that becomes a part of the
> domain language.

## Where do canonical comments cite references?

Selected: pointer to a registry. The comment carries a short key, and a
project-level registry maps keys to full references, so a reference has one
canonical source.

## Standing instructions given alongside

> ZERO COMMENTS IN CODE until we establish standards for that. appropriate
> naming should suffice for now.

> Do not trust your memory; if it isn't written down in canonical form (or in
> the folder of stuff to be thrown away once we have a canonical place for it),
> it cannot be trusted.
