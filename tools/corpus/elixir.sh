#!/usr/bin/env bash
# Elixir corpus: clones popular Elixir projects at pinned commits into the directory given as the
# first argument (default /tmp/corpus/elixir), parses every .ex and .exs file with canon's plain
# Elixir grammar and then with its canonically commented dialect, and prints files parsed per
# repository, the failures, and the slowest files. Elixir itself is sampled to lib/, which holds
# the standard library, Mix, ExUnit, IEx, EEx, and Logger with their tests. Rerun after changing
# a grammar; no rebuild is needed unless Haskell changed. ref:DEC-elixir-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

CORPUS=${1:-/tmp/corpus/elixir}
PLAIN=(grammars/elixir/ElixirLexer.g4 grammars/elixir/ElixirParser.g4 file)
DIALECT=(grammars/elixir/canonically_commented/ElixirLexer.g4 grammars/elixir/canonically_commented/ElixirParser.g4 file)
EXTENSIONS=(ex exs)

REPOS=(
  "elixir|https://github.com/elixir-lang/elixir|23423047325d0c9fef23e81955ee4295957f8705|/lib/"
  "phoenix|https://github.com/phoenixframework/phoenix|2ca60ffe811c0e585835cfc309b645c3a4190df1|"
  "ecto|https://github.com/elixir-ecto/ecto|94d69279c517347ff0962b138f4ccd0556486ae2|"
  "plug|https://github.com/elixir-plug/plug|73404f851852a00ffb2014be95d4598900fa77b8|"
  "jason|https://github.com/michalmuskala/jason|4ede42858eb19f80ec9e863aab52df466eab8608|"
)

EXCLUDE=(
)

source "$(dirname "$0")/beam-common.sh"
main
