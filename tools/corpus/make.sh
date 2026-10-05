#!/usr/bin/env bash
# Corpus check for canon's Makefile grammar (REQ-make-support, DEC-make-dialect).
# Clones widely used projects' makefiles, each pinned to a commit, shallow and blob-filtered, and
# sparse to their makefiles; extracts the makefiles GNU make's own test suite embeds in Perl; parses
# every makefile with the Makefile grammar (grammars/make/canonically_commented, which is both the
# reader and the canonically commented dialect, so both passes use it) under a per-file CPU-time limit;
# and prints per repository the files parsed out of the files, the failures, and the slowest files.
# Usage: tools/corpus/make.sh [clone-dir]   (default /tmp/corpus/make)
# Environment: CORPUS_TIMEOUT CPU seconds per file (default 10; the SLOW files get their own),
# CORPUS_JOBS parallel parses (default 8), CORPUS_CLONE_ONLY=1 to fetch the repositories without
# parsing, CORPUS_CANON a canon binary to use instead of the one stack built.
set -euo pipefail

LANG_NAME=make
DIR=${1:-/tmp/corpus/$LANG_NAME}
TIMEOUT=${CORPUS_TIMEOUT:-10}
JOBS=${CORPUS_JOBS:-8}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CANON=${CORPUS_CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
G=$ROOT/grammars/make/canonically_commented
# canon's Makefile grammar is its own and has no plain sibling: the dialect is the reader.
PLAIN=("$G/MakefileLexer.g4" "$G/MakefileParser.g4" makefile)
DIALECT=("$G/MakefileLexer.g4" "$G/MakefileParser.g4" makefile)

# Repositories: name, URL, pinned commit, and the sparse paths (none means the whole tree).
# linux is sampled to its top Makefile and Kbuild, scripts/Makefile.* and scripts/Kbuild.include,
# and the Makefiles of a handful of subsystems; cpython, git, and canon's own tree to their
# makefiles; GNU make to tests/scripts, whose makefiles are extracted from the Perl test scripts.
REPOS='
linux https://github.com/torvalds/linux 67f0943b394d920b6c142aad8c6af94340342ae7 /Makefile /Kbuild /scripts/Makefile.* /scripts/Kbuild.include /kernel/Makefile /mm/Makefile /fs/Makefile /fs/ext4/Makefile /net/Makefile /net/ipv4/Makefile /drivers/Makefile /drivers/net/Makefile /arch/x86/Makefile /arch/x86/Makefile_32.cpu /arch/x86/boot/Makefile /arch/arm64/Makefile /tools/scripts/Makefile.include /tools/build/Makefile.build /tools/perf/Makefile.perf /tools/perf/Makefile.config
cpython https://github.com/python/cpython 3f9118f1d17ae2ff0e25bd07fce9940ba13afdff /Makefile.pre.in Makefile *.mk
git https://github.com/git/git 8103b446517e0c44e67561b9d0ccce56efa60a71 Makefile *.mak *.mk config.mak.*
gnumake-tests https://github.com/mirror/make c63a5bc6a2881d515bb3020ed477fcba08fb2f3d /tests/scripts/
canon local:. 0
'

# Files listed here are known to be slow, with the CPU seconds they get instead and the reason.
SLOW='
'

# Files listed here are deliberate exclusions, each with its reason; they are counted, not parsed.
# GNU make's test fixtures that make itself rejects while reading them are added as they are extracted.
EXCLUDE='
'

files_of() { # files_of DIR: the files of the language under DIR
  if [ -d "$1/tests/scripts" ]; then
    extract_gnumake_tests "$1"
    find "$1/extracted" -type f -name '*.mk' | LC_ALL=C sort
    return
  fi
  find "$1" -type f \( -name Makefile -o -name makefile -o -name GNUmakefile -o -name 'Makefile.*' \
    -o -name Kbuild -o -name '*.mk' -o -name '*.mak' -o -name 'config.mak.*' \) -not -path '*/.git/*' -not -path '*/.stack-work/*' \
    -not -path '*/extracted/*' -not -name '*.orig' -not -name '*.yaml' | LC_ALL=C sort
}

# extract_gnumake_tests CLONE: writes each makefile a test script under tests/scripts hands to
# run_make_test, or prints to MAKEFILE, as CLONE/extracted/<script>.<n>.mk, evaluating only Perl
# string literals (in a Safe compartment); a fixture whose expected output shows make rejecting the
# makefile while reading it is added to EXCLUDE as an invalid-code fixture.
extract_gnumake_tests() {
  rm -rf "$1/extracted"; mkdir -p "$1/extracted"
  local invalid
  invalid=$(cd "$1/tests/scripts" && find . -type f ! -name test_template | LC_ALL=C sort | perl -e '
    use strict; use warnings; use Safe;
    my $safe = Safe->new; my $out = shift;
    my $syntax = qr/\*\*\* (missing separator|missing .(?:endif|endef)|invalid syntax in conditional|only one .else|recipe commences before first target|prerequisites cannot be defined in recipes|empty variable name|unterminated variable reference|unterminated call to function|target pattern contains no|mixed implicit|grouped targets must provide a recipe|invalid variable name)|#MAKEFILE#:\d+: \$(?:nosep|unterm)\b/;
    sub literal { # literal(TEXT, POS): the source of the Perl string literal at POS and its end
      my ($t, $p) = @_; my $s = $p;
      if (substr($t, $p) =~ /\A(qq?)\s*([^\w\s])/) {
        my $open = $2; my $q = $p + length($&); my %pair = ("(" => ")", "{" => "}", "[" => "]", "<" => ">");
        my $close = $pair{$open} // $open; my $depth = 1;
        while ($q < length $t) { my $c = substr($t, $q, 1);
          if ($c eq "\\") { $q += 2; next }
          if ($c eq $close && $close ne $open) { $depth--; } elsif ($c eq $open && $close ne $open) { $depth++; } elsif ($c eq $close) { $depth = 0 }
          $q++; last if $depth == 0 }
        return (substr($t, $s, $q - $s), $q);
      }
      my $c = substr($t, $p, 1); return () unless $c eq "\x27" || $c eq "\"";
      my $q = $p + 1;
      while ($q < length $t) { my $d = substr($t, $q, 1); if ($d eq "\\") { $q += 2; next } $q++; last if $d eq $c }
      return (substr($t, $s, $q - $s), $q);
    }
    while (my $f = <STDIN>) { chomp $f; $f =~ s{^\./}{};
      open my $h, "<", $f or next; local $/; my $t = <$h>; close $h;
      my @starts; while ($t =~ /(?:run_make_test\s*\(\s*|print\s+MAKEFILE\s+)/g) { push @starts, [$-[0], pos($t)] }
      my $n = 0;
      for my $i (0 .. $#starts) {
        my ($at, $p) = @{$starts[$i]}; my $next = $i < $#starts ? $starts[$i + 1][0] : length $t;
        my $src;
        if (substr($t, $p) =~ /\A<<\s*(["\x27]?)(\w+)\1;?[^\n]*\n/) {
          my ($quote, $tag) = ($1, $2); my $b = $p + length($&);
          my $e = index($t, "\n$tag\n", $b - 1); next if $e < 0;
          my $body = substr($t, $b, $e - $b + 1);
          if ($quote eq "\x27") { write_out($out, $f, ++$n, $body, rejected(substr($t, $e, $next - $e))); next }
          $src = "<<\"EOT_EXTRACT\";\n${body}EOT_EXTRACT\n";
        } else {
          my ($lit, $end) = literal($t, $p); next unless defined $lit;
          next unless substr($t, $end) =~ /\A\s*[,;)]/;
          $src = $lit;
        }
        my $value = $safe->reval($src); next unless defined $value && length $value;
        write_out($out, $f, ++$n, $value, rejected(substr($t, $p, $next - $p)));
      }
    }
    sub rejected { # rejected(TEXT): the syntax error make reports in the expected output, if any
      my ($text) = @_; return undef unless $text =~ $syntax;
      my $m = $&; $m =~ s/^#MAKEFILE#:\d+: //; $m =~ s/^\$nosep$/*** missing separator/; $m =~ s/^\$unterm$/*** unterminated variable reference/;
      return $m }
    sub write_out { my ($out, $f, $n, $text, $bad) = @_; (my $name = $f) =~ s{/}{-}g;
      my $path = sprintf "%s/%s.%02d.mk", $out, $name, $n;
      open my $o, ">", $path or die "$path: $!"; print $o $text; close $o;
      printf "%s %s\n", substr($path, length($out) + 1), $bad if defined $bad }
  ' "$1/extracted")
  local f msg
  while read -r f msg; do
    [ -n "$f" ] && EXCLUDE="$EXCLUDE
gnumake-tests/extracted/$f invalid-code fixture, make stops with: $msg"
  done <<< "$invalid"

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
