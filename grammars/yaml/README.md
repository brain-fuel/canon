# YAML Grammar

`YAMLLexer.g4` and `YAMLParser.g4` are a grammar for the block structure of
YAML 1.2, written for canon under canon's MIT license (Copyright (c) 2026
brain-fuel) from the [YAML 1.2.2 specification](https://yaml.org/spec/1.2.2/).
[antlr/grammars-v4](https://github.com/antlr/grammars-v4) has no YAML grammar
(checked at commit `7df52be94698550d219d299d04105c6bafadd9c3`), so no line is
marked as changed. `canonically_commented/` holds the dialect canon reads
Pulumi YAML programs with. The decision is recorded as
`DEC-pulumi-yaml-grammar` in canon's `canonical_decisions.yaml`.

## What it reads

- Block mappings and block sequences, including a sequence at the same
  indentation as its key, and complex keys after `?`, which may be any node, a
  block sequence or a block scalar too, in block and in flow collections.
- Plain scalars, which may hold spaces, colons not followed by a space, and
  hashes not preceded by one, and may continue on lines indented past the
  scalar's parent, whatever those lines hold: a shell command's
  `if [[ -e f ]]; then`, a quote, or a GitHub expression's closing `}}`. In a
  flow collection a plain scalar may continue on the next line too.
- Double-quoted and single-quoted scalars, which may span lines. The hook
  splits each into its quotes and its text, so a quoted key is named without
  its quotes.
- Literal (`|`) and folded (`>`) block scalars with their indicators.
- Flow sequences and flow mappings, nested to any depth and spanning lines,
  with JSON-like pairs such as `{"a":1}`, whose colon directly follows a quoted
  key: the hook splits a plain scalar that starts with that colon into the
  colon and the value.
- A Pulumi interpolation such as `${site-bucket}` inside a flow plain scalar,
  as in `[${a}, ${b}]`. Strict YAML 1.2 forbids braces in a flow plain scalar;
  canon reads them as part of the scalar, as Pulumi programs mean them.
- Anchors, aliases, tags, verbatim tags such as `!<tag:yaml.org,2002:str>`,
  and `%` directives. A node's tag or anchor may stand on its own line above
  the block collection it belongs to, as in `- &base` or `--- !tag`.
- Streams of documents: the `---` and `...` markers, a bare document after an
  end marker, and a document indented as a whole after its start marker, as
  Ansible playbooks often are. Three dashes or dots are a marker only at the
  start of a line and followed by a space or the line's end; elsewhere, as in
  `value: ...`, they are a plain scalar.
- Comments, which go to the hidden channel.

YAML nests by indentation, which no context-free grammar sees. The
`YAMLLexerBase` superClass selects the `Canon.Antlr4.Lex.YAML` hook in canon,
which works as canon's F# hook does:

- Outside flow collections, the first token of a line is preceded by `INDENT`
  when it is right of the current block, `NEWLINE` when it is level with it,
  and a `DEDENT` for each block it is left of. Layout tokens are empty and sit
  where the last code token ends, so they widen no span.
- The content after a sequence entry's dash is indented to its own column, so
  `- name: x` followed by `  value: y` is one mapping inside the entry.
- A block scalar ends at the first line that is not indented past the key, or
  the dash, on its header's line. Its lines are text tokens that take no part
  in layout.
- A complex key's question mark, and the colon that starts its value's line,
  indent what follows them to its own column, as a dash does.
- A lexer predicate decides whether a line continues the plain scalar before
  it: the scalar must be in block context and the line indented past the
  scalar's parent, the key on the scalar's line or else the block around it.
  Such a line is one `PLAIN_CONTINUATION` token, without its line break and
  indentation, which takes no part in layout, so continuation lines may be
  indented unevenly.
- Line breaks and spaces tell the hook whether a token starts its line, so a
  plain scalar never starts with a document marker there, and a marker that
  does not start its line is read as a plain scalar.

## The dialect

In `canonically_commented/` comments are tokenized in a `DocLine` mode. The
hook holds each comment back until the next code token has its layout tokens,
then emits it just before that token, so a comment sits inside the entry it
documents. A comment after code on its line, inside a flow collection, or
parted from the next line of code by a blank line, is hidden.

The top-level mapping of a Pulumi program is read by its sections. Each entry
of these sections is a unit named by its key:

| Section | Kind | Requires a Why |
|---------|------|----------------|
| `resources` | `resource` | no |
| `variables` | `variable` | no |
| `outputs` | `output` | yes |
| `config` | `config` | when it declares a `type` or a `default` |
| `template` / `config` | `templateConfig` | when it declares a `type` or a `default` |

- The comment directly above an entry is its Why. Comment lines with nothing
  between them are one comment. A comment above a section key, or above an
  entry that is not a unit, binds to nothing and is not reported.
- The entries of the `template` section's `config`, which `pulumi new` asks
  for when it makes a project from the program, are units of kind
  `templateConfig`, read as config keys are.
- The `description` of a config key is a Why too, because Pulumi shows it as
  that key's documentation. A comment above wins over it. Pulumi defines no
  description on a resource, a variable, or an output.
- A resource is named by its logical name, as Pulumi addresses it in `${...}`.
  Its type, properties, and options are its How.
- Outputs need a Why because they are a stack's interface. A config key that
  declares a type or a default declares that interface too. A key that only
  sets a value, as the keys of a stack file do, may have one.
- Any other YAML file parses as plain YAML and has no units.

## Plain YAML

Most YAML files are not Pulumi programs: Kubernetes manifests, GitHub
workflows and issue forms, CloudFormation templates, Ansible playbooks, Helm
values, and settings files. Such a file may well have a top-level `config`,
`resources`, or `outputs` key, which the Pulumi dialect would read as units, so
canon reads YAML that is not a Pulumi program through the plain grammar, under
a profile with no units and no comment syntax:

```yaml
languages:
  pulumi:
    files: [Pulumi.yaml, Pulumi.yml, "Pulumi.*.yaml", "Pulumi.*.yml", Main.yaml, Main.yml]
    lexer: grammars/yaml/canonically_commented/YAMLLexer.g4
    parser: grammars/yaml/canonically_commented/YAMLParser.g4
    start: yamlFile
  yaml:
    extensions: [.yaml, .yml]
    lexer: grammars/yaml/YAMLLexer.g4
    parser: grammars/yaml/YAMLParser.g4
    start: yamlFile
    units: []
```

The Pulumi profile's file names win over the `yaml` profile's extensions, so
the Pulumi programs and stack files keep their units. Every other YAML file is
parsed whole, so a file that is not YAML is reported, and gives only its file
unit: YAML has no doc comment syntax, and a comment in a manifest or a workflow
documents nothing canon can name. With no comment syntax, no comment is read as
a doc comment, so none is reported as an orphan.

The grammar parses all 693 `Pulumi.yaml`, `Pulumi.<stack>.yaml`, and
`Main.yaml` files of the pulumi-yaml repository and the Pulumi examples, among
them the adversarial test programs of the Pulumi YAML language host, and every
YAML file of the corpus below but two templates.

## Known limitations

- canon accepts tab indentation, which YAML forbids, counting a tab as one
  column; it does not reject such a file. Pulumi refuses such a program
  before canon would read it, and refusing it too would change no unit of a
  program Pulumi runs.
- canon reads `${...}` inside a flow plain scalar as part of the scalar,
  which strict YAML 1.2 does not, by design: Pulumi programs mean it so.
- A comment line inside a multi-line plain scalar ends the scalar in YAML, and
  a more indented line after it is an error. The plain grammar reads that line
  as a continuation instead; YAML parsers reject such a file before canon
  would read it.
- Three dashes followed by a space are a document marker at the start of a
  line, as YAML says, and a plain scalar elsewhere, so `a: --- x` is the
  scalar `--- x`.

No YAML 1.2 construct is known to be unsupported: anchors, aliases, merge
keys, tags, verbatim tags, flow collections spanning lines, multi-document
streams, and complex keys all parse, in the corpus below and in the tests.

A comment in any other place than above an entry parses: among a resource's
properties, in a sequence or a flow collection, after a block scalar, or at
the end of a section or of the file. It binds to nothing and is not reported,
since YAML has no doc comment syntax and every banner would be a finding.

## Corpus

`tools/corpus/yaml.sh` checks the grammar against the Pulumi examples, the
Kubernetes examples and documentation, the GitHub workflows, issue forms, and
other `.github` YAML of popular repositories, CloudFormation templates, Ansible
playbooks, and Bitnami's Helm values. It shallow-clones each repository below
at the pinned commit into `/tmp/corpus/yaml`, or the directory given as its
first argument, parses every `.yaml` and `.yml` file with the plain grammar
under a timeout of 10 seconds per file, and then parses every file the plain
grammar parsed with the Pulumi dialect, which must parse them all. Large
repositories are sampled by subdirectory with a sparse checkout; a pattern
such as `*.yaml` takes only the YAML files of a repository.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Seconds |
|------------|--------|---------|------:|-------:|---------:|--------:|
| [pulumi/examples](https://github.com/pulumi/examples) | `925d7de14c87` | `*.yaml`, `*.yml` | 409 | 408 | 1 | 43.3 |
| [pulumi/pulumi-yaml](https://github.com/pulumi/pulumi-yaml) | `e0aeb48e47a5` | `*.yaml`, `*.yml` | 1019 | 1018 | 1 | 86.9 |
| [kubernetes/examples](https://github.com/kubernetes/examples) | `d6b8cd27eacb` | `*.yaml`, `*.yml` | 250 | 250 | 0 | 16.3 |
| [kubernetes/website](https://github.com/kubernetes/website) | `abc9ea495989` | `/content/en/examples/` | 404 | 404 | 0 | 27.4 |
| [kubernetes/kubernetes](https://github.com/kubernetes/kubernetes) | `8ae47e9fc94c` | `/.github/` | 5 | 5 | 0 | 0.3 |
| [microsoft/vscode](https://github.com/microsoft/vscode) | `729f257fa411` | `/.github/` | 26 | 26 | 0 | 2.1 |
| [facebook/react](https://github.com/facebook/react) | `278794d7dee9` | `/.github/` | 30 | 30 | 0 | 2.5 |
| [rust-lang/rust](https://github.com/rust-lang/rust) | `602727f26878` | `/.github/` | 8 | 8 | 0 | 0.5 |
| [python/cpython](https://github.com/python/cpython) | `3f9118f1d17a` | `/.github/` | 31 | 31 | 0 | 2.5 |
| [nodejs/node](https://github.com/nodejs/node) | `019e869ad3a3` | `/.github/` | 56 | 56 | 0 | 4.2 |
| [tensorflow/tensorflow](https://github.com/tensorflow/tensorflow) | `1d968a6e8868` | `/.github/` | 21 | 21 | 0 | 1.6 |
| [pytorch/pytorch](https://github.com/pytorch/pytorch) | `8646abda0492` | `/.github/` | 201 | 201 | 0 | 20.0 |
| [vercel/next.js](https://github.com/vercel/next.js) | `6194d642b6fd` | `/.github/` | 44 | 44 | 0 | 5.2 |
| [pulumi/pulumi](https://github.com/pulumi/pulumi) | `059b146050a7` | `/.github/` | 34 | 34 | 0 | 2.9 |
| [home-assistant/core](https://github.com/home-assistant/core) | `43a27100abbe` | `/.github/` | 22 | 22 | 0 | 3.2 |
| [ansible/ansible](https://github.com/ansible/ansible) | `be0fd3b10c00` | `/.github/` | 5 | 5 | 0 | 0.3 |
| [angular/angular](https://github.com/angular/angular) | `7d96a37af4f7` | `/.github/` | 19 | 19 | 0 | 1.5 |
| [django/django](https://github.com/django/django) | `fd91518f17c8` | `/.github/` | 22 | 22 | 0 | 2.0 |
| [denoland/deno](https://github.com/denoland/deno) | `3d44d1d82fda` | `/.github/` | 13 | 13 | 0 | 2.5 |
| [microsoft/TypeScript](https://github.com/microsoft/TypeScript) | `ca197b7b8586` | `/.github/` | 23 | 23 | 0 | 1.8 |
| [grafana/grafana](https://github.com/grafana/grafana) | `0833fa888096` | `/.github/` | 119 | 119 | 0 | 10.1 |
| [electron/electron](https://github.com/electron/electron) | `e91b6a0ab5b6` | `/.github/` | 75 | 75 | 0 | 6.3 |
| [flutter/flutter](https://github.com/flutter/flutter) | `0f35e8df0fb7` | `/.github/` | 37 | 37 | 0 | 2.9 |
| [golang/vscode-go](https://github.com/golang/vscode-go) | `756676b85c18` | `/.github/` | 5 | 5 | 0 | 0.3 |
| [hashicorp/terraform-provider-azurerm](https://github.com/hashicorp/terraform-provider-azurerm) | `8f1dfbe2371f` | `/.github/` | 57 | 57 | 0 | 4.5 |
| [docker/compose](https://github.com/docker/compose) | `42f48072bbf9` | `/.github/` | 15 | 15 | 0 | 1.1 |
| [prometheus/prometheus](https://github.com/prometheus/prometheus) | `770ca8fb8f8e` | `/.github/` | 18 | 18 | 0 | 1.2 |
| [aws-cloudformation/aws-cloudformation-templates](https://github.com/aws-cloudformation/aws-cloudformation-templates) | `a0f43bc6d208` | `*.yaml`, `*.yml` | 162 | 162 | 0 | 13.6 |
| [ansible/ansible-examples](https://github.com/ansible/ansible-examples) | `b50586543c6c` | `*.yaml`, `*.yml` | 151 | 151 | 0 | 11.3 |
| [bitnami/charts](https://github.com/bitnami/charts) | `bb5e98a6e3c5` | `/bitnami/*/values.yaml`, `/bitnami/*/Chart.yaml`, `/.github/` | 251 | 251 | 0 | 27.6 |
| Total | | | 3532 | 3530 | 2 | 305.9 |

Of the 3,532 files, 15.4 MB, 1,043 are Pulumi programs and stack files. Every
file parses with the plain grammar and with the dialect but two, which are
excluded as templates, files that are YAML only once a template engine renders
them:

| File | Reason |
|------|--------|
| `pulumi-examples/aws-ts-eks-distro/eksdistro/cluster.yaml` | a Mustache template, `{{{CLUSTER_NAME}}}`, that the example's `index.ts` renders before kops reads it |
| `pulumi-yaml/pkg/pulumiyaml/packages/testdata/good/ignored.yaml` | a Helm chart template, `{{- if ... -}}`, kept among the test data of the Pulumi YAML package loader |

The seconds are the sum of each file's wall time, the `canon` process
included, with 8 files parsed at once. A file takes 0.08 seconds at the median,
0.12 at the 90th percentile, 0.26 at the 99th, and 1.6 at most, Deno's
generated `ci.generated.yml`; the two templates fail within 0.13 seconds.

The corpus found these gaps, now fixed: continuation lines of plain scalars
that hold brackets, quotes, or braces in Kubernetes examples and in the
workflows of next.js, Home Assistant, Electron, and Flutter; `...` as a value
in a Flutter issue form; a document after an end marker in the Kubernetes
documentation; Ansible playbooks indented as a whole after `---`; and, in the
dialect only, a comment above a scalar value in CPython's workflow. Tests and
probes beyond the corpus found the others: complex keys that are block nodes,
complex keys in flow collections, verbatim tags, properties on their own line,
`--- !tag`, and plain scalars spanning lines in flow collections.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/yaml.sh                      # clones into /tmp/corpus/yaml
CORPUS_SKIP_FETCH=1 tools/corpus/yaml.sh  # reuses the clones
```

`CORPUS_TIMEOUT` sets the seconds per file and `CORPUS_JOBS` the files parsed
at once. The script exits nonzero when a file that is not a listed exclusion
fails, or when the dialect fails a file the plain grammar parses.
