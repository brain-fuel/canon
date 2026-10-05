/** The Makefile lexer of the canonically commented dialect: GNU make as a line language. A canonical comment opens with a hash and a bar and continues on following hash lines, as the Haskell dialect's opens with two dashes and a bar; a recipe line is one token from its leading tab; an assignment sends the rest of the line into a value mode, since a value is text make expands and not names; and a rule line is names, a colon, and names. A name carries its variable references whole, nested to any depth, so a colon, an equals sign, a comma, a space, or a hash inside a reference is part of the name, as make reads it. ref:DEC-make-dialect */
lexer grammar MakefileLexer;

// canon: grown on the corpus of tools/corpus/make.sh (Linux, CPython, git, GNU make's own test
// suite): references nest, backslash line breaks join every kind of line, directives take the rest
// of their line, and override, private, undefine, vpath, load, and grouped targets are read. The
// default mode is the start of a line, where make looks for directives and recipes; the first name
// or separator of a line moves to the Body mode, where a word such as define or include is a name,
// and the line break returns. ref:DEC-make-dialect

/** A canonical comment opens with a hash, optional spaces, and a bar, and its contents are tokenized in the DocLine mode so the parser can read the Why and the citations. ref:DEC-make-dialect */
DOC_OPEN : '#' ' '* '|' -> pushMode(DocLine);

/** A help line, two hashes after a rule's prerequisites, is the rule's one-line What, which the help target prints; it is kept as a token so the parser can see it and the extractor can ignore it. */
HELP : '##' ~[\r\n]* ;

/** Any other comment is hidden. It may not begin with a bar after the hash and its spaces, so a canonical comment is never taken for a plain one by length; a backslash at the end of its line continues it on the next, as make reads a comment. ref:DEC-make-dialect */
COMMENT : '#' (' '* ~[ |\r\n] CommentChar* | ' '*) '\\'? -> channel(HIDDEN);

/** A recipe line: a tab and the rest of the line, which is shell and never read further; a backslash at the end of the line continues the same recipe line on the next, whatever that line starts with. ref:DEC-make-dialect */
RECIPE : '\t' LineRest ;

/** A backslash before a line break joins the next line to this one outside a value, with the next line's leading blanks, so a continued prerequisite list is never taken for a recipe. */
CONTINUATION : '\\' '\r'? '\n' [ \t]* -> skip;

/** A line break. */
NEWLINE : '\r'? '\n' ;

/** Spaces between names. */
WS : [ \t]+ -> skip;

/** A define opens a verbatim block that endef closes; the rest of its line names the variable and its flavour. A define followed by an assignment operator assigns a variable named define instead. */
DEFINE : 'define' [ \t]+ ~[ \t\r\n=:+?!#] LineRest -> pushMode(Define);

/** A conditional on two values, with the rest of its line. */
IFEQ : ('ifeq' | 'ifneq') [ \t(] LineRest ;

/** A conditional on a variable being defined. */
IFDEF : ('ifdef' | 'ifndef') [ \t]+ LineRest ;

/** The else of a conditional, with an optional second condition, as else ifeq chains them. */
ELSE : 'else' ([ \t]+ LineRest)? ;

/** The end of a conditional. */
ENDIF : 'endif' ;

/** An include of another makefile, in any of its three spellings. */
INCLUDE : ('include' | '-include' | 'sinclude') [ \t]+ LineRest ;

/** The removal of a variable, with the rest of its line. ref:DEC-make-dialect */
UNDEFINE : 'undefine' [ \t]+ LineRest ;

/** A search path for prerequisites matching a pattern, with the rest of its line. ref:DEC-make-dialect */
VPATH : 'vpath' ([ \t]+ LineRest)? ;

/** A load of a dynamic object that extends make, with the rest of its line. ref:DEC-make-dialect */
LOAD : ('load' | '-load') [ \t]+ LineRest ;

/** Exporting a variable to recipes, or withdrawing it. */
EXPORT : 'export' | 'unexport' ;

/** The override modifier, which sets a variable over the command line's value. ref:DEC-make-dialect */
OVERRIDE : 'override' ;

/** The private modifier, which keeps a variable from the prerequisites' recipes. ref:DEC-make-dialect */
PRIVATE : 'private' ;

/** An assignment operator in any of make's flavours; the value that follows is read in the Value mode to the end of the line. */
ASSIGN : AssignOp -> pushMode(Value);

/** The colon of grouped targets, which one recipe makes together. ref:DEC-make-dialect */
GROUPED : '&:' ':'? -> mode(Body);

/** A double colon, for a rule that may have several definitions. */
DCOLON : '::' -> mode(Body);

/** The colon that separates targets from prerequisites. */
COLON : ':' -> mode(Body);

/** The bar that separates order-only prerequisites. */
PIPE : '|' -> mode(Body);

/** A semicolon, which begins a recipe on the rule's own line; the rest is read as a value. */
SEMI : ';' -> mode(Body), pushMode(Value);

/** A special target, a dot and capitals, such as .PHONY; listed before NAME so it wins their tie. */
SPECIAL : '.' [A-Z_]+ -> mode(Body);

/** A pattern, a name with a percent sign in it; listed before NAME so it wins their tie. */
PATTERN : NamePart* '%' (NamePart | '%')* -> mode(Body);

/** A name: a target, a prerequisite, or a variable, with the variable references and escapes it carries; a run of the characters that begin operators, where no operator follows, is a name too, as a line after .RECIPEPREFIX may hold one. */
NAME : (NamePart+ | [&+?!]+) -> mode(Body);

/** One piece of a name: a plain character, a reference, an escaped character, or a run of the characters that also begin an operator, when a name character follows, so CFLAGS+= is a name and an operator. */
fragment NamePart : NameChar | Reference | '\\' ~[\r\n] | [&+?!]+ (NameChar | Reference | '\\' ~[\r\n]) ;

/** The characters of a name: all but blanks, line breaks, and the characters that separate or begin something else. */
fragment NameChar : ~[ \t\r\n:=;|#$%\\&+?!] ;

/** A variable reference or function call: a dollar and a parenthesised or braced body, nested to any depth, or a dollar and one character; a dollar before a backslash line break swallows the break and the next line's indent, the idiom that joins lines without a space. */
fragment Reference : '$' ('(' ParenBody* ')' | '{' BraceBody* '}' | '\\' '\r'? '\n' [ \t]* | ~[\r\n({]) ;

/** A piece of a parenthesised reference: a nested reference, a balanced pair of parentheses, an escape, a joined line, or any other character. */
fragment ParenBody : Reference | '(' ParenBody* ')' | '\\' '\r'? '\n' | '\\' ~[\r\n] | ~[()$\\\r\n] ;

/** A piece of a braced reference, as ParenBody is for parentheses. */
fragment BraceBody : Reference | '{' BraceBody* '}' | '\\' '\r'? '\n' | '\\' ~[\r\n] | ~[{}$\\\r\n] ;

/** The rest of a line, with backslash line breaks joining the lines that follow; a carriage return not before a line feed is an ordinary character, as make reads it. */
fragment LineRest : (~[\n\\] | '\\' '\r'? '\n' | '\\' ~[\n])* '\\'? ;

/** An assignment operator in any of make's flavours. */
fragment AssignOp : ':::=' | '::=' | ':=' | '?:=' | '?=' | '+=' | '!=' | '=' ;

/** A character of a comment, with a backslash line break continuing it. */
fragment CommentChar : ~[\r\n\\] | '\\' ~[\r\n] | '\\' '\r'? '\n' ;

/** The rest of a line after its first name or separator, where directives are not recognised, so define, include, or else there is a name. ref:DEC-make-dialect */
mode Body;

/** A help line after a rule's prerequisites. */
BODY_HELP : '##' ~[\r\n]* -> type(HELP);

/** A comment after code on a line, hidden whatever follows its hash, since a canonical comment is a line of its own. */
BODY_COMMENT : '#' CommentChar* '\\'? -> channel(HIDDEN);

/** A backslash line break, which joins the next line to this one with its indent. */
BODY_CONTINUATION : '\\' '\r'? '\n' [ \t]* -> skip;

/** The line break that ends the line and returns to the start of the next. */
BODY_NEWLINE : '\r'? '\n' -> type(NEWLINE), mode(DEFAULT_MODE);

/** Blanks between names, tabs included. */
BODY_WS : [ \t]+ -> skip;

/** Exporting in a target-specific assignment, or a target named export. */
BODY_EXPORT : ('export' | 'unexport') -> type(EXPORT);

/** The override modifier in a target-specific assignment, or a target named override. */
BODY_OVERRIDE : 'override' -> type(OVERRIDE);

/** The private modifier in a target-specific assignment, or a target named private. */
BODY_PRIVATE : 'private' -> type(PRIVATE);

/** An assignment operator, whose value is read in the Value mode. */
BODY_ASSIGN : AssignOp -> type(ASSIGN), pushMode(Value);

/** The colon of grouped targets. */
BODY_GROUPED : '&:' ':'? -> type(GROUPED);

/** A double colon. */
BODY_DCOLON : '::' -> type(DCOLON);

/** A colon. */
BODY_COLON : ':' -> type(COLON);

/** The bar before order-only prerequisites. */
BODY_PIPE : '|' -> type(PIPE);

/** A semicolon, which begins a recipe on the rule's own line. */
BODY_SEMI : ';' -> type(SEMI), pushMode(Value);

/** A special target. */
BODY_SPECIAL : '.' [A-Z_]+ -> type(SPECIAL);

/** A pattern. */
BODY_PATTERN : NamePart* '%' (NamePart | '%')* -> type(PATTERN);

/** A name. */
BODY_NAME : (NamePart+ | [&+?!]+) -> type(NAME);

/** After an assignment operator: the value, with backslash line breaks kept, to the end of the line. */
mode Value;

/** The value of an assignment, possibly empty, which returns to the default mode at the line break. */
VALUE : LineRest -> popMode;

/** Inside a define block. */
mode Define;

/** The end of a define block, which may be indented and carry a comment. */
ENDEF : [ \t]* 'endef' ([ \t] ~[\r\n]*)? -> popMode;

/** A define inside a define block, which make counts so that its endef does not end the outer block. ref:DEC-make-dialect */
NESTED_DEFINE : [ \t]* 'define' [ \t]+ ~[\r\n]* -> pushMode(Define);

/** A verbatim line of a define block. */
DEFINE_LINE : ~[\r\n]+ ;

/** A line break inside a define block. */
DEFINE_NL : '\r'? '\n' ;

/** Inside a canonical comment. */
mode DocLine;

/** A following line that starts with a hash continues the comment, so a comment is as many lines as it needs. */
DOC_CONTINUE : ('\r'? '\n') [ \t]* '#' -> skip;

/** The line break that ends a canonical comment, typed as a NEWLINE so the parser sees the line break as usual. */
DOC_CLOSE : ('\r'? '\n') -> popMode, type(NEWLINE);

/** A citation of a registry reference inside a canonical comment. */
DOC_REF : 'ref:' DocKey;

/** A citation of a registry license inside a canonical comment. */
DOC_LICENSE : 'license:' DocKey;

/** Whitespace inside a canonical comment. */
DOC_WS : [ \t]+ -> skip;

/** Punctuation inside a canonical comment, kept separate so a citation followed by a comma is still a citation. */
DOC_PUNCT : [,.;:()!?[\]{}"'`<>=+|];

/** A word of prose inside a canonical comment. */
DOC_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|]+;

/** The shape of a reference key. */
fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;
