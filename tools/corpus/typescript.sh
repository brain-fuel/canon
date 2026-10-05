#!/usr/bin/env bash
# Parses the TypeScript corpus with canon's TypeScript grammar: shallow-clones each repository below,
# pinned to a commit, into the directory given as the first argument (default /tmp/corpus/typescript),
# parses every .ts, .mts, and .cts file with the plain grammar under a per-file timeout, prints per
# repository the files parsed, the deliberate exclusions, the failures, and the slowest files, and
# then parses every file the plain grammar parsed with the canonically commented dialect, which must
# parse them all. Large repositories are sampled by subdirectory with a sparse checkout; the sampled
# paths are the patterns after the commit below. See jsts-common.sh for the environment it reads.
# ref:DEC-more-languages ref:DEC-typescript-dialect
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=${1:-/tmp/corpus/typescript}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
PLAIN=("$CANON_DIR/grammars/typescript/TypeScriptLexer.g4" "$CANON_DIR/grammars/typescript/TypeScriptParser.g4")
DIALECT=("$CANON_DIR/grammars/typescript/canonically_commented/TypeScriptLexer.g4" "$CANON_DIR/grammars/typescript/canonically_commented/TypeScriptParser.g4")
START=program
EXTENSIONS=('*.ts' '*.mts' '*.cts')
SKIPPED=()

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "TypeScript https://github.com/microsoft/TypeScript 050880ce59e30b356b686bd3144efe24f875ebc8 /src/"
  "vscode https://github.com/microsoft/vscode 729f257fa411ea4b1cbdb7f404aa79941182209b /src/vs/base/common/ /src/vs/editor/common/"
  "angular https://github.com/angular/angular 7d96a37af4f7b7dd9dc9a2b9b90cc043c7da2a31 /packages/core/src/ /packages/common/src/ /packages/router/src/"
  "nest https://github.com/nestjs/nest 35142c3eca8edaaf6abc5984d915da2fbd458aa2 /packages/"
  "std https://github.com/denoland/std f834d0223364361169314833e3c7a8f62ce11d58"
)

# The class of a failing file that is a deliberate exclusion, or nothing: a file the TypeScript
# compiler's own parser rejects, by a TS1xxx syntax error from tsc, when tsc is on the path.
exclusion_class() {
  local file=$3
  command -v tsc > /dev/null || return 0
  if timeout 120 tsc --noEmit --pretty false --noResolve --skipLibCheck --types '' --lib esnext "$file" 2>&1 | grep -qE 'error TS1[0-9]{3}'; then
    printf 'rejected by the TypeScript parser'
  fi
}

# shellcheck source=jsts-common.sh
source "$CANON_DIR/tools/corpus/jsts-common.sh"
run_corpus
