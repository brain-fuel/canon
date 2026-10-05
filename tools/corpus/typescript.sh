#!/usr/bin/env bash
# Parses the TypeScript corpus with canon's TypeScript grammar: shallow-clones each repository below,
# pinned to a commit, into the directory given as the first argument (default /tmp/corpus/typescript),
# parses every .ts, .mts, .cts, and .tsx file with the plain grammar under a per-file timeout, a .tsx
# file through TypeScriptJsxLexer.g4, which reads JSX, prints per repository and per kind of file
# (TS, TSX) the files parsed, the deliberate exclusions, the failures, and the slowest files, and
# then parses every file the plain grammar parsed with the canonically commented dialect, which must
# parse them all. Large repositories are sampled by subdirectory with a sparse checkout; the sampled
# paths are the patterns after the commit below. See jsts-common.sh for the environment it reads.
# ref:DEC-more-languages ref:DEC-typescript-dialect ref:DEC-javascript-jsx
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=${1:-/tmp/corpus/typescript}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
START=program
EXTENSIONS=('*.ts' '*.mts' '*.cts' '*.tsx')
SKIPPED=()

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "TypeScript https://github.com/microsoft/TypeScript 050880ce59e30b356b686bd3144efe24f875ebc8 /src/"
  "vscode https://github.com/microsoft/vscode 729f257fa411ea4b1cbdb7f404aa79941182209b /src/vs/base/common/ /src/vs/editor/common/"
  "angular https://github.com/angular/angular 7d96a37af4f7b7dd9dc9a2b9b90cc043c7da2a31 /packages/core/src/ /packages/common/src/ /packages/router/src/"
  "nest https://github.com/nestjs/nest 35142c3eca8edaaf6abc5984d915da2fbd458aa2 /packages/"
  "std https://github.com/denoland/std f834d0223364361169314833e3c7a8f62ce11d58"
  "ui https://github.com/shadcn-ui/ui 0e3abd65a97707f4a9cc3ed07bf5006e1cb67b13 /apps/"
  "next.js https://github.com/vercel/next.js 263f6820b21d451101dacb55c1299da441da168f /packages/next/src/client/"
  "material-ui https://github.com/mui/material-ui daaa525c3af0bd99329da1f1ab0d2bd64648ea79 /packages/mui-material/src/"
)

# The kind of a file and the grammar pair that reads it, for the plain grammar or the dialect.
grammar_for() {
  local which=$1 file=$2 sub=
  [ "$which" = dialect ] && sub=/canonically_commented
  if [[ $file == *.tsx ]]; then
    printf 'TSX\t%s\t%s\n' "$CANON_DIR/grammars/typescript$sub/TypeScriptJsxLexer.g4" "$CANON_DIR/grammars/typescript$sub/TypeScriptParser.g4"
  else
    printf 'TS\t%s\t%s\n' "$CANON_DIR/grammars/typescript$sub/TypeScriptLexer.g4" "$CANON_DIR/grammars/typescript$sub/TypeScriptParser.g4"
  fi
}

# The class of a failing file that is a deliberate exclusion, or nothing: a file the TypeScript
# compiler's own parser rejects, by a TS1xxx syntax error from tsc, when tsc is on the path.
exclusion_class() {
  local file=$3
  command -v tsc > /dev/null || return 0
  if timeout 120 tsc --noEmit --pretty false --noResolve --skipLibCheck --types '' --lib esnext --jsx preserve "$file" 2>&1 | grep -qE 'error TS1[0-9]{3}'; then
    printf 'rejected by the TypeScript parser'
  fi
}

# shellcheck source=jsts-common.sh
source "$CANON_DIR/tools/corpus/jsts-common.sh"
run_corpus
