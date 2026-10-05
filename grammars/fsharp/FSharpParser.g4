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
        // canon: corpus, a return type on the line below the parameters, indented, with the body
        // left of it.
        | functionHead COLON INDENT ~(EQUALS | NEWLINE | INDENT | DEDENT)+ EQUALS DEDENT INDENT block DEDENT matchArms?
    )
    ;

// canon: corpus, the equals sign may start the line below a value's return type.
valueBinding
    : attributes? bindingModifier* access? bindingModifier* valueHead returnType? EQUALS soupItem* matchArms?
    | attributes? bindingModifier* access? bindingModifier* valueHead returnType INDENT EQUALS soupItem* DEDENT
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

// canon: corpus, each name of a tuple binding may say its own access, as in
// let private get, _, public set = ..., and the whole may be named, as in let (a, b) as t = ...
valueHead
    : bindingName typeParameters? (COMMA access? bindingName)* (AS identifier)?
    ;

// canon: corpus, a value may bind a struct tuple, as in let struct (a, b) = f ().
bindingName
    : identifier
    | group
    | MULTIPLY_NAME
    | STRUCT group
    ;

argumentPattern
    : identifier
    | group
    | NUMBER
    | STRING
    | CHAR
    | SYMBOLIC_OPERATOR identifier
    // canon: corpus, a struct tuple pattern, as in let inline vFst struct (a, _) = a.
    | STRUCT group
    ;

returnType
    : COLON ~(EQUALS | NEWLINE | INDENT | DEDENT)+
    ;

// canon: corpus, a constraint's member signature in parentheses may hold an equals sign or an
// angle bracket, as in NonStructural<'T when 'T: (static member (=): 'T * 'T -> bool)>.
typeParameters
    : LESS (typeParameters | group | ~(LESS | GREATER | EQUALS | NEWLINE | INDENT | DEDENT | LPAREN | RPAREN))* GREATER
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
// canon: corpus, a type's constraints may follow its parameters, as in type S<'T> when 'T: comparison.
typeHead
    : leadingAttributes? (TYPE | AND) attributes? access? (TYPE_PARAMETER | group)? typeName typeParameters? typeConstraints?
    ;

typeConstraints
    : WHEN (group | ~(EQUALS | NEWLINE | INDENT | DEDENT | WITH | LPAREN | RPAREN))+
    ;

// A head whose name is on the line below type or and, indented; the type's rule closes the block.
splitTypeHead
    : leadingAttributes? (TYPE | AND) attributes? INDENT leadingAttributes? access? (TYPE_PARAMETER | group)? typeName typeParameters? typeConstraints?
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
    // canon: corpus, the equals sign may start the line below the name, with the cases after it.
    | typeHead INDENT EQUALS unionBody (NEWLINE? withMembers)? DEDENT
    ;

// A with that starts a line indented below the union's cases begins its members.
unionRepresentation
    : unionBody (NEWLINE? withMembers)?
    | unionBody INDENT withMembers DEDENT
    | INDENT unionBody (NEWLINE? withMembers | NEWLINE classMembers)? DEDENT
    // canon: corpus, cases at the column of type may be followed by indented members without a with.
    | NEWLINE unionBody (INDENT classMembers DEDENT)?
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

// A case's fields may continue on lines indented below it, as a multi-line anonymous record does,
// but an indented line that starts with with begins the union's members.
caseFields
    : (~(BAR | NEWLINE | INDENT | DEDENT | WITH) | INDENT caseFieldLines DEDENT)+
    ;

caseFieldLines
    : ~(WITH | NEWLINE | INDENT | DEDENT) soupItem* (NEWLINE blockLine)*
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
    : INTERFACE (INDENT interfaceElement (NEWLINE interfaceElement)* DEDENT)? NEWLINE? END
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
        // canon: corpus, members after a class ... end, in a with at the class's column.
        | INDENT classBlock NEWLINE withMembers DEDENT
        | sameLineClassMember
    )
    // canon: corpus, a body of class ... end at the column of the equals sign, as Fantomas lays out a
    // long primary constructor.
    | typeHead INDENT primaryConstructor (AS identifier)? NEWLINE? EQUALS NEWLINE (classMembers | classBlock) DEDENT
    | typeHead primaryConstructor? (AS identifier)? INDENT EQUALS NEWLINE (classMembers | classBlock) DEDENT
    | splitTypeHead primaryConstructor? (AS identifier)? EQUALS (NEWLINE classMembers | INDENT classMembers DEDENT) DEDENT
    | splitTypeHead INDENT primaryConstructor (AS identifier)? EQUALS DEDENT NEWLINE classMembers DEDENT
    // canon: corpus, a primary constructor indented below the name with the members left of it, and
    // an equals sign on a line of its own with the members indented further.
    | typeHead INDENT primaryConstructor (AS identifier)? EQUALS DEDENT INDENT classMembers DEDENT
    | typeHead primaryConstructor? (AS identifier)? INDENT EQUALS INDENT classMembers DEDENT DEDENT
    ;

// The one member a class may have on the line of its name, which must say it is a member, so a
// parenthesized abbreviation is not taken for a class.
sameLineClassMember
    : memberDefinition
    | abstractMemberDefinition
    | valDeclaration
    | INHERIT soupItem+
    ;

// canon: corpus, an empty class or interface may close with end on the line below.
classBlock
    : (CLASS | STRUCT) (INDENT classMembers DEDENT | classMember)? NEWLINE? END
    // canon: corpus, class on the line of the equals sign, with end at the column of the members.
    | (CLASS | STRUCT) INDENT classMembers NEWLINE END DEDENT
    ;

// The constructor's access is not the type's, so it is not the access rule.
primaryConstructor
    : attributes? (PUBLIC | PRIVATE | INTERNAL)? NEWLINE? group
    ;

typeExtension
    : typeHead WITH (INDENT classMembers DEDENT | classMember) (NEWLINE? END)?
    ;

// canon: corpus, the name of an abbreviation may be on the line below and, after its attributes.
abbreviationType
    : typeHead EQUALS soupItem+
    | splitTypeHead EQUALS soupItem+ DEDENT
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

// canon: corpus, default val declares an auto-property, as override val does.
memberKeyword
    : STATIC? MEMBER VAL?
    | OVERRIDE VAL?
    | DEFAULT VAL?
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

// Let bindings in a class, and in the body of a function, member, or expression, are private to it,
// so they are rules of their own, and so are the and bindings that follow them.
localLetGroup
    : (localFunctionDefinition | localValueDefinition) (NEWLINE (localAndFunctionDefinition | localAndValueDefinition))*
    ;

localAndFunctionDefinition
    : AND functionBinding
    ;

localAndValueDefinition
    : AND valueBinding
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
// canon: corpus, a lone constant argument may also be a name, as in [<DefaultValue false>].
attribute
    : (identifier COLON)? longIdentifier typeParameters? (group | STRING | NUMBER | longIdentifier)?
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
    : group
    | ~(LPAREN | RPAREN | LBRACK | RBRACK | LBRACE | RBRACE | LBRACKBAR | BARRBRACK | LBRACEBAR | BARRBRACE | LATTR | RATTR)
    ;
