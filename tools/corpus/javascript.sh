#!/usr/bin/env bash
# Parses the JavaScript corpus with canon's JavaScript grammar: shallow-clones each repository below,
# pinned to a commit, into the directory given as the first argument (default /tmp/corpus/javascript),
# parses every .js, .jsx, .mjs, and .cjs file with the plain grammar under a per-file timeout,
# prints per repository and per kind of file (JS, JSX, Flow) the files parsed, the deliberate
# exclusions, the failures, and the slowest files, and then parses every file the plain grammar
# parsed with the canonically commented dialect, which must parse them all. A file whose first
# comment holds @flow, and every file of a repository listed in FLOW_REPOS, as a Flow project's
# profile would read it, is read by the TypeScript grammar's .tsx pair, which reads Flow's types and
# JSX; any other file by the JavaScript grammar, which reads JSX. Large repositories are sampled by
# subdirectory with a sparse checkout; the sampled paths are the patterns after the commit below.
# See jsts-common.sh for the environment it reads. ref:DEC-more-languages ref:DEC-javascript-dialect
# ref:DEC-javascript-jsx
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=${1:-/tmp/corpus/javascript}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
START=program
EXTENSIONS=('*.js' '*.jsx' '*.mjs' '*.cjs')
# Minified bundles and vendored builds are generated, not code a person documents.
SKIPPED=('*.min.js' '*/dist/*' '*/build/*')
# Repositories whose every file is Flow, as a Flow project's profile reads them.
FLOW_REPOS="react"

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "react https://github.com/facebook/react 278794d7dee9cd2a3a2aaf9f0b2a4b8b747d74ee /packages/"
  "node https://github.com/nodejs/node 019e869ad3a3941cd83d6b77fb1d4b3eaad2d64c /lib/"
  "lodash https://github.com/lodash/lodash 2b5e6f7399a7b48005140b5d5c6bc6c0e62919a8"
  "express https://github.com/expressjs/express 7ef98448f8b38099ab1ded55e458538ad47a51e7"
  "three.js https://github.com/mrdoob/three.js 457581a08070dd660d3bbfb01ec57d6920d4477d /src/"
  "next.js https://github.com/vercel/next.js 263f6820b21d451101dacb55c1299da441da168f /examples/ /packages/create-next-app/templates/"
  "material-ui https://github.com/mui/material-ui daaa525c3af0bd99329da1f1ab0d2bd64648ea79 /packages/mui-material/src/ /packages/mui-system/src/"
)

# Files a failure of which is a deliberate exclusion: the repository-relative path, a tab, and why.
EXCLUSIONS=(
  "next.js/examples/with-custom-babel-config/pages/index.js	the pipeline operator |>, a Babel proposal plugin's syntax and no JavaScript"
)

# The kind of a file and the grammar pair that reads it, for the plain grammar or the dialect. The
# kind JSX is the .jsx files and the .js files that hold a closing tag; it only groups the report.
grammar_for() {
  local which=$1 file=$2 sub= kind name rel
  [ "$which" = dialect ] && sub=/canonically_commented
  rel=${file#"$ROOT/"}
  name=${rel%%/*}
  if [[ " $FLOW_REPOS " == *" $name "* ]] || head -c 4000 "$file" | perl -0ne 'exit !(/\A\s*(?:#![^\n]*\n\s*)?(\/\*.*?\*\/|\/\/[^\n]*(?:\n\s*\/\/[^\n]*)*)/s && $1 =~ /\@flow\b/)'; then
    printf 'Flow\t%s\t%s\n' "$CANON_DIR/grammars/typescript$sub/TypeScriptJsxLexer.g4" "$CANON_DIR/grammars/typescript$sub/TypeScriptParser.g4"
    return
  fi
  kind=JS
  if [[ $file == *.jsx ]] || grep -qE '</[A-Za-z]*>|/>' "$file"; then kind=JSX; fi
  printf '%s\t%s\t%s\n' "$kind" "$CANON_DIR/grammars/javascript$sub/JavaScriptLexer.g4" "$CANON_DIR/grammars/javascript$sub/JavaScriptParser.g4"
}
export ROOT FLOW_REPOS

# The class of a failing file that is a deliberate exclusion, or nothing.
exclusion_class() {
  local name=$1 rel=$2 entry
  for entry in ${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}; do
    if [ "${entry%%	*}" = "$name/$rel" ]; then
      printf '%s' "${entry#*	}"
      return
    fi
  done
}

# shellcheck source=jsts-common.sh
source "$CANON_DIR/tools/corpus/jsts-common.sh"
run_corpus
