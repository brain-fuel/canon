# canon's front door: the Stack commands the README names, so a person types make and a verb.
# Every target runs natively, since canon is a library and a binary and nothing more, and each is
# canonically commented like every other unit of the project. ref:DEC-make-dialect

# | Where Stack put the binary, read once so every target runs the build it just made.
BIN = $$(stack path --local-install-root)/bin/canon

# | The directory the site is rendered into.
OUT ?= _site

.DEFAULT_GOAL := help
.PHONY: help build test check ingest vet decisions tangle tangle-check site clean

# | What you can ask for, read from the help lines of the rules below, so the list cannot drift.
help: ## what you can ask for
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | awk -F'\t' '{ printf "  %-12s %s\n", $$1, $$2 }'

# | Build the library and the binary. ref:DEC-parser-foundation
build: ## build the library and the binary
	stack build --no-terminal

# | Run the suite: the interpreter against the meta-grammar, the dialects, the extraction, the
# vetting, the tangler. ref:DEC-parser-foundation
test: ## run the test suite
	stack test --no-terminal

# | Check canon itself: its sources, its grammars, and its pages, failing on any failing finding.
# ref:DEC-comment-vetting
check: build ## check the project with canon
	$(BIN) check

# | Record every piece of canonical material without a verdict as pending. ref:DEC-comment-vetting
ingest: build ## record new canonical material as pending
	$(BIN) ingest

# | List what needs a human verdict, with its text. ref:DEC-human-sign-off
vet: build ## list the material that needs a verdict
	$(BIN) vet

# | The decision ledger, open decisions first. ref:DEC-decision-ledger
decisions: build ## list the decision ledger
	$(BIN) decisions

# | Write every source the pages tangle to. ref:DEC-tangle-in-canon
tangle: build ## write the sources the pages tangle to
	$(BIN) tangle

# | Report the tangled sources that differ from their pages, without writing. ref:DEC-tangle-in-canon
tangle-check: build ## report stale tangled sources
	$(BIN) tangle --check

# | Render the pages to a static site under OUT. ref:DEC-site-renderer
site: build ## render docs/ to a static site
	$(BIN) site $(OUT)

# | Drop the extraction cache and the rendered site; the ledgers stay.
clean: ## drop the cache and the site
	rm -rf .canon-cache $(OUT)
