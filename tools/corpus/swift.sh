#!/usr/bin/env bash
# Parse a corpus of widely used Swift projects with canon's Swift grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/swift.sh [CORPUS_DIR]   (default /tmp/corpus/swift; JOBS, TIMEOUT, and ONLY,
# one repository's name, may be set in the environment). Run from anywhere after `stack build`; the
# clones never enter the repository. Each file is parsed in the build canon reads by default, the
# first branch of each #if whose condition some build satisfies. ref:DEC-swift-grammar
. "$(dirname "$0")/process-group.sh"
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/swift}
JOBS=${JOBS:-8}
# CPU seconds per file. The largest files of the corpus, swift-syntax's generated syntax nodes,
# parse in a few seconds; every failing file fails in under one.
TIMEOUT=${TIMEOUT:-60}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=net-common.sh
. "$ROOT/tools/corpus/net-common.sh"

G=$ROOT/grammars/swift
PLAIN_LEXER=$G/SwiftLexer.g4
PLAIN_PARSER=$G/SwiftParser.g4
DIALECT_LEXER=$G/canonically_commented/SwiftLexer.g4
DIALECT_PARSER=$G/canonically_commented/SwiftParser.g4
START=topLevel

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository). Swift's
# own repository is sampled to its standard library, whose .swift.gyb templates are not Swift and
# are not read.
REPOS=(
  "swift-nio https://github.com/apple/swift-nio e12881f2a69168c984b890eec7a10de70441d2d7"
  "swift-collections https://github.com/apple/swift-collections 935f696a549abf069a2a1e4c6db2f834f7009cd3"
  "swift-algorithms https://github.com/apple/swift-algorithms 5b7143f8e291dee0e14c118fd0212487f0b37af5"
  "argument-parser https://github.com/apple/swift-argument-parser efd239f0055b3d6b6cc122a786c46a0ea8d0235b"
  "alamofire https://github.com/Alamofire/Alamofire bda9ed57d72988a3a2ada33d824583541f86eac6"
  "vapor https://github.com/vapor/vapor bf77fc69b1426dd297c78938349e0c7468be56be"
  "swift-syntax https://github.com/swiftlang/swift-syntax 09b1d91451c5a0277600cee849fd968d5302460b"
  "swift-format https://github.com/swiftlang/swift-format b15dd59fad21f1770cdc888b1ca6e2937490001a"
  "kingfisher https://github.com/onevcat/Kingfisher 08557202ba5a412758fa09f01c4e807f2ad94036"
  "snapkit https://github.com/SnapKit/SnapKit 250529bec615066185ff328984855101820fcbee"
  "composable-architecture https://github.com/pointfreeco/swift-composable-architecture bc2db5ba8ad3a47deba5db32fa340637ba6c9a76"
  "swift-stdlib https://github.com/swiftlang/swift fd5346677872e94cdf205781504dac8a57eb11a3 stdlib/public"
  "rxswift https://github.com/ReactiveX/RxSwift 3e33f90c1bcd3cdea25bdb49bd4a594a50c3ab84"
  "swiftyjson https://github.com/SwiftyJSON/SwiftyJSON 3d2544101a03f22b2217d464dc7d359eeb86e159"
  "charts https://github.com/ChartsOrg/Charts 1bad5469f57628782110b05996d4fa00473abf06"
  "lottie https://github.com/airbnb/lottie-ios 1fb4d7d5b45b0e81239c0c0cab95136a10153762"
  "moya https://github.com/Moya/Moya 24c26671a2f0fc26b53c9fa2410c97987fb0f05a"
)

# Files left out deliberately, as "repository path reason": invalid-code fixtures and files the
# Swift compiler rejects, as `swiftc -parse` reports. A path ending in / leaves out the directory.
EXCLUDES=$(cat <<'EXC'
composable-architecture Sources/ComposableArchitecture/Documentation.docc/Tutorials/BuildingSyncUps/07-SyncUpDetailNavigation/MeetingNavigation-02-code-0004-previous.swift rejected: an elided tutorial step, which swiftc -parse rejects as missing a closing brace
EXC
)

# The existing samples, vendored in the repository.
SAMPLES=(swift-argument-parser)

corpus_main swift -name '*.swift'
