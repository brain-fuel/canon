#!/usr/bin/env bash
# Corpus check for canon's Prolog grammar (REQ-prolog-support, DEC-prolog-dialect).
# Clones widely used Prolog projects, each pinned to a commit, shallow and blob-filtered, and
# sparse where a repository is large; parses every .pl file with the plain grammar
# (grammars/prolog/prolog.g4) under a per-file CPU-time limit; prints per repository the files parsed out
# of the files, the failures, and the slowest files; then parses every file the plain grammar
# accepted with the canonically commented dialect, which must accept it too.
# Usage: tools/corpus/prolog.sh [clone-dir]   (default /tmp/corpus/prolog)
# Environment: CORPUS_TIMEOUT CPU seconds per file (default 10; the SLOW files get their own),
# CORPUS_JOBS parallel parses (default 8), CORPUS_CLONE_ONLY=1 to fetch the repositories without
# parsing, CORPUS_CANON a canon binary to use instead of the one stack built.
set -euo pipefail

LANG_NAME=prolog
DIR=${1:-/tmp/corpus/$LANG_NAME}
TIMEOUT=${CORPUS_TIMEOUT:-10}
JOBS=${CORPUS_JOBS:-8}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CANON=${CORPUS_CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
G=$ROOT/grammars/prolog
PLAIN=("$G/prolog.g4" p_text)
DIALECT=("$G/canonically_commented/PrologLexer.g4" "$G/canonically_commented/PrologParser.g4" p_text)

# Repositories: name, URL, pinned commit, and the sparse paths (none means the whole tree).
# swipl-devel is sampled to library/, SWI-Prolog's standard library; logtalk3 to core/ and
# adapters/, the Prolog the Logtalk compiler and its backend adapters are written in (library/ is
# Logtalk .lgt source plus generated Unicode tables).
REPOS='
swipl-library https://github.com/SWI-Prolog/swipl-devel 741efc02f1c24fd965b8dec8e478a276efe6daf2 /library/
logtalk3 https://github.com/LogtalkDotOrg/logtalk3 9dda2f8d7f94c645711b9c1c3794ba68e6d75ca5 /core/ /adapters/
marelle https://github.com/larsyencken/marelle 02fb567b10493d1469b533013486994c34a92547
'

# Files listed here are known to be slow, with the CPU seconds they get instead and the reason.
# Both parse whole; their time is the parser's (src/Canon/Antlr4/Parse.hs), roughly linear in
# the file's size.
SLOW='
logtalk3/core/core.pl 60 the Logtalk compiler, 30,363 lines and 1.6 MB in one file, about 10 s of CPU
swipl-library/library/clp/clpfd.pl 20 CLP(FD), 7,906 lines, about 2 s of CPU
'

# Files listed here are deliberate exclusions, each with its reason; they are counted, not parsed.
EXCLUDE='
'

files_of() { # files_of DIR: the files of the language under DIR
  find "$1" -type f -name '*.pl' -not -path '*/.git/*' | LC_ALL=C sort
}

# ---- common driver (the same in every tools/corpus script of this set) ----

clone() { # clone NAME URL SHA [PATH...]: fetch one commit, shallow and blob-filtered; PATHs make it sparse
  local name=$1 url=$2 sha=$3; shift 3
  local dest=$DIR/$name
  if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" = "$sha" ]; then return 0; fi
  rm -rf "$dest"; mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"
  if [ $# -gt 0 ]; then git -C "$dest" sparse-checkout set --no-cone "$@"; fi
  git -C "$dest" fetch -q --depth 1 --filter=blob:none origin "$sha"
  git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# parse_list OUT GRAMMAR-ARGS... < NUL-separated files: one line per file into OUT,
# "status<TAB>CPU seconds<TAB>file<TAB>first error line", status ok, fail, or timeout. A parse is
# limited and measured in CPU seconds, which do not grow with the load of the machine as wall time
# does; ten times the limit in wall time stops a parse that waits instead.
parse_list() {
  local out=$1; shift
  CANON=$CANON TIMEOUT=$TIMEOUT xargs -0 -n1 -P "$JOBS" bash -c '
    f=${!#}; set -- "${@:1:$(($#-1))}"
    if err=$( (ulimit -t "$TIMEOUT"; exec timeout "$((TIMEOUT * 10))" "$CANON" parse "$@" "$f") 2>&1 >/dev/null); then st=ok; else
      c=$?; if [ "$c" = 124 ] || [ "$c" -ge 128 ]; then st=timeout; else st=fail; fi; fi
    tf=$(mktemp); times > "$tf"
    cpu=$(awk "NR == 2 { split(\$1, u, /[ms]/); split(\$2, k, /[ms]/); printf \"%.2f\", u[1] * 60 + u[2] + k[1] * 60 + k[2] }" "$tf"); rm -f "$tf"
    msg=$(printf "%s" "$err" | head -n 1 | cut -c1-160 | tr "\t" " ")
    printf "%s\t%s\t%s\t%s\n" "$st" "$cpu" "$f" "$msg"
  ' _ "$@" > "$out"
}

main() {
  mkdir -p "$DIR"
  local results=$DIR/.results
  rm -rf "$results"; mkdir -p "$results"
  printf '%s corpus under %s (limit %s CPU seconds per file; times are CPU seconds)\n' "$LANG_NAME" "$DIR" "$TIMEOUT"
  echo "$REPOS" | while read -r name url sha paths; do
    [ -z "$name" ] && continue
    local base
    case $url in
      local:/*) base=${url#local:} ;;
      local:*) base=$ROOT/${url#local:} ;;
      *) # shellcheck disable=SC2086
         clone "$name" "$url" "$sha" $paths < /dev/null; base=$DIR/$name ;;
    esac
    [ -d "$base" ] || { printf '\n== %s: %s not present, skipped\n' "$name" "$base"; continue; }
    [ -n "${CORPUS_CLONE_ONLY:-}" ] && continue
    files_of "$base" > "$results/$name.all"
    : > "$results/$name.excluded"; : > "$results/$name.todo"; : > "$results/$name.slow"
    while IFS= read -r f; do
      rel=${f#"$base"/}
      reason=$(echo "$EXCLUDE" | awk -v k="$name/$rel" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }')
      slow=$(echo "$SLOW" | awk -v k="$name/$rel" '$1 == k { print $2; exit }')
      if [ -n "$reason" ]; then printf '%s\t%s\n' "$rel" "$reason" >> "$results/$name.excluded"
      elif [ -n "$slow" ]; then printf '%s\0' "$f" >> "$results/$name.slow.$slow"
      else printf '%s\0' "$f" >> "$results/$name.todo"; fi
    done < "$results/$name.all"
    parse_list "$results/$name.plain" "${PLAIN[@]}" < "$results/$name.todo"
    for s in "$results/$name".slow.*; do # each slow file with its own timeout
      [ -e "$s" ] || continue
      TIMEOUT=${s##*.} parse_list "$s.out" "${PLAIN[@]}" < "$s"; cat "$s.out" >> "$results/$name.plain"
    done
    : > "$results/$name.ok"
    awk -F'\t' '$1 == "ok" { print $3 }' "$results/$name.plain" | while IFS= read -r f; do
      slow=$(echo "$SLOW" | awk -v k="$name/${f#"$base"/}" '$1 == k { print $2; exit }')
      if [ -n "$slow" ]; then printf '%s\0' "$f" >> "$results/$name.okslow.$slow"
      else printf '%s\0' "$f" >> "$results/$name.ok"; fi
    done
    parse_list "$results/$name.dialect" "${DIALECT[@]}" < "$results/$name.ok"
    for s in "$results/$name".okslow.*; do
      [ -e "$s" ] || continue
      TIMEOUT=${s##*.} parse_list "$s.out" "${DIALECT[@]}" < "$s"; cat "$s.out" >> "$results/$name.dialect"
    done
    local n x ok
    n=$(wc -l < "$results/$name.all" | tr -d ' ')
    x=$(wc -l < "$results/$name.excluded" | tr -d ' ')
    ok=$(awk -F'\t' '$1 == "ok"' "$results/$name.plain" | wc -l | tr -d ' ')
    printf '\n== %s @ %s%s\n' "$name" "${sha:0:12}" "${paths:+ (sparse: $paths)}"
    printf '   plain grammar: %s / %s parsed, %s excluded, %s failing; %ss total\n' "$ok" "$n" "$x" \
      "$((n - x - ok))" "$(awk -F'\t' '{ t += $2 } END { printf "%.1f", t }' "$results/$name.plain")"
    awk -F'\t' -v b="$base/" '$1 != "ok" { sub(b, "", $3); printf "   FAIL %-7s %6.2fs %s: %s\n", $1, $2, $3, $4 }' "$results/$name.plain"
    awk -F'\t' '{ printf "   EXCLUDED %s: %s\n", $1, $2 }' "$results/$name.excluded"
    printf '   slowest:'; sort -t"$(printf '\t')" -k2,2 -rn "$results/$name.plain" | awk 'NR <= 3' \
      | awk -F'\t' -v b="$base/" '{ sub(b, "", $3); printf " %s (%.2fs)", $3, $2 } END { print "" }'
    local dok
    dok=$(awk -F'\t' '$1 == "ok"' "$results/$name.dialect" | wc -l | tr -d ' ')
    printf '   dialect: %s / %s of the plain-parsed files\n' "$dok" "$ok"
    awk -F'\t' -v b="$base/" '$1 != "ok" { sub(b, "", $3); printf "   DIALECT FAIL %-7s %6.2fs %s: %s\n", $1, $2, $3, $4 }' "$results/$name.dialect"
  done
  [ -n "${CORPUS_CLONE_ONLY:-}" ] && return 0
  cat "$results"/*.plain > "$results/all.plain" 2>/dev/null || :
  printf '\n== CPU time per file (plain grammar, all repositories)\n'
  awk -F'\t' '{ if ($2 < 0.5) a++; else if ($2 < 1) b++; else if ($2 < 2) c++; else if ($2 < 5) d++; else e++
                if ($1 != "ok" && $2 > fm) fm = $2 }
              END { printf "   <0.5s %d, 0.5-1s %d, 1-2s %d, 2-5s %d, >=5s %d; slowest failure %.2fs\n", a, b, c, d, e, fm }' "$results/all.plain"
  printf '   slowest:'; sort -t"$(printf '\t')" -k2,2 -rn "$results/all.plain" | awk 'NR <= 5' \
    | awk -F'\t' -v d="$DIR/" '{ sub(d, "", $3); printf "\n     %6.2fs %s", $2, $3 } END { print "" }'
  local bad
  bad=$(cat "$results"/*.dialect | awk -F'\t' '$1 != "ok"' | wc -l | tr -d ' ')
  bad=$((bad + $(awk -F'\t' '$1 != "ok"' "$results/all.plain" | wc -l | tr -d ' ')))
  [ "$bad" = 0 ]
}

main
