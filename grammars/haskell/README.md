# Haskell Grammar

`HaskellLexer.g4` and `HaskellParser.g4` are the Haskell grammar of
[antlr/grammars-v4](https://github.com/antlr/grammars-v4) (BSD-3-Clause,
Copyright (c) 2020 Evgeniy Slobodkin), with canon's changes. Every change is
marked `// canon:` in the grammar and recorded as `DEC-haskell-grammar-fixes`
in canon's `canonical_decisions.yaml`. The layout algorithm that the
upstream port's `HaskellBaseLexer` implements is ported as a lexer hook,
`src/Canon/Antlr4/Lex/Haskell.hs`, selected by the lexer's `superClass`.
`canonically_commented/` holds the dialect canon extracts Haskell units with,
recorded as `DEC-haskell-dialect`; it carries every change of the plain
grammar.

## What canon changed

- The C preprocessor. A directive at the start of a line is one hidden token,
  `CPP_DIRECTIVE`, with its backslash continuation lines; a script's `#!`
  line is hidden the same way. The hook reads `#if`, `#ifdef`, `#ifndef`,
  `#elif`, `#else`, and `#endif` with `Canon.Preprocessor` and hides every
  token of a branch the build does not read, from the parser and from the
  layout algorithm. See "The C preprocessor" below.
- Pragmas. A whole `{-# ... #-}` is one hidden token, as GHC ignores a pragma
  it does not know and none changes what canon reads. The hook still learns
  from `LANGUAGE` pragmas whether `QuasiQuotes`, `RecursiveDo`, or `Arrows` is
  on. The rules that read a pragma's parts stay in the grammar for its record.
- Operators by maximal munch, as the Haskell report lexes them. `VARSYM`,
  `CONSYM`, `QVARSYM` (`Map.!`, `C..`), and `QCONSYM` are one token each, and
  a reserved operator or a one-character operator with a token of its own
  wins its tie because its rule comes first. Upstream read an operator as a
  run of one-character tokens, which `=>`, `<-`, `..`, and `$$` broke apart,
  so `==>`, `>=>`, `..:`, and `<-.` did not parse. Dashes followed by a symbol
  character are an operator, not a comment (`-->`). `(#.)` and `(#)` are an
  operator in parentheses, not an unboxed tuple.
- Character classes. `SMALL`, `LARGE`, `DIGIT`, and `SYMBOL` are each one set
  by Unicode general category instead of alternations of hundreds of ranges,
  which the lexer tried one by one for every character of every name and
  which made lexing the larger part of parse time.
- Literals. Integer literals take `NumericUnderscores` underscores and binary
  digits, and literals take `MagicHash` suffixes (`1#`, `2##`, `"bytes"#`).
  `EXPONENT` is a fragment, so `e-1` in `show (e-1)` is a name, a minus, and a
  number. Inside a string an escape is read by its first character and the
  digits after it as ordinary characters, which bounds the token the same;
  reading `\x1885` as an escape of one to four digits made a string of n
  numeric escapes lex in time exponential in n.
- Block comments nest.
- Quotations. `[e|` opens an expression quotation as `[|` does. With
  `QuasiQuotes` on, `[quoter|...|]` is one `QUASIQUOTE` token whose body is
  never read as Haskell; without it, `[x|x<-xs]` stays a list comprehension.
- Modules, imports, and exports. A module body may be empty. An import may be
  `safe`, name its package in a string, and put `qualified` after the module
  name. An export or import item may be a `pattern`, a `type` operator, an
  operator in parentheses with members, and members may mix `..` with names.
- Declarations and expressions. A data or newtype instance declares its
  constructors; a type application may stand between arguments; a record
  wildcard may follow named fields; a pattern guard's expression may carry a
  type annotation; `unsafe`, `safe`, and `interruptible` are names outside a
  foreign declaration; an empty case may hold the semicolon the layout
  algorithm puts before its closing brace.
- Layout, in the hook, approximating the parse-error rule where GHC needs it:
  a closing record brace level with the statements of a `do` closes nothing;
  a guard's bar that starts a line level with the innermost block closes it;
  a `where` closes every `do` block it is inside; a `let` inside a guard does
  not end the guard at its own equals sign; unboxed-tuple and quotation
  brackets are brackets; `[d|` opens a layout block as GHC's does; an empty
  module body closes at the end of the file; `rec` and `mdo` open a block only
  where `RecursiveDo` or `Arrows` is on.
- Layout, in the hook, from canon 0.2.1 (`DEC-layout-bars-commas-and-of`):
  the hook tracks where each block's current alternative, binding, or
  statement stands at the block's own level, so a bar after a body with no
  guard ends a `case`'s or `let`'s block (a `case` inside a comprehension), a
  bar ends a `do` block (a guard after a `do`), a comma after a body outside
  brackets ends the block (a `let` in a guard before the next condition), and
  an equals sign or a non-lambda arrow after a body ends a `let`'s or `case`'s
  block (a guard's `let` ended by the guard's `=` or an alternative's `->`,
  across lines); `of` ends the blocks opened since its `case` (a `do` block as
  scrutinee); a line-leading infix operator ends a `do` block; `deriving`
  ends a GADT's constructors. Explicit braces, a layout keyword's or a
  record's, suspend the layout around them as the report says, and the brace
  closing them closes the blocks opened inside, so a `let { ... }` leaves its
  `in` nothing to close. A line-leading `do`, `mdo`, `rec`, or `\case`
  starts an item; a line-leading pragma sets the line's indentation.
- Leading semicolons in statement and declaration lists, a view pattern as a
  record field's pattern, and `\cases`.

The dialect adds, beyond the plain grammar: a Haddock comment in an export
list or on a record field is read where it stands as an orphan, since neither
is a unit; and the hook ends each held doc comment with an empty `DOC_END`
token, declared in the dialect lexer's `tokens` block, so a comment has one
end rather than one per word, which the parser tried at every word of every
comment and which made a heavily documented module ten times slower to parse
than its plain reading.

## The C preprocessor

GHC runs the C preprocessor before its lexer in a module with `CPP`, and the
base library, lens, and aeson branch on compiler and package versions
throughout. canon reads a module with directives the way it reads C# and F#
(`DEC-preprocessor-builds`): directive lines are hidden, and each `#if` reads
the first branch whose condition holds for some choice of the symbols it
names. A condition canon cannot evaluate, such as
`MIN_VERSION_base(4,8,0)` or `__GLASGOW_HASKELL__ >= 908`, is taken to hold,
so the branch written first is the one read, as the code for the current
compiler usually is. `defined(X)` is the symbol `X`, and a number is false
when zero, so `#if 0` hides its branch. `#define` and `#undef` of a symbol
are known from the line they are on. `canon parse` and the corpus read that
default build; `canon check` reads a module once per build of the few that
together read every branch some build compiles and merges what each finds.
Macros are not expanded and `#include` is not read, so code that uses a macro
as syntax, such as lens's `KVS(k1 k2)`, does not parse.

## Known limitations

- Macros are not expanded and included files are not read (above).
- `QuasiQuotes`, `RecursiveDo`, and `Arrows` are seen only in the file's own
  `LANGUAGE` pragmas, not in a cabal file's `default-extensions`.
- The parse-error rule of the layout algorithm is approximated for the
  tokens real code puts where a block cannot hold them (see
  `DEC-haskell-grammar-fixes` and `DEC-layout-bars-commas-and-of`); a token
  no rule names stays out of reach.
- `UnicodeSyntax` arrows and colons (`→`, `∷`, `⇒`, `∀`) lex as operators, not
  as the reserved symbols they stand for.
- The grammar is more permissive than GHC: it accepts `...` as an operator in
  lens's unfinished `experimental/` code, which GHC rejects.
- A doc comment the dialect does not read where it stands, such as one inside
  a deriving clause, is recovered as a stray comment with one more parse of
  the file for each (`DEC-stray-comments`).

## Corpus

`tools/corpus/haskell.sh [clone-dir]` clones the repositories below at the
pinned commits, shallow and blob-filtered (sparse where noted), into
`/tmp/corpus/haskell` by default, parses every `.hs` file with the plain
grammar under a per-file limit of `CORPUS_TIMEOUT` CPU seconds (default 10),
`CORPUS_JOBS` at a time (default 8), prints per repository the files parsed
out of the files, the failures, the exclusions with their reasons, and the
slowest files, then parses every file the plain grammar accepted with the
dialect, which must accept it too. Times are CPU seconds, which do not grow
with the load of the machine. The script exits non-zero if any file fails.
canon's own `src/` is the last repository. The figures are canon 0.2.1's.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Failing | Plain CPU | Dialect CPU |
|------------|--------|---------|------:|-------:|---------:|--------:|----------:|------------:|
| [ghc](https://github.com/ghc/ghc) | `575c4bc6cb70` | `libraries/base/` | 520 | 520 | 0 | 0 | 26.2 s | 30.6 s |
| [ghc](https://github.com/ghc/ghc) | `575c4bc6cb70` | `compiler/` | 862 | 861 | 1 | 0 | 86.6 s | 103.6 s |
| [haskell/containers](https://github.com/haskell/containers) | `953428ad079d` | whole | 79 | 79 | 0 | 0 | 9.1 s | 10.1 s |
| [haskell/text](https://github.com/haskell/text) | `ba2c00651f90` | whole | 106 | 106 | 0 | 0 | 7.9 s | 8.6 s |
| [haskell/bytestring](https://github.com/haskell/bytestring) | `05142995e2d6` | whole | 57 | 57 | 0 | 0 | 4.8 s | 5.5 s |
| [mrkkrp/megaparsec](https://github.com/mrkkrp/megaparsec) | `1ccb703fbc22` | whole | 44 | 44 | 0 | 0 | 3.6 s | 4.4 s |
| [haskell-servant/servant](https://github.com/haskell-servant/servant) | `c12cc3702a62` | whole | 233 | 233 | 0 | 0 | 14.3 s | 15.6 s |
| [haskell/haskell-language-server](https://github.com/haskell/haskell-language-server) | `f9e99b35ec4d` | `ghcide/` | 85 | 85 | 0 | 0 | 6.6 s | 7.3 s |
| [brain-fuel/lawspec](https://github.com/brain-fuel/lawspec) | `4b897c6ae2d7` | whole | 245 | 245 | 0 | 0 | 24.6 s | 26.3 s |
| [jgm/pandoc](https://github.com/jgm/pandoc) | `cbc9cca43735` | whole | 366 | 366 | 0 | 0 | 34.8 s | 37.8 s |
| [haskell/aeson](https://github.com/haskell/aeson) | `8e0be2d5aecb` | whole | 126 | 126 | 0 | 0 | 9.1 s | 9.9 s |
| [ekmett/lens](https://github.com/ekmett/lens) | `b931919c4164` | whole | 120 | 119 | 1 | 0 | 9.1 s | 10.9 s |
| [commercialhaskell/stack](https://github.com/commercialhaskell/stack) | `d5effcd3f32e` | whole | 691 | 690 | 1 | 0 | 40.3 s | 46.3 s |
| [xmonad/xmonad](https://github.com/xmonad/xmonad) | `284dd52c9c95` | whole | 30 | 30 | 0 | 0 | 2.2 s | 2.3 s |
| canon `src/` | this tree | `src/` | 70 | 70 | 0 | 0 | 5.8 s | 6.7 s |

LawSpec is pinned to the commit before it reshaped valid Haskell canon could
not read (its `DEC-haskell-grammar-workarounds`); ghc's compiler writes the same
forms, with explicit braces and leading semicolons, throughout.

The excluded files, each a file GHC itself does not compile as it stands:

- `ghc-compiler/compiler/GHC/Builtin/PrimOps.hs` takes `allThePrimOps` from
  `#include "primop-list.hs-incl"`, a file ghc's build generates; canon reads
  conditionals but includes no files.
- `lens/tests/properties.hs` uses `KVS(k1 k2)`, a function-like macro from
  `include/lens-common.h`; canon reads conditionals but expands no macros.
- `stack/tests/integration/tests/2781-shadow-bug/files/myPackageB/src/MyPackageB.hs`
  is the text `To be replaced.`, not Haskell; the integration test writes the
  module before it builds.

Before these changes the plain grammar parsed 1360 of the 1823 files of the
first five repositories, with 85 files over a ten-second limit. Of the 1919
files parsed now, 1826 parse in under half a CPU second, 70 in half a second to
one, 20 in one to two, and 3 in two to five; none takes longer. The slowest
are `lens/src/Control/Lens/Tuple.hs` (2.4 s),
`stack/tests/unit/Stack/Build/ConstructPlanSpec.hs` (2.2 s), and
`pandoc/src/Text/Pandoc/Writers/Powerpoint/Output.hs` (2.1 s); through the
dialect the slowest is `pandoc/src/Text/Pandoc/Writers/Powerpoint/Presentation.hs`
(3.9 s). A syntax error fails within a second: the 3067-line
`Powerpoint/Output.hs` with an error at line 101 fails in 0.4 CPU seconds
through either grammar. At canon 0.2.1, all but 16 of the 3,631 files parsed take
under half a CPU second and none more than two; the slowest are LawSpec's
`runtime/LawSpecRuntime.hs` (1.1 s) and ghc's
`compiler/GHC/CmmToAsm/X86/CodeGen.hs` (1.1 s, 1.2 s through the dialect).
