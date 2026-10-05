#!/usr/bin/env bash
# Parses the JavaScript corpus with canon's JavaScript grammar: shallow-clones each repository below,
# pinned to a commit, into the directory given as the first argument (default /tmp/corpus/javascript),
# parses every .js, .mjs, and .cjs file with the plain grammar under a per-file timeout, prints per
# repository the files parsed, the deliberate exclusions, the failures, and the slowest files, and
# then parses every file the plain grammar parsed with the canonically commented dialect, which must
# parse them all. Large repositories are sampled by subdirectory with a sparse checkout; the sampled
# paths are the patterns after the commit below. Node classifies the failures: a file node --check
# rejects is an exclusion. See jsts-common.sh for the environment it reads.
# ref:DEC-more-languages ref:DEC-javascript-dialect
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=${1:-/tmp/corpus/javascript}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
PLAIN=("$CANON_DIR/grammars/javascript/JavaScriptLexer.g4" "$CANON_DIR/grammars/javascript/JavaScriptParser.g4")
DIALECT=("$CANON_DIR/grammars/javascript/canonically_commented/JavaScriptLexer.g4" "$CANON_DIR/grammars/javascript/canonically_commented/JavaScriptParser.g4")
START=program
EXTENSIONS=('*.js' '*.mjs' '*.cjs')
# Minified bundles and vendored builds are generated, not code a person documents.
SKIPPED=('*.min.js' '*/dist/*' '*/build/*')

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "react https://github.com/facebook/react 278794d7dee9cd2a3a2aaf9f0b2a4b8b747d74ee /packages/"
  "node https://github.com/nodejs/node 019e869ad3a3941cd83d6b77fb1d4b3eaad2d64c /lib/"
  "lodash https://github.com/lodash/lodash 2b5e6f7399a7b48005140b5d5c6bc6c0e62919a8"
  "express https://github.com/expressjs/express 7ef98448f8b38099ab1ded55e458538ad47a51e7"
  "three.js https://github.com/mrdoob/three.js 457581a08070dd660d3bbfb01ec57d6920d4477d /src/"
)

# The class of a failing file that is a deliberate exclusion, or nothing: a file node itself rejects,
# by node --check, which in React is Flow type syntax or JSX, neither of which is JavaScript and
# both of which React compiles away with Babel before node or a browser reads it.
exclusion_class() {
  local file=$3
  command -v node > /dev/null || return 0
  if ! node --check "$file" > /dev/null 2>&1; then
    if grep -qE '@flow|@noflow|import type |</[A-Za-z]|/>' "$file"; then
      printf 'Flow or JSX syntax, which node rejects'
    else
      printf 'rejected by node'
    fi
  fi
}

# shellcheck source=jsts-common.sh
source "$CANON_DIR/tools/corpus/jsts-common.sh"
run_corpus
