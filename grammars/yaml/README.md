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
  indentation as its key, and complex keys after `?`.
- Plain scalars, which may hold spaces, colons not followed by a space, and
  hashes not preceded by one, and may continue on more indented lines.
- Double-quoted and single-quoted scalars, which may span lines.
- Literal (`|`) and folded (`>`) block scalars with their indicators.
- Flow sequences and flow mappings, nested to any depth and spanning lines.
- Anchors, aliases, tags, `%` directives, and the `---` and `...` markers.
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

- The comment directly above an entry is its Why. Comment lines with nothing
  between them are one comment. A comment above a section key, or above an
  entry that is not a unit, binds to nothing and is not reported.
- The `description` of a config key is a Why too, because Pulumi shows it as
  that key's documentation. A comment above wins over it. Pulumi defines no
  description on a resource, a variable, or an output.
- A resource is named by its logical name, as Pulumi addresses it in `${...}`.
  Its type, properties, and options are its How.
- Outputs need a Why because they are a stack's interface. A config key that
  declares a type or a default declares that interface too. A key that only
  sets a value, as the keys of a stack file do, may have one.
- Any other YAML file parses as plain YAML and has no units.

The grammar parses all 693 `Pulumi.yaml`, `Pulumi.<stack>.yaml`, and
`Main.yaml` files of the pulumi-yaml repository and the Pulumi examples, among
them the adversarial test programs of the Pulumi YAML language host. Through
the plain grammar it parses 392 of the 393 other YAML files of those
repositories and of the Terraform modules canon's HCL grammar was tested on,
such as GitHub workflows and pre-commit configurations; the one it does not is
a Helm template, which is not YAML until it is rendered.

## Known limitations

- A quoted key keeps its quotes in the unit's name.
- In a flow collection, a plain scalar cannot hold `,`, `[`, `]`, `{`, or `}`,
  as the specification says, so `[${a}]` does not parse; Pulumi programs quote
  such values.
- A colon directly after a quoted key in a flow mapping, as in `{"a":1}`, is
  read as the start of a plain scalar.
- Tabs count as one column of indentation. YAML forbids tabs there.
- A plain scalar used as a key cannot span lines.
