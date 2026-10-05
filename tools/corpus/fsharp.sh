#!/usr/bin/env bash
# Parse a corpus of widely used F# projects with canon's F# grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/fsharp.sh [CORPUS_DIR]   (default /tmp/corpus/fsharp; JOBS, TIMEOUT, and ONLY,
# one repository's name, may be set in the environment). Run from anywhere; the clones never
# enter the repository. ref:DEC-fsharp-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/fsharp}
JOBS=${JOBS:-8}
TIMEOUT=${TIMEOUT:-20}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=net-common.sh
. "$ROOT/tools/corpus/net-common.sh"

G=$ROOT/grammars/fsharp
PLAIN_LEXER=$G/FSharpLexer.g4
PLAIN_PARSER=$G/FSharpParser.g4
DIALECT_LEXER=$G/canonically_commented/FSharpLexer.g4
DIALECT_PARSER=$G/canonically_commented/FSharpParser.g4
START=file

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "fsharp https://github.com/dotnet/fsharp d16ac1bc6d29afc0652787af2814ac4d6863a9d9 src/FSharp.Core"
  "fantomas https://github.com/fsprojects/fantomas 0b69ef1393883cafc763ae6a1922e11e1b69b4a1 src"
  "giraffe https://github.com/giraffe-fsharp/Giraffe 279fe3a30c27bd647d2655745f71190c74bdd749"
  "fake https://github.com/fsprojects/FAKE e8e1cae79e3573167d7421c622b51adc8c536004 src/app"
  "paket https://github.com/fsprojects/Paket 641da499fb7078bfa2e6bb4d79782d1dffbe31b7 src/Paket.Core src/Paket"
)

# Files left out deliberately, as "repository path reason": files the F# compiler rejects, invalid-code
# test fixtures, and generated files. A path ending in / leaves out the directory.
EXCLUDES=$(cat <<'EXC'
EXC
)

# The existing samples, vendored in the repository.
SAMPLES=(fsharp-giraffe-viewengine)

corpus_main fsharp -name '*.fs' -o -name '*.fsi' -o -name '*.fsx'
