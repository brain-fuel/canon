/**
 * Kotlin Grammar for ANTLR v4
 *
 * Based on:
 * jetbrains.github.io/kotlin-spec/#_grammars_and_parsing
 * and
 * kotlinlang.org/docs/reference/grammar.html
 *
 * Tested on
 * github.com/JetBrains/kotlin/tree/master/compiler/testData/psi
 * (stale link)
 */

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar KotlinParser;

options {
    tokenVocab = KotlinLexer;
}

kotlinFile
    : shebangLine? NL* fileAnnotation* packageHeader importList topLevelObject* EOF
    ;

// canon: the last statement may end the file without a newline.
script
    : shebangLine? NL* fileAnnotation* packageHeader importList (statement semi)* statement? EOF
    ;

fileAnnotation
    : '@file' NL* ':' NL* ('[' unescapedAnnotation+ ']' | unescapedAnnotation) NL*
    ;

packageHeader
    : ('package' identifier semi?)?
    ;

importList
    : importHeader*
    ;

importHeader
    : 'import' identifier ('.' '*' | importAlias)? semi?
    ;

importAlias
    : 'as' simpleIdentifier
    ;

topLevelObject
    : declaration semis?
    ;

// canon: a fun interface, Kotlin 1.4, is an interface.
classDeclaration
    : modifiers? ('class' | ('fun' NL*)? 'interface') NL* simpleIdentifier (NL* typeParameters)? (
        NL* primaryConstructor
    )? (NL* ':' NL* delegationSpecifiers)? (NL* typeConstraints)? (
        NL* classBody
        | NL* enumClassBody
    )?
    ;

primaryConstructor
    : (modifiers? 'constructor' NL*)? classParameters
    ;

classParameters
    : '(' NL* (classParameter (NL* ',' NL* classParameter)*)? NL* ','? ')'
    ;

classParameter
    : modifiers? ('val' | 'var')? NL* simpleIdentifier ':' NL* type_ (NL* '=' NL* expression)?
    ;

delegationSpecifiers
    : annotatedDelegationSpecifier (NL* ',' NL* annotatedDelegationSpecifier)*
    ;

annotatedDelegationSpecifier
    : annotation* NL* delegationSpecifier
    ;

delegationSpecifier
    : constructorInvocation
    | explicitDelegation
    | userType
    | functionType
    ;

constructorInvocation
    : userType valueArguments
    ;

explicitDelegation
    : (userType | functionType) NL* 'by' NL* expression
    ;

classBody
    : '{' NL* classMemberDeclarations NL* '}'
    ;

classMemberDeclarations
    : (classMemberDeclaration semis?)*
    ;

classMemberDeclaration
    : declaration
    | companionObject
    | anonymousInitializer
    | secondaryConstructor
    ;

anonymousInitializer
    : 'init' NL* block
    ;

secondaryConstructor
    : modifiers? 'constructor' NL* functionValueParameters (NL* ':' NL* constructorDelegationCall)? NL* block?
    ;

constructorDelegationCall
    : 'this' NL* valueArguments
    | 'super' NL* valueArguments
    ;

enumClassBody
    : '{' NL* enumEntries? (NL* ';' NL* classMemberDeclarations)? NL* '}'
    ;

enumEntries
    : enumEntry (NL* ',' NL* enumEntry)* NL* ','?
    ;

enumEntry
    : (modifiers NL*)? simpleIdentifier (NL* valueArguments)? (NL* classBody)?
    ;

functionDeclaration
    : modifiers? 'fun' (NL* typeParameters)? (NL* receiverType NL* '.')? NL* simpleIdentifier NL* functionValueParameters (
        NL* ':' NL* type_
    )? (NL* typeConstraints)? (NL* functionBody)?
    ;

functionValueParameters
    : '(' NL* (functionValueParameter (NL* ',' NL* functionValueParameter)*)? NL* ','? ')'
    ;

functionValueParameter
    : modifiers? parameter (NL* '=' NL* expression)?
    ;

parameter
    : simpleIdentifier NL* ':' NL* type_
    ;

setterParameter
    : simpleIdentifier NL* (':' NL* type_)?
    ;

functionBody
    : block
    | '=' NL* expression
    ;

objectDeclaration
    : modifiers? 'object' NL* simpleIdentifier (NL* ':' NL* delegationSpecifiers)? (NL* classBody)?
    ;

// canon: a companion block, companion { ... }, holds a class's static members, Kotlin 2.4.
companionObject
    : modifiers? 'companion' NL* 'object' (NL* simpleIdentifier)? (
        NL* ':' NL* delegationSpecifiers
    )? (NL* classBody)?
    | modifiers? 'companion' NL* classBody
    ;

propertyDeclaration
    : modifiers? ('val' | 'var') (NL* typeParameters)? (NL* receiverType NL* '.')? (
        NL* (multiVariableDeclaration | variableDeclaration)
    ) (NL* typeConstraints)? (NL* ('=' NL* expression | propertyDelegate))? (NL+ ';')? NL* (
        getter? (NL* semi? setter)?
        | setter? (NL* semi? getter)?
    )
    /*
        XXX: actually, it's not that simple. You can put semi only on the same line as getter, but any other semicolons
        between property and getter are forbidden
        Is this a bug in kotlin parser? Who knows.
    */
    ;

// canon: a destructuring declaration may end with a trailing comma; its entries may be written
// val a or val a = name, by name, and [a, b] destructures by position, as Kotlin 2.3 and later allow.
multiVariableDeclaration
    : '(' NL* destructuringEntry (NL* ',' NL* destructuringEntry)* (NL* ',')? NL* ')'
    | '[' NL* variableDeclaration (NL* ',' NL* variableDeclaration)* (NL* ',')? NL* ']'
    ;

destructuringEntry
    : (('val' | 'var') NL*)? variableDeclaration (NL* '=' NL* simpleIdentifier)?
    ;

// canon: a name-based destructuring declaration that names val or var in each entry,
// (val a, val b) = pair, which needs no val before its parentheses.
destructuringDeclaration
    : multiVariableDeclaration NL* '=' NL* expression
    ;

variableDeclaration
    : annotation* NL* simpleIdentifier (NL* ':' NL* type_)?
    ;

propertyDelegate
    : 'by' NL* expression
    ;

getter
    : modifiers? 'get'
    | modifiers? 'get' NL* '(' NL* ')' (NL* ':' NL* type_)? NL* functionBody
    ;

setter
    : modifiers? 'set'
    | modifiers? 'set' NL* '(' (annotation | parameterModifier)* setterParameter ')' (
        NL* ':' NL* type_
    )? NL* functionBody
    ;

typeAlias
    : modifiers? 'typealias' NL* simpleIdentifier (NL* typeParameters)? NL* '=' NL* type_
    ;

typeParameters
    : '<' NL* typeParameter (NL* ',' NL* typeParameter)* NL* ','? '>'
    ;

typeParameter
    : typeParameterModifiers? NL* simpleIdentifier (NL* ':' NL* type_)?
    ;

typeParameterModifiers
    : typeParameterModifier+
    ;

typeParameterModifier
    : reificationModifier NL*
    | varianceModifier NL*
    | annotation
    ;

// canon: a definitely non-nullable type, T & Any, Kotlin 1.7.
type_
    : typeModifiers? (parenthesizedType | nullableType | typeReference | functionType | definitelyNonNullableType)
    ;

// canon: as Kotlin's grammar has it.
definitelyNonNullableType
    : typeModifiers? (userType | parenthesizedUserType) NL* '&' NL* typeModifiers? (userType | parenthesizedUserType)
    ;

typeModifiers
    : typeModifier+
    ;

// canon: a function type may take context parameters, context(T) () -> R.
typeModifier
    : annotation
    | 'suspend' NL*
    | contextModifier NL*
    ;

parenthesizedType
    : '(' NL* type_ NL* ')'
    ;

nullableType
    : (typeReference | parenthesizedType) NL* quest+
    ;

typeReference
    : userType
    | 'dynamic' // do we need a separate dynamic support here?
    ;

functionType
    : (receiverType NL* '.' NL*)? functionTypeParameters NL* '->' NL* type_
    ;

receiverType
    : typeModifiers? (parenthesizedType | nullableType | typeReference)
    ;

userType
    : simpleUserType (NL* '.' NL* simpleUserType)*
    ;

parenthesizedUserType
    : '(' NL* userType NL* ')'
    | '(' NL* parenthesizedUserType NL* ')'
    ;

simpleUserType
    : simpleIdentifier (NL* typeArguments)?
    ;

// canon: the parameters may end with a trailing comma, as Kotlin 1.4 allows.
functionTypeParameters
    : '(' NL* (parameter | type_)? (NL* ',' NL* (parameter | type_))* (NL* ',')? NL* ')'
    ;

typeConstraints
    : 'where' NL* typeConstraint (NL* ',' NL* typeConstraint)*
    ;

typeConstraint
    : annotation* simpleIdentifier NL* ':' NL* type_
    ;

block
    : '{' NL* statements NL* '}'
    ;

statements
    : (statement ((';' | NL)+ statement)* semis?)?
    ;

// canon: a statement may be a name-based destructuring declaration.
statement
    : (label | annotation)* (declaration | assignment | loopStatement | expression | destructuringDeclaration)
    ;

declaration
    : classDeclaration
    | objectDeclaration
    | functionDeclaration
    | propertyDeclaration
    | typeAlias
    ;

assignment
    : directlyAssignableExpression '=' NL* expression
    | assignableExpression assignmentAndOperator NL* expression
    ;

expression
    : disjunction
    ;

disjunction
    : conjunction (NL* '||' NL* conjunction)*
    ;

conjunction
    : equality (NL* '&&' NL* equality)*
    ;

equality
    : comparison (/* NO NL! */ equalityOperator NL* comparison)*
    ;

comparison
    : infixOperation (/* NO NL! */ comparisonOperator NL* infixOperation)?
    ;

infixOperation
    : elvisExpression (/* NO NL! */ inOperator NL* elvisExpression | isOperator NL* type_)*
    ;

elvisExpression
    : infixFunctionCall (NL* elvis NL* infixFunctionCall)*
    ;

infixFunctionCall
    : rangeExpression (/* NO NL! */ simpleIdentifier NL* rangeExpression)*
    ;

// canon: ..< is a range operator too, as Kotlin 1.8 allows.
rangeExpression
    : additiveExpression (/* NO NL! */ ('..' | '..<') NL* additiveExpression)*
    ;

additiveExpression
    : multiplicativeExpression (/* NO NL! */ additiveOperator NL* multiplicativeExpression)*
    ;

multiplicativeExpression
    : asExpression (/* NO NL! */ multiplicativeOperator NL* asExpression)*
    ;

asExpression
    : prefixUnaryExpression (NL* asOperator NL* type_)?
    ;

prefixUnaryExpression
    : unaryPrefix* postfixUnaryExpression
    ;

unaryPrefix
    : annotation
    | label
    | prefixUnaryOperator NL*
    ;

postfixUnaryExpression
    : primaryExpression
    | primaryExpression postfixUnarySuffix+
    ;

postfixUnarySuffix
    : postfixUnaryOperator
    | typeArguments
    | callSuffix
    | indexingSuffix
    | navigationSuffix
    ;

directlyAssignableExpression
    : postfixUnaryExpression assignableSuffix
    | simpleIdentifier
    ;

assignableExpression
    : prefixUnaryExpression
    ;

assignableSuffix
    : typeArguments
    | indexingSuffix
    | navigationSuffix
    ;

indexingSuffix
    : '[' NL* expression (NL* ',' NL* expression)* NL* ']'
    ;

navigationSuffix
    : NL* memberAccessOperator NL* (simpleIdentifier | parenthesizedExpression | 'class')
    ;

callSuffix
    : typeArguments? valueArguments? annotatedLambda
    | typeArguments? valueArguments
    ;

annotatedLambda
    : annotation* label? NL* lambdaLiteral
    ;

valueArguments
    : '(' NL* ')'
    | '(' NL* valueArgument (NL* ',' NL* valueArgument)* NL* ','? ')'
    ;

typeArguments
    : '<' NL* typeProjection (NL* ',' NL* typeProjection)* NL* ','? '>'
    ;

typeProjection
    : typeProjectionModifiers? type_
    | '*'
    ;

typeProjectionModifiers
    : typeProjectionModifier+
    ;

typeProjectionModifier
    : varianceModifier NL*
    | annotation
    ;

valueArgument
    : annotation? NL* (simpleIdentifier NL* '=' NL*)? '*'? NL* expression
    ;

primaryExpression
    : parenthesizedExpression
    | literalConstant
    | stringLiteral
    | simpleIdentifier
    | callableReference
    | functionLiteral
    | objectLiteral
    | collectionLiteral
    | thisExpression
    | superExpression
    | ifExpression
    | whenExpression
    | tryExpression
    | jumpExpression
    ;

parenthesizedExpression
    : '(' NL* expression NL* ')'
    ;

collectionLiteral
    : '[' NL* expression (NL* ',' NL* expression)* NL* ','? ']'
    | '[' NL* ']'
    ;

literalConstant
    : BooleanLiteral
    | IntegerLiteral
    | HexLiteral
    | BinLiteral
    | CharacterLiteral
    | RealLiteral
    | NullLiteral
    | LongLiteral
    | UnsignedLiteral // canon: unsigned literals, Kotlin 1.5
    ;

stringLiteral
    : lineStringLiteral
    | multiLineStringLiteral
    ;

lineStringLiteral
    : QUOTE_OPEN (lineStringContent | lineStringExpression)* QUOTE_CLOSE
    ;

multiLineStringLiteral // why is lineStringLiteral here? there is no escaping in multiline strings
    : TRIPLE_QUOTE_OPEN (multiLineStringContent | multiLineStringExpression | MultiLineStringQuote)* TRIPLE_QUOTE_CLOSE
    ;

lineStringContent
    : LineStrText
    | LineStrEscapedChar
    | LineStrRef
    ;

// canon: an expression in ${...} may span lines.
lineStringExpression
    : LineStrExprStart NL* expression NL* '}'
    ;

multiLineStringContent
    : MultiLineStrText
    | MultiLineStringQuote
    | MultiLineStrRef
    ;

multiLineStringExpression
    : MultiLineStrExprStart NL* expression NL* '}'
    ;

lambdaLiteral // anonymous functions?
    : LCURL NL* statements NL* RCURL
    | LCURL NL* lambdaParameters? NL* ARROW NL* statements NL* '}'
    ;

lambdaParameters
    : lambdaParameter (NL* COMMA NL* lambdaParameter)* COMMA?
    ;

lambdaParameter
    : variableDeclaration
    | multiVariableDeclaration (NL* COLON NL* type_)?
    ;

anonymousFunction
    : 'fun' (NL* type_ NL* '.')? NL* functionValueParameters (NL* ':' NL* type_)? (
        NL* typeConstraints
    )? (NL* functionBody)?
    ;

functionLiteral
    : lambdaLiteral
    | anonymousFunction
    ;

objectLiteral
    : 'object' NL* ':' NL* delegationSpecifiers (NL* classBody)?
    | 'object' NL* classBody
    ;

thisExpression
    : 'this'
    | THIS_AT
    ;

superExpression
    : 'super' ('<' NL* type_ NL* '>')? ('@' simpleIdentifier)?
    | SUPER_AT
    ;

controlStructureBody
    : block
    | statement
    ;

ifExpression
    : 'if' NL* '(' NL* expression NL* ')' NL* controlStructureBody (
        ';'? NL* 'else' NL* controlStructureBody
    )?
    | 'if' NL* '(' NL* expression NL* ')' NL* (';' NL*)? 'else' NL* controlStructureBody
    ;

// canon: the subject may bind a value, as Kotlin 1.3 allows.
whenExpression
    : 'when' NL* whenSubject? NL* '{' NL* (whenEntry NL*)* NL* '}'
    ;

whenSubject
    : '(' (annotation* NL* 'val' NL* variableDeclaration NL* '=' NL*)? expression ')'
    ;

// canon: a condition may carry a guard, is T if cond ->, as Kotlin 2.2 allows, and the conditions
// a trailing comma.
whenEntry
    : whenCondition (NL* ',' NL* whenCondition)* (NL* ',')? (NL* whenEntryGuard)? NL* '->' NL* controlStructureBody semi?
    | 'else' NL* '->' NL* controlStructureBody semi?
    ;

// canon: the guard of a when entry.
whenEntryGuard
    : 'if' NL* expression
    ;

whenCondition
    : expression
    | rangeTest
    | typeTest
    ;

rangeTest
    : inOperator NL* expression
    ;

typeTest
    : isOperator NL* type_
    ;

tryExpression
    : 'try' NL* block ((NL* catchBlock)+ (NL* finallyBlock)? | NL* finallyBlock)
    ;

catchBlock
    : 'catch' NL* '(' annotation* simpleIdentifier ':' userType ')' NL* block
    ;

finallyBlock
    : 'finally' NL* block
    ;

loopStatement
    : forStatement
    | whileStatement
    | doWhileStatement
    ;

forStatement
    : 'for' NL* '(' annotation* (variableDeclaration | multiVariableDeclaration) 'in' expression ')' NL* controlStructureBody?
    ;

whileStatement
    : 'while' NL* '(' expression ')' NL* controlStructureBody
    | 'while' NL* '(' expression ')' NL* ';'
    ;

doWhileStatement
    : 'do' NL* controlStructureBody? NL* 'while' NL* '(' expression ')'
    ;

jumpExpression
    : 'throw' NL* expression
    | ('return' | RETURN_AT) expression?
    | 'continue'
    | CONTINUE_AT
    | 'break'
    | BREAK_AT
    ;

callableReference // ?:: here is not an actual operator, it's just a lexer hack to avoid (?: + :) vs (? + ::) ambiguity
    : (receiverType? NL* '::' NL* (simpleIdentifier | 'class'))
    ;

assignmentAndOperator
    : '+='
    | '-='
    | '*='
    | '/='
    | '%='
    ;

equalityOperator
    : '!='
    | '!=='
    | '=='
    | '==='
    ;

comparisonOperator
    : '<'
    | '>'
    | '<='
    | '>='
    ;

inOperator
    : 'in'
    | NOT_IN
    ;

isOperator
    : 'is'
    | NOT_IS
    ;

additiveOperator
    : '+'
    | '-'
    ;

multiplicativeOperator
    : '*'
    | '/'
    | '%'
    ;

asOperator
    : 'as'
    | 'as?'
    ;

prefixUnaryOperator
    : '++'
    | '--'
    | '-'
    | '+'
    | excl
    ;

postfixUnaryOperator
    : '++'
    | '--'
    | EXCL_NO_WS excl
    ;

memberAccessOperator
    : '.'
    | safeNav
    | '::'
    ;

modifiers
    : (annotation | modifier)+
    ;

modifier
    : (
        classModifier
        | memberModifier
        | visibilityModifier
        | functionModifier
        | propertyModifier
        | inheritanceModifier
        | parameterModifier
        | platformModifier
        | contextModifier
    ) NL*
    ;

// canon: context parameters, context(logger: Logger), and the context receivers before them,
// context(Logger), Kotlin 2.2, before a declaration or a function type.
contextModifier
    : 'context' NL* '(' NL* contextParameter (NL* ',' NL* contextParameter)* (NL* ',')? NL* ')'
    ;

contextParameter
    : (simpleIdentifier NL* ':' NL*)? type_
    ;

// canon: value, as in value class, Kotlin 1.5.
classModifier
    : 'enum'
    | 'sealed'
    | 'annotation'
    | 'data'
    | 'inner'
    | 'value'
    ;

memberModifier
    : 'override'
    | 'lateinit'
    ;

visibilityModifier
    : 'public'
    | 'private'
    | 'internal'
    | 'protected'
    ;

varianceModifier
    : 'in'
    | 'out'
    ;

functionModifier
    : 'tailrec'
    | 'operator'
    | 'infix'
    | 'inline'
    | 'external'
    | 'suspend'
    ;

propertyModifier
    : 'const'
    ;

inheritanceModifier
    : 'abstract'
    | 'final'
    | 'open'
    ;

parameterModifier
    : 'vararg'
    | 'noinline'
    | 'crossinline'
    ;

reificationModifier
    : 'reified'
    ;

platformModifier
    : 'expect'
    | 'actual'
    ;

label
    : IdentifierAt NL*
    ;

// canon: each annotation is labeled marker, so canon can tell a test by its annotation, such as
// @Test.
annotation
    : (marker = singleAnnotation | marker = multiAnnotation) NL*
    ;

singleAnnotation
    : annotationUseSiteTarget NL* ':' NL* unescapedAnnotation
    | '@' unescapedAnnotation
    ;

multiAnnotation
    : annotationUseSiteTarget NL* ':' NL* '[' unescapedAnnotation+ ']'
    | '@' '[' unescapedAnnotation+ ']'
    ;

annotationUseSiteTarget
    : '@field'
    | '@property'
    | '@get'
    | '@set'
    | '@receiver'
    | '@param'
    | '@setparam'
    | '@delegate'
    ;

unescapedAnnotation
    : constructorInvocation
    | userType
    ;

simpleIdentifier
    : Identifier //soft keywords:
    | 'abstract'
    | 'annotation'
    | 'by'
    | 'catch'
    | 'companion'
    | 'constructor'
    | 'crossinline'
    | 'data'
    | 'dynamic'
    | 'enum'
    | 'external'
    | 'final'
    | 'finally'
    | 'get'
    | 'import'
    | 'infix'
    | 'init'
    | 'inline'
    | 'inner'
    | 'internal'
    | 'lateinit'
    | 'noinline'
    | 'open'
    | 'operator'
    | 'out'
    | 'override'
    | 'private'
    | 'protected'
    | 'public'
    | 'reified'
    | 'sealed'
    | 'tailrec'
    | 'set'
    | 'vararg'
    | 'where'
    | 'expect'
    | 'actual'
    | 'const'
    | 'suspend'
    | 'value' // canon: a soft keyword since Kotlin 1.5
    | 'context' // canon: a soft keyword since Kotlin 2.2
    ;

identifier
    : simpleIdentifier (NL* '.' simpleIdentifier)*
    ;

shebangLine
    : ShebangLine NL+
    ;

quest
    : QUEST_NO_WS
    | QUEST_WS
    ;

elvis
    : QUEST_NO_WS ':'
    ;

safeNav
    : QUEST_NO_WS '.'
    ;

excl
    : EXCL_NO_WS
    | EXCL_WS
    ;

semi
    : (';' | NL) NL* // actually, it's WS or comment between ';', here it's handled in lexer (see ;; token)
    | EOF
    ;

semis // writing this as "semi+" sends antlr into infinite loop or smth
    : (';' | NL)+
    | EOF
    ;