#!/usr/bin/env bash
# Parse a corpus of widely used Kotlin projects with canon's Kotlin grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/kotlin.sh [CORPUS_DIR]   (default /tmp/corpus/kotlin; JOBS and TIMEOUT
# may be set in the environment). Run from anywhere; the clones never enter the repository.
# ref:DEC-kotlin-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/kotlin}
JOBS=${JOBS:-8}
TIMEOUT=${TIMEOUT:-20}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=jvm-common.sh
. "$ROOT/tools/corpus/jvm-common.sh"

G=$ROOT/grammars/kotlin
PLAIN_LEXER=$G/KotlinLexer.g4
PLAIN_PARSER=$G/KotlinParser.g4
DIALECT_LEXER=$G/canonically_commented/KotlinLexer.g4
DIALECT_PARSER=$G/canonically_commented/KotlinParser.g4

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "kotlinx.coroutines https://github.com/Kotlin/kotlinx.coroutines bd2e9a1b90400fb7b2fa4f8731e7d8148799ab73"
  "ktor https://github.com/ktorio/ktor 1d177d32df5de4df0dfee67cee159e01e226419f ktor-server/ktor-server-core ktor-client/ktor-client-core ktor-http ktor-io ktor-utils ktor-shared/ktor-serialization"
  "okhttp https://github.com/square/okhttp ac3d46c892ef486eca5bd84259dfb9bc8778d909"
  "compose-multiplatform https://github.com/JetBrains/compose-multiplatform 6b7b6ad83bfc87ca554e00409fa25c6707513280"
  "kotlin-stdlib https://github.com/JetBrains/kotlin e5b61f33dedf8f0cd170ed316d321ac837478ffc libraries/stdlib"
)

# Files left out deliberately, as "repository path reason": files kotlinc rejects, invalid-code
# test fixtures, and generated files.
EXCLUDES=$(cat <<'EOF'
compose-multiplatform html/compose-compiler-integration/testcases/passing/ComposableWithDefaultValuesDefinedByOtherParams.kt test case of several modules, split at // @Module: markers by its harness; imports after declarations, which kotlinc rejects in one file
compose-multiplatform html/compose-compiler-integration/testcases/passing/ComposableWithParamsWithDefaultValues.kt test case of several modules, as above
compose-multiplatform html/compose-compiler-integration/testcases/passing/ComposableWithTypedDefaultValues.kt test case of several modules, as above
compose-multiplatform html/compose-compiler-integration/testcases/passing/ComposableWithTypeParams.kt test case of several modules, as above
compose-multiplatform html/compose-compiler-integration/testcases/passing/PassingComposableToConstructor.kt test case of several modules, as above
compose-multiplatform compose/integrations/compose-with-ktx-serialization/build.gradle.kts Groovy DSL in a .kts file, group "com.example", which kotlinc rejects
compose-multiplatform gradle-plugins/compose/src/test/test-projects/application/aot/build.gradle.kts template with a %JAVA_VERSION% placeholder its test fills in
compose-multiplatform gradle-plugins/compose/src/test/test-projects/misc/hugeResources/expected/String0.commonMain.kt generated, the expected output of the resource generator for a stress test, 0.9 MB, beyond the time limit
compose-multiplatform gradle-plugins/compose/src/test/test-projects/misc/hugeResources/expected/String100.commonMain.kt generated, as above
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
SAMPLES=(kotlin-turbine)

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
    corpus_run "$name" "$dir" "$lexer" "$parser" kotlinFile "$CORPUS/results/$name.$kind" "$ex" -name '*.kt'
    # A script is read from the rule script, which takes statements at the top level.
    corpus_run "$name (.kts)" "$dir" "$lexer" "$parser" script "$CORPUS/results/$name.kts.$kind" "$ex" -name '*.kts'
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
  corpus_compare "$CORPUS/results/$1.kts.plain" "$CORPUS/results/$1.kts.dialect" "$dir" "$CORPUS/results/$1.excludes"
done
echo "== timing"
corpus_histogram "$CORPUS"/results/*.plain
