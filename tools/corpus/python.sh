#!/usr/bin/env bash
# Corpus check for canon's Python grammar (REQ-python-support, DEC-python-grammar).
# Clones widely used Python projects, each pinned to a commit, shallow and blob-filtered, and
# sparse where a repository is large; parses every .py file with the plain grammar
# (grammars/python) under a per-file timeout; prints per repository the files parsed out of the
# files, the failures, and the slowest files; then parses every file the plain grammar accepted
# with the canonically commented dialect, which must accept it too.
# Usage: tools/corpus/python.sh [clone-dir]   (default /tmp/corpus/python)
# Environment: CORPUS_TIMEOUT wall seconds per file (default 60), CORPUS_JOBS parallel parses (default 8),
# CORPUS_CLONE_ONLY=1 to fetch the repositories without parsing, CORPUS_ONLY=name to run one repository.
set -euo pipefail

LANG_NAME=python
DIR=${1:-/tmp/corpus/$LANG_NAME}
TIMEOUT=${CORPUS_TIMEOUT:-60}
JOBS=${CORPUS_JOBS:-8}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CANON=$(cd "$ROOT" && stack path --local-install-root)/bin/canon
G=$ROOT/grammars/python
PLAIN=("$G/Python3Lexer.g4" "$G/Python3Parser.g4" file_input)
DIALECT=("$G/canonically_commented/Python3Lexer.g4" "$G/canonically_commented/Python3Parser.g4" file_input)

# Repositories: name, URL, pinned commit, and the sparse paths (none means the whole tree).
# cpython is sampled to Lib/, the standard library; numpy to numpy/, its Python package.
REPOS='
cpython-lib https://github.com/python/cpython dc0add3a65fc5de8f0ec8a687dccba435d52d97a /Lib/
django https://github.com/django/django fd91518f17c8a84fa47fe0e5534ef46afa7a0f7a
requests https://github.com/psf/requests 611c6162cbc4ac2020a2f91c7cfa4f3abf9bbb60
flask https://github.com/pallets/flask d73fa1cdcbd8b1465c151db8924ba58b1dd14e35
numpy https://github.com/numpy/numpy a9d5324eb7343ea64f387618d74e54393e238a91 /numpy/
pandas https://github.com/pandas-dev/pandas 67b43b389914bc348b084f727b39033a7a3602ff
itsdangerous-sample local:lang_samples/python-itsdangerous/source 0
'

# Deliberate exclusions: repository, a path glob relative to the repository, and the reason.
# Matching files are counted as excluded, not parsed.
EXCLUDE='
cpython-lib Lib/test/tokenizedata/badsyntax_* invalid-code fixture: CPython test_unicode_identifiers and test_utf8source expect a SyntaxError
django tests/test_runner_apps/tagged/tests_syntax_error.py invalid-code fixture: Django test_runner expects its SyntaxError
'

files_of() { # files_of DIR: the files of the language under DIR
  find "$1" -type f -name '*.py' -not -path '*/.git/*' | LC_ALL=C sort
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
