/** The canonically commented dialect of the Folio parser. A page with front matter is a unit of kind doc whose Why is its front matter and whose What is its id, and each section whose heading is followed by prose is a unit of kind section whose What is its title, whose Why is all of its prose, before and after its fenced blocks, and whose How is its fenced blocks. A --- line below the top of the page is a thematic break. ref:DEC-folio-dialect ref:DEC-section-prose-is-why ref:DEC-doc-kind */
parser grammar FolioParser;

options {
    tokenVocab = FolioLexer;
}

/** A page: one with front matter, which is a unit, or one without, whose sections stand alone. */
document
    : page EOF
    | content EOF
    ;

/** A page with front matter at its top: the front matter is its Why, the id field's value its What, and the page is required to have both. */
page
    : FRONT_OPEN why = frontFields FRONT_CLOSE content # doc
    ;

/** What follows the front matter: the elements before the first heading, then the sections. */
content
    : element* section*
    ;

/** The fields of front matter, one or more. */
frontFields
    : frontField+
    ;

/** One field: the id, which names the page; the video, whose value is cited as a reference is; or any other field, whose value is prose. */
frontField
    : FIELD_ID what = frontValue
    | FIELD_VIDEO ref = frontValue
    | (FIELD_KIND | FIELD_TITLE | FIELD_OTHER) frontValue?
    | frontValue
    ;

/** The value of a field, tokenized as a canonical comment is. */
frontValue
    : docPart+
    ;

/** A section: a heading and what follows it up to the next heading. */
section
    : documentedSection
    | bareSection
    ;

/** A section whose heading is followed by prose: the title is its What, all of its prose its Why, and its fenced blocks its How, as every tangled block of the section takes its Why from the section's prose. ref:DEC-section-prose-is-why */
documentedSection
    : HEADING_OPEN what = title why = sectionProse # section
    ;

/** The body of a documented section: its prose, with each fenced block labeled how, so the Why is the prose around the blocks and the How the blocks. */
sectionProse
    : paragraphs (how = codeBlock | paragraphs)*
    ;

/** A section whose heading is followed by no prose, which is no unit. */
bareSection
    : HEADING_OPEN title? sectionRest?
    ;

/** The title of a heading. */
title
    : (TITLE_WORD | TITLE_PUNCT)+
    ;

/** The rest of a section that opens with a fenced block: the blocks with the prose between them. */
sectionRest
    : codeBlock element*
    ;

/** One thing on a page that is not a heading: a fenced block or prose. */
element
    : codeBlock
    | paragraphs
    ;

/** Prose: one or more lines of it, blank lines between them included. */
paragraphs
    : docPart+
    ;

/** A fenced block: the fence with its info string, the body lines, and the closer, in either fence length. */
codeBlock
    : FENCE3 CODE_LINE* CLOSE3
    | FENCE4 CODE_LINE* CLOSE4
    ;

/** One piece of front matter or prose: a reference citation, a license citation, a word, or punctuation. */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
