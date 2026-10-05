#!/usr/bin/env bash
# Parse a corpus of widely used Rust projects with canon's Rust grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/rust.sh [CORPUS_DIR]   (default /tmp/corpus/rust; JOBS, TIMEOUT, and ONLY,
# one repository's name, may be set in the environment). Run from anywhere; the clones never
# enter the repository. ref:DEC-rust-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/rust}
JOBS=${JOBS:-8}
TIMEOUT=${TIMEOUT:-20}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=net-common.sh
. "$ROOT/tools/corpus/net-common.sh"

G=$ROOT/grammars/rust
PLAIN_LEXER=$G/RustLexer.g4
PLAIN_PARSER=$G/RustParser.g4
DIALECT_LEXER=$G/canonically_commented/RustLexer.g4
DIALECT_PARSER=$G/canonically_commented/RustParser.g4
START=crate

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "rust https://github.com/rust-lang/rust 602727f26878dcf9eb2999e2f58e5df1269ff47e library/core library/alloc library/std"
  "tokio https://github.com/tokio-rs/tokio b2636752450484955e7ad334bac678424d51bc4a"
  "serde https://github.com/serde-rs/serde 6693a89cca77e0151437da1c7f890090b9ebf04c"
  "ripgrep https://github.com/BurntSushi/ripgrep 3fce3b5bb0236da2df6d99672afb8a719642eca7"
  "cargo https://github.com/rust-lang/cargo bb2126cffae48394a37db8728dc50a17bbfe54d4"
  "bevy https://github.com/bevyengine/bevy 14d79ccc341c4ab9ec91e2c01938c62c86b0d53a crates/bevy_ecs crates/bevy_app crates/bevy_math crates/bevy_reflect crates/bevy_transform crates/bevy_input"
)

# Files left out deliberately, as "repository path reason": files rustc rejects, invalid-code
# test fixtures, and generated files. A path ending in / leaves out the directory.
EXCLUDES=$(grep -v '^#' <<'EXC'
# rustfix fixtures: the input carries the compiler error rustfix's suggestion fixes (E0178,
# a missing comma between match arms); the .fixed.rs beside each parses.
cargo crates/rustfix/tests/everything/E0178.rs
cargo crates/rustfix/tests/everything/handle-insert-only.rs
# rustc's frontmatter ui tests, which Cargo vendors: each is rejected (a .stderr expectation or a
# //~ ERROR annotation) for a malformed fence or infostring.
cargo tests/testsuite/script/rustc_fixtures/fence-close-extra-after.rs
cargo tests/testsuite/script/rustc_fixtures/fence-indented.rs
cargo tests/testsuite/script/rustc_fixtures/fence-indented-mismatch.rs
cargo tests/testsuite/script/rustc_fixtures/fence-mismatch-1.rs
cargo tests/testsuite/script/rustc_fixtures/fence-mismatch-2.rs
cargo tests/testsuite/script/rustc_fixtures/fence-too-many-dashes.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-1.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-2.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-3.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-4.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-5.rs
cargo tests/testsuite/script/rustc_fixtures/fence-unclosed-6.rs
cargo tests/testsuite/script/rustc_fixtures/infostring-comma.rs
cargo tests/testsuite/script/rustc_fixtures/infostring-dot-leading.rs
cargo tests/testsuite/script/rustc_fixtures/infostring-hyphen-leading.rs
cargo tests/testsuite/script/rustc_fixtures/infostring-space.rs
cargo tests/testsuite/script/rustc_fixtures/multifrontmatter.rs
# Not a crate or module: tokens that a test includes as an expression with include!.
cargo tests/testsuite/script/rustc_fixtures/auxiliary/expr.rs
EXC
)

# The existing samples, vendored in the repository.
SAMPLES=(rust-scopeguard)

corpus_main rust -name '*.rs'
