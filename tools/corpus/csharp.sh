#!/usr/bin/env bash
# Parse a corpus of widely used C# projects with canon's C# grammar and its canonically
# commented dialect, and report per repository how many files each parses and the slowest.
# Usage: tools/corpus/csharp.sh [CORPUS_DIR]   (default /tmp/corpus/csharp; JOBS, TIMEOUT, and ONLY,
# one repository's name, may be set in the environment). Run from anywhere; the clones never
# enter the repository. ref:DEC-csharp-grammar
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${1:-/tmp/corpus/csharp}
JOBS=${JOBS:-8}
# CPU seconds per file. Generated C# runs to 40,000 lines, as Roslyn's syntax tree is, and the
# largest such files parse in 45 to 60 seconds; every failing file fails in under one.
TIMEOUT=${TIMEOUT:-120}
CANON=${CANON:-$(cd "$ROOT" && stack path --local-install-root)/bin/canon}
# shellcheck source=net-common.sh
. "$ROOT/tools/corpus/net-common.sh"

G=$ROOT/grammars/csharp
PLAIN_LEXER=$G/CSharpLexer.g4
PLAIN_PARSER=$G/CSharpParser.g4
DIALECT_LEXER=$G/canonically_commented/CSharpLexer.g4
DIALECT_PARSER=$G/canonically_commented/CSharpParser.g4
START=compilation_unit

# name, URL, pinned commit, and the subdirectories checked out (none: the whole repository).
REPOS=(
  "runtime https://github.com/dotnet/runtime 8e6821d2d9120795d68b6ebbcc47c9c7079de361 src/libraries/System.Private.CoreLib/src src/libraries/System.Collections src/libraries/System.Linq src/libraries/System.Text.Json/src src/libraries/System.Net.Http/src"
  "aspnetcore https://github.com/dotnet/aspnetcore aaec58f9ccee7962c6071b36f5b17eb07af0e856 src/Http src/Mvc/Mvc.Core src/Servers/Kestrel/Core"
  "roslyn https://github.com/dotnet/roslyn 303af2d38ee08b5fbf84246b215873399d4d613a src/Compilers/Core/Portable src/Compilers/CSharp/Portable"
  "newtonsoft-json https://github.com/JamesNK/Newtonsoft.Json 52fa3aef1f2cadcd3a3f874251eddc98d3efbbaa"
  "avalonia https://github.com/AvaloniaUI/Avalonia daed7a2592f1a56d3f93aa92bf59a0f51a8995d0 src/Avalonia.Base src/Avalonia.Controls"
)

# Files left out deliberately, as "repository path reason": files the C# compiler rejects, invalid-code
# test fixtures, and generated files. A path ending in / leaves out the directory.
EXCLUDES=$(cat <<'EXC'
aspnetcore src/Http/Routing/src/Matching/ILEmitTrieFactory.cs rejected: the #if IL_EMIT_SAVE_ASSEMBLY branch, a symbol no build defines (the project defines IL_EMIT_SAVE_ASSEMBLIES), lacks a closing parenthesis
runtime src/libraries/System.Private.CoreLib/src/System/Diagnostics/Tracing/TraceLogging/EnumHelper.cs rejected: the #if EVENTSOURCE_GENERICS branch, a symbol no build defines, begins with a stray ?using
EXC
)

# The existing samples, vendored in the repository.
SAMPLES=(csharp-guardclauses)

corpus_main csharp -name '*.cs'
