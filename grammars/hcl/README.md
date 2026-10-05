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
- Identifiers are Unicode identifiers, as the specification says: a letter or
  underscore and then letters, digits, marks, connectors, underscores, or
  dashes, so `local.π` lexes. ASCII comes first in each character set, and the
  first character and the rest are separate sets, so no character can be
  matched two ways and lexing stays as fast as it was with ASCII alone.
- An attribute's name and a block's type may be quoted strings, as HCL 1
  allows and Nomad's agent and volume files still write, such as
  `meta { "rack" = "r2" }` and `plugin "x" { "config" { ... } }`. HCL 2's
  native syntax rejects them; canon accepts them, since Nomad reads those
  files. In the dialect a quoted top-level name is named without its quotes.
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
including their `.tftest.hcl` files, and every file of the corpus below.

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
- An attribute's name or a block's type written as a quoted string, which
  HCL 1 allows and HCL 2 rejects, parses, since Nomad reads such files; canon
  does not tell a Terraform file that writes one from a Nomad file that may.
- Blocks that nothing tells apart are numbered, so inserting one before
  another renumbers it. Terraform itself gives such a block no address, so
  there is no name to give it that an edit could not change.

A comment between an object `for` expression's opening brace and its `for`,
as terraform-aws-alb writes to explain the expression, is a note: the hook
hides comments inside the expression only once the `for` has opened it.

In a JSON file a variable's or an output's `//` property is its Why wherever
it is written, and its `description` is the Why only when it has none, as a
comment above wins over a description in the native syntax. A comment in any
other place parses, inside an expression, among the arguments of a call, in
an object, a `for` expression, or an interpolation, or at the end of a block,
and is a note.

## Corpus

`tools/corpus/hcl.sh` checks the grammar against the most used Terraform
modules and HashiCorp's own HCL. It shallow-clones each repository below at
the pinned commit into `/tmp/corpus/hcl`, or the directory given as its first
argument, parses every `.tf`, `.tfvars`, `.hcl`, `.tf.json`, and
`.tfvars.json` file with the plain grammar under a timeout of 10 seconds per
file, and then parses every file the plain grammar parsed with the dialect,
which must parse them all. Large repositories are sampled by subdirectory with
a sparse checkout.

| Repository | Commit | Sampled | Files | Parsed | Excluded | Seconds |
|------------|--------|---------|------:|-------:|---------:|--------:|
| [terraform-aws-modules/terraform-aws-vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) | `b3abd6df2ecf` | all | 77 | 77 | 0 | 6.5 |
| [terraform-aws-modules/terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks) | `e07246207174` | all | 90 | 90 | 0 | 9.1 |
| [terraform-aws-modules/terraform-aws-iam](https://github.com/terraform-aws-modules/terraform-aws-iam) | `da8e6a867393` | all | 99 | 99 | 0 | 7.2 |
| [terraform-aws-modules/terraform-aws-rds](https://github.com/terraform-aws-modules/terraform-aws-rds) | `175da043429c` | all | 104 | 104 | 0 | 7.5 |
| [terraform-aws-modules/terraform-aws-rds-aurora](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora) | `d72cba285514` | all | 52 | 52 | 0 | 3.8 |
| [terraform-aws-modules/terraform-aws-s3-bucket](https://github.com/terraform-aws-modules/terraform-aws-s3-bucket) | `5dc2f1f89743` | all | 93 | 93 | 0 | 6.6 |
| [terraform-aws-modules/terraform-aws-security-group](https://github.com/terraform-aws-modules/terraform-aws-security-group) | `b3c1b2e8beff` | all | 441 | 441 | 0 | 30.0 |
| [terraform-aws-modules/terraform-aws-lambda](https://github.com/terraform-aws-modules/terraform-aws-lambda) | `3a1405b98f47` | all | 99 | 99 | 0 | 10.5 |
| [terraform-aws-modules/terraform-aws-ec2-instance](https://github.com/terraform-aws-modules/terraform-aws-ec2-instance) | `4dfedcdd1f26` | all | 16 | 16 | 0 | 2.4 |
| [terraform-aws-modules/terraform-aws-alb](https://github.com/terraform-aws-modules/terraform-aws-alb) | `6c6e48c10d45` | all | 28 | 28 | 0 | 3.7 |
| [terraform-aws-modules/terraform-aws-autoscaling](https://github.com/terraform-aws-modules/terraform-aws-autoscaling) | `2a249e91c798` | all | 12 | 12 | 0 | 3.1 |
| [terraform-aws-modules/terraform-aws-ecs](https://github.com/terraform-aws-modules/terraform-aws-ecs) | `135c225c75c7` | all | 64 | 64 | 0 | 9.4 |
| [terraform-aws-modules/terraform-aws-dynamodb-table](https://github.com/terraform-aws-modules/terraform-aws-dynamodb-table) | `b6cc51576046` | all | 25 | 25 | 0 | 2.7 |
| [terraform-aws-modules/terraform-aws-cloudfront](https://github.com/terraform-aws-modules/terraform-aws-cloudfront) | `5b9a0a480220` | all | 24 | 24 | 0 | 2.8 |
| [terraform-aws-modules/terraform-aws-sqs](https://github.com/terraform-aws-modules/terraform-aws-sqs) | `a68b4d515f9c` | all | 12 | 12 | 0 | 1.4 |
| [terraform-aws-modules/terraform-aws-sns](https://github.com/terraform-aws-modules/terraform-aws-sns) | `4538b7e208f5` | all | 12 | 12 | 0 | 1.2 |
| [terraform-aws-modules/terraform-aws-kms](https://github.com/terraform-aws-modules/terraform-aws-kms) | `d25e459bd43d` | all | 12 | 12 | 0 | 1.8 |
| [terraform-aws-modules/terraform-aws-route53](https://github.com/terraform-aws-modules/terraform-aws-route53) | `883f987d6bb3` | all | 40 | 40 | 0 | 4.3 |
| [terraform-aws-modules/terraform-aws-acm](https://github.com/terraform-aws-modules/terraform-aws-acm) | `aae84c011dd6` | all | 24 | 24 | 0 | 2.6 |
| [terraform-aws-modules/terraform-aws-apigateway-v2](https://github.com/terraform-aws-modules/terraform-aws-apigateway-v2) | `95e6a1d56d6d` | all | 21 | 21 | 0 | 2.8 |
| [terraform-aws-modules/terraform-aws-eventbridge](https://github.com/terraform-aws-modules/terraform-aws-eventbridge) | `f9934726324c` | all | 50 | 50 | 0 | 7.8 |
| [terraform-aws-modules/terraform-aws-step-functions](https://github.com/terraform-aws-modules/terraform-aws-step-functions) | `16c7a1ffaa72` | all | 9 | 9 | 0 | 1.2 |
| [terraform-aws-modules/terraform-aws-notify-slack](https://github.com/terraform-aws-modules/terraform-aws-notify-slack) | `a7765ac0a547` | all | 14 | 14 | 0 | 1.8 |
| [terraform-aws-modules/terraform-aws-atlantis](https://github.com/terraform-aws-modules/terraform-aws-atlantis) | `ffb75c7ef06e` | all | 20 | 20 | 0 | 4.1 |
| [terraform-aws-modules/terraform-aws-ecr](https://github.com/terraform-aws-modules/terraform-aws-ecr) | `f05e615fa452` | all | 24 | 24 | 0 | 4.2 |
| [terraform-aws-modules/terraform-aws-efs](https://github.com/terraform-aws-modules/terraform-aws-efs) | `e0ec33d84363` | all | 12 | 12 | 0 | 1.6 |
| [terraform-aws-modules/terraform-aws-elasticache](https://github.com/terraform-aws-modules/terraform-aws-elasticache) | `a43aabccb95c` | all | 56 | 56 | 0 | 7.5 |
| [terraform-aws-modules/terraform-aws-msk-kafka-cluster](https://github.com/terraform-aws-modules/terraform-aws-msk-kafka-cluster) | `b6320829cdff` | all | 25 | 25 | 0 | 4.5 |
| [terraform-aws-modules/terraform-aws-eks-pod-identity](https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity) | `b4a8990773bc` | all | 30 | 30 | 0 | 4.8 |
| [terraform-aws-modules/terraform-aws-transit-gateway](https://github.com/terraform-aws-modules/terraform-aws-transit-gateway) | `7973ea089017` | all | 12 | 12 | 0 | 2.1 |
| [hashicorp/terraform-provider-aws](https://github.com/hashicorp/terraform-provider-aws) | `e7bb9cc38b62` | `/examples/` | 133 | 133 | 0 | 16.1 |
| [hashicorp/terraform-provider-google](https://github.com/hashicorp/terraform-provider-google) | `0aba4009b6bb` | `/examples/` | 22 | 22 | 0 | 2.6 |
| [hashicorp/terraform](https://github.com/hashicorp/terraform) | `35ab6fb201e4` | `/internal/configs/testdata/valid-files/`, `/internal/configs/testdata/valid-modules/` | 106 | 106 | 0 | 12.1 |
| [hashicorp/nomad](https://github.com/hashicorp/nomad) | `04af70ce00ae` | `/e2e/**/*.hcl`, `/demo/**/*.hcl` | 154 | 154 | 0 | 19.0 |
| [hashicorp/packer-plugin-amazon](https://github.com/hashicorp/packer-plugin-amazon) | `62c6d423e412` | `*.hcl` | 27 | 27 | 0 | 3.0 |
| Total | | | 2039 | 2039 | 0 | 211.8 |

Every one of the 2,039 files, 5.2 MB, parses with the plain grammar and with
the dialect: 1,815 `.tf`, 198 `.hcl` (Nomad jobs and agent files, Packer
templates, and Terraform tests), 17 `.tfvars`, and 9 `.tf.json` files. No file
is excluded. The seconds are the sum of each file's wall time, the `canon`
process included, with 8 files parsed at once. A file takes 0.08 seconds at
the median, 0.16 at the 90th percentile, 0.37 at the 99th, and 0.93 at most,
`terraform-aws-ecs/variables.tf`; the files that failed before the fixes
failed within 0.06 seconds.

The corpus found three gaps, now fixed: a Unicode identifier in Terraform's
`valid-files/locals.tf`, HCL 1 quoted names in eight Nomad files, and, in the
dialect only, a comment before an object `for` in `terraform-aws-alb`.

To rerun it, from the repository root:

```sh
stack build
tools/corpus/hcl.sh                      # clones into /tmp/corpus/hcl
CORPUS_SKIP_FETCH=1 tools/corpus/hcl.sh  # reuses the clones
```

`CORPUS_TIMEOUT` sets the seconds per file and `CORPUS_JOBS` the files parsed
at once. The script exits nonzero when a file that is not a listed exclusion
fails, or when the dialect fails a file the plain grammar parses.
