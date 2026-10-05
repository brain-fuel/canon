# HCL Grammar

`HCLLexer.g4` and `HCLParser.g4` are a grammar for HCL, the HashiCorp
configuration language that Terraform, Packer, Nomad, and Terragrunt files are
written in. They are written for canon, under canon's MIT license (Copyright
(c) 2026 brain-fuel), from the
[HCL native syntax specification](https://github.com/hashicorp/hcl/blob/main/hclsyntax/spec.md).
`canonically_commented/` holds the dialect canon extracts Terraform units
with. The decision is recorded as `DEC-hcl-grammar` in canon's
`canonical_decisions.yaml`.

## Why not the grammars-v4 grammar

[antlr/grammars-v4](https://github.com/antlr/grammars-v4/tree/7df52be94698550d219d299d04105c6bafadd9c3/terraform)
has a Terraform grammar, `terraform.g4`. In canon's interpreter it parsed 344
of the 554 `.tf` files of the corpus below, and none of its `.tfvars` or
`.hcl` files, since it requires at least one block. It reads heredocs only
with the delimiters `EOF` and `DESCRIPTION`, cannot read a quote inside an
interpolation, spells `null` as `nul`, and ignores line breaks, which HCL uses
to end an attribute. It was evaluated and not vendored, so no line here is
marked as changed from it.

## What it reads

- A file is a body of attributes and blocks. A block is a type, labels that
  are quoted strings or identifiers, and a body in braces.
- Expressions follow the specification: unary `-` and `!`, then `*`, `/`, `%`,
  then `+`, `-`, then comparisons, equality, `&&`, `||`, and the conditional.
  Terms are numbers, `true`, `false`, `null`, tuples, objects, quoted and
  heredoc templates, function calls (with provider namespaces such as
  `provider::aws::arn_parse`), variables, for expressions, indexes, attribute
  access, legacy `.0` indexes, and both splats.
- Templates have their own lexer modes: text, `${ }` interpolations, `%{ }`
  directives, strip markers, and `$${` escapes. Braces push the default mode,
  so a quote inside an interpolation does not end the string.
- An `%{ if }` directive must be closed by `%{ endif }`, with an optional
  `%{ else }`, and `%{ for }` by `%{ endfor }`. A template whose directives do
  not pair does not parse, as Terraform rejects it.
- Comments are `#` and `//` to the end of the line, and `/* */`.
- Terraform's JSON syntax (`.tf.json` and `.tfvars.json`): a file whose first
  token is `{` is one JSON object. Its strings are templates, as Terraform
  reads them.

The `HCLLexerBase` superClass selects the `Canon.Antlr4.Lex.HCL` hook in canon:

- It hides line breaks inside parentheses, brackets, interpolations, and
  object for expressions, and directly after an opening brace, where HCL
  ignores them, and every line break of a JSON file. Everywhere else a line
  break is a `NEWLINE` token.
- It records each heredoc's delimiter word and closes the heredoc at the line
  that holds only that word, indented or not.

It parses all 592 `.tf`, `.tfvars`, and `.hcl` files, 2.0 MB, of
terraform-aws-vpc, terraform-aws-eks, terraform-aws-s3-bucket,
terraform-aws-lambda, terraform-null-label, Azure's verified storage account
module, terragrunt-infrastructure-live-example, and learn-terraform-test,
including their `.tftest.hcl` files.

## The dialect

HCL has no separate doc comment syntax, so in `canonically_commented/` every
comment is tokenized in a `DocLine` or `DocBlock` mode, and the hook decides
which comments can be a Why:

- A comment after code on its line, or inside brackets, is hidden.
- The line break between a comment line and the line directly below it is
  hidden. So consecutive comment lines are one comment, and a comment binds
  only to the block directly below it.
- A comment that a blank line parts from what follows, or that sits above an
  attribute, is a note: the parser accepts it and canon does not report it.
  Section banners are notes.

Each top-level block is a unit, named as Terraform addresses it:

| Block | Kind | Name |
|-------|------|------|
| `resource "aws_vpc" "main"` | `resource` | `aws_vpc.main` |
| `data "aws_ami" "ubuntu"` | `data` | `aws_ami.ubuntu` |
| `module "network"` | `module` | `network` |
| `variable "region"` | `variable` | `region` |
| `output "vpc_id"` | `output` | `vpc_id` |
| `provider "aws"` | `provider` | `aws` |
| `provider "aws"` with `alias = "west"` | `provider` | `aws.west` |
| `moved` with `from = aws_instance.old` | `moved` | `aws_instance.old` |
| `removed` with `from = aws_instance.gone` | `removed` | `aws_instance.gone` |
| `import` with `to = aws_instance.new` | `importBlock` | `aws_instance.new` |
| `terraform` | `terraform` | `terraform` |
| `run "plan_succeeds"` | `run` | `plan_succeeds` |
| an entry `prefix = ...` of `locals` | `local` | `prefix` |
| any other block, such as `check "health"` | `block` | `check.health` |
| such a block with an `alias`, as `mock_provider "aws"` in a test | `block` | `mock_provider.aws.fake` |
| a top-level attribute, as in `.tfvars` | `attribute` | its name |

- The labels of a unit are its What, joined with a dot. The quotes are left
  out. A block with no labels is named by what tells it apart: a provider's
  alias, the address a `moved` or `removed` block moves from, the address an
  `import` block imports to. `import` is an ANTLR keyword, so the kind is
  `importBlock`. Only blocks that nothing tells apart, such as two
  `variables {}` blocks in a test file, are numbered: `variables`,
  `variables#2`.
- The `description` of a variable or an output is a Why, because Terraform
  shows it as the documentation. A comment directly above wins over it.
- `variable` and `output` are labeled `required`: they are a module's
  interface, so they need a Why. Other blocks may have one.
- A `run` block is a test, because `terraform test` runs it, so it needs a Why
  that cites a requirement.
- HCL has no annotations, so nothing is labeled `marker`.
- The `locals` block is no unit, and a comment above it is a note. Its entries
  are units, with Terraform's `local.<name>` addresses.

A JSON file gives the same units with the same names. A block type's
property holds blocks keyed by their labels, as
`{"resource": {"aws_vpc": {"main": {...}}}}`; the keys above a block that are
part of its address are labeled `qualifier`, which makes them the first parts
of the name of every unit below them, so this resource is
`resource/aws_vpc.main` too. In Terraform's JSON syntax a property named `//`
is a comment, so a block's `//` property is its Why, and a variable's or an
output's `description` is one as well. A variable and an output require a Why,
which the colon after their name is labeled `required` to say. The HCL
profile owns JSON files by name, since their extension is `.json`:

```yaml
extensions: [.tf, .tfvars, .hcl]
files: ["*.tf.json", "*.tfvars.json"]
```

## Known limitations

- JSON has no schema to tell a block from an attribute, so a top-level
  property of a JSON file that is not a Terraform block type canon knows
  (`resource`, `data`, `module`, `variable`, `output`, `provider`, `locals`,
  `terraform`, `check`, `moved`, `removed`, `import`) is a unit of kind
  `attribute`, as in a `.tfvars.json` file. A `.tf.json` file and a
  `.tfvars.json` file are read with one grammar, which does not see the file's
  name, and Terraform rejects an unknown block type in a `.tf.json` file, so
  the reading only matters for files Terraform accepts, where it is right.
- Blocks that nothing tells apart are numbered, so inserting one before
  another renumbers it. Terraform itself gives such a block no address, so
  there is no name to give it that an edit could not change.

In a JSON file a variable's or an output's `//` property is its Why wherever
it is written, and its `description` is the Why only when it has none, as a
comment above wins over a description in the native syntax. A comment in any
other place parses, inside an expression, among the arguments of a call, in
an object, a `for` expression, or an interpolation, or at the end of a block,
and is a note.
