/** The Makefile parser of the canonically commented dialect: a makefile is statements, each a rule, a variable, a conditional, an include, a define, or an export. A rule with a plain target is a unit that requires a canonical comment, its target the What and its recipe the How; a special or pattern rule and a variable are units whose comment is optional. ref:DEC-make-dialect */
parser grammar MakefileParser;

options {
    tokenVocab = MakefileLexer;
}

/** A makefile: statements and blank lines to the end. */
makefile : (statement | NEWLINE)* EOF ;

/** One statement of a makefile. */
statement : rule | variable | conditional | include | define | export ;

/** A rule: its canonical comment, after any that bind to nothing and are reported as orphans, its targets, the colon, its prerequisites or a target-specific assignment, an optional help line, and its recipe. A rule with a plain target requires the comment; a special target such as .PHONY or a pattern rule may carry one. ref:DEC-make-dialect */
rule
    : ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = NAME target* required = colon ruleTail HELP? NEWLINE? how = recipes? # rule
    | ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = SPECIAL target* colon ruleTail HELP? NEWLINE? how = recipes? # specialRule
    | ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = PATTERN target* colon ruleTail HELP? NEWLINE? how = recipes? # patternRule
    ;

/** The colon of a rule, single or double. */
colon : COLON | DCOLON ;

/** What follows a rule's colon: prerequisites, with order-only ones after a bar, or a target-specific variable assignment. */
ruleTail
    : target* (PIPE target*)?
    | NAME ASSIGN VALUE
    ;

/** A target or prerequisite name of any shape. */
target : NAME | SPECIAL | PATTERN ;

/** The recipe lines of a rule, with blank lines between them allowed. */
recipes : RECIPE NEWLINE? (NEWLINE* RECIPE NEWLINE?)* ;

/** A variable assignment: its optional canonical comment, its name, the operator, and its value. */
variable : ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = variableName ASSIGN how = VALUE NEWLINE? # variable ;

/** The name of a variable, which may be a special one such as .DEFAULT_GOAL. */
variableName : NAME | SPECIAL ;

/** A conditional block with an optional else. */
conditional : (IFEQ | IFDEF) NEWLINE? (statement | NEWLINE)* (ELSE NEWLINE? (statement | NEWLINE)*)? ENDIF NEWLINE? ;

/** An include line. */
include : INCLUDE NEWLINE? ;

/** A define block, verbatim to its endef. */
define : DEFINE DEFINE_NL (DEFINE_LINE | DEFINE_NL)* ENDEF NEWLINE? ;

/** An export or unexport of a variable, with or without an assignment. */
export : EXPORT variableName (ASSIGN VALUE)? NEWLINE? ;

/** A canonical comment: the opener and its parts. */
canonicalComment : DOC_OPEN docPart* ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
