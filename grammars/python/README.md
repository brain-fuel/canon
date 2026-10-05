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
  none a bytes, an f-string, or a t-string. canon joins the contents of adjacent strings. The docstring of
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
- `isPublicTopLevel` reads the tokens before a definition backwards only to
  the block that encloses it, and decides a definition at the first column at
  once, so a long module takes time linear in its length rather than in its
  square.

## Corpus

`tools/corpus/python.sh` checks the grammar against the Python standard
library and the most used Python projects. It shallow-clones each repository
below at the pinned commit into `/tmp/corpus/python`, or the directory given as
its first argument, parses every `.py` file with the plain grammar under a
timeout of 60 seconds per file, and then parses every file the plain grammar
parsed with the dialect, which must parse them all. CPython is sampled to
`Lib/`, its standard library and tests, and numpy to `numpy/`, its Python
package, with a sparse checkout; the other repositories are read whole.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Dialect | Seconds | Dialect seconds |
|------------|--------|---------|------:|-------:|---------:|--------:|--------:|----------------:|
| [python/cpython](https://github.com/python/cpython) | `dc0add3a65fc` | `/Lib/` | 2073 | 2069 | 4 | 2069 | 285.5 | 296.4 |
| [django/django](https://github.com/django/django) | `fd91518f17c8` | all | 2933 | 2932 | 1 | 2932 | 180.3 | 186.5 |
| [psf/requests](https://github.com/psf/requests) | `611c6162cbc4` | all | 37 | 37 | 0 | 37 | 3.2 | 3.2 |
| [pallets/flask](https://github.com/pallets/flask) | `d73fa1cdcbd8` | all | 83 | 83 | 0 | 83 | 4.7 | 4.9 |
| [numpy/numpy](https://github.com/numpy/numpy) | `a9d5324eb734` | `/numpy/` | 429 | 429 | 0 | 429 | 74.5 | 77.9 |
| [pandas-dev/pandas](https://github.com/pandas-dev/pandas) | `67b43b389914` | all | 1544 | 1544 | 0 | 1544 | 227.7 | 227.5 |
| sample `lang_samples/python-itsdangerous/source` | — | all | 15 | 15 | 0 | 15 | 0.7 | 0.7 |
| Total | | | 7114 | 7109 | 5 | 7109 | 776.6 | 797.1 |

Of the 7,114 files, 95 MB, 7,109 parse with the plain grammar and with the
dialect, and 5 are excluded, each a file CPython or Django rejects or one
canon cannot read:

| Excluded | Reason |
|----------|--------|
| `Lib/test/tokenizedata/badsyntax_3131.py`, `badsyntax_pep3120.py` | invalid-code fixtures: CPython's `test_unicode_identifiers` and `test_utf8source` expect a `SyntaxError` |
| `tests/test_runner_apps/tagged/tests_syntax_error.py` | invalid-code fixture: Django's test runner tests expect its `SyntaxError` |
| `Lib/test/encoded_modules/module_iso_8859_1.py`, `module_koi8_r.py` | not UTF-8: a PEP 263 coding declaration names latin-1 or koi8-r, and canon reads every source as UTF-8 |

The seconds are the sum of each file's process time, user and system, of the
`canon parse` process, with 8 files parsed at once; wall time depended on the
load of the machine, which other work shared. A file takes 0.04 seconds at the
median, 0.25 at the 90th percentile, 1.0 at the 99th, and 5.0 at most,
`numpy/_core/tests/test_multiarray.py`, 12,000 lines; the dialect takes 3%
longer in all. 6,831 files take under half a second, 198 under one, 68 under
two, 11 under five, and one longer. Every excluded file fails within 0.02
seconds.

The corpus found these gaps, now fixed in the plain grammar and the dialect,
each marked `canon:`:

- Syntax added from Python 3.8 to 3.15: named expressions (`:=`) in
  conditions, displays, arguments, subscripts, and match subjects;
  positional-only parameters of a lambda; any expression as a decorator;
  parenthesized context managers; starred items in a return, a yield, a
  `for`, an annotated or augmented assignment, and a subscript; `*args: *Ts`;
  a match on a tuple, with `case` a soft keyword elsewhere, and a unary plus
  on a number in a pattern; `except*`, and `except A, B:` without
  parentheses; type parameters on `def` and `class`, with bounds, defaults,
  `*Ts`, and `**P`, and the `type` alias statement, `type` a soft keyword;
  `lazy import` and `lazy from`, `lazy` a soft keyword; digits grouped by
  underscores; t-strings; and f-strings whose replacement fields hold any
  expression, strings in the same quotes, nested fields, and comments, as
  Python 3.12 allows. An f-string and a t-string stay one `STRING` token.
- A UTF-8 byte order mark at the start of a file is skipped.
- A backslash in a string escaped a `NEWLINE` token as well as a character,
  so at the start of a file the spaces after it matched two ways and a module
  docstring that draws a diagram in backslashes, as `http/cookiejar.py`'s
  does, took longer with each backslash. It escapes one character, or a CRLF.
- An f-string field read three quotes either as a long string or as an empty
  string and a short one, and a field that did not close went on through
  every later string of the file in each reading; three quotes now always
  open a long string, as Python's tokenizer reads them, so a field has one
  reading.
- The items of a display, a call, and a subscript were the rules
  `testlist_comp`, `dictorsetmaker`, `arglist`, and `subscriptlist`, which
  could end after any item, so canon's parser built a tree for each and a list
  of n items took time in n squared: a table of 8,000 numbers took 14
  seconds. They are read in the rule that holds their brackets, `atom`,
  `trailer`, and `classdef`, and take time linear in their length.
- In the dialect, `isPublicTopLevel` read every token before each
  definition, so a module took time in the square of its length; it reads
  back only to the block around the definition.

Known limits: a source in a PEP 263 encoding other than UTF-8 is not read,
since canon reads every source as UTF-8; Python 2 syntax, such as the `print`
statement, is rejected, as Python 3 rejects it; the grammar accepts some
programs that CPython rejects, such as a `lazy import` inside a `try`; and an
f-string format spec whose fill character is a quote, as in `f"{x:'>10}"`,
does not lex, since a quote in a field opens a string.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/python.sh                   # clones into /tmp/corpus/python
CORPUS_ONLY=django tools/corpus/python.sh  # one repository
```
