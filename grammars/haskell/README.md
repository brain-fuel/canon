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
  `DEC-haskell-grammar-fixes`); a let in a guard of a case alternative, closed
  by the alternative's arrow, and other tokens stay out of reach.
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
canon's own `src/` is the last repository.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Failing | Plain CPU | Dialect CPU |
|------------|--------|---------|------:|-------:|---------:|--------:|----------:|------------:|
| [ghc](https://github.com/ghc/ghc) | `575c4bc6cb70` | `libraries/base/` | 520 | 520 | 0 | 0 | 57.5 s | 65.5 s |
| [jgm/pandoc](https://github.com/jgm/pandoc) | `cbc9cca43735` | whole | 366 | 366 | 0 | 0 | 106.4 s | 129.1 s |
| [haskell/aeson](https://github.com/haskell/aeson) | `8e0be2d5aecb` | whole | 126 | 126 | 0 | 0 | 23.2 s | 27.2 s |
| [ekmett/lens](https://github.com/ekmett/lens) | `b931919c4164` | whole | 120 | 119 | 1 | 0 | 24.9 s | 31.8 s |
| [commercialhaskell/stack](https://github.com/commercialhaskell/stack) | `d5effcd3f32e` | whole | 691 | 690 | 1 | 0 | 92.2 s | 100.6 s |
| [xmonad/xmonad](https://github.com/xmonad/xmonad) | `284dd52c9c95` | whole | 30 | 30 | 0 | 0 | 5.3 s | 5.7 s |
| canon `src/` | this tree | `src/` | 68 | 68 | 0 | 0 | 16.4 s | 17.4 s |

The excluded files, each a file GHC itself does not compile as it stands:

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
through either grammar.
