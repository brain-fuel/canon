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

Planned stages for the interpreter:

1. A `.g4` reader, built from ANTLR's own meta-grammar
   (`ANTLRv4Lexer.g4` and `ANTLRv4Parser.g4` in grammars-v4). This is the
   first grammar `canon` needs and belongs under `grammars/antlr4/`.
2. An interpreter over the loaded grammar: build the augmented transition
   network and simulate it with ALL(*), so that ordered alternatives and left
   recursion mean what ANTLR intends.
3. Per-language base lexers in Haskell, reached through a hook interface that
   resolves `superClass` and lexer actions. The Haskell layout lexer is the
   first port.

The alternative considered was generating a Java parser with the official
ANTLR tool and having it dump parse trees for `canon` to read. It was rejected
because it makes a Haskell tool depend on a JVM.

## References

- https://hackage.haskell.org/package/antlr-haskell
- https://github.com/cronburg/antlr-haskell
- https://github.com/antlr/grammars-v4/blob/master/haskell/HaskellParser.g4
- https://github.com/antlr/grammars-v4/blob/master/haskell/HaskellLexer.g4
- https://github.com/antlr/grammars-v4/blob/master/haskell/Java/HaskellBaseLexer.java
- https://github.com/antlr/grammars-v4/discussions/3437
