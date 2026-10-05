#!/usr/bin/env bash
# The corpus run shared by javascript.sh and typescript.sh, which set the variables below and
# source this file: it shallow-clones each repository pinned to a commit, sparse where patterns are
# given, parses every file of the language with the plain grammar under a per-file timeout, prints
# per repository the files, the files parsed, the deliberate exclusions, the failures, and the
# slowest files, and parses every file the plain grammar parsed with the canonically commented
# dialect, which must parse them all. ref:DEC-more-languages
#
# The caller sets ROOT, PLAIN (lexer and parser), DIALECT (lexer and parser), START, REPOS (name,
# https URL, commit, then sparse-checkout patterns), EXTENSIONS (find -name patterns), SKIPPED
# (find -path patterns of files that are never the language's code, as minified bundles), and a
# function exclusion_class that prints the class of a failing file that is a deliberate exclusion.
# Environment: CORPUS_TIMEOUT (seconds per file, default 300), CORPUS_JOBS (parallel parses, default
# 8), CORPUS_SKIP_FETCH=1 to reuse the clones as they are, CORPUS_ONLY to run one repository.
set -euo pipefail

TIMEOUT_SECONDS=${CORPUS_TIMEOUT:-300}
JOBS=${CORPUS_JOBS:-8}
BIN=$(cd "$CANON_DIR" && stack path --local-install-root)/bin/canon

# Clones a repository at its pinned commit, shallow and without blobs outside the sparse paths.
fetch() {
  local name=$1 url=$2 commit=$3
  shift 3
  local dir=$ROOT/$name
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
    return
  fi
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  if [ $# -gt 0 ]; then
    git -C "$dir" config core.sparseCheckout true
    printf '%s\n' "$@" > "$dir/.git/info/sparse-checkout"
  fi
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
}

# The files of the language under a directory, outside .git and node_modules and the skipped paths.
language_files() {
  local names=() skips=() e
  for e in "${EXTENSIONS[@]}"; do names+=(-o -name "$e"); done
  for e in ${SKIPPED[@]+"${SKIPPED[@]}"}; do skips+=(-o -path "$e"); done
  find "$1" \( -path '*/.git' -o -path '*/node_modules' ${skips[@]+"${skips[@]}"} \) -prune -o -type f \( -false "${names[@]}" \) -print0
}

# Parses one file with a grammar pair and prints status, seconds, path, and the first error line.
parse_one() {
  local lexer=$1 parser=$2 file=$3 start end status err
  err=$(mktemp)
  start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  if timeout "$TIMEOUT_SECONDS" "$BIN" parse "$lexer" "$parser" "$START" "$file" > /dev/null 2> "$err"; then
    status=ok
  elif [ $? -eq 124 ]; then
    status=timeout
  else
    status=fail
  fi
  end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  printf '%s\t%s\t%s\t%s\n' "$status" "$(perl -e "printf '%.3f', $end - $start")" "$file" "$(head -c 200 "$err" | head -n 1)"
  rm -f "$err"
}
export -f parse_one
export BIN START TIMEOUT_SECONDS

# Parses a NUL-separated list of files in parallel into a results file.
parse_all() {
  local lexer=$1 parser=$2 out=$3
  xargs -0 -P "$JOBS" -n 1 bash -c 'parse_one "$0" "$1" "$2"' "$lexer" "$parser" > "$out"
}

run_corpus() {
  mkdir -p "$ROOT"
  local results=$ROOT/.results spec name
  mkdir -p "$results"
  local selected=()
  for spec in "${REPOS[@]}"; do
    name=${spec%% *}
    if [ -z "${CORPUS_ONLY:-}" ] || [ "$CORPUS_ONLY" = "$name" ]; then selected+=("$spec"); fi
  done

  for spec in "${selected[@]}"; do
    # The patterns are for git, not the shell, so the split does not expand them.
    set -f
    # shellcheck disable=SC2086
    set -- $spec
    set +f
    if [ "${CORPUS_SKIP_FETCH:-0}" != 1 ]; then
      echo "fetching $1" >&2
      fetch "$@"
    fi
  done

  printf '%-14s %7s %7s %8s %9s %9s  %s\n' repository files parsed excluded failures seconds slowest
  local total_files=0 total_parsed=0 total_excluded=0 total_failed=0
  : > "$results/plain-all.tsv"
  : > "$results/failures.tsv"
  : > "$results/exclusions.tsv"
  for spec in "${selected[@]}"; do
    name=${spec%% *}
    language_files "$ROOT/$name" | parse_all "${PLAIN[0]}" "${PLAIN[1]}" "$results/$name.tsv"
    cat "$results/$name.tsv" >> "$results/plain-all.tsv"
    local files parsed excluded=0 failed=0 seconds slowest status secs file message rel class
    files=$(wc -l < "$results/$name.tsv" | tr -d ' ')
    parsed=$(awk -F '\t' '$1 == "ok"' "$results/$name.tsv" | wc -l | tr -d ' ')
    while IFS=$'\t' read -r status secs file message; do
      [ "$status" = ok ] && continue
      rel=${file#"$ROOT/$name/"}
      class=$(exclusion_class "$name" "$rel" "$file")
      if [ -n "$class" ]; then
        excluded=$((excluded + 1))
        printf '%s\t%s\t%s\n' "$class" "$name/$rel" "$message" >> "$results/exclusions.tsv"
      else
        failed=$((failed + 1))
        printf '%s\t%s\t%s\t%s\n' "$status" "$secs" "$name/$rel" "$message" >> "$results/failures.tsv"
      fi
    done < "$results/$name.tsv"
    seconds=$(awk -F '\t' '{ s += $2 } END { printf "%.1f", s }' "$results/$name.tsv")
    slowest=$(sort -t $'\t' -k2,2 -rn "$results/$name.tsv" | awk 'NR <= 3' | awk -F '\t' -v root="$ROOT/$name/" '{ sub(root, "", $3); printf "%s %ss  ", $3, $2 }')
    printf '%-14s %7s %7s %8s %9s %9s  %s\n' "$name" "$files" "$parsed" "$excluded" "$failed" "$seconds" "$slowest"
    total_files=$((total_files + files))
    total_parsed=$((total_parsed + parsed))
    total_excluded=$((total_excluded + excluded))
    total_failed=$((total_failed + failed))
  done
  printf '%-14s %7s %7s %8s %9s\n' total "$total_files" "$total_parsed" "$total_excluded" "$total_failed"

  echo
  echo "exclusions by class:"
  cut -f1 "$results/exclusions.tsv" | sort | uniq -c | sed 's/^/  /'
  echo "failures not excluded:"
  cat "$results/failures.tsv"

  echo
  echo "time per file (seconds):"
  sort -t $'\t' -k2,2 -n "$results/plain-all.tsv" | awk -F '\t' '{ t[NR] = $2 } END { if (NR) printf "  p50 %s  p90 %s  p99 %s  max %s\n", t[int(NR * 0.5) + 1], t[int(NR * 0.9) + 1], t[int(NR * 0.99) + 1], t[NR] }'
  echo "slowest failing files (seconds):"
  awk -F '\t' '$1 != "ok"' "$results/plain-all.tsv" | sort -t $'\t' -k2,2 -rn | awk 'NR <= 3' | awk -F '\t' '{ printf "  %s %s\n", $2, $3 }'
  echo "slowest files:"
  sort -t $'\t' -k2,2 -rn "$results/plain-all.tsv" | awk 'NR <= 5' | awk -F '\t' '{ printf "  %s %s\n", $2, $3 }'

  echo
  echo "dialect over the files the plain grammar parsed:"
  awk -F '\t' '$1 == "ok" { printf "%s%c", $3, 0 }' "$results/plain-all.tsv" | parse_all "${DIALECT[0]}" "${DIALECT[1]}" "$results/dialect.tsv"
  local dialect_files dialect_parsed
  dialect_files=$(wc -l < "$results/dialect.tsv" | tr -d ' ')
  dialect_parsed=$(awk -F '\t' '$1 == "ok"' "$results/dialect.tsv" | wc -l | tr -d ' ')
  echo "  $dialect_parsed / $dialect_files parsed"
  awk -F '\t' '$1 != "ok" { printf "  %s %s %s\n", $1, $3, $4 }' "$results/dialect.tsv"

  [ "$total_failed" -eq 0 ] && [ "$dialect_parsed" -eq "$dialect_files" ]
}
