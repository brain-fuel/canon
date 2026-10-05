/** The canonically commented dialect of the Folio lexer. Where the plain lexer makes each line one token, this one tokenizes the front matter and the prose into words, punctuation, reference citations, and license citations, as every dialect tokenizes a canonical comment, and a heading into the words of its title, so the parser can label the front matter as the page's Why, its id as the page's What, and each section's prose as the section's Why. DEFAULT_MODE is the first line of the page, where three dashes open front matter; LineStart is the start of every later line, which decides what the line is; a mode per kind of line reads the rest of it. A --- line below the top of the page is a thematic break, as in Markdown. ref:DEC-folio-dialect ref:DEC-folio-language */
lexer grammar FolioLexer;

/** Three dashes alone on the first line, which open the page's front matter; the lines after it start in LineStart. */
FRONT_OPEN : '---' [ \t]* -> mode(LineStart), pushMode(FrontMatter) ;

/** Any other first line: an empty match that reads it, and every line after it, from LineStart. */
PAGE_START : -> mode(LineStart), channel(HIDDEN) ;

/** A registry key: letters and digits, with dots, underscores, and hyphens inside. */
fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])? ;

/** The start of a line below the first. */
mode LineStart;

/** Three or more dashes alone on a line below the top of the page: a thematic break, which separates paragraphs and decides nothing else. */
THEMATIC_BREAK : '---' '-'* [ \t]* ('\r'? '\n' | EOF) -> skip ;

/** The hashes and the space that open a heading, whose depth is the number of hashes and whose title follows. */
HEADING_OPEN : '#'+ [ \t]+ -> pushMode(HeadingLine) ;

/** A fence of four backticks with its info string, for a block whose body holds three-backtick lines; listed before the three-backtick fence so it wins their tie. */
FENCE4 : '````' ~[\r\n]* -> pushMode(Code4) ;

/** A fence of three backticks with its info string, which names the language, the file the block tangles to, and what it defines. */
FENCE3 : '```' ~[\r\n]* -> pushMode(Code3) ;

/** A blank line, which separates paragraphs and decides nothing else. */
BLANK : [ \t]* '\r'? '\n' -> skip ;

/** Any other line is prose: an empty match that starts reading the line as prose without consuming it. */
PROSE_START : -> pushMode(ProseLine), channel(HIDDEN) ;

/** The start of a line of front matter. */
mode FrontMatter;

/** The three dashes that close front matter. */
FRONT_CLOSE : '---' [ \t]* -> popMode ;

/** The id field's key; its value is the page's What. */
FIELD_ID : 'id' [ \t]* ':' -> mode(FrontValue) ;

/** The kind field's key; its value names a Diátaxis quadrant. */
FIELD_KIND : 'kind' [ \t]* ':' -> mode(FrontValue) ;

/** The title field's key. */
FIELD_TITLE : 'title' [ \t]* ':' -> mode(FrontValue) ;

/** The video field's key; its value is the key of a registry entry of kind video, cited as a reference is. */
FIELD_VIDEO : 'video' [ \t]* ':' -> mode(FrontValue) ;

/** The key of any other field. */
FIELD_OTHER : [A-Za-z_] [A-Za-z0-9_-]* [ \t]* ':' -> mode(FrontValue) ;

/** A blank line inside front matter. */
FRONT_BLANK : [ \t]* '\r'? '\n' -> skip ;

/** A line of front matter without a key: an empty match that reads it as a value. */
FRONT_LINE : -> mode(FrontValue), channel(HIDDEN) ;

/** The rest of a line of front matter, tokenized as a canonical comment is. */
mode FrontValue;

/** The line break that ends a field. */
FRONT_VALUE_END : '\r'? '\n' -> mode(FrontMatter), skip ;

/** A reference citation in front matter. */
FRONT_REF : 'ref:' DocKey -> type(DOC_REF) ;

/** A license citation in front matter. */
FRONT_LICENSE : 'license:' DocKey -> type(DOC_LICENSE) ;

/** An inline code span in a value, one word of it. */
FRONT_CODE : '`' ~[`\r\n]+ '`' -> type(DOC_WORD) ;

/** Spaces between the words of a value. */
FRONT_WS : [ \t]+ -> skip ;

/** Punctuation in a value. */
FRONT_PUNCT : [,.;:()!?[\]{}"'`<>=+|*_] -> type(DOC_PUNCT) ;

/** A word of a value. */
FRONT_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|*_]+ -> type(DOC_WORD) ;

/** The title of a heading. */
mode HeadingLine;

/** The line break that ends a heading. */
HEADING_END : '\r'? '\n' -> popMode, skip ;

/** Spaces between the words of a title. */
HEADING_WS : [ \t]+ -> skip ;

/** Punctuation in a title, which the unit's name keeps. */
TITLE_PUNCT : [,.;:()!?[\]{}"'`<>=+|*_] ;

/** A word of a title. */
TITLE_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|*_]+ ;

/** A line of prose, tokenized as a canonical comment is. */
mode ProseLine;

/** The line break that ends a line of prose. */
PROSE_END : '\r'? '\n' -> popMode, skip ;

/** A reference citation: the prefix ref and a colon, then a registry key. */
DOC_REF : 'ref:' DocKey ;

/** A license citation: the prefix license and a colon, then the key of a registry entry of kind license. */
DOC_LICENSE : 'license:' DocKey ;

/** An inline code span, one word of prose, so a citation written in backticks is an example rather than a citation. */
DOC_CODE : '`' ~[`\r\n]+ '`' -> type(DOC_WORD) ;

/** Spaces between words. */
DOC_WS : [ \t]+ -> skip ;

/** Punctuation and Markdown emphasis. */
DOC_PUNCT : [,.;:()!?[\]{}"'`<>=+|*_] ;

/** A word of prose. */
DOC_WORD : ~[ \t\r\n,.;:()!?[\]{}"'`<>=+|*_]+ ;

/** Inside a three-backtick block. */
mode Code3;

/** The closer of a three-backtick block; it ties with a code line of the same text and wins by order. */
CLOSE3 : '```' [ \t]* -> popMode ;

/** A line of the block's body. */
CODE_LINE : ~[\r\n]+ ;

/** A line ending inside a block. */
CODE_NL : '\r'? '\n' -> skip ;

/** Inside a four-backtick block, where a three-backtick line is body. */
mode Code4;

/** The closer of a four-backtick block. */
CLOSE4 : '````' [ \t]* -> popMode ;

/** A line of the block's body, typed as a code line so the parser sees one kind. */
CODE4_LINE : ~[\r\n]+ -> type(CODE_LINE) ;

/** A line ending inside a four-backtick block. */
CODE4_NL : '\r'? '\n' -> skip ;
