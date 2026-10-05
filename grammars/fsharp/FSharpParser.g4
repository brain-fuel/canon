// The F# parser canon reads F# with, written for canon because grammars-v4 has no F# grammar. It
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
file
    : (namespaceDeclaration (NEWLINE namespaceDeclaration)* | topModule | moduleElements)? EOF
    ;

// A namespace holds the declarations that follow it at its own column, or indented below it, up to
// the next namespace.
namespaceDeclaration
    : NAMESPACE REC? (GLOBAL | longIdentifier) (NEWLINE moduleElements | INDENT moduleElements DEDENT)?
    ;

// A top-level module holds the rest of the file.
topModule
    : leadingAttributes? MODULE access? REC? longIdentifier (NEWLINE moduleElements | INDENT moduleElements DEDENT)?
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
    : leadingAttributes? MODULE access? REC? identifier EQUALS (
        INDENT moduleElements DEDENT
        | BEGIN (INDENT moduleElements DEDENT NEWLINE? | moduleElements)? END
    )
    ;

moduleAbbreviation
    : MODULE identifier EQUALS longIdentifier
    ;

// An open, a do binding, an expression, or anything else that declares nothing, with the lines of
// a match that continue it at its own column.
otherModuleElement
    : leadingAttributes? ~(NEWLINE | INDENT | DEDENT | NAMESPACE | BAR | LATTR) soupItem* (NEWLINE BAR soupItem*)*
    ;

// A let, with the and bindings of a let rec after it. An and is read here and not on its own, so
// an and that continues a type is never read as a binding.
letGroup
    : (functionDefinition | valueDefinition) (NEWLINE (andFunctionDefinition | andValueDefinition))*
    ;

// A let binding with parameters.
functionDefinition
    : leadingAttributes? LET REC? functionBinding
    ;

// A let binding without parameters.
valueDefinition
    : leadingAttributes? LET REC? valueBinding
    ;

andFunctionDefinition
    : AND functionBinding
    ;

andValueDefinition
    : AND valueBinding
    ;

// A function's parameters may follow on lines indented below its name, with the body at their
// column after the equals sign.
functionBinding
    : attributes? bindingModifier* access? bindingModifier* (
        functionHead returnType? EQUALS soupItem* matchArms?
        | bindingName typeParameters? argumentPattern* (INDENT block DEDENT)+ matchArms?
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
    : bindingName typeParameters? argumentPattern+
    ;

valueHead
    : bindingName typeParameters? (COMMA bindingName)*
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
    : leadingAttributes? STATIC? VAL MUTABLE? INLINE? access? bindingName typeParameters? COLON soupItem+
    ;

exceptionDefinition
    : leadingAttributes? EXCEPTION access? identifier (OF soupItem+ | EQUALS soupItem+)? (NEWLINE? withMembers)?
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
    : longIdentifier
    ;

recordType
    : typeHead EQUALS recordRepresentation
    | splitTypeHead EQUALS recordRepresentation DEDENT
    ;

recordRepresentation
    : recordBody (NEWLINE? withMembers)?
    | INDENT recordBody (NEWLINE? withMembers | NEWLINE classMembers)? DEDENT
    ;

recordBody
    : (access NEWLINE?)? LBRACE BRNL* recordField ((SEMI | BRNL)+ recordField)* (SEMI | BRNL)* RBRACE
    ;

recordField
    : fieldAttributes? STATIC? MUTABLE? access? identifier COLON fieldType
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
    : typeHead EQUALS (enumBody | INDENT enumBody (NEWLINE classMembers)? DEDENT | NEWLINE enumBody)
    ;

enumBody
    : BAR? enumCase (NEWLINE? BAR enumCase)*
    ;

enumCase
    : attributes? identifier EQUALS ~(BAR | NEWLINE | INDENT | DEDENT)+
    ;

unionType
    : typeHead EQUALS unionRepresentation
    | splitTypeHead EQUALS unionRepresentation DEDENT
    ;

unionRepresentation
    : unionBody (NEWLINE? withMembers)?
    | INDENT unionBody (NEWLINE? withMembers | NEWLINE classMembers)? DEDENT
    | NEWLINE unionBody
    ;

// A union starts with a bar, has a case of some type, or has two cases, which tells it from an
// abbreviation.
unionBody
    : (access NEWLINE?)? BAR unionCase (NEWLINE? BAR unionCase)*
    | (access NEWLINE?)? unionCase (NEWLINE? BAR unionCase)+
    | (access NEWLINE?)? unionCaseOf
    ;

unionCase
    : attributes? identifier (OF caseFields)?
    ;

// A lone case without a bar, which must have fields to be a union.
unionCaseOf
    : attributes? identifier OF caseFields
    ;

caseFields
    : (~(BAR | NEWLINE | INDENT | DEDENT | WITH) | INDENT block DEDENT)+
    ;

delegateType
    : typeHead EQUALS (DELEGATE OF soupItem+ | INDENT DELEGATE OF soupItem+ DEDENT)
    ;

interfaceType
    : typeHead EQUALS (
        INDENT interfaceElement (NEWLINE interfaceElement)* DEDENT
        | interfaceBlock
        | INDENT interfaceBlock DEDENT
    )
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
    : typeHead primaryConstructor? (AS identifier)? EQUALS (
        INDENT classMembers DEDENT
        | classBlock
        | INDENT classBlock DEDENT
        | sameLineClassMember
    )
    | typeHead INDENT primaryConstructor (AS identifier)? NEWLINE? EQUALS NEWLINE classMembers DEDENT
    | typeHead primaryConstructor? (AS identifier)? INDENT EQUALS NEWLINE classMembers DEDENT
    | splitTypeHead primaryConstructor? (AS identifier)? EQUALS (NEWLINE classMembers | INDENT classMembers DEDENT) DEDENT
    | splitTypeHead INDENT primaryConstructor (AS identifier)? EQUALS DEDENT NEWLINE classMembers DEDENT
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
    : typeHead WITH (INDENT classMembers DEDENT | classMember) (NEWLINE? END)?
    ;

abbreviationType
    : typeHead EQUALS soupItem+
    ;

abstractType
    : typeHead
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
    : leadingAttributes? memberKeyword access? INLINE? access? memberHead memberRest? matchArms?
    ;

memberKeyword
    : STATIC? MEMBER VAL?
    | OVERRIDE VAL?
    | DEFAULT
    ;

abstractMemberDefinition
    : leadingAttributes? STATIC? ABSTRACT MEMBER? access? memberHead memberRest?
    ;

memberHead
    : (identifier DOT)? memberName
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
    : leadingAttributes? access? NEW soupItem*
    ;

// Let bindings in a class are private to it, so they are rules of their own.
localLetGroup
    : (localFunctionDefinition | localValueDefinition) (NEWLINE (andFunctionDefinition | andValueDefinition))*
    ;

localFunctionDefinition
    : leadingAttributes? STATIC? LET REC? functionBinding
    ;

localValueDefinition
    : leadingAttributes? STATIC? LET REC? valueBinding
    ;

interfaceImplementation
    : INTERFACE ~(WITH | NEWLINE | INDENT | DEDENT)+ (WITH (INDENT classMembers DEDENT | classMember)? (NEWLINE? END)?)?
    ;

otherClassMember
    : leadingAttributes? ~(NEWLINE | INDENT | DEDENT | BAR | LATTR | END) soupItem*
    ;

// Private and internal are labeled optional, so a comment is required only on what is public.
access
    : PUBLIC
    | optional = PRIVATE
    | optional = INTERNAL
    ;

leadingAttributes
    : (attributes NEWLINE?)+
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
soupItem
    : ~(NEWLINE | INDENT | DEDENT)
    | INDENT block DEDENT
    ;

block
    : soupItem+ (NEWLINE soupItem+)*
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
    : group
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | LBRACKBAR | BARRBRACK | LBRACEBAR | BARRBRACE | LATTR | RATTR)
    ;
