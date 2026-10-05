#!/usr/bin/env bash
# Parse a corpus of widely used Java projects with canon's Java grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/java.sh [CORPUS_DIR]   (default /tmp/corpus/java; JOBS and TIMEOUT
# may be set in the environment). Run from anywhere; the clones never enter the repository.
# ref:DEC-java-grammar
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/java}
JOBS=${JOBS:-8}
TIMEOUT=${TIMEOUT:-20}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=jvm-common.sh
. "$ROOT/tools/corpus/jvm-common.sh"

G=$ROOT/grammars/java
PLAIN_LEXER=$G/JavaLexer.g4
PLAIN_PARSER=$G/JavaParser.g4
DIALECT_LEXER=$G/canonically_commented/JavaLexer.g4
DIALECT_PARSER=$G/canonically_commented/JavaParser.g4
START=compilationUnit

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "spring-framework https://github.com/spring-projects/spring-framework 3a91d153165490b0736c9907fda1d8669c6ef3f4 spring-core spring-beans spring-context spring-web"
  "guava https://github.com/google/guava 81c7d030f8f144a4885ccf8efdc72c92605b4eec guava guava-testlib guava-tests"
  "elasticsearch https://github.com/elastic/elasticsearch c11078209dc8e63b7669216655cc62185487b70b libs modules/lang-painless server/src/main/java/org/elasticsearch/cluster"
  "jdk https://github.com/openjdk/jdk 8cbb6b7036f1cbc48efea2d9e4830d240ab01fec src/java.base"
  "commons-lang https://github.com/apache/commons-lang 682a8ff5cddfeedecb98f62ac7c8d94b5ff65f33"
)

# Files left out deliberately, as "repository path reason": files javac rejects, invalid-code
# test fixtures, and generated files.
EXCLUDES=$(cat <<'EOF'
EOF
)

mkdir -p "$CORPUS/results"
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  echo "cloning $1 at $3${4:+ (sampled: ${*:4})}" >&2
  corpus_clone "$CORPUS/$1" "$2" "$3" "${@:4}"
done

# The existing samples, vendored in the repository.
SAMPLES=(java-commons-lang java-gson java-joda-time)

run_all() {
  local kind=$1 lexer=$2 parser=$3 name ex
  echo "== $kind grammar"
  for entry in "${REPOS[@]}" "${SAMPLES[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    name=$1
    local dir=$CORPUS/$name
    [ -d "$dir" ] || dir=$ROOT/lang_samples/$name/source
    ex=$CORPUS/results/$name.excludes
    printf '%s\n' "$EXCLUDES" | awk -v n="$name" '$1 == n {print $2}' >"$ex"
    corpus_run "$name" "$dir" "$lexer" "$parser" "$START" "$CORPUS/results/$name.$kind" "$ex" -name '*.java'
  done
}

run_all plain "$PLAIN_LEXER" "$PLAIN_PARSER"
run_all dialect "$DIALECT_LEXER" "$DIALECT_PARSER"

echo "== files the plain grammar parses and the dialect does not"
for entry in "${REPOS[@]}" "${SAMPLES[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  dir=$CORPUS/$1
  [ -d "$dir" ] || dir=$ROOT/lang_samples/$1/source
  corpus_compare "$CORPUS/results/$1.plain" "$CORPUS/results/$1.dialect" "$dir" "$CORPUS/results/$1.excludes"
done
echo "== timing"
corpus_histogram "$CORPUS"/results/*.plain
