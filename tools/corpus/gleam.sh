#!/usr/bin/env bash
# Gleam corpus: clones popular Gleam packages and the Gleam compiler at pinned commits into the
# directory given as the first argument (default /tmp/corpus/gleam), parses every .gleam file with
# canon's plain Gleam grammar and then with its canonically commented dialect, and prints files
# parsed per repository, the failures, and the slowest files. The compiler is sampled to its .gleam
# files, which are test projects and fixtures. Rerun after changing a grammar; no rebuild is
# needed unless Haskell changed. ref:DEC-gleam-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

CORPUS=${1:-/tmp/corpus/gleam}
PLAIN=(grammars/gleam/GleamLexer.g4 grammars/gleam/GleamParser.g4 module)
DIALECT=(grammars/gleam/canonically_commented/GleamLexer.g4 grammars/gleam/canonically_commented/GleamParser.g4 module)
EXTENSIONS=(gleam)

REPOS=(
  "stdlib|https://github.com/gleam-lang/stdlib|84ac8c701824b5b004897562c30cdd9c9aced346|"
  "json|https://github.com/gleam-lang/json|9792d8a5ec14e03760f8ccbc8992dff4d45105fe|"
  "otp|https://github.com/gleam-lang/otp|235c761d8b8769fafe2b725d19458bc37e0ea178|"
  "erlang|https://github.com/gleam-lang/erlang|dfa7cd705d8e97fe3af48754307130ecc14b5a45|"
  "http|https://github.com/gleam-lang/http|fa4b3342dba943103458a36628de7ca8299887bc|"
  "httpc|https://github.com/gleam-lang/httpc|0f5f2fdc88d58740e8790991e7b18529ead7d85a|"
  "crypto|https://github.com/gleam-lang/crypto|7f0dc2624b9ec1822e8534b68935775084cbb379|"
  "javascript|https://github.com/gleam-lang/javascript|b51b4365c2b5fa3f9767a349a7e7a68a874264cb|"
  "time|https://github.com/gleam-lang/time|09b049db0d697a5c9ffceec6010fa17ad6c7a53a|"
  "regexp|https://github.com/gleam-lang/regexp|4764177ecd1a818f4eba496d0a2af97f3c04a6b2|"
  "yielder|https://github.com/gleam-lang/yielder|2134616880ea690c81e1aced354a6bd2c845dccb|"
  "gleeunit|https://github.com/lpil/gleeunit|3d6fc20588d52ddb8e75eaf158f46900809380e8|"
  "wisp|https://github.com/gleam-wisp/wisp|f6e70b460f318d3308f9810f090315f575cbab24|"
  "lustre|https://github.com/lustre-labs/lustre|64b383521970eaf0c311051b19291fc20d73d79c|"
  "mist|https://github.com/rawhat/mist|6be7897833c796019a27a3df7082e50a64b419f5|"
  "pog|https://github.com/lpil/pog|1260e90168cba09acdab3a226ca026c9afb69285|"
  "sqlight|https://github.com/lpil/sqlight|b19f58d9f1543b9cf7efd3da8b00e09900f2dd08|"
  "envoy|https://github.com/lpil/envoy|8c3e845563c752ad9cf01a990e7ca9c904b45116|"
  "birdie|https://github.com/giacomocavalieri/birdie|4523e5760d227706af1639d3deb6c80fff4b8c3f|"
  "glance|https://github.com/lpil/glance|119266f8ebaf65251831038fdfa1e6369f034dc3|"
  "simplifile|https://github.com/bcpeinhardt/simplifile|8404c143b9d777de25115d7098368bfa224d5a02|"
  "squirrel|https://github.com/giacomocavalieri/squirrel|5b6407d14a7c83af102944f2c86f52a521a74d57|"
  "maths|https://github.com/gleam-community/maths|31fb0d20fa09e5d50fc653fc875853dd01dfba16|"
  "ansi|https://github.com/gleam-community/ansi|a5ea289692ea17f7a6ff78486aeef0c0e0b24d0c|"
  "gleam|https://github.com/gleam-lang/gleam|52e735c82d42811dd08d29d5508f564da081fd7d|*.gleam"
)

EXCLUDE=(
)

source "$(dirname "$0")/beam-common.sh"
main
