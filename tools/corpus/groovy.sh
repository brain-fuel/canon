#!/usr/bin/env bash
# Parse a corpus of widely used Groovy projects with canon's Groovy grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/groovy.sh [CORPUS_DIR]   (default /tmp/corpus/groovy; JOBS and TIMEOUT
# may be set in the environment). Run from anywhere; the clones never enter the repository.
# ref:DEC-groovy-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/groovy}
JOBS=${JOBS:-8}
TIMEOUT=${TIMEOUT:-20}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=jvm-common.sh
. "$ROOT/tools/corpus/jvm-common.sh"

G=$ROOT/grammars/groovy
PLAIN_LEXER=$G/GroovyLexer.g4
PLAIN_PARSER=$G/GroovyParser.g4
DIALECT_LEXER=$G/canonically_commented/GroovyLexer.g4
DIALECT_PARSER=$G/canonically_commented/GroovyParser.g4
START=compilationUnit

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "groovy https://github.com/apache/groovy 84b0d5072e2d8d02d10720b8a337493af1bda9fe src/main src/spec src/test subprojects/groovy-json subprojects/groovy-xml subprojects/groovy-sql subprojects/groovy-templates subprojects/groovy-console subprojects/groovy-swing subprojects/groovy-contracts subprojects/groovy-ginq subprojects/groovy-macro subprojects/groovy-typecheckers"
  "gradle https://github.com/gradle/gradle 81c85f2d52959d1bb34e523e4309de16ede8fc0c subprojects/core platforms/core-configuration"
  "spock https://github.com/spockframework/spock 61e6461703d572a1cca0f5b4112b521919f6b84a"
  "grails-core https://github.com/apache/grails-core 232bb340064ff0aead5a435fb2d8a4056d7c59d3 grails-core grails-gsp grails-datamapping-core grails-web-url-mappings grails-async grails-events grails-fields"
  "pipeline-examples https://github.com/jenkinsci/pipeline-examples fb9575a8182b51614f5f0df912b46b37d95fbb8d"
  "fabric8-pipeline-library https://github.com/fabric8io/fabric8-pipeline-library 8f3562d748d0fde2dfcb8b4d9600cfdce6d81e21"
)

# Files left out deliberately, as "repository path reason": files groovyc rejects, invalid-code
# test fixtures, and generated files.
EXCLUDES=$(cat <<'EOF'
spock spock-specs/src/test/resources/snapshots/ renderings of the ASTs and compiler errors that Spock tests compare against, not Groovy source
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
SAMPLES=(groovy-spock-genesis)

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
    corpus_run "$name" "$dir" "$lexer" "$parser" "$START" "$CORPUS/results/$name.$kind" "$ex" \
      -name '*.groovy' -o -name '*.gvy' -o -name '*.gy' -o -name '*.gsh' -o -name '*.gradle' -o -name 'Jenkinsfile*'
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
