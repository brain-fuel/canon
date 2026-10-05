#!/usr/bin/env bash
# Corpus check for canon's Go grammar (REQ-go-support, DEC-go-grammar).
# Clones widely used Go projects, each pinned to a commit, shallow and blob-filtered, and
# sparse where a repository is large; parses every .go file with the plain grammar
# (grammars/golang) under a per-file timeout; prints per repository the files parsed out of the
# files, the failures, and the slowest files; then parses every file the plain grammar accepted
# with the canonically commented dialect, which must accept it too.
# Usage: tools/corpus/go.sh [clone-dir]   (default /tmp/corpus/go)
# Environment: CORPUS_TIMEOUT wall seconds per file (default 60), CORPUS_JOBS parallel parses (default 8),
# CORPUS_CLONE_ONLY=1 to fetch the repositories without parsing, CORPUS_ONLY=name to run one repository.
set -euo pipefail

LANG_NAME=go
DIR=${1:-/tmp/corpus/$LANG_NAME}
TIMEOUT=${CORPUS_TIMEOUT:-60}
JOBS=${CORPUS_JOBS:-8}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CANON=$(cd "$ROOT" && stack path --local-install-root)/bin/canon
G=$ROOT/grammars/golang
PLAIN=("$G/GoLexer.g4" "$G/GoParser.g4" sourceFile)
DIALECT=("$G/canonically_commented/GoLexer.g4" "$G/canonically_commented/GoParser.g4" sourceFile)

# Repositories: name, URL, pinned commit, and the sparse paths (none means the whole tree).
# go is sampled to src/, the standard library and toolchain; kubernetes to pkg/ and client-go;
# moby to everything outside vendor/, which holds copies of other repositories.
REPOS='
go-src https://github.com/golang/go 6200ca72531c80fd5c183a6d72e3b829c8f7487b /src/
kubernetes https://github.com/kubernetes/kubernetes 8ae47e9fc94cbb1f8a36dafb13209984d5e07d0f /pkg/ /staging/src/k8s.io/client-go/
moby https://github.com/moby/moby 0598cf16389e055e3216de351a285c34d5fb493a /* !/vendor/
hugo https://github.com/gohugoio/hugo 6b3ba3a7e22ae2809605b8118aeed08b244f1955
terraform https://github.com/hashicorp/terraform 35ab6fb201e48a9df4e7f30d9c5c1f00ab1022a6
uuid-sample local:lang_samples/go-uuid/source 0
'

# Deliberate exclusions: repository, a path glob relative to the repository, and the reason.
# Matching files are counted as excluded, not parsed.
EXCLUDE='
go-src src/cmd/compile/internal/syntax/testdata/issue20789.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue23385.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue23434.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue31092.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue43527.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue43674.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue46558.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue47704.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue48382.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue49205.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue49482.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue52391.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue56022.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue60599.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue63835.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue68589.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/issue70957.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/sample.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/smoketest.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/tparams.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/syntax/testdata/typeset.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/types2/testdata/local/issue47996.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/compile/internal/types2/testdata/local/issue68183.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/constdecl.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/decls0.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/expr0.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/expr3.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/issues0.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/stmt0.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/typeinst0.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/check/vardecl.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/examples/functions.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/examples/types.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue39634.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue42987.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue43087.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue43190.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue45635.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue46403.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue48827.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue50427a.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue50427b.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue51658.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/internal/types/testdata/fixedbugs/issue58612.go invalid-code fixture: its ERROR comments mark the syntax errors the Go parser must report
go-src src/cmd/cover/testdata/ranges/ranges.go not Go: cover test input whose « and » mark the expected ranges
go-src src/go/parser/testdata/issue42951/not_a_file.go/invalid.go not Go: a fixture that the ParseDir of go/parser must skip
go-src src/cmd/go/internal/modindex/testdata/ignore_non_source/b.go not Go: an empty fixture with no package clause
'

files_of() { # files_of DIR: the files of the language under DIR
  find "$1" -type f -name '*.go' -not -path '*/.git/*' | LC_ALL=C sort
}

# ---- common driver (the same in every tools/corpus script of this set) ----

clone() { # clone NAME URL SHA [PATH...]: fetch one commit, shallow and blob-filtered; PATHs make it sparse
  local name=$1 url=$2 sha=$3; shift 3
  local dest=$DIR/$name
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" = "$sha" ]; then
    if [ $# -gt 0 ]; then git -C "$dest" sparse-checkout set --no-cone "$@"; fi
    return 0
  fi
  rm -rf "$dest"; mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"
  if [ $# -gt 0 ]; then git -C "$dest" sparse-checkout set --no-cone "$@"; fi
  git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$sha"
  git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# parse_list OUT GRAMMAR-ARGS... < NUL-separated files: one line per file into OUT,
# "status<TAB>cpu seconds<TAB>file<TAB>first error line<TAB>wall seconds", status ok, fail, or
# timeout. CPU time is reported because wall time depends on the machine's load; the timeout is
# on wall time. Each canon runs on one capability (GHCRTS=-N1), since JOBS of them run at once.
parse_list() {
  local out=$1; shift
  CANON=$CANON TIMEOUT=$TIMEOUT GHCRTS=-N1 xargs -0 -n1 -P "$JOBS" bash -c '
    f=${!#}; set -- "${@:1:$(($#-1))}"
    tf=$(mktemp); ef=$(mktemp)
    for attempt in 1 2; do
      s=$(perl -MTime::HiRes=time -e "printf q(%.3f), time")
      if /usr/bin/time -p -o "$tf" timeout "$TIMEOUT" "$CANON" parse "$@" "$f" >/dev/null 2>"$ef"; then st=ok; else
        c=$?; if [ "$c" = 124 ]; then st=timeout; else st=fail; fi; fi
      e=$(perl -MTime::HiRes=time -e "printf q(%.3f), time")
      # A parse killed from outside, with no message of its own, is run once more.
      [ "$st" = fail ] && [ ! -s "$ef" ] || break
    done
    cpu=$(awk "/^(user|sys) / { t += \$2 } END { printf \"%.2f\", t }" "$tf")
    msg=$(head -n 1 "$ef" | cut -c1-160 | tr "\t" " ")
    rm -f "$tf" "$ef"
    printf "%s\t%s\t%s\t%s\t%.2f\n" "$st" "$cpu" "$f" "$msg" "$(echo "$e - $s" | bc)"
  ' _ "$@" > "$out"
}

# split_excluded NAME BASE RESULTS: sort the files of NAME into RESULTS/NAME.excluded
# ("path<TAB>reason") and the NUL-separated RESULTS/NAME.todo, by the EXCLUDE globs.
split_excluded() {
  local name=$1 base=$2 results=$3 rel f i
  local -a pats=() reasons=()
  while read -r repo pat reason; do
    [ "$repo" = "$name" ] || continue
    pats+=("$pat"); reasons+=("$reason")
  done <<< "$EXCLUDE"
  : > "$results/$name.excluded"; : > "$results/$name.todo"
  while IFS= read -r f; do
    rel=${f#"$base"/}
    for i in "${!pats[@]}"; do
      # shellcheck disable=SC2053
      if [[ $rel == ${pats[$i]} ]]; then printf '%s\t%s\n' "$rel" "${reasons[$i]}" >> "$results/$name.excluded"; continue 2; fi
    done
    printf '%s\0' "$f" >> "$results/$name.todo"
  done < "$results/$name.all"
}

main() {
  mkdir -p "$DIR"
  local results=$DIR/.results
  mkdir -p "$results"
  printf '%s corpus under %s (timeout %ss per file)\n' "$LANG_NAME" "$DIR" "$TIMEOUT"
  echo "$REPOS" | while read -r name url sha paths; do
    [ -z "$name" ] && continue
    [ -n "${CORPUS_ONLY:-}" ] && [ "$CORPUS_ONLY" != "$name" ] && continue
    local base
    case $url in
      local:/*) base=${url#local:} ;;
      local:*) base=$ROOT/${url#local:} ;;
      *) # shellcheck disable=SC2086
         set -f; clone "$name" "$url" "$sha" $paths < /dev/null; set +f; base=$DIR/$name ;;
    esac
    [ -d "$base" ] || { printf '\n== %s: %s not present, skipped\n' "$name" "$base"; continue; }
    [ -n "${CORPUS_CLONE_ONLY:-}" ] && continue
    files_of "$base" > "$results/$name.all"
    split_excluded "$name" "$base" "$results"
    parse_list "$results/$name.plain" "${PLAIN[@]}" < "$results/$name.todo"
    awk -F'\t' '$1 == "ok" { printf "%s%c", $3, 0 }' "$results/$name.plain" > "$results/$name.ok"
    parse_list "$results/$name.dialect" "${DIALECT[@]}" < "$results/$name.ok"
    local n x ok
    n=$(wc -l < "$results/$name.all" | tr -d ' ')
    x=$(wc -l < "$results/$name.excluded" | tr -d ' ')
    ok=$(awk -F'\t' '$1 == "ok"' "$results/$name.plain" | wc -l | tr -d ' ')
    printf '\n== %s @ %s%s\n' "$name" "${sha:0:12}" "${paths:+ (sparse: $paths)}"
    printf '   plain grammar: %s / %s parsed, %s excluded, %s failing; %ss total\n' "$ok" "$n" "$x" \
      "$((n - x - ok))" "$(awk -F'\t' '{ t += $2 } END { printf "%.1f", t }' "$results/$name.plain")"
    awk -F'\t' -v b="$base/" '$1 != "ok" { sub(b, "", $3); printf "   FAIL %-7s %6.2fs %s: %s\n", $1, $2, $3, $4 }' "$results/$name.plain"
    awk -F'\t' '{ r[$2]++ } END { for (k in r) printf "   EXCLUDED %d: %s\n", r[k], k }' "$results/$name.excluded"
    printf '   slowest:'; sort -t"$(printf '\t')" -k2,2 -rn "$results/$name.plain" | \
      awk -F'\t' -v b="$base/" 'NR <= 3 { sub(b, "", $3); printf " %s (%.2fs)", $3, $2 } END { print "" }'
    local dok
    dok=$(awk -F'\t' '$1 == "ok"' "$results/$name.dialect" | wc -l | tr -d ' ')
    printf '   dialect: %s / %s of the plain-parsed files\n' "$dok" "$ok"
    awk -F'\t' -v b="$base/" '$1 != "ok" { sub(b, "", $3); printf "   DIALECT FAIL %-7s %6.2fs %s: %s\n", $1, $2, $3, $4 }' "$results/$name.dialect"
  done
  [ -n "${CORPUS_CLONE_ONLY:-}" ] && return 0
  cat "$results"/*.plain > "$results/all.txt" 2>/dev/null || :
  printf '\n== time per file (plain grammar, all repositories)\n'
  awk -F'\t' '{ if ($2 < 0.5) a++; else if ($2 < 1) b++; else if ($2 < 2) c++; else if ($2 < 5) d++; else e++
                if ($1 != "ok" && $2 > fm) fm = $2 }
              END { printf "   <0.5s %d, 0.5-1s %d, 1-2s %d, 2-5s %d, >=5s %d; slowest failure %.2fs\n", a, b, c, d, e, fm }' "$results/all.txt"
  printf '   slowest:'; sort -t"$(printf '\t')" -k2,2 -rn "$results/all.txt" | \
    awk -F'\t' -v d="$DIR/" 'NR <= 5 { sub(d, "", $3); printf "\n     %6.2fs %s", $2, $3 } END { print "" }'
  local bad
  bad=$(cat "$results"/*.dialect | awk -F'\t' '$1 != "ok"' | wc -l | tr -d ' ')
  bad=$((bad + $(awk -F'\t' '$1 != "ok"' "$results/all.txt" | wc -l | tr -d ' ')))
  [ "$bad" = 0 ]
}

main
