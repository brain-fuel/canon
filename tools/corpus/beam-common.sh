# The shared part of tools/corpus/erlang.sh, elixir.sh, and gleam.sh, sourced by each after it sets
# CORPUS, PLAIN, DIALECT, EXTENSIONS, REPOS, and EXCLUDE. It clones each repository shallowly at its
# pinned commit, parses every file of the language with canon's plain grammar and then with the
# canonically commented dialect, prints a table per repository, and exits non-zero when a file
# fails that no exclusion names, or when the dialect fails a file the plain grammar parses.
#
#   REPOS    entries "name|url|commit|patterns": patterns are sparse-checkout patterns (non-cone,
#            space separated); none means the whole repository.
#   EXCLUDE  entries "name|regex|reason": a file of the repository whose path relative to the
#            clone matches the extended regex is a deliberate exclusion, given with its reason.
#   JOBS     parallel parses (default 4); TIMEOUT CPU seconds per file (default 20).

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
JOBS=${JOBS:-4}
TIMEOUT=${TIMEOUT:-20}
RESULTS="$CORPUS/results"

BIN="$(cd "$ROOT" && stack path --local-install-root)/bin/canon"
[[ -x "$BIN" ]] || { echo "no canon binary at $BIN; run stack build first" >&2; exit 2; }

# Runs one parse under a CPU-time limit and prints "status<TAB>cpu seconds<TAB>file<TAB>first error
# line<TAB>wall seconds" in one write, so lines from parallel runs never interleave. CPU time, not
# wall time, is the measure: other work on the machine stretches wall time but not CPU time. A
# wall-clock alarm of ten times the limit stops a parse that waits instead of computing. The runner
# always exits 0, since xargs stops at a command that exits 255.
RUNNER='
use strict; use Time::HiRes qw(time);
my ($tmo, @cmd) = @ARGV; my $file = $cmd[-1]; my $t0 = time;
my ($status, $first, $cpu) = ("fail", "", 0);
eval {
  pipe(my $r, my $w) or die "pipe: $!";
  my $pid; for (1 .. 30) { $pid = fork; last if defined $pid; sleep 1 } defined $pid or die "fork: $!";
  if (!$pid) { close $r; open STDOUT, ">", "/dev/null"; open STDERR, ">&", $w; exec "/bin/sh", "-c", "ulimit -t $tmo; exec \"\$@\"", "sh", @cmd; exit 127 }
  close $w; my $err = ""; my $timed = 0; my ($u0, $s0) = (times)[2, 3];
  eval { local $SIG{ALRM} = sub { die "alarm\n" }; alarm 10 * $tmo; local $/; $err = <$r> // ""; waitpid $pid, 0; alarm 0; 1 } or do { kill 9, $pid; waitpid $pid, 0; $timed = 1 };
  my $ws = $?; my ($u1, $s1) = (times)[2, 3]; $cpu = $u1 + $s1 - $u0 - $s0; my $sig = $ws & 127;
  $status = ($timed || $sig == 24 || $sig == 9) ? "timeout" : (($ws >> 8) == 0 && $sig == 0 ? "ok" : "fail");
  ($first) = grep { /\S/ } split /\n/, $err; $first //= ""; 1;
} or do { $first = "runner: $@" };
$first =~ s/[\t\n]/ /g;
syswrite STDOUT, sprintf("%s\t%.2f\t%s\t%s\t%.2f\n", $status, $cpu, $file, substr($first, 0, 240), time - $t0);
exit 0;
'

# Clones a repository at a commit: shallow, without blobs outside the sparse patterns.
clone() {
  local name=$1 url=$2 commit=$3 patterns=$4 dir="$CORPUS/$1"
  if [[ -d "$dir/.git" ]] && [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$commit" ]]; then return; fi
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$url"
  if [[ -n "$patterns" ]]; then
    git -C "$dir" config core.sparseCheckout true
    tr ' ' '\n' <<<"$patterns" >"$dir/.git/info/sparse-checkout"
  fi
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# Lists the files of the language in a clone, relative to it, sorted.
files_of() {
  local dir=$1 expr=() e
  for e in "${EXTENSIONS[@]}"; do expr+=(-o -name "*.$e"); done
  (cd "$dir" && find . -path ./.git -prune -o -type f \( "${expr[@]:1}" \) -print | sed 's|^\./||' | LC_ALL=C sort)
}

# Parses the listed absolute paths with the grammar arguments, in parallel, into a TSV file.
parse_all() {
  local out=$1; shift
  tr '\n' '\0' | xargs -0 -n 1 -P "$JOBS" perl -e "$RUNNER" "$TIMEOUT" "$BIN" parse "$@" >"$out" || true
}

main() {
  mkdir -p "$CORPUS" "$RESULTS"
  local entry name url commit patterns
  for entry in "${REPOS[@]}"; do
    IFS='|' read -r name url commit patterns <<<"$entry"
    echo "clone $name at ${commit:0:12}${patterns:+ (sampled: $patterns)}" >&2
    clone "$name" "$url" "$commit" "$patterns"
  done

  : >"$RESULTS/files.txt"
  for entry in "${REPOS[@]}"; do
    IFS='|' read -r name _ <<<"$entry"
    files_of "$CORPUS/$name" | sed "s|^|$CORPUS/$name/|" >>"$RESULTS/files.txt"
  done
  local plain=() dialect=() g
  for g in "${PLAIN[@]}"; do [[ "$g" == *.g4 ]] && plain+=("$ROOT/$g") || plain+=("$g"); done
  for g in "${DIALECT[@]}"; do [[ "$g" == *.g4 ]] && dialect+=("$ROOT/$g") || dialect+=("$g"); done

  echo "plain grammar: $(wc -l <"$RESULTS/files.txt" | tr -d ' ') files, $JOBS jobs, ${TIMEOUT}s of CPU per file" >&2
  parse_all "$RESULTS/plain.tsv" "${plain[@]}" <"$RESULTS/files.txt"
  awk -F'\t' '$1 == "ok" { print $3 }' "$RESULTS/plain.tsv" | LC_ALL=C sort >"$RESULTS/plain-ok.txt"
  echo "dialect: $(wc -l <"$RESULTS/plain-ok.txt" | tr -d ' ') files the plain grammar parses" >&2
  parse_all "$RESULTS/dialect.tsv" "${dialect[@]}" <"$RESULTS/plain-ok.txt"
  if [[ $(wc -l <"$RESULTS/plain.tsv") -ne $(wc -l <"$RESULTS/files.txt") || $(wc -l <"$RESULTS/dialect.tsv") -ne $(wc -l <"$RESULTS/plain-ok.txt") ]]; then
    echo "incomplete run: a parse was not recorded for every file; rerun" >&2
    exit 2
  fi

  printf '%s\n' "${REPOS[@]}" >"$RESULTS/repos.txt"
  printf '%s\n' "${EXCLUDE[@]+"${EXCLUDE[@]}"}" >"$RESULTS/exclude.txt"
  awk -F'\t' -v corpus="$CORPUS/" -v reposfile="$RESULTS/repos.txt" -v exclfile="$RESULTS/exclude.txt" -v dialectfile="$RESULTS/dialect.tsv" '
    function repo_of(path,   rel) { rel = substr(path, length(corpus) + 1); return substr(rel, 1, index(rel, "/") - 1) }
    function rel_of(path,   rel) { rel = substr(path, length(corpus) + 1); return substr(rel, index(rel, "/") + 1) }
    function reason_of(repo, rel,   i) { for (i = 1; i <= nx; i++) if (xrepo[i] == repo && rel ~ xre[i]) return xwhy[i]; return "" }
    BEGIN {
      while ((getline line < reposfile) > 0) { split(line, p, "|"); order[++nr] = p[1] }
      while ((getline line < exclfile) > 0) { if (line == "") continue; split(line, p, "|"); nx++; xrepo[nx] = p[1]; xre[nx] = p[2]; xwhy[nx] = p[3] }
      while ((getline line < dialectfile) > 0) { split(line, p, "\t"); dstat[p[3]] = p[1]; derr[p[3]] = p[4] }
    }
    {
      r = repo_of($3); rel = rel_of($3); files[r]++; secs[r] += $2; times[++nt] = $2
      if ($2 > maxt[r]) maxt[r] = $2
      slow[nt] = sprintf("%7.2fs  %s  %s/%s", $2, $1, r, rel)
      why = reason_of(r, rel)
      if ($1 == "ok") {
        parsed[r]++
        if (why != "") stale[++ns] = r "/" rel " parses but is excluded (" why ")"
        if (dstat[$3] != "ok") { dfail[r]++; dlist[++nd] = sprintf("%s/%s: %s %s", r, rel, dstat[$3], derr[$3]) } else dok[r]++
      } else if (why != "") { excluded[r]++; xcount[r SUBSEP why]++ }
      else { failed[r]++; flist[++nf] = sprintf("%s/%s: %s (%.2fs) %s", r, rel, $1, $2, $4); ftimes[nf] = $2 }
    }
    END {
      printf "\n%-22s %7s %7s %9s %9s %9s %9s %8s %8s\n", "repository", "files", "parsed", "excluded", "failures", "dialect", "d-fail", "cpu(s)", "max(s)"
      for (i = 1; i <= nr; i++) {
        r = order[i]; tf += files[r]; tp += parsed[r]; tx += excluded[r]; tfl += failed[r]; td += dok[r]; tdf += dfail[r]
        printf "%-22s %7d %7d %9d %9d %9d %9d %8.1f %8.2f\n", r, files[r], parsed[r], excluded[r], failed[r], dok[r], dfail[r], secs[r], maxt[r]
      }
      printf "%-22s %7d %7d %9d %9d %9d %9d\n", "total", tf, tp, tx, tfl, td, tdf
      printf "\nparse rate: %d of %d files (%.2f%%); with exclusions %d of %d (%.2f%%)\n", tp, tf, tf ? 100 * tp / tf : 0, tp + tx, tf, tf ? 100 * (tp + tx) / tf : 0
      n = asort_num(times)
      if (n) printf "CPU time per file: median %.2fs, p90 %.2fs, p99 %.2fs, max %.2fs\n", times[int(n * 0.5) + (n * 0.5 > int(n * 0.5))], times[pct(n, 0.9)], times[pct(n, 0.99)], times[n]
      if (nf) { m = 0; for (i = 1; i <= nf; i++) if (ftimes[i] > m) m = ftimes[i]; printf "slowest failure: %.2fs\n", m }
      print "\nslowest files (CPU seconds):"; k = sort_slow(nt); for (i = 1; i <= k && i <= 10; i++) print "  " slowsorted[i]
      if (tx) { print "\nexclusions:"; for (key in xcount) { split(key, q, SUBSEP); printf "  %s: %d file(s), %s\n", q[1], xcount[key], q[2] } }
      if (ns) { print "\nstale exclusions:"; for (i = 1; i <= ns; i++) print "  " stale[i] }
      if (nf) { print "\nfailures:"; for (i = 1; i <= nf; i++) print "  " flist[i] }
      if (nd) { print "\ndialect failures on files the plain grammar parses:"; for (i = 1; i <= nd; i++) print "  " dlist[i] }
      exit (nf || nd) ? 1 : 0
    }
    function pct(n, q,   k) { k = int(n * q); if (k < 1) k = 1; return k }
    function asort_num(a,   i, j, t, n) { n = 0; for (i in a) n++; for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } return n }
    function sort_slow(n,   i, j, t) { for (i = 1; i <= n; i++) slowsorted[i] = slow[i]; for (i = 2; i <= n; i++) { t = slowsorted[i]; for (j = i - 1; j >= 1 && slowsorted[j] < t; j--) slowsorted[j + 1] = slowsorted[j]; slowsorted[j + 1] = t } return n }
  ' "$RESULTS/plain.tsv"
}
