#!/usr/bin/env bash
# Reproduces the Scala corpus run recorded in grammars/scala/README.md and DEC-scala-grammar: clones
# each repository at its pinned commit into a directory (default /tmp/scala-corpus), parses every
# .scala file with canon's Scala grammar, plain or canonically commented, under a per-file timeout,
# and prints the files parsed per repository. Files in the excluded classes listed below are counted
# apart. Run it from the root of canon after `stack build`. ref:DEC-scala-grammar
#
# Usage: tools/corpus/scala.sh [corpus-dir] [plain|dialect] [jobs]
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

corpus="${1:-/tmp/scala-corpus}"
variant="${2:-plain}"
jobs="${3:-8}"
timeout_seconds=30
root="$(cd "$(dirname "$0")/../.." && pwd)"
canon="$(cd "$root" && stack path --local-install-root)/bin/canon"
if [ "$variant" = dialect ]; then
  grammar="$root/grammars/scala/canonically_commented"
else
  grammar="$root/grammars/scala"
fi

# owner/name commit
repositories="
scala/scala3 39f42801b17af4a49df3ae37f35ce65ab874e2a9
scala/scala 8b318bf418a1fb94c3ceb3e3a18179664b9652fd
sbt/sbt b7bba1147a292d97f6f92a012a4d618faf5898ad
com-lihaoyi/mill b214318529f6d4dd2356ff811a17300e3d65d609
apache/spark b93fb8d4995949e2bc622a13cf68816b3a12d0a7
apache/pekko ecd05d1d64093427b6910c3d27269a13ef88a240
playframework/playframework 069b71cd37ebf51addcd17502056b429f46d995e
apache/kafka c2fbf6f52f78ecc1c11c6511242aade6a2c50b71
twitter/finagle ca472deb355c7d3b8d7eb077223991e8c8f4ad8b
linkerd/linkerd ea82499d386e44e8958be58e0386f593e639645b
gatling/gatling 045b67dc789257969c1e9ce10fc48a3056e329ea
lichess-org/lila 1dc9cb2df29c9d35238c905d79ea7f0cb9ef4f97
typelevel/cats 4a2ea736632c64aaf2e4915e6922e3585379382f
typelevel/cats-effect de84c01f76b2f42fcee9d43aba66c82992add103
typelevel/fs2 8aa47aba38454789ce206ad282ed30d45dcbae26
zio/zio 9005388637beffd91a6a48be2b215bb0ccf172f5
http4s/http4s f81cb4ac926ffd65d94bb856908de5f11d1ffe22
circe/circe 23a9bcd82d097668a43cc4d6c2af3ea59c5721d8
scalaz/scalaz 9980ce1d41fa8881669b3db9df227970f2fc39f8
milessabin/shapeless de22d6a0a698328219fe5a9469fdbba5581fd190
scalameta/scalameta f31620cefa9aa20b6ba1a4f9bcd787b84e5817c5
scalatest/scalatest fe1d39319d5076919b24b54515f2524a685c85aa
slick/slick 24c2956f7da52578adca13ddc686a4934c7e880a
"

# Excluded classes, as path patterns: sources the compilers' and build tools' own test suites keep
# because they do not compile: negative tests (neg, neg-macros, untried/neg, and the like), the
# Scala 3 parser's fuzzing inputs, its pending and disabled tests, and fixtures of parse, format,
# presentation-compiler, and incremental-compile errors, three of them sbt scripted-test sources
# broken on purpose and named one by one; one file encoded in UTF-16, which canon does not read; and
# the Scala 3 test of experimental dedented string literals, which nests them in each other's holes.
excluded='/neg[^/]*/|/tests/fuzzy/|/tests/pending/|/tests/disabled/|/pos-special/utf16encoded.scala|/tests/run/dedented-string-literals.scala|/sbt-test/project-load/subdirectory/foo/A.scala|/sbt-test/project/usePipelining-cancellation/|/sbt-test/nio/legacy-filters/src/main/scala/Bar.scala|/test/files/presentation/|/compile-error|/sbt-test/[^ ]*/(changes|pending)/|/sbt-test/watch/|/palantirformat/|/test/files/positions/'

mkdir -p "$corpus"
for entry in $(echo "$repositories" | awk 'NF {print $1 "@" $2}'); do
  repo="${entry%@*}"
  commit="${entry#*@}"
  dir="$corpus/$(echo "$repo" | tr / _)"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "https://github.com/$repo.git"
  fi
  if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q FETCH_HEAD
  fi
done

parse_one() {
  local file="$1" start end status err
  err="$(mktemp)"
  start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  if timeout "$timeout_seconds" "$canon" parse "$grammar/ScalaLexer.g4" "$grammar/ScalaParser.g4" compilationUnit "$file" > /dev/null 2> "$err"; then
    status=OK
  else
    status=FAIL
  fi
  end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  printf '%s\t%s\t%s\t%s\n' "$status" "$(echo "$end - $start" | bc)" "$file" "$(head -c 200 "$err" | tr '\n\t' '  ')"
  rm -f "$err"
}
export -f parse_one
export canon grammar timeout_seconds

results="$corpus/results-$variant.tsv"
find "$corpus" -type f -name '*.scala' -print0 | xargs -0 -P "$jobs" -n 1 bash -c 'parse_one "$0"' > "$results"

printf '%-30s %8s %8s %8s %8s\n' repository files parsed failed excluded
for entry in $(echo "$repositories" | awk 'NF {print $1}'); do
  dir="$corpus/$(echo "$entry" | tr / _)/"
  awk -F'\t' -v dir="$dir" -v repo="$entry" -v excl="$excluded" '
    index($3, dir) == 1 {
      if ($3 ~ excl) { x++ } else { n++; if ($1 == "OK") ok++; else bad++ }
    }
    END { printf "%-30s %8d %8d %8d %8d\n", repo, n, ok, bad, x }
  ' "$results"
done
echo "results: $results"
echo "failures outside the excluded classes:"
awk -F'\t' -v excl="$excluded" '$1 == "FAIL" && $3 !~ excl {print $3 ": " $4}' "$results"
echo "slowest files:"
sort -t "$(printf '\t')" -k2 -rn "$results" | head -10 | cut -f1-3
