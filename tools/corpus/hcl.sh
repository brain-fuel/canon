#!/usr/bin/env bash
# Parses the HCL corpus with canon's HCL grammar: shallow-clones each repository below, pinned to a
# commit, into the directory given as the first argument (default /tmp/corpus/hcl), parses every
# .tf, .tfvars, .hcl, .tf.json, and .tfvars.json file with the plain grammar under a per-file
# timeout, prints per repository the files parsed, the failures, and the slowest files, and then
# parses every file the plain grammar parsed with the canonically commented dialect, which must
# parse them all. Large repositories are sampled by subdirectory with a sparse checkout; the
# sampled paths are the patterns after the commit below. ref:DEC-hcl-grammar
#
# Environment: CORPUS_TIMEOUT (seconds per file, default 10), CORPUS_JOBS (parallel parses,
# default 8), CORPUS_SKIP_FETCH=1 to reuse the clones as they are.
set -euo pipefail

ROOT=${1:-/tmp/corpus/hcl}
TIMEOUT_SECONDS=${CORPUS_TIMEOUT:-10}
JOBS=${CORPUS_JOBS:-8}
CANON_DIR=$(cd "$(dirname "$0")/../.." && pwd)
BIN=$(cd "$CANON_DIR" && stack path --local-install-root)/bin/canon
PLAIN=("$CANON_DIR/grammars/hcl/HCLLexer.g4" "$CANON_DIR/grammars/hcl/HCLParser.g4")
DIALECT=("$CANON_DIR/grammars/hcl/canonically_commented/HCLLexer.g4" "$CANON_DIR/grammars/hcl/canonically_commented/HCLParser.g4")
START=configFile

# name, https URL, pinned commit, and for a sampled repository the sparse-checkout patterns.
REPOS=(
  "terraform-aws-vpc https://github.com/terraform-aws-modules/terraform-aws-vpc b3abd6df2ecf052451a361ed55b8f06f8742a795"
  "terraform-aws-eks https://github.com/terraform-aws-modules/terraform-aws-eks e07246207174bd1ad8ed250f3bb54a9494342e80"
  "terraform-aws-iam https://github.com/terraform-aws-modules/terraform-aws-iam da8e6a8673933ee651f0f0fe611d5ac6b9f9bcb9"
  "terraform-aws-rds https://github.com/terraform-aws-modules/terraform-aws-rds 175da043429cbbe41c512f976105719f6d0e538c"
  "terraform-aws-rds-aurora https://github.com/terraform-aws-modules/terraform-aws-rds-aurora d72cba285514b5e2e83bea7dd1272c1c206a4f64"
  "terraform-aws-s3-bucket https://github.com/terraform-aws-modules/terraform-aws-s3-bucket 5dc2f1f89743ab935114b0b039bc88044a672ca2"
  "terraform-aws-security-group https://github.com/terraform-aws-modules/terraform-aws-security-group b3c1b2e8beff9671960f874f5569d77c803b0127"
  "terraform-aws-lambda https://github.com/terraform-aws-modules/terraform-aws-lambda 3a1405b98f47d1cb45acfa9e10a2fef2f02266df"
  "terraform-aws-ec2-instance https://github.com/terraform-aws-modules/terraform-aws-ec2-instance 4dfedcdd1f26006009c52439bbadba40a76ddb79"
  "terraform-aws-alb https://github.com/terraform-aws-modules/terraform-aws-alb 6c6e48c10d450d01cf6715346e926df0b858efc2"
  "terraform-aws-autoscaling https://github.com/terraform-aws-modules/terraform-aws-autoscaling 2a249e91c798fdf85ab60c3b1592cc5e11805cc4"
  "terraform-aws-ecs https://github.com/terraform-aws-modules/terraform-aws-ecs 135c225c75c7f0044966329c55ad8d647b358a57"
  "terraform-aws-dynamodb-table https://github.com/terraform-aws-modules/terraform-aws-dynamodb-table b6cc515760466a455ff0acb97b16151fdca4511e"
  "terraform-aws-cloudfront https://github.com/terraform-aws-modules/terraform-aws-cloudfront 5b9a0a480220b84f29f02d84ff71dd5340953f68"
  "terraform-aws-sqs https://github.com/terraform-aws-modules/terraform-aws-sqs a68b4d515f9ccc729fb8bf84c6760c6b91302ce0"
  "terraform-aws-sns https://github.com/terraform-aws-modules/terraform-aws-sns 4538b7e208f5bbd6c9972f427f85c9bd735aedad"
  "terraform-aws-kms https://github.com/terraform-aws-modules/terraform-aws-kms d25e459bd43d8d0bdff7c250ba6b237a12be7381"
  "terraform-aws-route53 https://github.com/terraform-aws-modules/terraform-aws-route53 883f987d6bb328c09bd4dfc5a04024534b371d59"
  "terraform-aws-acm https://github.com/terraform-aws-modules/terraform-aws-acm aae84c011dd68ace1beb5d10e1feddfe9a334953"
  "terraform-aws-apigateway-v2 https://github.com/terraform-aws-modules/terraform-aws-apigateway-v2 95e6a1d56d6d761ec12c89b36b29aad03a421b2f"
  "terraform-aws-eventbridge https://github.com/terraform-aws-modules/terraform-aws-eventbridge f9934726324c988f823682884b4fa003586a7b6f"
  "terraform-aws-step-functions https://github.com/terraform-aws-modules/terraform-aws-step-functions 16c7a1ffaa72643d714a7b3924216edce9413482"
  "terraform-aws-notify-slack https://github.com/terraform-aws-modules/terraform-aws-notify-slack a7765ac0a547f95c8aa48459f84077be8562c0f7"
  "terraform-aws-atlantis https://github.com/terraform-aws-modules/terraform-aws-atlantis ffb75c7ef06eea96abead8506a9eaed13ad1a103"
  "terraform-aws-ecr https://github.com/terraform-aws-modules/terraform-aws-ecr f05e615fa452e813935986295e7770f8fa96948b"
  "terraform-aws-efs https://github.com/terraform-aws-modules/terraform-aws-efs e0ec33d8436363960395b859aff0168ce25c27a4"
  "terraform-aws-elasticache https://github.com/terraform-aws-modules/terraform-aws-elasticache a43aabccb95cdbe539a89dcc1039dd081831c321"
  "terraform-aws-msk-kafka-cluster https://github.com/terraform-aws-modules/terraform-aws-msk-kafka-cluster b6320829cdff49c1d0370e1ee9089ecb25eac07e"
  "terraform-aws-eks-pod-identity https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity b4a8990773bc3542408978f704c9fff66b2379a5"
  "terraform-aws-transit-gateway https://github.com/terraform-aws-modules/terraform-aws-transit-gateway 7973ea0890176868b62bb60a694768cec19daf9a"
  "terraform-provider-aws https://github.com/hashicorp/terraform-provider-aws e7bb9cc38b6210f7240b9c8d37d3a9cd18ad10e1 /examples/"
  "terraform-provider-google https://github.com/hashicorp/terraform-provider-google 0aba4009b6bbed7cffd69581fa0c1a02edebc3d0 /examples/"
  "terraform https://github.com/hashicorp/terraform 35ab6fb201e48a9df4e7f30d9c5c1f00ab1022a6 /internal/configs/testdata/valid-files/ /internal/configs/testdata/valid-modules/"
  "nomad https://github.com/hashicorp/nomad 04af70ce00aecbc3321982a80e89e312e40ae67f /e2e/**/*.hcl /demo/**/*.hcl"
  "packer-plugin-amazon https://github.com/hashicorp/packer-plugin-amazon 62c6d423e4127f2f8bb83cb2dfc1501eca2efdf7 *.hcl"
)

# Files a failure of which is a deliberate exclusion: the repository-relative path, then the class.
EXCLUSIONS=(
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
  find "$1" -path '*/.git' -prune -o -type f \( -name '*.tf' -o -name '*.tfvars' -o -name '*.hcl' -o -name '*.tf.json' -o -name '*.tfvars.json' \) -print0
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
