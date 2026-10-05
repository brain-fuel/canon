#!/usr/bin/env bash
# Parses the YAML corpus with canon's YAML grammar: shallow-clones each repository below, pinned to
# a commit, into the directory given as the first argument (default /tmp/corpus/yaml), parses every
# .yaml and .yml file with the plain grammar under a per-file timeout, prints per repository the
# files parsed, the failures, and the slowest files, and then parses every file the plain grammar
# parsed with the canonically commented Pulumi dialect, which must parse them all. Pulumi programs
# (Pulumi.yaml, Pulumi.<stack>.yaml, Main.yaml) are what the dialect reads into units; any other
# YAML file, such as a Kubernetes manifest or a GitHub workflow, is read by the plain grammar under
# a plain YAML profile and has no units. Large repositories are sampled by subdirectory with a
# sparse checkout; the sampled paths are the patterns after the commit below.
# ref:DEC-pulumi-yaml-grammar
#
# Environment: CORPUS_TIMEOUT (seconds per file, default 10), CORPUS_JOBS (parallel parses,
# default 8), CORPUS_SKIP_FETCH=1 to reuse the clones as they are.
set -euo pipefail

ROOT=${1:-/tmp/corpus/yaml}
TIMEOUT_SECONDS=${CORPUS_TIMEOUT:-10}
JOBS=${CORPUS_JOBS:-8}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
BIN=$(cd "$CANON_DIR" && stack path --local-install-root)/bin/canon
PLAIN=("$CANON_DIR/grammars/yaml/YAMLLexer.g4" "$CANON_DIR/grammars/yaml/YAMLParser.g4")
DIALECT=("$CANON_DIR/grammars/yaml/canonically_commented/YAMLLexer.g4" "$CANON_DIR/grammars/yaml/canonically_commented/YAMLParser.g4")
START=yamlFile

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "pulumi-examples https://github.com/pulumi/examples 925d7de14c87a74b2ce46de5c0b0606b312c8322 *.yaml *.yml"
  "pulumi-yaml https://github.com/pulumi/pulumi-yaml e0aeb48e47a5ebc66ab95a5b1fae848485f4018b *.yaml *.yml"
  "kubernetes-examples https://github.com/kubernetes/examples d6b8cd27eacb51e651a1aa6f7c190a28713eff6e *.yaml *.yml"
  "kubernetes-website https://github.com/kubernetes/website abc9ea495989b5660aae4bb7dafa1fb15cad0aad /content/en/examples/"
  "kubernetes https://github.com/kubernetes/kubernetes 8ae47e9fc94cbb1f8a36dafb13209984d5e07d0f /.github/"
  "vscode https://github.com/microsoft/vscode 729f257fa411ea4b1cbdb7f404aa79941182209b /.github/"
  "react https://github.com/facebook/react 278794d7dee9cd2a3a2aaf9f0b2a4b8b747d74ee /.github/"
  "rust https://github.com/rust-lang/rust 602727f26878dcf9eb2999e2f58e5df1269ff47e /.github/"
  "cpython https://github.com/python/cpython 3f9118f1d17ae2ff0e25bd07fce9940ba13afdff /.github/"
  "node https://github.com/nodejs/node 019e869ad3a3941cd83d6b77fb1d4b3eaad2d64c /.github/"
  "tensorflow https://github.com/tensorflow/tensorflow 1d968a6e886854cd650b7c378baee96effdef3dc /.github/"
  "pytorch https://github.com/pytorch/pytorch 8646abda04925953cd39f3103cd42e894dcdf3af /.github/"
  "next.js https://github.com/vercel/next.js 6194d642b6fd743437da21dac3c720a587e6b9b2 /.github/"
  "pulumi https://github.com/pulumi/pulumi 059b146050a7ab4339be0d5215c7ae2d75b4fd71 /.github/"
  "home-assistant https://github.com/home-assistant/core 43a27100abbe777f5f7725bfba72c1b9b3800dd3 /.github/"
  "ansible https://github.com/ansible/ansible be0fd3b10c00bf604b3a8bb519a5960074f2e26d /.github/"
  "angular https://github.com/angular/angular 7d96a37af4f7b7dd9dc9a2b9b90cc043c7da2a31 /.github/"
  "django https://github.com/django/django fd91518f17c8a84fa47fe0e5534ef46afa7a0f7a /.github/"
  "deno https://github.com/denoland/deno 3d44d1d82fdaca0b4e776bfe89e46e026e29f72d /.github/"
  "typescript https://github.com/microsoft/TypeScript ca197b7b8586900c3b75c0365fac31cfcaaacca7 /.github/"
  "grafana https://github.com/grafana/grafana 0833fa8880960f3d49a034718c89fddcce83c0e0 /.github/"
  "electron https://github.com/electron/electron e91b6a0ab5b6648c447ed11bdc3d54f7d50a17e3 /.github/"
  "flutter https://github.com/flutter/flutter 0f35e8df0fb70005ab9bd15183c52b55c34c33c5 /.github/"
  "vscode-go https://github.com/golang/vscode-go 756676b85c18f217e5a16565ba9e0ab83d8bb58c /.github/"
  "terraform-provider-azurerm https://github.com/hashicorp/terraform-provider-azurerm 8f1dfbe2371f97d7f1d6e1f34b69451febfba244 /.github/"
  "compose https://github.com/docker/compose 42f48072bbf92ee9b0e43f9fdf2008d03546e7ca /.github/"
  "prometheus https://github.com/prometheus/prometheus 770ca8fb8f8e0765318910f2c43107261f9b875d /.github/"
  "aws-cloudformation-templates https://github.com/aws-cloudformation/aws-cloudformation-templates a0f43bc6d20813052892546f445037cf84c75b54 *.yaml *.yml"
  "ansible-examples https://github.com/ansible/ansible-examples b50586543c6c4be907fdc88f9f78a2b35d2a895f *.yaml *.yml"
  "bitnami-charts https://github.com/bitnami/charts bb5e98a6e3c5ca196420d2414769b681c9284101 /bitnami/*/values.yaml /bitnami/*/Chart.yaml /.github/"
)

# Files a failure of which is a deliberate exclusion: the repository-relative path, then the class.
EXCLUSIONS=(
  "pulumi-examples/aws-ts-eks-distro/eksdistro/cluster.yaml template: a Mustache template that index.ts renders before kops reads it as YAML"
  "pulumi-yaml/pkg/pulumiyaml/packages/testdata/good/ignored.yaml template: a Helm chart template, YAML only once Helm renders it"
)

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

# The files of the language under a directory, outside .git.
language_files() {
  find "$1" -path '*/.git' -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print0
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

# The exclusion class of a failing file, or nothing.
exclusion_of() {
  local rel=$1 entry
  for entry in ${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}; do
    if [ "${entry%% *}" = "$rel" ]; then
      printf '%s' "${entry#* }"
      return
    fi
  done
}

mkdir -p "$ROOT"
RESULTS=$ROOT/.results
mkdir -p "$RESULTS"

for spec in "${REPOS[@]}"; do
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

printf '%-32s %7s %7s %8s %9s %8s  %s\n' repository files parsed excluded failures seconds slowest
total_files=0
total_parsed=0
total_excluded=0
total_failed=0
: > "$RESULTS/plain-all.tsv"
: > "$RESULTS/failures.tsv"
for spec in "${REPOS[@]}"; do
  name=${spec%% *}
  language_files "$ROOT/$name" | parse_all "${PLAIN[0]}" "${PLAIN[1]}" "$RESULTS/$name.tsv"
  cat "$RESULTS/$name.tsv" >> "$RESULTS/plain-all.tsv"
  files=$(wc -l < "$RESULTS/$name.tsv" | tr -d ' ')
  parsed=$(awk -F '\t' '$1 == "ok"' "$RESULTS/$name.tsv" | wc -l | tr -d ' ')
  excluded=0
  failed=0
  while IFS=$'\t' read -r status seconds file message; do
    [ "$status" = ok ] && continue
    rel=${file#"$ROOT/$name/"}
    class=$(exclusion_of "$name/$rel")
    if [ -n "$class" ]; then
      excluded=$((excluded + 1))
    else
      failed=$((failed + 1))
      printf '%s\t%s\t%s\t%s\n' "$status" "$seconds" "$name/$rel" "$message" >> "$RESULTS/failures.tsv"
    fi
  done < "$RESULTS/$name.tsv"
  seconds=$(awk -F '\t' '{ s += $2 } END { printf "%.1f", s }' "$RESULTS/$name.tsv")
  slowest=$(sort -t $'\t' -k2,2 -rn "$RESULTS/$name.tsv" | awk 'NR <= 3' | awk -F '\t' -v root="$ROOT/$name/" '{ sub(root, "", $3); printf "%s %ss  ", $3, $2 }')
  printf '%-32s %7s %7s %8s %9s %8s  %s\n' "$name" "$files" "$parsed" "$excluded" "$failed" "$seconds" "$slowest"
  total_files=$((total_files + files))
  total_parsed=$((total_parsed + parsed))
  total_excluded=$((total_excluded + excluded))
  total_failed=$((total_failed + failed))
done
printf '%-32s %7s %7s %8s %9s\n' total "$total_files" "$total_parsed" "$total_excluded" "$total_failed"

echo
echo "failures not excluded:"
cat "$RESULTS/failures.tsv"

echo
echo "time per file (seconds):"
sort -t $'\t' -k2,2 -n "$RESULTS/plain-all.tsv" | awk -F '\t' '{ t[NR] = $2 } END { if (NR) printf "  p50 %s  p90 %s  p99 %s  max %s\n", t[int(NR * 0.5) + 1], t[int(NR * 0.9) + 1], t[int(NR * 0.99) + 1], t[NR] }'
echo "slowest failing file (seconds):"
awk -F '\t' '$1 != "ok"' "$RESULTS/plain-all.tsv" | sort -t $'\t' -k2,2 -rn | awk 'NR <= 3' | awk -F '\t' '{ printf "  %s %s\n", $2, $3 }'
echo "slowest files:"
sort -t $'\t' -k2,2 -rn "$RESULTS/plain-all.tsv" | awk 'NR <= 5' | awk -F '\t' '{ printf "  %s %s\n", $2, $3 }'

echo
echo "dialect over the files the plain grammar parsed:"
awk -F '\t' '$1 == "ok" { printf "%s%c", $3, 0 }' "$RESULTS/plain-all.tsv" | parse_all "${DIALECT[0]}" "${DIALECT[1]}" "$RESULTS/dialect.tsv"
dialect_files=$(wc -l < "$RESULTS/dialect.tsv" | tr -d ' ')
dialect_parsed=$(awk -F '\t' '$1 == "ok"' "$RESULTS/dialect.tsv" | wc -l | tr -d ' ')
echo "  $dialect_parsed / $dialect_files parsed"
awk -F '\t' '$1 != "ok" { printf "  %s %s %s\n", $1, $3, $4 }' "$RESULTS/dialect.tsv"

[ "$total_failed" -eq 0 ] && [ "$dialect_parsed" -eq "$dialect_files" ]
