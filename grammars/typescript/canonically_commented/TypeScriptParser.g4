/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 by Bart Kiers (original author) and Alexandre Vitorelli (contributor -> ported to CSharp)
 * Copyright (c) 2017 by Ivan Kochurkin (Positive Technologies):
    added ECMAScript 6 support, cleared and transformed to the universal grammar.
 * Copyright (c) 2018 by Juan Alvarez (contributor -> ported to Go)
 * Copyright (c) 2019 by Andrii Artiushok (contributor -> added TypeScript support)
 * Copyright (c) 2024 by Andrew Leppard (www.wegrok.review)
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar TypeScriptParser;

// canon: the canonically commented dialect of the TypeScript grammar. TSDoc comments are canonical
// comments on the default channel; each declaration a TSDoc comment documents is a labeled unit
// alternative with its Why, its What, and where it differs from the whole node its How; a TSDoc
// comment the grammar accepts but binds to nothing is an orphan. Every change from the plain grammar
// is marked canon: and listed in grammars/typescript/README.md.

// canon: a doc comment may stand between any two tokens; where the grammar does not accept one,
// canon reads the file without it and reports it as an orphan, as the strayComment option says.
// ref:DEC-stray-comments
options {
    tokenVocab = TypeScriptLexer;
    superClass = TypeScriptParserBase;
    strayComment = canonicalComment;
}

// SupportSyntax

initializer
    : '=' singleExpression
    ;

bindingPattern
    : (arrayLiteral | objectLiteral)
    ;

// TypeScript SPart
// A.1 Types
typeParameters
    : '<' typeParameterList? '>'
    ;

typeParameterList
    : typeParameter (',' typeParameter)*
    ;

typeParameter
    : identifier constraint?
    | identifier '=' typeArgument
    | typeParameters
    ;

constraint
    : 'extends' type_
    ;

typeArguments
    : '<' typeArgumentList? '>'
    ;

typeArgumentList
    : typeArgument (',' typeArgument)*
    ;

typeArgument
    : type_
    ;

// Union and intersection types can have a leading '|' or '&'
// See https://github.com/microsoft/TypeScript/pull/12386
type_
    : ('|' | '&')? unionOrIntersectionOrPrimaryType Extends type_ '?' type_ ':' type_ // canon: conditional types
    | ('|' | '&')? unionOrIntersectionOrPrimaryType
    | functionType
    | constructorType
    | typeGeneric
    ;

unionOrIntersectionOrPrimaryType
    : unionOrIntersectionOrPrimaryType '|' unionOrIntersectionOrPrimaryType # Union
    | unionOrIntersectionOrPrimaryType '&' unionOrIntersectionOrPrimaryType # Intersection
    | primaryType                                                           # Primary
    ;

primaryType
    : '(' type_ ')'                              # ParenthesizedPrimType
    | predefinedType                             # PredefinedPrimType
    | typeReference                              # ReferencePrimType
    | objectType                                 # ObjectPrimType
    | primaryType {this.notLineTerminator()}? (orphan = canonicalComment)* '[' primaryType? ']' # ArrayPrimType // canon: a TSDoc comment before [ binds to nothing
    | '[' tupleElementTypes ']'                  # TuplePrimType
    | typeQuery                                  # QueryPrimType
    | This                                       # ThisPrimType
    | typeReference Is primaryType               # RedefinitionOfType
    | KeyOf primaryType                          # KeyOfType
    | Infer identifier                           # InferType // canon: infer U in a conditional type
    | ReadOnly primaryType                       # ReadonlyType // canon: readonly T[]
    | templateStringLiteral                      # TemplateLiteralPrimType // canon: a template literal type, as `pre-${string}`
    ;

predefinedType
    : Any
    | NullLiteral
    | Number
    | DecimalLiteral
    | Boolean
    | BooleanLiteral
    | String
    | StringLiteral
    | Unique? Symbol
    | Never
    | Undefined
    | Object
    | Void
    ;

typeReference
    : typeName typeGeneric?
    ;

typeGeneric
    : '<' typeArgumentList typeGeneric?'>'
    ;

typeName
    : identifier
    | namespaceName
    ;

// canon: a TSDoc comment after the last member binds to nothing.
objectType
    : '{' typeBody? (orphan = canonicalComment)* '}'
    ;

typeBody
    : typeMemberList (SemiColon | ',')?
    ;

typeMemberList
    : typeMember ((SemiColon | ',') typeMember)*
    ;

// canon: each member of an object type is a unit, a property or method named by its name and a
// call, construct, or index signature by its position; a mapped type's member is none.
typeMember
    : (orphan = canonicalComment)* mappedTypeMember // canon: { [P in keyof T]: T[P] } with its modifiers
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) propertySignatur # property
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) ordinal = callSignature # call
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) ordinal = constructSignature # new
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) ordinal = indexSignature # index
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) methodSignature ('=>' type_)? # method
    ;

arrayType
    : primaryType {this.notLineTerminator()}? (orphan = canonicalComment)* '[' ']' // canon: a TSDoc comment before [ binds to nothing
    ;

tupleType
    : '[' tupleElementTypes ']'
    ;

// Tuples can have a trailing comma. See https://github.com/Microsoft/TypeScript/issues/28893
tupleElementTypes
    : type_ (',' type_)* ','?
    ;

functionType
    : typeParameters? '(' parameterList? ')' '=>' type_
    ;

constructorType
    : 'new' typeParameters? '(' parameterList? ')' '=>' type_
    ;

typeQuery
    : 'typeof' typeQueryExpression
    ;

typeQueryExpression
    : identifier
    | (identifierName '.')+ identifierName
    ;

propertySignatur
    : ReadOnly? what = propertyName '?'? typeAnnotation? ('=>' type_)?
    ;

// canon: a mapped type's single member, with optional +/- readonly and ? modifiers.
mappedTypeMember
    : (('+' | '-')? ReadOnly)? '[' identifier In type_ ']' (('+' | '-')? '?')? typeAnnotation?
    ;

typeAnnotation
    : ':' type_
    ;

callSignature
    : typeParameters? '(' parameterList? ')' typeAnnotation?
    ;

// Function parameter list can have a trailing comma.
// See https://github.com/Microsoft/TypeScript/issues/16152
parameterList
    : restParameter
    | parameter (',' parameter)* (',' restParameter)? ','?
    ;

requiredParameterList
    : requiredParameter (',' requiredParameter)*
    ;

parameter
    : requiredParameter
    | optionalParameter
    ;

optionalParameter
    : decoratorList? (
        accessibilityModifier? identifierOrPattern (
            '?' typeAnnotation?
            | typeAnnotation? initializer
        )
    )
    ;

restParameter
    : '...' singleExpression typeAnnotation?
    ;

requiredParameter
    : decoratorList? accessibilityModifier? ReadOnly? identifierOrPattern typeAnnotation?
    ;

accessibilityModifier
    : Public
    | Private
    | Protected
    ;

identifierOrPattern
    : identifierName
    | bindingPattern
    ;

constructSignature
    : 'new' typeParameters? '(' parameterList? ')' typeAnnotation?
    ;

indexSignature
    : '[' identifier ':' (Number | String) ']' typeAnnotation
    ;

methodSignature
    : what = propertyName '?'? merge = callSignature
    ;

// canon: export is labeled required. The members of the object types on the right, alone or in a
// union or an intersection, are as exported as the alias, so the right side is labeled inherited.
typeAliasDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? Declare? 'type' what = identifier typeParameters? '=' inherited = type_ eos # type
    ;

// canon: a constructor is a unit; private and protected are labeled optional.
constructorDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (Public | optional = Private | optional = Protected)? what = Constructor merge = '(' formalParameterList? ')' (
        ('{' how = functionBody '}')
        | SemiColon
    )? # constructor
    ;

// A.5 Interface

// canon: export is labeled required, and the members of an interface are as exported as it is, so
// its body is labeled inherited.
interfaceDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? Declare? Interface what = identifier typeParameters? interfaceExtendsClause? inherited = objectType SemiColon? # interface
    ;

interfaceExtendsClause
    : Extends classOrInterfaceTypeList
    ;

classOrInterfaceTypeList
    : typeReference (',' typeReference)*
    ;

// A.7 Interface

// canon: export is labeled required, and an enum's members are as exported as it is, so its body
// is labeled inherited.
enumDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? Declare? Const? Enum what = identifier '{' inherited = enumBody? (orphan = canonicalComment)* '}' # enum
    ;

enumBody
    : enumMemberList ','?
    ;

enumMemberList
    : enumMember (',' enumMember)*
    ;

enumMember
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = propertyName ('=' singleExpression)? # member
    ;

// A.8 Namespaces

// canon: a namespace is a unit and its body is read as a module's, so its exported bindings are
// units; export is labeled required.
namespaceDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? Declare? Namespace what = namespaceName '{' moduleItem* (orphan = canonicalComment)* '}' # namespace
    ;

// canon: an ambient module declaration, a unit named by its string or name.
moduleDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? Declare? Module (MODULE_QUOTE what = MODULE_NAME MODULE_QUOTE | what = StringLiteral | what = namespaceName) '{' moduleItem* (orphan = canonicalComment)* '}' # module
    ;

namespaceName
    : identifier ('.'+ identifier)*
    ;

importAliasDeclaration
    : identifier '=' namespaceName SemiColon
    ;

// Ext.2 Additions to 1.8: Decorators

decoratorList
    : decorator+
    ;

decorator
    : '@' (decoratorMemberExpression | decoratorCallExpression)
    ;

decoratorMemberExpression
    : identifier
    | decoratorMemberExpression '.' identifierName
    | '(' singleExpression ')'
    ;

decoratorCallExpression
    : decoratorMemberExpression arguments
    ;

// ECMAPart
// canon: the first TSDoc comment of a file is the file's Why when a blank line or an import follows
// it, or when it holds a file tag such as @packageDocumentation, @module, or @license; otherwise it
// documents the declaration below it. A TSDoc comment at the end of a file binds to nothing.
program
    : HashBangLine? ( // canon: a hashbang line, as JavaScript reads it
        why = fileComment DOC_BLANK_LINE? importStatement
        | why = fileComment DOC_BLANK_LINE
        | why = taggedFileComment DOC_BLANK_LINE?
    )? moduleItem* (orphan = canonicalComment)* EOF
    ;

// canon: a statement at the top of a module or namespace, where a variable statement declares a
// binding the module may export, as other declarations do anywhere; export is labeled required.
moduleItem
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = Export (Declare varModifier? | varModifier) ReadOnly? what = identifierOrKeyWord typeAnnotation? '=' inherited = memberObject (
        As Const
        | As type_
        | {this.n("satisfies")}? identifier type_
    )? SemiColon? # variable // canon: an exported object literal's properties are units
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? (Declare varModifier? | varModifier) ReadOnly? declaredVariable (
        ',' variableDeclaration
    )* SemiColon? # variable
    | statement
    ;

// canon: the first binding of a variable statement, which names it.
declaredVariable
    : what = (identifierOrKeyWord | arrayLiteral | objectLiteral) typeAnnotation? singleExpression? (
        '=' typeParameters? singleExpression
    )?
    ;

sourceElement
    : Export? statement
    ;

// canon: declarations come first, so a TSDoc comment above one binds to it; a TSDoc comment above
// a local binding binds to nothing, and above any other statement, as anywhere else the grammar
// does not take one, it is a stray comment and an orphan.
statement
    : namespaceDeclaration //ADDED
    | moduleDeclaration // canon: declare module 'name' { ... }
    | classDeclaration
    | functionDeclaration
    | interfaceDeclaration //ADDED
    | typeAliasDeclaration //ADDED
    | enumDeclaration      //ADDED
    | exportStatement
    | block
    | variableStatement
    | (orphan = canonicalComment)+ varModifier ReadOnly? variableDeclarationList SemiColon? // canon: a TSDoc comment above a local binding binds to nothing
    | importStatement
    | emptyStatement_
    | abstractDeclaration //ADDED
    | ifStatement
    | iterationStatement
    | continueStatement
    | breakStatement
    | returnStatement
    | yieldStatement
    | withStatement
    | labelledStatement
    | switchStatement
    | throwStatement
    | tryStatement
    | debuggerStatement
    | arrowFunctionDeclaration
    | generatorFunctionDeclaration
    | Export statement
    | expressionStatement
    ;

// canon: a TSDoc comment after the last statement of a block binds to nothing.
block
    : '{' statementList? (orphan = canonicalComment)* '}'
    ;

statementList
    : statement+
    ;

abstractDeclaration
    : Abstract (identifier callSignature | variableStatement) eos
    ;

importStatement
    : Import (orphan = canonicalComment)* importFromBlock // canon: a TSDoc comment after import binds to nothing
    ;

// canon: import type and an inline type modifier, as in import type {A} and import {type A}, which
// the plain grammar reads as an expression, so a TSDoc comment above an import stays the file's Why.
importFromBlock
    : TypeAlias? importDefault? (importNamespace | importModuleItems) importFrom eos
    | StringLiteral eos
    ;

importModuleItems
    : '{' (importAliasName ',')* (importAliasName ','?)? '}'
    ;

importAliasName
    : TypeAlias? moduleExportName (As importedBinding)? // canon: import {type A}
    ;

moduleExportName
    : identifierName
    | StringLiteral
    ;

// yield and await are permitted as BindingIdentifier in the grammar
importedBinding
    : Identifier
    | Yield
    | Await
    ;

importDefault
    : aliasName ','
    ;

importNamespace
    : ('*' | identifierName) (As identifierName)?
    ;

importFrom
    : From StringLiteral
    ;

aliasName
    : identifierName (As identifierName)?
    ;

// canon: export default is a unit named default, and export is labeled required, since what a
// module exports is its API. An exported declaration holds its export keyword itself; a TSDoc
// comment above a list of exports binds to nothing.
exportStatement
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = Export what = Default inherited = memberObject eos # export // canon: an exported object literal's properties are units
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = Export what = Default (orphan = canonicalComment)* singleExpression eos # export
    | (orphan = canonicalComment)* Export Default? (exportFromBlock | declaration) eos # ExportDeclaration
    ;

// canon: export type, as in export type {A} from, and an inline type modifier, as in export {type A}.
exportFromBlock
    : TypeAlias? importNamespace importFrom eos
    | TypeAlias? exportModuleItems importFrom? eos
    ;

exportModuleItems
    : '{' (exportAliasName ',')* (exportAliasName ','?)? '}'
    ;

exportAliasName
    : TypeAlias? moduleExportName (As moduleExportName)? // canon: export {type A}
    ;

declaration
    : variableStatement
    | classDeclaration
    | functionDeclaration
    ;

variableStatement
    : bindingPattern typeAnnotation? initializer SemiColon?
    | accessibilityModifier? varModifier? ReadOnly? variableDeclarationList SemiColon?
    | Declare varModifier? variableDeclarationList SemiColon?
    ;

variableDeclarationList
    : variableDeclaration (',' variableDeclaration)*
    ;

variableDeclaration
    : (identifierOrKeyWord | arrayLiteral | objectLiteral) typeAnnotation? singleExpression? (
        '=' typeParameters? singleExpression
    )? // ECMAScript 6: Array & Object Matching
    ;

emptyStatement_
    : SemiColon
    ;

expressionStatement
    : {this.notOpenBraceAndNotFunctionAndNotInterface()}? expressionSequence SemiColon?
    ;

ifStatement
    : If '(' expressionSequence ')' statement (Else statement)?
    ;

iterationStatement
    : Do statement While '(' expressionSequence ')' eos                                                                     # DoStatement
    | While '(' expressionSequence ')' statement                                                                            # WhileStatement
    | For '(' expressionSequence? SemiColon expressionSequence? SemiColon expressionSequence? ')' statement                 # ForStatement
    | For '(' varModifier variableDeclarationList SemiColon expressionSequence? SemiColon expressionSequence? ')' statement # ForVarStatement
    | For '(' singleExpression In expressionSequence ')' statement                                                          # ForInStatement
    | For '(' varModifier variableDeclaration In expressionSequence ')' statement                                           # ForVarInStatement
    | For Await? '(' singleExpression identifier {this.p("of")}? expressionSequence (As type_)? ')' statement                            # ForOfStatement
    | For Await? '(' varModifier variableDeclaration identifier {this.p("of")}? expressionSequence (As type_)? ')' statement             # ForVarOfStatement
    ;

varModifier
    : Var
    | Let
    | Const
    ;

continueStatement
    : Continue ({this.notLineTerminator()}? identifier)? eos
    ;

breakStatement
    : Break ({this.notLineTerminator()}? identifier)? eos
    ;

returnStatement
    : Return ({this.notLineTerminator()}? expressionSequence)? eos
    ;

yieldStatement
    : (Yield | YieldStar) ({this.notLineTerminator()}? expressionSequence)? eos
    ;

withStatement
    : With '(' expressionSequence ')' statement
    ;

switchStatement
    : Switch '(' expressionSequence ')' caseBlock
    ;

// canon: a TSDoc comment before a case, a default, or the closing brace binds to nothing.
caseBlock
    : '{' caseClauses? (defaultClause caseClauses?)? (orphan = canonicalComment)* '}'
    ;

caseClauses
    : caseClause+
    ;

caseClause
    : (orphan = canonicalComment)* Case expressionSequence ':' statementList?
    ;

defaultClause
    : (orphan = canonicalComment)* Default ':' statementList?
    ;

labelledStatement
    : identifier ':' statement
    ;

throwStatement
    : Throw {this.notLineTerminator()}? expressionSequence eos
    ;

tryStatement
    : Try block (catchProduction finallyProduction? | finallyProduction)
    ;

catchProduction
    : Catch ('(' identifier typeAnnotation? ')')? block
    ;

finallyProduction
    : Finally block
    ;

debuggerStatement
    : Debugger eos
    ;

// canon: a function declaration is a unit wherever it stands, an overload included; export and
// export default are part of it, and export is labeled required.
functionDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export Default?)? Declare? Async? Function_ '*'? what = identifier merge = callSignature (
        ('{' how = functionBody '}')
        | SemiColon
    ) # function
    ;

//Ovveride ECMA
// canon: a class declaration is a unit wherever it stands, export labeled required; its members are
// as exported as it is, so its tail is labeled inherited.
classDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? (required = Export Default?)? Declare? Abstract? Class what = identifier typeParameters? classHeritage inherited = classTail # class
    ;

classHeritage
    : classExtendsClause? implementsClause?
    ;

// canon: a TSDoc comment after the last member binds to nothing.
classTail
    : '{' classElement* (orphan = canonicalComment)* '}'
    ;

classExtendsClause
    : Extends typeReference
    ;

implementsClause
    : Implements classOrInterfaceTypeList
    ;

// Classes modified
// canon: the decorators of a member are part of it, after its TSDoc comment.
classElement
    : constructorDeclaration
    | propertyMemberDeclaration
    | indexMemberDeclaration
    | statement
    ;

// canon: each property, method, and accessor is a unit; an accessor is named by get or set and its
// property, so a getter and setter pair are two units.
propertyMemberDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? propertyMemberBase what = classElementName '?'? typeAnnotation? initializer? SemiColon # property // canon: #private members
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? propertyMemberBase what = classElementName merge = callSignature (('{' how = functionBody '}') | SemiColon) # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? propertyMemberBase (classGetAccessor | classSetAccessor) # accessor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? propertyMemberBase Abstract what = classElementName merge = callSignature eos # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) decoratorList? propertyMemberBase Abstract ReadOnly? what = classElementName '?'? typeAnnotation? eos # property
    | (orphan = canonicalComment)* decoratorList? abstractDeclaration # AbstractMemberDeclaration
    ;

// canon: private and protected are labeled optional, since a member so marked is not exported.
propertyMemberBase
    : (Public | optional = Private | optional = Protected)? Async? Static? ReadOnly?
    ;

// canon: an index signature of a class is a unit named by its position.
indexMemberDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) ordinal = indexSignature SemiColon # index
    ;

generatorMethod
    : (Async {this.notLineTerminator()}?)? '*'? propertyName '(' formalParameterList? ')' '{' functionBody '}'
    ;

generatorFunctionDeclaration
    : Async? Function_ '*' identifier? '(' formalParameterList? ')' '{' functionBody '}'
    ;

generatorBlock
    : '{' generatorDefinition (',' generatorDefinition)* ','? '}'
    ;

generatorDefinition
    : '*' iteratorDefinition
    ;

iteratorBlock
    : '{' iteratorDefinition (',' iteratorDefinition)* ','? '}'
    ;

iteratorDefinition
    : '[' singleExpression ']' '(' formalParameterList? ')' '{' functionBody '}'
    ;

// canon: a #private name is labeled optional, since it is never exported.
classElementName
    : propertyName
    | optional = privateIdentifier
    ;

privateIdentifier
    : '#' identifierName
    ;

formalParameterList
    : formalParameterArg (',' formalParameterArg)* (',' lastFormalParameterArg)? ','?
    | lastFormalParameterArg
    | arrayLiteral                             // ECMAScript 6: Parameter Context Matching
    | objectLiteral (':' formalParameterList)? // ECMAScript 6: Parameter Context Matching
    ;

formalParameterArg
    : decorator? accessibilityModifier? ReadOnly? assignable '?'? typeAnnotation? ( // canon: readonly parameter properties
        '=' singleExpression
    )? // ECMAScript 6: Initialization
    ;

lastFormalParameterArg // ECMAScript 6: Rest Parameter
    : Ellipsis identifier typeAnnotation?
    ;

// canon: a TSDoc comment after the last statement of a body binds to nothing.
functionBody
    : sourceElements? (orphan = canonicalComment)*
    ;

sourceElements
    : sourceElement+
    ;

arrayLiteral
    : ('[' elementList ']')
    ;

// JavaScript supports arrasys like [,,1,2,,].
elementList
    : ','* arrayElement? (','+ arrayElement) * ','* // Yes, everything is optional
    ;

arrayElement // ECMAScript 6: Spread Operator
    : Ellipsis? (singleExpression | identifier) ','?
    ;

// canon: an object literal that an exported module-level binding or export default holds directly, whose
// properties, methods, and accessors are units, as the members of a class are; a property whose
// value is such an object literal holds units of its own. Its tail is labeled inherited where it
// is used, so what the module exports requires a comment down to these members.
memberObject
    : '{' (memberProperty (',' memberProperty)* ','?)? (orphan = canonicalComment)* '}'
    ;

memberProperty
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = propertyName ':' inherited = memberObject # property
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = propertyName ':' singleExpression # property
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (Async {this.notLineTerminator()}?)? '*'? what = propertyName '?'? callSignature '{' how = functionBody '}' # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = getter '(' ')' typeAnnotation? '{' how = functionBody '}' # accessor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = setter '(' formalParameterList? ')' '{' how = functionBody '}' # accessor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) what = identifierOrKeyWord # property
    | (orphan = canonicalComment)* Ellipsis singleExpression
    ;

// canon: any other object literal is an expression, so a TSDoc comment on one of its properties or
// after the last binds to nothing.
objectLiteral
    : '{' (propertyAssignment (',' propertyAssignment)* ','?)? (orphan = canonicalComment)* '}'
    ;

// MODIFIED
propertyAssignment
    : propertyName (':' | '=') singleExpression     # PropertyExpressionAssignment
    | {this.propertyAhead()}? (orphan = canonicalComment)+ propertyName ':' singleExpression # PropertyExpressionAssignment // canon: a TSDoc comment before a property binds to nothing
    | '[' singleExpression ']' ':' singleExpression # ComputedPropertyExpressionAssignment
    | getAccessor                                   # PropertyGetter
    | setAccessor                                   # PropertySetter
    | generatorMethod                               # MethodProperty
    | identifierOrKeyWord                           # PropertyShorthand
    | Ellipsis? singleExpression                    # SpreadOperator
    | restParameter                                 # RestParameterInObject
    ;

getAccessor
    : getter '(' ')' typeAnnotation? '{' functionBody '}'
    ;

setAccessor
    : setter '(' formalParameterList? ')' '{' functionBody '}'
    ;

// canon: getAccessor and setAccessor in a class, where the accessor is named by get or set and its
// property.
classGetAccessor
    : what = getter '(' ')' typeAnnotation? '{' how = functionBody '}'
    ;

classSetAccessor
    : what = setter '(' formalParameterList? ')' '{' how = functionBody '}'
    ;

propertyName
    : identifierName
    | StringLiteral
    | numericLiteral
    | '[' singleExpression ']'
    ;

arguments
    : '(' (argumentList ','?)? ')'
    ;

argumentList
    : argument (',' argument)*
    ;

argument // ECMAScript 6: Spread Operator
    : Ellipsis? (singleExpression | identifier)
    ;

expressionSequence
    : singleExpression (',' singleExpression)*
    ;

singleExpression
    : anonymousFunction                                           # FunctionExpression
    | Class identifier? typeParameters? classHeritage classTail   # ClassExpression
    | singleExpression '?.'? '[' expressionSequence ']'           # MemberIndexExpression
    | singleExpression '?.' singleExpression                      # OptionalChainExpression
    | singleExpression '?.' arguments                             # OptionalCallExpression // canon: f?.()
    | singleExpression '!'? '.' '#'? identifierName typeGeneric?  # MemberDotExpression
    | singleExpression '?'? '.' '#'? identifierName typeGeneric?  # MemberDotExpression
    // Split to try `new Date()` first, then `new Date`.
    | New singleExpression typeArguments? arguments                   # NewExpression
    | New singleExpression typeArguments?                             # NewExpression
    | singleExpression arguments                                      # ArgumentsExpression
    | singleExpression {this.notLineTerminator()}? '++'               # PostIncrementExpression
    | singleExpression {this.notLineTerminator()}? '--'               # PostDecreaseExpression
    | Delete singleExpression                                         # DeleteExpression
    | Void singleExpression                                           # VoidExpression
    | Typeof singleExpression                                         # TypeofExpression
    | '++' singleExpression                                           # PreIncrementExpression
    | '--' singleExpression                                           # PreDecreaseExpression
    | '+' singleExpression                                            # UnaryPlusExpression
    | '-' singleExpression                                            # UnaryMinusExpression
    | '~' singleExpression                                            # BitNotExpression
    | '!' singleExpression                                            # NotExpression
    | Await singleExpression                                          # AwaitExpression
    | <assoc = right> singleExpression '**' singleExpression          # PowerExpression
    | singleExpression ('*' | '/' | '%') singleExpression             # MultiplicativeExpression
    | singleExpression ('+' | '-') singleExpression                   # AdditiveExpression
    | singleExpression '??' singleExpression                          # CoalesceExpression
    | singleExpression ('<<' | '>' '>' | '>' '>' '>') singleExpression # BitShiftExpression
    | singleExpression ('<' | '>' | '<=' | '>=') singleExpression     # RelationalExpression
    | singleExpression Instanceof singleExpression                    # InstanceofExpression
    | singleExpression In singleExpression                            # InExpression
    | singleExpression ('==' | '!=' | '===' | '!==') singleExpression # EqualityExpression
    | singleExpression '&' singleExpression                           # BitAndExpression
    | singleExpression '^' singleExpression                           # BitXOrExpression
    | singleExpression '|' singleExpression                           # BitOrExpression
    | singleExpression '&&' singleExpression                          # LogicalAndExpression
    | singleExpression '||' singleExpression                          # LogicalOrExpression
    | singleExpression '?' singleExpression ':' singleExpression      # TernaryExpression
    | singleExpression '=' singleExpression                           # AssignmentExpression
    | singleExpression assignmentOperator singleExpression            # AssignmentOperatorExpression
    | singleExpression templateStringLiteral                          # TemplateStringExpression     // ECMAScript 6
    | iteratorBlock                                                   # IteratorsExpression          // ECMAScript 6
    | generatorBlock                                                  # GeneratorsExpression         // ECMAScript 6
    | generatorFunctionDeclaration                                    # GeneratorsFunctionExpression // ECMAScript 6
    | yieldStatement                                                  # YieldExpression              // ECMAScript 6
    | This                                                            # ThisExpression
    | identifierName singleExpression?                                # IdentifierExpression
    | Super                                                           # SuperExpression
    | literal                                                         # LiteralExpression
    | arrayLiteral                                                    # ArrayLiteralExpression
    | objectLiteral                                                   # ObjectLiteralExpression
    | '(' expressionSequence ')'                                      # ParenthesizedExpression
    | typeArguments expressionSequence?                               # GenericTypes
    | singleExpression As asExpression                                # CastAsExpression
// TypeScript v2.0
    | singleExpression '!'                                            # NonNullAssertionExpression
    ;

asExpression
    : type_ // canon: any type may follow `as`, including object types
    | predefinedType ('[' ']')?
    | singleExpression
    ;

assignable
    : identifier
    | keyword
    | arrayLiteral
    | objectLiteral
    ;

// canon: a named function expression is an expression, not a declaration, so it is no unit.
anonymousFunction
    : Async? Function_ '*'? identifier callSignature '{' functionBody '}'
    | Async? Function_ '*'? '(' formalParameterList? ')' typeAnnotation? '{' functionBody '}'
    | arrowFunctionDeclaration
    ;

arrowFunctionDeclaration
    : Async? arrowFunctionParameters typeAnnotation? '=>' arrowFunctionBody
    ;

arrowFunctionParameters
    : propertyName
    | '(' formalParameterList? ')'
    ;

arrowFunctionBody
    : singleExpression
    | '{' functionBody '}'
    ;

assignmentOperator
    : '*='
    | '/='
    | '%='
    | '+='
    | '-='
    | '<<='
    | '>>='
    | '>>>='
    | '&='
    | '^='
    | '|='
    | '**='
    | '??='
    | '||=' // canon: logical assignment
    | '&&='
    ;

literal
    : NullLiteral
    | BooleanLiteral
    | StringLiteral
    | templateStringLiteral
    | RegularExpressionLiteral
    | numericLiteral
    | bigintLiteral
    ;

templateStringLiteral
    : BackTick templateStringAtom* BackTick
    ;

templateStringAtom
    : TemplateStringAtom
    | TemplateStringStartExpression singleExpression TemplateCloseBrace
    | TemplateStringEscapeAtom
    ;

numericLiteral
    : DecimalLiteral
    | HexIntegerLiteral
    | OctalIntegerLiteral
    | OctalIntegerLiteral2
    | BinaryIntegerLiteral
    ;

bigintLiteral
    : BigDecimalIntegerLiteral
    | BigHexIntegerLiteral
    | BigOctalIntegerLiteral
    | BigBinaryIntegerLiteral
    ;

getter
    : {this.n("get")}? identifier classElementName
    ;

setter
    : {this.n("set")}? identifier classElementName
    ;

identifierName
    : identifier
    | reservedWord
    ;

identifier
    : Identifier
    | Async
    | As
    | From
    | Yield
    | Of
    | Any
    | Any
    | Number
    | Boolean
    | String
    | Unique
    | Symbol
    | Never
    | Undefined
    | Object
    | KeyOf
    | TypeAlias
    | Constructor
    | Namespace
    | Abstract
    ;

identifierOrKeyWord
    : identifier
    | TypeAlias
    | Require
    ;

reservedWord
    : keyword
    | NullLiteral
    | BooleanLiteral
    ;

keyword
    : Break
    | Do
    | Instanceof
    | Typeof
    | Case
    | Else
    | New
    | Var
    | Catch
    | Finally
    | Return
    | Void
    | Continue
    | For
    | Switch
    | While
    | Debugger
    | Function_
    | This
    | With
    | Default
    | If
    | Throw
    | Delete
    | In
    | Try
    | Class
    | Enum
    | Extends
    | Super
    | Const
    | Export
    | Import
    | Implements
    | Let
    | Private
    | Public
    | Interface
    | Package
    | Protected
    | Static
    | Yield
    | Async
    | Await
    | ReadOnly
    | Is // canon: `is` is a property name too, as in t.is(...)
    | Infer
    | From
    | As
    | Require
    | TypeAlias
    | String
    | Boolean
    | Number
    | Module
    ;

eos
    : SemiColon
    | EOF
    | {this.lineTerminatorAhead()}?
    | {this.closeBrace()}?
    ;

// canon: a canonical comment, a TSDoc block, holding prose, reference citations, and license
// citations. The first TSDoc comment of a file may document the declaration below it.
canonicalComment
    : DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    | FILE_DOC_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: the first TSDoc comment of a file, when it may be the file's Why.
fileComment
    : FILE_DOC_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: the first TSDoc comment of a file holding a file tag, which is always the file's Why.
taggedFileComment
    : FILE_DOC_OPEN docPart* DOC_FILE_TAG (docPart | DOC_FILE_TAG)* DOC_BLOCK_CLOSE
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
