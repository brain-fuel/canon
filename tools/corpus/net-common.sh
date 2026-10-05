# Shared by rust.sh, csharp.sh, and fsharp.sh: clone a repository pinned to a commit, shallow,
# blob-filtered, and sparse when asked, then run canon's plain grammar and its canonically
# commented dialect over every file of the language and report parse rates and times.
# Sourced, not run. Each caller sets CANON, JOBS, and TIMEOUT before calling these functions.

# corpus_clone DIR URL COMMIT [SUBDIR...]: a depth-1 clone of COMMIT into DIR, with only the
# SUBDIRs checked out when any are given. A clone already at COMMIT is reused.
corpus_clone() {
  local dir=$1 url=$2 commit=$3
  shift 3
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
    if [ $# -gt 0 ]; then git -C "$dir" sparse-checkout set "$@" >/dev/null; fi
    return 0
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  if [ $# -gt 0 ]; then
    git -C "$dir" sparse-checkout set "$@" >/dev/null
  fi
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# corpus_parse_one LEXER PARSER START FILE: one line, "ok|fail|timeout SECONDS FILE", and on
# failure the first line of canon's message, indented, on the next line. PARSER may be "-" for a
# combined grammar named by LEXER. SECONDS is CPU time, user and system, and TIMEOUT limits CPU
# time, so a loaded machine measures the parser rather than the wait for a core; ten times TIMEOUT
# of wall time is a backstop.
corpus_parse_one() {
  local lexer=$1 parser=$2 start=$3 file=$4 rc err secs
  local args=("$lexer" "$parser" "$start" "$file")
  if [ "$parser" = - ]; then args=("$lexer" "$start" "$file"); fi
  err=$(mktemp)
  rc=0
  (ulimit -t "$TIMEOUT"; exec /usr/bin/time -p timeout $((TIMEOUT * 10)) "$CANON" parse "${args[@]}") >/dev/null 2>"$err" || rc=$?
  secs=$(awk '$1 == "user" || $1 == "sys" {s += $2} END {printf "%.2f", s}' "$err")
  if [ $rc -eq 0 ]; then
    printf 'ok %s %s\n' "$secs" "$file"
  elif [ $rc -eq 124 ] || [ $rc -eq 152 ] || [ $rc -eq 137 ]; then
    printf 'timeout %s %s\n' "$secs" "$file"
  else
    printf 'fail %s %s\n\t%s\n' "$secs" "$file" "$(grep -v -m1 -E '^(real|user|sys) |^$' "$err" | cut -c1-240)"
  fi
  rm -f "$err"
}
export -f corpus_parse_one

# corpus_files DIR FIND-ARGS...: the files of the language under DIR, NUL-separated, sorted,
# outside .git.
corpus_files() {
  local dir=$1
  shift
  find "$dir" -name .git -prune -o -type f \( "$@" \) -print0 | sort -z
}

# corpus_run NAME DIR LEXER PARSER START OUT EXCLUDES FIND-ARGS...: parse every file of the
# language under DIR in JOBS processes, write the per-file lines to OUT, and print the
# repository's summary: files, parsed, excluded, failures, total time, and the slowest files.
# EXCLUDES lists one path per line relative to DIR; a path ending in / excludes the directory.
# Each parse runs on one capability (GHCRTS=-N1, unless GHCRTS is set), since JOBS parses already
# run side by side and canon's parallel garbage collector would add a thread per core to each.
corpus_run() {
  local name=$1 dir=$2 lexer=$3 parser=$4 start=$5 out=$6 excludes=$7
  shift 7
  corpus_files "$dir" "$@" |
    TIMEOUT=$TIMEOUT CANON=$CANON GHCRTS=${GHCRTS:--N1} xargs -0 -n 1 -P "$JOBS" bash -c 'corpus_parse_one "$@"' _ "$lexer" "$parser" "$start" >"$out"
  local files parsed failed excluded secs
  files=$(grep -cE '^(ok|fail|timeout) ' "$out" || true)
  parsed=$(grep -c '^ok ' "$out" || true)
  excluded=$(corpus_failures "$dir" "$excludes" "$out" excluded | grep -c '^    [a-z]' || true)
  failed=$((files - parsed - excluded))
  secs=$(awk '/^(ok|fail|timeout) / {s += $2} END {printf "%.0f", s}' "$out")
  printf '%-22s %6d files  %6d parsed  %4d excluded  %4d failed  %6ss\n' \
    "$name" "$files" "$parsed" "$excluded" "$failed" "$secs"
  corpus_failures "$dir" "$excludes" "$out" failed | head -80 || true
  awk '/^(ok|fail|timeout) / {print $2, $1, $3}' "$out" | sort -rn | head -3 |
    awk -v d="$dir/" '{p = $3; if (index(p, d) == 1) p = substr(p, length(d) + 1); printf "    slow: %ss %s %s\n", $1, $2, p}' || true
}

# corpus_failures DIR EXCLUDES OUT failed|excluded: the failing files of OUT, relative to DIR,
# with canon's message, that are not (failed) or are (excluded) listed in EXCLUDES.
corpus_failures() {
  awk -v d="$1/" -v ex="$2" -v want="$4" '
    BEGIN { n = 0; while ((getline line < ex) > 0) if (line != "") skip[n++] = line }
    function excluded(p,   i, s) {
      for (i = 0; i < n; i++) {
        s = skip[i]
        if (p == s) return 1
        if (substr(s, length(s)) == "/" && index(p, s) == 1) return 1
      }
      return 0
    }
    /^(ok|fail|timeout) / {
      show = 0
      if ($1 == "ok") next
      p = $3; if (index(p, d) == 1) p = substr(p, length(d) + 1)
      show = (excluded(p) == (want == "excluded"))
      if (show) printf "    %s %ss %s\n", $1, $2, p
      next
    }
    show && want == "failed" { sub(/^\t/, ""); print "      " $0 }' "$3"
}

# corpus_compare PLAIN DIALECT: the files the plain grammar parsed and the dialect did not.
corpus_compare() {
  comm -23 <(awk '$1 == "ok" {print $3}' "$1" | sort) <(awk '$1 == "ok" {print $3}' "$2" | sort)
}

# corpus_histogram OUT...: how many files took under 0.5, 1, 2, 5, and 10 seconds of CPU time, and
# longer, and how long the slowest failure took.
corpus_histogram() {
  cat "$@" | awk '/^(ok|fail|timeout) / {
      n++; t = $2
      if (t < 0.5) a++; else if (t < 1) b++; else if (t < 2) c++; else if (t < 5) d++; else if (t < 10) e++; else f++
      if ($1 != "ok") { m++; if (t > mx) mx = t }
    } END {
      printf "  time per file: <0.5s %d, <1s %d, <2s %d, <5s %d, <10s %d, >=10s %d (of %d)\n", a, b, c, d, e, f, n
      printf "  failing files: %d, slowest failure %.2fs\n", m, mx
    }'
}

# corpus_main LANG FIND-ARGS...: clone every entry of REPOS, then parse each repository and each
# of SAMPLES with the plain grammar and the dialect, and report. The caller sets REPOS, SAMPLES,
# EXCLUDES, CORPUS, ROOT, PLAIN_LEXER, PLAIN_PARSER, DIALECT_LEXER, DIALECT_PARSER, and START.
# ONLY, when set, names the one repository to run.
corpus_main() {
  shift
  local find_args=("$@") entry name dir ex
  mkdir -p "$CORPUS/results"
  for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    if [ -n "${ONLY:-}" ] && [ "$1" != "$ONLY" ]; then continue; fi
    echo "cloning $1 at $3${4:+ (sampled: ${*:4})}" >&2
    corpus_clone "$CORPUS/$1" "$2" "$3" "${@:4}"
  done
  local names=()
  for entry in "${REPOS[@]}" "${SAMPLES[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    if [ -n "${ONLY:-}" ] && [ "$1" != "$ONLY" ]; then continue; fi
    names+=("$1")
  done
  local kind lexer parser
  for kind in plain dialect; do
    if [ $kind = plain ]; then lexer=$PLAIN_LEXER parser=$PLAIN_PARSER; else lexer=$DIALECT_LEXER parser=$DIALECT_PARSER; fi
    echo "== $kind grammar"
    for name in "${names[@]}"; do
      dir=$CORPUS/$name
      [ -d "$dir" ] || dir=$ROOT/lang_samples/$name/source
      ex=$CORPUS/results/$name.excludes
      printf '%s\n' "$EXCLUDES" | awk -v n="$name" '$1 == n {print $2}' >"$ex"
      corpus_run "$name" "$dir" "$lexer" "$parser" "$START" "$CORPUS/results/$name.$kind" "$ex" "${find_args[@]}"
    done
  done
  echo "== files the plain grammar parses and the dialect does not"
  for name in "${names[@]}"; do
    corpus_compare "$CORPUS/results/$name.plain" "$CORPUS/results/$name.dialect"
  done
  echo "== timing, plain grammar"
  for name in "${names[@]}"; do echo "$CORPUS/results/$name.plain"; done | xargs cat | corpus_histogram
  echo "== timing, dialect"
  for name in "${names[@]}"; do echo "$CORPUS/results/$name.dialect"; done | xargs cat | corpus_histogram
}
