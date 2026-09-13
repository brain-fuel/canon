# Decision: roll our own ANTLR4 grammar interpreter rather than use antlr-haskell

Waiting for: a canonical place for decisions and their references (a decision
record format and the reference registry).

Date: 2026-09-12

## Decision

`canon` will consume ANTLR4 `.g4` grammars from
[grammars-v4](https://github.com/antlr/grammars-v4) where possible, and will
implement its own reader and interpreter for them in Haskell. The Hackage
package [antlr-haskell](https://hackage.haskell.org/package/antlr-haskell) is
not used.

## Why

antlr-haskell 0.1.0.2 was evaluated against this project's toolchain, Stackage
LTS 24.58 with GHC 9.10.3, on 2026-09-12.

- It does not build. Its `hashable` upper bound rejects the snapshot version,
  and with an older `hashable` pinned it fails to compile on an ambiguous
  `foldl'` import. The May 2026 release only modernised it to GHC 9.6. It is
  in no Stackage snapshot.
- It cannot read `.g4` files. Grammars are supplied through a Template Haskell
  quasiquoter embedded in Haskell source, which conflicts with keeping grammars
  under `grammars/<lang>/`.
- It does not handle full-size grammars. Its own test for the grammars-v4 C
  grammar is commented out in full, and the Swift grammar is excluded from CI
  as unusably slow.
- Open issues cover constructs the Haskell grammar uses: the `-> skip` lexer
  command, parenthesised grouping, and left recursion elimination for ALL(*).
  The GLR backend has known wrong-parse bugs on input with remaining tokens.

Independently of the parser library, the grammars-v4 Haskell grammar declares a
Java or C# superclass and calls into it from six lexer actions. That base
class, about 430 lines, implements the layout rule by injecting virtual braces
and semicolons. Any Haskell runtime must reimplement it.

## Consequences

Amended 2026-09-12 after the reader was built.

The parser combinator foundation is
[grammatical-parsers](https://hackage.haskell.org/package/grammatical-parsers)
0.7.2.1. It was chosen over two alternatives:

- Earley, which is in the Stackage snapshot but has had no release since 2019.
- A hand-written packrat combinator core with Warth-style left recursion
  support, which would give full control and a Parsec feel but has to be
  built and tested before anything else can be.

grammatical-parsers is actively maintained (June 2026), is tested on GHC
9.10, represents a grammar as a first-class Rank2 record, and offers a
left-recursive backend. It is not in LTS 24.58 and is pinned as an extra-dep.

The `.g4` reader is a single scannerless grammar record on the PEG packrat
backend. Because the grammar knows whether it is inside a parser rule or a
lexer rule, ANTLR's `LexerAdaptor`, whose only job is deciding whether `[`
opens an argument block or a character set, is not needed and is not ported.
Action, argument, character set, and string literal bodies are consumed by
pure scanners that mirror the upstream lexer rules, including taking the
shortest action body when triple-quoted and double-quoted strings could be
read either way.

Remaining stages:

1. Interpret a `Grammar` value into a grammatical-parsers record on the
   left-recursive backend, so that a grammars-v4 grammar becomes a running
   parser without code generation. Open question: ANTLR resolves
   left-recursive alternatives by precedence climbing with ordered
   alternatives, while grammatical-parsers' context-free backends return all
   parses. The interpretation must pick one meaning and record it.
2. Per-language base lexers in Haskell, reached through a hook interface that
   resolves `superClass` and lexer actions. The Haskell layout lexer is the
   first port.

## References

- https://hackage.haskell.org/package/grammatical-parsers
- Blažević and Milić, "Grampa: a packrat parser combinator library with left recursion and grammar composition", Haskell Symposium 2017
- Warth, Douglass, and Millstein, "Packrat Parsers Can Support Left Recursion", PEPM 2008
- https://hackage.haskell.org/package/antlr-haskell
- https://github.com/cronburg/antlr-haskell
- https://github.com/antlr/grammars-v4/blob/master/haskell/HaskellParser.g4
- https://github.com/antlr/grammars-v4/blob/master/haskell/HaskellLexer.g4
- https://github.com/antlr/grammars-v4/blob/master/haskell/Java/HaskellBaseLexer.java
- https://github.com/antlr/grammars-v4/discussions/3437
