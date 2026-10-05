// The canonically commented dialect of the F# parser canon reads F# with. Doc comments are canonical
// comments, which the lexer hook places right before the declaration they document; each
// declaration that carries documentation is a labeled unit alternative with its Why and its What;
// a doc comment the grammar accepts but binds to nothing, as in an expression, is an orphan. Every
// change from the plain grammar is marked canon: and listed in grammars/fsharp/README.md.
//
// The plain grammar is the F# parser canon reads F# with, written for canon because grammars-v4 has no F# grammar. It
// parses the declarations that carry documentation: namespaces, modules, let bindings, types and
// their members, record fields, union cases, val declarations, and exceptions. Expressions, types,
// and patterns are runs of tokens, kept whole by the INDENT, DEDENT, and NEWLINE tokens the
// FSharpLexerBase hook emits and by bracket nesting, so the parser finds where each declaration
// ends without typing what is inside it. A line it cannot read as a declaration is read as an
// expression, as a script's top-level code is. See grammars/fsharp/README.md for what it leaves out.
//
// Two labels serve canon: marker on each attribute, so a test is told by its attribute, and
// optional on private and internal, so a comment is required only on what a file exports.
//
// MIT License, as canon.

parser grammar FSharpParser;

options {
    tokenVocab = FSharpLexer;
}

// A file is namespaces, a top-level module, or the declarations of an implicit module.
// canon: a doc comment at the end of a file binds to nothing.
file
    : (namespaceDeclaration (NEWLINE namespaceDeclaration)* | topModule | moduleElements)? (orphan = canonicalComment)* EOF
    ;

// A namespace holds the declarations that follow it at its own column, or indented below it, up to
// the next namespace.
namespaceDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) NAMESPACE REC? (GLOBAL | what = longIdentifier) (NEWLINE moduleElements | INDENT moduleElements DEDENT)? # namespace
    ;

// A top-level module holds the rest of the file.
topModule
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? MODULE access? REC? what = longIdentifier (NEWLINE moduleElements | INDENT moduleElements DEDENT)? # module
    ;

moduleElements
    : moduleElement (NEWLINE moduleElement)*
    ;

moduleElement
    : nestedModule
    | moduleAbbreviation
    | letGroup
    | typeDefinition
    | valDeclaration
    | exceptionDefinition
    | otherModuleElement
    ;

nestedModule
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? MODULE access? REC? what = identifier EQUALS (
        INDENT moduleElements DEDENT
        | BEGIN (INDENT moduleElements DEDENT NEWLINE? | moduleElements)? END
    ) # module
    ;

moduleAbbreviation
    : MODULE identifier EQUALS longIdentifier
    ;

// An open, a do binding, an expression, or anything else that declares nothing, with the lines of
// a match that continue it at its own column.
// canon: a doc comment above a line that declares nothing binds to nothing.
otherModuleElement
    : leadingAttributes? (orphan = canonicalComment)* ~(NEWLINE | INDENT | DEDENT | NAMESPACE | BAR | LATTR | DOC_OPEN | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE) soupItem* (NEWLINE BAR soupItem*)*
    ;

// A let, with the and bindings of a let rec after it. An and is read here and not on its own, so
// an and that continues a type is never read as a binding.
letGroup
    : (functionDefinition | valueDefinition) (NEWLINE (andFunctionDefinition | andValueDefinition))*
    ;

// A let binding with parameters.
functionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault leadingAttributes? LET REC? functionBinding # function
    ;

// A let binding without parameters.
valueDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? LET REC? valueBinding # value
    ;

andFunctionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault AND functionBinding # function
    ;

andValueDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) AND valueBinding # value
    ;

// A function's parameters may follow on lines indented below its name, with the body at their
// column after the equals sign.
functionBinding
    : attributes? bindingModifier* access? bindingModifier* (
        functionHead returnType? EQUALS soupItem* matchArms?
        | what = bindingName typeParameters? argumentPattern* (INDENT block DEDENT)+ matchArms?
    )
    ;

valueBinding
    : attributes? bindingModifier* access? bindingModifier* valueHead returnType? EQUALS soupItem* matchArms?
    ;

// The arms of a function or match that F# lets start at the column of the binding they end.
matchArms
    : (NEWLINE BAR soupItem*)+
    ;

bindingModifier
    : INLINE
    | MUTABLE
    ;

functionHead
    : what = bindingName typeParameters? argumentPattern+
    ;

valueHead
    : what = bindingName typeParameters? (COMMA bindingName)*
    ;

bindingName
    : identifier
    | group
    | MULTIPLY_NAME
    ;

argumentPattern
    : identifier
    | group
    | NUMBER
    | STRING
    | CHAR
    | SYMBOLIC_OPERATOR identifier
    ;

returnType
    : COLON ~(EQUALS | NEWLINE | INDENT | DEDENT)+
    ;

typeParameters
    : LESS (typeParameters | ~(LESS | GREATER | EQUALS | NEWLINE | INDENT | DEDENT))* GREATER
    ;

// A val declaration, as signature files and explicit fields have.
valDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? STATIC? VAL MUTABLE? INLINE? access? what = bindingName typeParameters? COLON soupItem+ # val
    ;

exceptionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault leadingAttributes? EXCEPTION access? what = identifier (OF soupItem+ | EQUALS soupItem+)? (NEWLINE? withMembers)? # exception
    ;

// Type definitions, one rule per kind of type, tried in this order: a record, an enum, a union, a
// delegate, an interface (only abstract members, no constructor), a class, an extension of an
// existing type, an abbreviation, and a type with no representation such as a unit of measure.
typeDefinition
    : recordType
    | enumType
    | unionType
    | delegateType
    | interfaceType
    | classType
    | typeExtension
    | abbreviationType
    | abstractType
    ;

// A type's parameters may come before its name, ML style, as in type 'a Tree.
typeHead
    : leadingAttributes? (TYPE | AND) attributes? access? (TYPE_PARAMETER | group)? typeName typeParameters?
    ;

// A head whose name is on the line below type or and, indented; the type's rule closes the block.
splitTypeHead
    : leadingAttributes? (TYPE | AND) attributes? INDENT leadingAttributes? access? (TYPE_PARAMETER | group)? typeName typeParameters?
    ;

typeName
    : what = longIdentifier
    ;

recordType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead EQUALS recordRepresentation # record
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault splitTypeHead EQUALS recordRepresentation DEDENT # record
    ;

recordRepresentation
    : recordBody (NEWLINE? withMembers)?
    | INDENT recordBody (NEWLINE? withMembers | NEWLINE classMembers)? DEDENT
    ;

recordBody
    : (access NEWLINE?)? LBRACE BRNL* recordField ((SEMI | BRNL)+ recordField)* (SEMI | BRNL)* RBRACE
    ;

recordField
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) fieldAttributes? STATIC? MUTABLE? access? what = identifier COLON fieldType # field
    ;

fieldAttributes
    : (attributes BRNL*)+
    ;

// A field's type may continue on lines that start with an arrow or a star.
fieldType
    : fieldTypeItem+ (BRNL+ (SYMBOLIC_OPERATOR | STAR) fieldTypeItem*)*
    ;

fieldTypeItem
    : group
    | ~(SEMI | BRNL | RBRACE | LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | LBRACKBAR | BARRBRACK | LBRACEBAR | BARRBRACE | LATTR | RATTR)
    ;

enumType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead EQUALS (enumBody | INDENT enumBody (NEWLINE classMembers)? DEDENT | NEWLINE enumBody) # enum
    ;

// canon: a case's doc comment comes before its bar, so the bar is part of the case.
enumBody
    : enumCase (NEWLINE? barEnumCase)*
    ;

enumCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) BAR? attributes? what = identifier EQUALS ~(BAR | NEWLINE | INDENT | DEDENT)+ # case
    ;

barEnumCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) BAR attributes? what = identifier EQUALS ~(BAR | NEWLINE | INDENT | DEDENT)+ # case
    ;

unionType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead EQUALS unionRepresentation # union
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault splitTypeHead EQUALS unionRepresentation DEDENT # union
    ;

// A with that starts a line indented below the union's cases begins its members.
unionRepresentation
    : unionBody (NEWLINE? withMembers)?
    | unionBody INDENT withMembers DEDENT
    | INDENT unionBody (NEWLINE? withMembers | NEWLINE classMembers)? DEDENT
    | NEWLINE unionBody
    ;

// A union starts with a bar, has a case of some type, or has two cases, which tells it from an
// abbreviation.
// canon: a case's doc comment comes before its bar, so the bar is part of the case.
unionBody
    : (access NEWLINE?)? barUnionCase (NEWLINE? barUnionCase)*
    | (access NEWLINE?)? unionCase (NEWLINE? barUnionCase)+
    | (access NEWLINE?)? unionCaseOf
    ;

unionCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) attributes? what = identifier (OF caseFields)? # case
    ;

barUnionCase
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) BAR attributes? what = identifier (OF caseFields)? # case
    ;

// A lone case without a bar, which must have fields to be a union.
unionCaseOf
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) attributes? what = identifier OF caseFields # case
    ;

// A case's fields may continue on lines indented below it, as a multi-line anonymous record does,
// but an indented line that starts with with begins the union's members.
caseFields
    : (~(BAR | NEWLINE | INDENT | DEDENT | WITH) | INDENT caseFieldLines DEDENT)+
    ;

caseFieldLines
    : ~(WITH | NEWLINE | INDENT | DEDENT) soupItem* (NEWLINE blockLine)*
    ;

delegateType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead EQUALS (DELEGATE OF soupItem+ | INDENT DELEGATE OF soupItem+ DEDENT) # delegate
    ;

interfaceType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead EQUALS (
        INDENT interfaceElement (NEWLINE interfaceElement)* DEDENT
        | interfaceBlock
        | INDENT interfaceBlock DEDENT
    ) # interface
    ;

interfaceBlock
    : INTERFACE (INDENT interfaceElement (NEWLINE interfaceElement)* DEDENT NEWLINE?)? END
    ;

interfaceElement
    : abstractMemberDefinition
    | INHERIT soupItem+
    | INTERFACE soupItem+
    ;

// A class's body is indented below it, or is one member on its line; its primary constructor, or
// the equals sign after it, may be on the line below its name, with the members at that column.
classType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead primaryConstructor? (AS identifier)? EQUALS (
        INDENT classMembers DEDENT
        | classBlock
        | INDENT classBlock DEDENT
        | sameLineClassMember
    ) # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead INDENT primaryConstructor (AS identifier)? NEWLINE? EQUALS NEWLINE classMembers DEDENT # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault typeHead primaryConstructor? (AS identifier)? INDENT EQUALS NEWLINE classMembers DEDENT # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault splitTypeHead primaryConstructor? (AS identifier)? EQUALS (NEWLINE classMembers | INDENT classMembers DEDENT) DEDENT # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault splitTypeHead INDENT primaryConstructor (AS identifier)? EQUALS DEDENT NEWLINE classMembers DEDENT # class
    ;

// The one member a class may have on the line of its name, which must say it is a member, so a
// parenthesized abbreviation is not taken for a class.
sameLineClassMember
    : memberDefinition
    | abstractMemberDefinition
    | valDeclaration
    | INHERIT soupItem+
    ;

classBlock
    : (CLASS | STRUCT) (INDENT classMembers DEDENT NEWLINE? | classMember)? END
    ;

// The constructor's access is not the type's, so it is not the access rule.
primaryConstructor
    : attributes? (PUBLIC | PRIVATE | INTERNAL)? NEWLINE? group
    ;

typeExtension
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) typeHead WITH (INDENT classMembers DEDENT | classMember) (NEWLINE? END)? # extension
    ;

abbreviationType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) typeHead EQUALS soupItem+ # abbreviation
    ;

abstractType
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) typeHead # type
    ;

withMembers
    : WITH (INDENT classMembers DEDENT | classMember)? (NEWLINE? END)?
    ;

classMembers
    : classMember (NEWLINE classMember)*
    ;

classMember
    : memberDefinition
    | abstractMemberDefinition
    | constructorDefinition
    | valDeclaration
    | localLetGroup
    | interfaceImplementation
    | otherClassMember
    ;

// A member, override, or default implementation, or an auto-property; the rest of the line and
// the block below it are its parameters and body.
memberDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault leadingAttributes? memberKeyword access? INLINE? access? memberHead memberRest? matchArms? # member
    ;

memberKeyword
    : STATIC? MEMBER VAL?
    | OVERRIDE VAL?
    | DEFAULT
    ;

abstractMemberDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = publicByDefault leadingAttributes? STATIC? ABSTRACT MEMBER? access? memberHead memberRest? # member
    ;

memberHead
    : (identifier DOT)? what = memberName
    ;

memberName
    : identifier
    | group
    | MULTIPLY_NAME
    ;

memberRest
    : (~(DOT | NEWLINE | INDENT | DEDENT) | INDENT block DEDENT) soupItem*
    ;

constructorDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? access? what = NEW soupItem* # constructor
    ;

// Let bindings in a class, and in the body of a function, member, or expression, are private to it,
// so they are rules of their own, and so are the and bindings that follow them.
localLetGroup
    : (localFunctionDefinition | localValueDefinition) (NEWLINE (localAndFunctionDefinition | localAndValueDefinition))*
    ;

localAndFunctionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) AND functionBinding # function
    ;

localAndValueDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) AND valueBinding # value
    ;

localFunctionDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? STATIC? LET REC? functionBinding # function
    ;

localValueDefinition
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) leadingAttributes? STATIC? LET REC? valueBinding # value
    ;

interfaceImplementation
    : INTERFACE ~(WITH | NEWLINE | INDENT | DEDENT)+ (WITH (INDENT classMembers DEDENT | classMember)? (NEWLINE? END)?)?
    ;

otherClassMember
    : leadingAttributes? (orphan = canonicalComment)* ~(NEWLINE | INDENT | DEDENT | BAR | LATTR | END | DOC_OPEN | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE) soupItem*
    ;

// Private and internal are labeled optional, so a comment is required only on what is public.
access
    : PUBLIC
    | optional = PRIVATE
    | optional = INTERNAL
    ;

// canon: a doc comment after a declaration's attributes binds to nothing, as F# warns.
leadingAttributes
    : (attributes NEWLINE? (orphan = canonicalComment)*)+
    ;

attributes
    : attributeList+
    ;

// Each attribute is labeled marker, so canon can tell a test by its attribute.
attributeList
    : LATTR BRNL* marker = attribute (BRNL* SEMI BRNL* marker = attribute)* (BRNL* SEMI)? BRNL* RATTR
    ;

// An attribute's argument is in parentheses, or is a lone constant as in [<Obsolete "...">].
attribute
    : (identifier COLON)? longIdentifier typeParameters? (group | STRING | NUMBER)?
    ;

longIdentifier
    : identifier (DOT identifier)*
    ;

identifier
    : IDENTIFIER
    | BACKTICK_IDENTIFIER
    | GLOBAL
    ;

// A run of tokens on one logical line, with the blocks indented below it.
// canon: a doc comment inside an expression binds to nothing.
soupItem
    : orphan = canonicalComment
    | ~(NEWLINE | INDENT | DEDENT | DOC_OPEN | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    | INDENT block DEDENT
    ;

// The lines of a block. A line that starts a let is a local binding, so its doc comment binds.
block
    : blockLine (NEWLINE blockLine)*
    ;

blockLine
    : localLetGroup
    | soupItem+
    ;

// Balanced brackets and what they hold.
group
    : LPAREN groupItem* RPAREN
    | LBRACK groupItem* RBRACK
    | LBRACE groupItem* RBRACE
    | LBRACKBAR groupItem* BARRBRACK
    | LBRACEBAR groupItem* BARRBRACE
    | LATTR groupItem* RATTR
    ;

groupItem
    : orphan = canonicalComment
    | group
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | LBRACKBAR | BARRBRACK | LBRACEBAR | BARRBRACE | LATTR | RATTR | DOC_OPEN | DOC_WORD | DOC_PUNCT | DOC_REF | DOC_LICENSE)
    ;

// canon: an F# declaration is public unless it says otherwise, so the declarations a file exports
// hold this empty rule, labeled required; private and internal are labeled optional, which wins.
publicByDefault
    :
    ;

// canon: a canonical comment, a /// doc comment, holding prose, reference citations, and license
// citations.
canonicalComment
    : DOC_OPEN docPart*
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
