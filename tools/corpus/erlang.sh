#!/usr/bin/env bash
# Erlang corpus: clones popular Erlang projects at pinned commits into the directory given as the
# first argument (default /tmp/corpus/erlang), parses every .erl, .hrl, and .escript file with
# canon's plain Erlang grammar and then with its canonically commented dialect, and prints files
# parsed per repository, the failures, and the slowest files. OTP is sampled to the lib/
# applications listed in its patterns, RabbitMQ to the deps/ listed in its. Rerun after changing
# a grammar; no rebuild is needed unless Haskell changed. ref:DEC-erlang-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

CORPUS=${1:-/tmp/corpus/erlang}
PLAIN=(grammars/erlang/Erlang.g4 forms)
DIALECT=(grammars/erlang/canonically_commented/ErlangLexer.g4 grammars/erlang/canonically_commented/ErlangParser.g4 forms)
EXTENSIONS=(erl hrl escript)

REPOS=(
  "otp|https://github.com/erlang/otp|cfe4f037932061f9d82a2622cd9a9577ee4f0226|/lib/stdlib/ /lib/kernel/ /lib/compiler/ /lib/ssl/ /lib/public_key/ /lib/crypto/ /lib/inets/ /lib/ssh/ /lib/eunit/ /lib/common_test/ /lib/mnesia/ /lib/syntax_tools/ /lib/tools/ /lib/sasl/ /lib/parsetools/ /lib/edoc/ /lib/dialyzer/ /lib/debugger/ /lib/runtime_tools/"
  "rabbitmq-server|https://github.com/rabbitmq/rabbitmq-server|fddc4cf564b3ce78ca0ca26ae207b4b648818890|/deps/rabbit/ /deps/rabbit_common/ /deps/amqp_client/ /deps/amqp10_common/ /deps/amqp10_client/ /deps/rabbitmq_management/ /deps/rabbitmq_mqtt/ /deps/rabbitmq_stream/ /deps/rabbitmq_shovel/ /deps/rabbitmq_federation/ /deps/rabbitmq_prometheus/ /deps/rabbitmq_ct_helpers/"
  "ejabberd|https://github.com/processone/ejabberd|46b1ceb23bbae91f43b0547c89b15455a2ced22b|"
  "recon|https://github.com/ferd/recon|cb45e7b19808bbae1796f934a9d00aa2b24d648f|"
)

# Files the Erlang compiler rejects or never compiles, each with its reason.
EXCLUDE=(
  "otp|^lib/common_test/test/ct_auto_compile_SUITE_data/bad_SUITE\\.erl$|invalid test fixture: a deliberate syntax error, so that common_test reports a module that does not compile"
  "otp|^lib/common_test/test/ct_error_SUITE_data/error/test/no_compile_SUITE\\.erl$|invalid test fixture: a deliberate syntax error, an -include without its dot"
  "otp|^lib/parsetools/include/leexinc\\.hrl$|template, not Erlang: leex fills its ## placeholders to make a scanner"
  "otp|^lib/syntax_tools/examples/merl/merl_build\\.erl$|the compiler rejects it: a -doc attribute lacks its closing dot"
)

# The largest OTP test suites, of 28,000 lines and more, take over 20 CPU seconds.
TIMEOUT=${TIMEOUT:-60}

source "$(dirname "$0")/beam-common.sh"
main
