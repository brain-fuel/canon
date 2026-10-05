/** The Makefile parser of the canonically commented dialect: a makefile is statements, each a rule, a variable, a conditional, an include, a define, an export, another directive, or a line that only expands references. A rule with a plain target is a unit that requires a canonical comment, its target the What and its recipe the How; a special or pattern rule and a variable are units whose comment is optional. ref:DEC-make-dialect */
parser grammar MakefileParser;

// canon: a canonical comment where the grammar accepts none, between recipe lines or above an
// endif, is read as an orphan rather than failing the file, as the strayComment option says.
// ref:DEC-stray-comments ref:DEC-make-dialect
options {
    tokenVocab = MakefileLexer;
    strayComment = canonicalComment;
}

/** A makefile: statements and blank lines to the end. */
makefile : (statement | NEWLINE)* EOF ;

/** One statement of a makefile. A recipe line that follows no rule and a help line on its own are statements too, since make reads a tab-indented line outside a rule as an ordinary line and a help line is a comment. ref:DEC-make-dialect */
statement : rule | variable | conditional | include | define | export | directive | expansion | groupedWithoutTargets | strayRecipe | helpLine ;

/** A rule: its canonical comment, after any that bind to nothing and are reported as orphans, its targets, the colon, its prerequisites or a target-specific assignment, an optional recipe after a semicolon, an optional help line, and its recipe. A rule with a plain target requires the comment; a special target such as .PHONY or a pattern rule may carry one. ref:DEC-make-dialect */
rule
    : ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = (NAME | keyword) target* required = colon ruleTail ruleEnd how = recipes? # rule
    | ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = SPECIAL target* colon ruleTail ruleEnd how = recipes? # specialRule
    | ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) what = PATTERN target* colon ruleTail ruleEnd how = recipes? # patternRule
    ;

/** The colon of a rule: single, double, or the grouped-targets colon. */
colon : COLON | DCOLON | GROUPED ;

/** What follows a rule's colon: prerequisites, with order-only ones after a bar and, in a static pattern rule, a target pattern and its prerequisite patterns after a second colon; or a target-specific variable assignment or export. ref:DEC-make-dialect */
ruleTail
    : prerequisites (colon prerequisites)?
    | modifier* variableName ASSIGN VALUE?
    | EXPORT target*
    ;

/** Prerequisites, with order-only ones after a bar. */
prerequisites : target* (PIPE target*)? ;

/** The end of a rule's line: a recipe after a semicolon, a help line, and the line break. */
ruleEnd : (SEMI VALUE?)? HELP? NEWLINE? ;

/** A modifier of a variable assignment. */
modifier : OVERRIDE | PRIVATE | EXPORT ;

/** A target or prerequisite name of any shape, including a word make otherwise reads as a modifier. */
target : NAME | SPECIAL | PATTERN | keyword ;

/** A word that is a modifier at the start of an assignment and a name elsewhere, as make reads export = 1 as an assignment to a variable named export. ref:DEC-make-dialect */
keyword : EXPORT | OVERRIDE | PRIVATE ;

/** The recipe lines of a rule, with blank lines, help lines, and conditionals among them, as make keeps reading a rule's recipe across a conditional. ref:DEC-make-dialect */
recipes : recipeLine ((NEWLINE | HELP)* recipeLine)* ;

/** One recipe line, or a conditional whose branches are recipe lines. */
recipeLine : RECIPE NEWLINE? | recipeConditional ;

/** A conditional between a rule's recipe lines, its branches recipe lines and blank lines. */
recipeConditional : (IFEQ | IFDEF) NEWLINE? recipeBody (ELSE NEWLINE? recipeBody)* ENDIF HELP? NEWLINE? ;

/** The branch of a conditional between recipe lines. */
recipeBody : (RECIPE | NEWLINE | HELP | recipeConditional)* ;

/** A variable assignment: its optional canonical comment, its override, private, or export modifiers, its name, the operator, and its value, which may be empty at the end of the file. */
variable : ((orphan = canonicalComment NEWLINE*)+ why = canonicalComment NEWLINE* | why = canonicalComment? NEWLINE*) modifier* what = variableName ASSIGN how = VALUE? NEWLINE? # variable ;

/** The name of a variable, which may be a special one such as .DEFAULT_GOAL, or a word make otherwise reads as a modifier. */
variableName : NAME | SPECIAL | keyword ;

/** A conditional block with optional else branches, each of which may chain another condition. */
conditional : (IFEQ | IFDEF) NEWLINE? (statement | NEWLINE)* (ELSE NEWLINE? (statement | NEWLINE)*)* ENDIF HELP? NEWLINE? ;

/** An include line. */
include : INCLUDE NEWLINE? ;

/** A define block, verbatim to its endef, with any modifiers before it and any define nested in it. */
define : modifier* DEFINE DEFINE_NL defineBody ENDEF NEWLINE? ;

/** The lines of a define block. */
defineBody : (DEFINE_LINE | DEFINE_NL | nestedDefine)* ;

/** A define inside a define block, which its own endef closes. */
nestedDefine : NESTED_DEFINE DEFINE_NL defineBody ENDEF ;

/** An export or unexport of variables without an assignment, or of every variable when it names none; an export with an assignment is a variable with the export modifier. */
export : EXPORT target* HELP? NEWLINE? ;

/** An undefine, vpath, or load directive, with its modifiers. ref:DEC-make-dialect */
directive : (OVERRIDE | PRIVATE | EXPORT)* (UNDEFINE | VPATH | LOAD) NEWLINE? ;

/** A line of names with no separator, such as $(eval ...) or $(foreach ...), which make expands and reads again; it may also be a recipe line written with the prefix .RECIPEPREFIX sets, which begins with that character and may hold an assignment. ref:DEC-make-dialect */
expansion : (NAME | SPECIAL | PATTERN | PIPE) (target | PIPE)* (ASSIGN VALUE? | SEMI VALUE?)? HELP? NEWLINE? ;

/** A grouped-targets colon with no targets before it, which make allows and ignores. */
groupedWithoutTargets : GROUPED ruleTail ruleEnd recipes? ;

/** A tab-indented line that follows no rule, which make reads as an ordinary line. */
strayRecipe : RECIPE NEWLINE? ;

/** A line that is only a help comment, such as a section heading written with two hashes. */
helpLine : HELP NEWLINE? ;

/** A canonical comment: the opener and its parts. */
canonicalComment : DOC_OPEN docPart* ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
