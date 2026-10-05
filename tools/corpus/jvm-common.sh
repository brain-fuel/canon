# Shared by java.sh, kotlin.sh, and groovy.sh: clone a repository pinned to a commit, shallow,
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
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  if [ $# -gt 0 ]; then
    git -C "$dir" sparse-checkout set "$@" >/dev/null
  fi
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# corpus_parse_one LEXER PARSER START FILE: one line, "ok|fail|timeout SECONDS FILE", and on
# failure the first line of canon's message, indented, on the next line. SECONDS is the CPU time
# canon took, and TIMEOUT caps it, so a loaded machine neither slows nor fails a file; canon runs
# on one capability, since many parallel parses each running the GC on every core thrash.
corpus_parse_one() {
  local lexer=$1 parser=$2 start=$3 file=$4 rc=0 err secs attempt
  err=$(mktemp)
  # A process that dies without a word, as one the system could not give memory to on a loaded
  # machine, is run once more before its file counts as failed.
  for attempt in 1 2; do
    rc=0
    (
      ulimit -t "$TIMEOUT"
      exec timeout $((TIMEOUT * 10)) "$CANON" parse "$lexer" "$parser" "$start" "$file" +RTS -N1 -RTS
    ) >/dev/null 2>"$err" || rc=$?
    if [ $rc -eq 0 ] || [ -s "$err" ] || [ $rc -eq 124 ] || [ $rc -eq 152 ] || [ $rc -eq 137 ]; then break; fi
  done
  times >"$err.times"
  secs=$(awk 'NR == 2 {
      split($1, u, /[ms]/); split($2, s, /[ms]/)
      printf "%.2f", u[1] * 60 + u[2] + s[1] * 60 + s[2] }' "$err.times")
  if [ $rc -eq 0 ]; then
    printf 'ok %s %s\n' "$secs" "$file"
  elif [ $rc -eq 124 ] || [ $rc -eq 152 ] || [ $rc -eq 137 ]; then
    printf 'timeout %s %s\n' "$secs" "$file"
  else
    printf 'fail %s %s\n\t%s\n' "$secs" "$file" "$( (grep -m1 . "$err" || echo "exit $rc without a message") | cut -c1-200)"
  fi
  rm -f "$err" "$err.times"
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
# repository's summary: files, parsed, failures (less the excluded paths listed one per line,
# relative to DIR, in the file EXCLUDES), and the slowest files.
corpus_run() {
  local name=$1 dir=$2 lexer=$3 parser=$4 start=$5 out=$6 excludes=$7
  shift 7
  corpus_files "$dir" "$@" |
    TIMEOUT=$TIMEOUT CANON=$CANON xargs -0 -n 1 -P "$JOBS" bash -c 'corpus_parse_one "$@" 2>/dev/null' _ "$lexer" "$parser" "$start" >"$out"
  local files parsed failed excluded secs
  files=$(grep -cE '^(ok|fail|timeout) ' "$out" || true)
  parsed=$(grep -c '^ok ' "$out" || true)
  excluded=$(corpus_failures "$dir" "$excludes" "$out" excluded | grep -c . || true)
  failed=$((files - parsed - excluded))
  secs=$(awk '/^(ok|fail|timeout) / {s += $2} END {printf "%.0f", s}' "$out")
  printf '%-22s %5d files  %5d parsed  %4d excluded  %4d failed  %6ss\n' \
    "$name" "$files" "$parsed" "$excluded" "$failed" "$secs"
  corpus_failures "$dir" "$excludes" "$out" failed | awk 'NR <= 60'
  awk '/^(ok|fail|timeout) / {print $2, $1, $3}' "$out" | sort -rn | awk 'NR <= 3' |
    awk -v d="$dir/" '{p = $3; if (index(p, d) == 1) p = substr(p, length(d) + 1); printf "    slow: %ss %s %s\n", $1, $2, p}'
}

# corpus_failures DIR EXCLUDES OUT failed|excluded: the failing files of OUT, relative to DIR,
# with canon's message, that are not (failed) or are (excluded) listed in EXCLUDES, one path per
# line, a path that ends in a slash standing for every file below it.
corpus_failures() {
  awk -v d="$1/" -v ex="$2" -v want="$4" '
    BEGIN { while ((getline line < ex) > 0) if (line ~ /\/$/) dirs[line] = 1; else skip[line] = 1 }
    /^(ok|fail|timeout) / {
      show = 0
      if ($1 == "ok") next
      p = $3; if (index(p, d) == 1) p = substr(p, length(d) + 1)
      hit = (p in skip)
      for (q in dirs) if (index(p, q) == 1) hit = 1
      show = (hit == (want == "excluded"))
      if (show) printf "    %s %ss %s\n", $1, $2, p
      next
    }
    show && want == "failed" { sub(/^\t/, ""); print "      " $0 }' "$3"
}

# corpus_compare PLAIN DIALECT [DIR EXCLUDES]: the files the plain grammar parsed and the dialect
# did not, less those EXCLUDES lists below DIR.
corpus_compare() {
  comm -23 <(awk '$1 == "ok" {print $3}' "$1" | sort) <(awk '$1 == "ok" {print $3}' "$2" | sort) |
    awk -v d="${3:-}/" -v ex="${4:-/dev/null}" '
      BEGIN { while ((getline line < ex) > 0) if (line ~ /\/$/) dirs[line] = 1; else skip[line] = 1 }
      {
        p = $0; if (index(p, d) == 1) p = substr(p, length(d) + 1)
        hit = (p in skip)
        for (q in dirs) if (index(p, q) == 1) hit = 1
        if (!hit) print
      }'
}

# corpus_histogram OUT...: how many files took under 0.5, 1, 2, 5, and 10 seconds, and longer.
corpus_histogram() {
  cat "$@" | awk '/^(ok|fail|timeout) / {
      n++; t = $2
      if (t < 0.5) a++; else if (t < 1) b++; else if (t < 2) c++; else if (t < 5) d++; else if (t < 10) e++; else f++
      if ($1 != "ok") { m++; if (t > mx) mx = t }
    } END {
      printf "  time per file: <0.5s %d, <1s %d, <2s %d, <5s %d, <10s %d, >=10s %d (of %d)\n", a, b, c, d, e, f, n
      printf "  files that fail, excluded ones included: %d, slowest %.2fs\n", m, mx
    }'
}
