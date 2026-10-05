/** The Makefile lexer of the canonically commented dialect: GNU make as a line language. A canonical comment opens with a hash and a bar and continues on following hash lines, as the Haskell dialect's opens with two dashes and a bar; a recipe line is one token from its leading tab; an assignment sends the rest of the line into a value mode, since a value is text make expands and not names; and a rule line is names, a colon, and names. ref:DEC-make-dialect */
lexer grammar MakefileLexer;

/** A canonical comment opens with a hash, optional spaces, and a bar, and its contents are tokenized in the DocLine mode so the parser can read the Why and the citations. ref:DEC-make-dialect */
DOC_OPEN : '#' ' '* '|' -> pushMode(DocLine);

/** A help line, two hashes after a rule's prerequisites, is the rule's one-line What, which the help target prints; it is kept as a token so the parser can see it and the extractor can ignore it. */
HELP : '##' ~[\r\n]* ;

/** Any other comment is hidden. It may not begin with a bar after the hash and its spaces, so a canonical comment is never taken for a plain one by length. */
COMMENT : '#' (' '* ~[ |\r\n] ~[\r\n]* | ' '*) -> channel(HIDDEN);

/** A recipe line: a tab and the rest of the line, which is shell and never read further. */
RECIPE : '\t' ~[\r\n]* ;

/** A backslash before a line break joins the next line to this one outside a value. */
CONTINUATION : '\\' '\r'? '\n' -> skip;

/** A line break. */
NEWLINE : '\r'? '\n' ;

/** Spaces between names. */
WS : [ \t]+ -> skip;

/** A define opens a verbatim block that endef closes. */
DEFINE : 'define' [ \t]+ ~[\r\n]* -> pushMode(Define);

/** A conditional on two values, with the rest of its line. */
IFEQ : ('ifeq' | 'ifneq') ~[\r\n]* ;

/** A conditional on a variable being defined. */
IFDEF : ('ifdef' | 'ifndef') [ \t]+ ~[\r\n]* ;

/** The else of a conditional, with an optional second condition. */
ELSE : 'else' ([ \t]+ ~[\r\n]*)? ;

/** The end of a conditional. */
ENDIF : 'endif' ;

/** An include of another makefile, in any of its three spellings. */
INCLUDE : ('include' | '-include' | 'sinclude') [ \t]+ ~[\r\n]* ;

/** Exporting a variable to recipes, or withdrawing it. */
EXPORT : 'export' | 'unexport' ;

/** An assignment operator in any of make's flavours; the value that follows is read in the Value mode to the end of the line. */
ASSIGN : ('::=' | ':=' | '?=' | '+=' | '!=' | '=') -> pushMode(Value);

/** A double colon, for a rule that may have several definitions. */
DCOLON : '::' ;

/** The colon that separates targets from prerequisites. */
COLON : ':' ;

/** The bar that separates order-only prerequisites. */
PIPE : '|' ;

/** A semicolon, which begins a recipe on the rule's own line; the rest is read as a value. */
SEMI : ';' -> pushMode(Value);

/** A special target, a dot and capitals, such as .PHONY; listed before NAME so it wins their tie. */
SPECIAL : '.' [A-Z_]+ ;

/** A pattern, a name with a percent sign in it; listed before NAME so it wins their tie. */
PATTERN : NameChar* '%' (NameChar | '%')* ;

/** A name: a target, a prerequisite, or a variable, with the characters make allows and the expansions targets carry. */
NAME : NameChar+ ;

/** The characters of a name. */
fragment NameChar : [A-Za-z0-9_./$(){}@<^*+,~-] ;

/** After an assignment operator: the value, with backslash line breaks kept, to the end of the line. */
mode Value;

/** The value of an assignment, possibly empty, which returns to the default mode at the line break. */
VALUE : (~[\r\n\\] | '\\' ~[\r\n] | '\\' '\r'? '\n')* -> popMode;

/** Inside a define block. */
mode Define;

/** The end of a define block. */
ENDEF : 'endef' [ \t]* -> popMode;

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
