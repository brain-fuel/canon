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

Interpretation, done 2026-09-14. A grammar value is interpreted directly by
`Canon.Antlr4.Lex` and `Canon.Antlr4.Parse` rather than translated into a
grammatical-parsers record. grammatical-parsers builds a grammar as a Rank2
record whose fields are fixed at compile time, and an interpreted grammar has
a rule set known only at run time, so its record machinery cannot be
instantiated for it. It remains the foundation of the hand-written `.g4`
reader.

The interpreter's meaning of a grammar:

- The lexer takes the longest match across the rules of the current mode,
  breaking ties by rule order and then alternative order, as ANTLR does. A
  non-greedy loop exits at the first iteration count that lets the rest of
  the rule match, which reproduces ANTLR's non-greedy behaviour. Literals in
  parser rules of a combined grammar get implicit token rules ahead of the
  explicit ones.
- The parser is a memoised all-parses parser over the token stream. Results
  are ordered by alternative order, greedy loops longest first, and the first
  complete parse wins. Left recursion, direct or indirect, is handled by
  iterating each cyclic group of rules at a position to a fixpoint.
  Precedence climbing, ANTLR's rewrite of left-recursive alternatives into
  precedence levels, is not implemented, so for an ambiguous left-recursive
  rule the tree returned is the first by alternative order, not the one
  ANTLR's precedence would give. This is recorded as an open decision.
- Semantic predicates are assumed true and embedded actions in parser rules
  do nothing. Lexer actions are resolved through a hook interface keyed by
  the grammar's `superClass` option; the ANTLR meta-grammar's adaptor is the
  first implementation and the Haskell layout lexer is the next.

The parse memo tables must be lazy maps. A strict map forces every entry
while the table is being built, and entries refer back to the table, so a
strict map never finishes.

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
