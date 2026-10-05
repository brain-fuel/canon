# Python 3 Grammar

An ANTLR4 grammar for Python 3 based on version 3.6 of 
[The Python Language Reference](https://docs.python.org/3/reference/grammar.html).

This grammar has been tested against the Python 3's 
[standard library](https://web.archive.org/web/20221228164112/https://hg.python.org/cpython/file/3.6/Lib/), 
the contents of the asyncio folder there is included in the examples section.

Note that there are two grammars here, one for Java and other for Python3
target. Target of grammars are mentioned at the top of the grammar.
This grammar contains embedded code that handles
the insertion of `INDENT` and `DEDENT` tokens. The embedded code,
located inside the `NEWLINE` lexer rule as well as the `@lexer::members`
section is well documented, so people trying to port this grammar to
another target should not have much difficulty.

## Reference
* [pldb](http://pldb.info/concepts/python)

## Canonically commented dialect

`canonically_commented/Python3Lexer.g4` and `Python3Parser.g4` are the
grammar above with docstrings as canonical comments, recorded as
`DEC-python-dialect` in canon's `canonical_decisions.yaml`. Each change is
marked `// canon:`:

- The lexer is the plain one. A docstring stays a `STRING` token, since only
  its place in the parse makes it a docstring; canon reads its prose,
  `ref:KEY`, and `license:KEY` from the string's contents.
- `docString` is a string, or adjacent strings that Python joins into one, that
  the `Python3ParserBase` predicate `isDocString` admits: a statement alone,
  none a bytes or an f-string. canon joins the contents of adjacent strings. The docstring of
  a module is a `why` element of `file_input` and the file's Why.
- `funcdef` and `classdef` take in `decorated` and `async_funcdef` and are the
  unit alternatives `# function` and `# class`, whose Why is the docstring
  that opens their body and whose decorators are `marker`s. An `async def` is
  a `funcdef`.
- A definition's name is labeled `required` when the predicate
  `isPublicTopLevel` holds, a name without a leading underscore that is nested
  in no `def` or `class` body, counted from the `INDENT` and `DEDENT` tokens
  before it, so a definition inside a module-level `if`, `try`, or `with` is
  public too; and `optional` when `isPrivateName`
  holds, a leading underscore other than `__init__`. A class body is labeled
  `inherited`, so the public methods of a public class need a docstring. A
  stub marked `@overload` is labeled `optional`.
- A string anywhere else and a `#` comment are no documentation, so the
  dialect has no orphans.
- A module's docstring is the file's Why but is never required, since canon
  requires no comment on a file unit.
