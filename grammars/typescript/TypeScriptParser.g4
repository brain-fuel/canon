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

options {
    tokenVocab = TypeScriptLexer;
    superClass = TypeScriptParserBase;
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
    : typeParameter (',' typeParameter)* ','? // canon: a trailing comma
    ;

typeParameter
    : typeParameterModifier* ('+' | '-')? identifier (':' type_)? constraint? ('=' typeArgument)? // canon: const, in, and out modifiers, and a constraint with a default; Flow's variance and bound, as <+T: U>
    | typeParameters
    ;

// canon: the modifiers of a type parameter: const, and the variance annotations in and out.
typeParameterModifier
    : Const
    | In
    | {this.n("out")}? identifier
    ;

constraint
    : 'extends' type_
    ;

typeArguments
    : '<' typeArgumentList? '>'
    ;

typeArgumentList
    : typeArgument (',' typeArgument)* ','? // canon: a trailing comma
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
    | flowFunctionType // canon: Flow's function type, whose parameters may be unnamed
    | '?' (functionType | flowFunctionType) // canon: Flow's maybe function type, ?() => T
    | primaryType '=>' type_ // canon: Flow's function type of one unparenthesised parameter, T => U
    | constructorType
    | typeGeneric
    ;

// canon: a Flow function type, as (string, number) => void or (...Array<T>) => U, whose parameters
// are types, named or not.
flowFunctionType
    : typeParameters? '(' (flowFunctionParameter (',' flowFunctionParameter)* ','?)? ')' '=>' type_
    ;

flowFunctionParameter
    : '...'? (identifierName '?'? ':')? type_
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
    | primaryType {this.notLineTerminator()}? '[' type_? ']' # ArrayPrimType // canon: any type as the index
    | '[' tupleElementTypes? ']'                 # TuplePrimType // canon: the empty tuple []
    | typeQuery                                  # QueryPrimType
    | This                                       # ThisPrimType
    | typeReference Is type_                     # RedefinitionOfType // canon: any type after is
    | KeyOf primaryType                          # KeyOfType
    | Infer identifier (Extends type_)?          # InferType // canon: infer U, infer U extends C
    | This Is type_                              # ThisPredicateType // canon: this is T
    | ({this.n("asserts")}? identifier | {this.n("implies")}? identifier) (identifier | This) (Is type_)? # AssertsType // canon: asserts x, asserts x is T, and Flow's implies x is T
    | Import '(' StringLiteral ')' ('.' identifierName)* typeGeneric? # ImportType // canon: import("m").T
    | '-'? numericLiteral                        # NumericLiteralType // canon: 0xFF and -1 as types
    | '-'? bigintLiteral                         # BigIntLiteralType
    | ReadOnly primaryType                       # ReadonlyType // canon: readonly T[]
    | templateLiteralType                        # TemplateLiteralPrimType // canon: a template literal type
    | '?' primaryType                            # MaybeType // canon: Flow's maybe type, ?T
    | '*'                                        # ExistentialType // canon: Flow's existential type
    | '{' '|' typeBody? '|' '}'                  # ExactObjectType // canon: Flow's exact object type, {| a: T |}
    | '{' '||' '}'                               # EmptyExactObjectType
    | {this.n("component")}? identifier '(' (flowFunctionParameter (',' flowFunctionParameter)* ','?)? ')' ({this.n("renders")}? identifier type_)? # ComponentType // canon: Flow's component type, component(...props: P)
    | Interface (Extends classOrInterfaceTypeList)? objectType # InlineInterfaceType // canon: Flow's inline interface type
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
    : '<' typeArgumentList? typeGeneric?'>' // canon: Flow's empty type arguments, T<>
    ;

typeName
    : identifier
    | namespaceName
    ;

objectType
    : '{' typeBody? '}'
    ;

typeBody
    : typeMemberList (SemiColon | ',')?
    ;

typeMemberList
    : typeMember ((SemiColon | ',' | {this.lineTerminatorAhead()}?) typeMember)* // canon: a line break separates members too
    ;

typeMember
    : mappedTypeMember // canon: { [P in keyof T]: T[P] } with its modifiers
    | '...' type_? // canon: Flow's spread and inexact object types, {...A, b: T, ...}
    | accessorSignature // canon: get x(): T and set x(v: T)
    | propertySignatur
    | callSignature
    | constructSignature
    | indexSignature
    | methodSignature ('=>' type_)?
    ;

arrayType
    : primaryType {this.notLineTerminator()}? '[' ']'
    ;

tupleType
    : '[' tupleElementTypes ']'
    ;

// Tuples can have a trailing comma. See https://github.com/Microsoft/TypeScript/issues/28893
tupleElementTypes
    : tupleElement (',' tupleElement)* ','? // canon: named, optional, and rest elements
    ;

// canon: a tuple element: a type, optional with ?, named as in [name: string], or a rest element.
tupleElement
    : '...'? (identifierName '?'? ':')? type_ '?'?
    ;

functionType
    : typeParameters? '(' parameterList? ')' '=>' type_
    ;

constructorType
    : Abstract? 'new' typeParameters? '(' parameterList? ')' '=>' type_ // canon: abstract new
    ;

typeQuery
    : 'typeof' typeQueryExpression
    ;

typeQueryExpression
    : identifier
    | (identifierName '.')+ identifierName
    | Import '(' StringLiteral ')' ('.' identifierName)* // canon: typeof import("m")
    ;

propertySignatur
    : ('+' | '-')? ReadOnly? propertyName '?'? typeAnnotation? ('=>' type_)? // canon: Flow's variance, +x: T
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
        accessibilityModifier? ({this.n("override")}? identifier)? ReadOnly? identifierOrPattern ( // canon: readonly and override parameter properties
            '?' typeAnnotation? initializer? // canon: Flow's optional parameter with a default
            | typeAnnotation? initializer
        )
    )
    ;

restParameter
    : '...' singleExpression typeAnnotation?
    ;

requiredParameter
    : decoratorList? accessibilityModifier? ({this.n("override")}? identifier)? ReadOnly? identifierOrPattern typeAnnotation? // canon: override parameter properties
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
    : ('+' | '-')? ReadOnly? '[' (identifier ':')? type_ ']' typeAnnotation // canon: readonly, and any key type, as symbol or a union; Flow's unnamed key and variance
    ;

methodSignature
    : propertyName '?'? callSignature
    ;

typeAliasDeclaration
    : Export? Declare? ({this.n("opaque")}? identifier)? 'type' identifier typeParameters? (':' type_)? ('=' type_)? eos // canon: Flow's opaque type, declare opaque type, and supertype
    ;

constructorDeclaration
    : accessibilityModifier? Constructor '(' formalParameterList? ')' (
        ('{' functionBody '}')
        | SemiColon
    )?
    ;

// A.5 Interface

interfaceDeclaration
    : Export? Declare? Interface identifier typeParameters? interfaceExtendsClause? objectType SemiColon?
    ;

interfaceExtendsClause
    : Extends classOrInterfaceTypeList
    ;

classOrInterfaceTypeList
    : typeReference (',' typeReference)*
    ;

// A.7 Interface

enumDeclaration
    : Const? Enum identifier '{' enumBody? '}'
    ;

enumBody
    : enumMemberList ','?
    ;

enumMemberList
    : enumMember (',' enumMember)*
    ;

enumMember
    : propertyName ('=' singleExpression)?
    ;

// A.8 Namespaces

namespaceDeclaration
    : Declare? Namespace namespaceName '{' statementList? '}'
    ;

// canon: an ambient module declaration.
moduleDeclaration
    : Declare? Module (StringLiteral | namespaceName) '{' statementList? '}'
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
    : decoratorMemberExpression typeArguments? arguments // canon: @Decorator<T>(...)
    ;

// ECMAPart
program
    : HashBangLine? sourceElements? EOF // canon: a hashbang line
    ;

sourceElement
    : Export? statement
    ;

statement
    : block
    | namespaceDeclaration //ADDED
    | moduleDeclaration // canon: declare module 'name' { ... }
    | variableStatement
    | importStatement
    | exportStatement
    | emptyStatement_
    | abstractDeclaration //ADDED
    | classDeclaration
    | functionDeclaration
    | interfaceDeclaration //ADDED
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
    | typeAliasDeclaration //ADDED
    | enumDeclaration      //ADDED
    | Export statement
    | expressionStatement
    ;

block
    : '{' statementList? '}'
    ;

statementList
    : statement+
    ;

abstractDeclaration
    : Abstract (identifier callSignature | variableStatement) eos
    ;

importStatement
    : Import importFromBlock
    ;

importFromBlock
    : (TypeAlias | Typeof)? importDefault? (importNamespace | importModuleItems) importFrom eos // canon: import type and Flow's import typeof
    | StringLiteral eos
    ;

importModuleItems
    : '{' (importAliasName ',')* (importAliasName ','?)? '}'
    ;

importAliasName
    : (TypeAlias | Typeof)? moduleExportName (As importedBinding)? // canon: import {type A}, and Flow's import {typeof A}
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

exportStatement
    : Export Default? (exportFromBlock | declaration) eos # ExportDeclaration
    | Export Default singleExpression eos                 # ExportDefaultDeclaration
    ;

exportFromBlock
    : importNamespace importFrom eos
    | exportModuleItems importFrom? eos
    ;

exportModuleItems
    : '{' (exportAliasName ',')* (exportAliasName ','?)? '}'
    ;

exportAliasName
    : moduleExportName (As moduleExportName)?
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
    : (identifierOrKeyWord | arrayLiteral | objectLiteral) '!'? typeAnnotation? singleExpression? ( // canon: x!: T
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

caseBlock
    : '{' caseClauses? (defaultClause caseClauses?)? '}'
    ;

caseClauses
    : caseClause+
    ;

caseClause
    : Case expressionSequence ':' statementList?
    ;

defaultClause
    : Default ':' statementList?
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

functionDeclaration
    : Async? Function_ '*'? identifier callSignature (('{' functionBody '}') | eos) // canon: an overload signature a line break ends
    ;

//Ovveride ECMA
classDeclaration
    : decoratorList? (Export Default?)? Abstract? Class identifier typeParameters? classHeritage classTail
    ;

classHeritage
    : classExtendsClause? implementsClause?
    ;

classTail
    : '{' classElement* '}'
    ;

classExtendsClause
    : Extends typeReference
    | Extends singleExpression typeArguments? // canon: any expression, as extends mixin(A, B)
    ;

implementsClause
    : Implements classOrInterfaceTypeList
    ;

// Classes modified
classElement
    : constructorDeclaration
    | decoratorList? propertyMemberDeclaration
    | indexMemberDeclaration
    | statement
    ;

propertyMemberDeclaration
    : propertyMemberBase classElementName ('?' | '!')? typeAnnotation? initializer? eos        # PropertyDeclarationExpression // canon: #private members, x!: T
    | propertyMemberBase '*'? classElementName '?'? callSignature (('{' functionBody '}') | eos) # MethodDeclarationExpression // canon: generator and optional methods, and a signature a line break ends
    | propertyMemberBase (getAccessor | setAccessor)                                     # GetterSetterDeclarationExpression
    | abstractDeclaration                                                                # AbstractMemberDeclaration
    ;

propertyMemberBase
    : (accessibilityModifier | Async | Static | ReadOnly | Declare | Abstract | {this.n("override")}? identifier | {this.n("accessor")}? identifier | '+' | '-')* // canon: and Flow's variance // canon: modifiers in any order, declare, override, and accessor
    ;

indexMemberDeclaration
    : indexSignature SemiColon
    ;

generatorMethod
    : (Async {this.notLineTerminator()}?)? '*'? propertyName '?'? callSignature '{' functionBody '}' // canon: type parameters, typed parameters, and a return type
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

classElementName
    : propertyName
    | privateIdentifier
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
    : decorator? accessibilityModifier? ({this.n("override")}? identifier)? ReadOnly? assignable '?'? typeAnnotation? ( // canon: readonly and override parameter properties
        '=' singleExpression
    )? // ECMAScript 6: Initialization
    ;

lastFormalParameterArg // ECMAScript 6: Rest Parameter
    : Ellipsis identifier typeAnnotation?
    ;

functionBody
    : sourceElements?
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

objectLiteral
    : '{' (propertyAssignment (',' propertyAssignment)* ','?)? '}'
    ;

// MODIFIED
propertyAssignment
    : propertyName (':' | '=') singleExpression     # PropertyExpressionAssignment
    | '[' singleExpression ']' ':' singleExpression # ComputedPropertyExpressionAssignment
    | getAccessor                                   # PropertyGetter
    | setAccessor                                   # PropertySetter
    | generatorMethod                               # MethodProperty
    | identifierOrKeyWord                           # PropertyShorthand
    | Ellipsis? singleExpression                    # SpreadOperator
    | restParameter                                 # RestParameterInObject
    ;

getAccessor
    : getter '(' ')' typeAnnotation? ('{' functionBody '}')? // canon: an accessor without a body, abstract or declared
    ;

setAccessor
    : setter '(' formalParameterList? ')' ('{' functionBody '}')?
    ;

// canon: an accessor's signature in an interface or object type, get x(): T or set x(v: T).
accessorSignature
    : getter '(' ')' typeAnnotation?
    | setter '(' parameterList? ')' typeAnnotation?
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
    | jsxElement # JsxExpression // canon: a JSX element, ref:DEC-javascript-jsx
    | This                                                            # ThisExpression
    | identifierName singleExpression?                                # IdentifierExpression
    | Super                                                           # SuperExpression
    | literal                                                         # LiteralExpression
    | arrayLiteral                                                    # ArrayLiteralExpression
    | objectLiteral                                                   # ObjectLiteralExpression
    | '(' expressionSequence ')'                                      # ParenthesizedExpression
    | typeArguments expressionSequence?                               # GenericTypes
    | singleExpression As asExpression                                # CastAsExpression
    | '(' singleExpression ':' type_ ')'                                # FlowTypeCastExpression // canon: Flow's cast, (x: T)
    | singleExpression {this.n("satisfies")}? identifier type_         # SatisfiesExpression // canon: e satisfies T
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

anonymousFunction
    : functionDeclaration
    | Async? Function_ '*'? typeParameters? '(' formalParameterList? ')' typeAnnotation? '{' functionBody '}' // canon: function <T>(x: T) {}
    | arrowFunctionDeclaration
    ;

arrowFunctionDeclaration
    : Async? typeParameters? arrowFunctionParameters typeAnnotation? '=>' arrowFunctionBody // canon: <T>(x: T) => x
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

// canon: a JSX element, a fragment, or a self-closing tag, whose name is namespaced, as a:b, or a
// member, as A.B, with attributes, spread attributes, and children: text, expression containers,
// which may be empty or hold only a comment, spread children, and nested elements. ref:DEC-javascript-jsx
jsxElement
    : JsxTagOpen jsxElementName? jsxTypeArguments? jsxAttribute* JsxSelfClose
    | JsxTagOpen jsxElementName? jsxTypeArguments? jsxAttribute* JsxTagClose jsxChild* JsxCloseOpen jsxElementName? JsxCloseEnd
    ;

jsxElementName
    : JsxName ((JsxColon | JsxDot) JsxName)*
    ;

// canon: the type arguments of a JSX tag in a .tsx file, as <Select<number> />.
jsxTypeArguments
    : JsxTypeArgumentsOpen typeArgumentList? JsxTypeArgumentsClose
    ;

jsxAttribute
    : JsxName (JsxColon JsxName)? (JsxAssign jsxAttributeValue)?
    | JsxExpressionOpen Ellipsis singleExpression JsxExpressionClose
    ;

jsxAttributeValue
    : JsxString
    | JsxExpressionOpen singleExpression JsxExpressionClose
    | jsxElement
    ;

jsxChild
    : JsxText
    | jsxElement
    | JsxExpressionOpen (Ellipsis? singleExpression)? JsxExpressionClose
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

// canon: a template literal type, as `${string}-${number}`, whose holes are types.
templateLiteralType
    : BackTick (TemplateStringAtom | TemplateStringEscapeAtom | TemplateStringStartExpression type_ TemplateCloseBrace)* BackTick
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
    | Module // canon: the contextual keywords that are names too
    | Declare
    | Is
    | Infer
    | Require
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
