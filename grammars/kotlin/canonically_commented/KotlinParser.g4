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

// canon: the canonically commented dialect of the Kotlin grammar. KDoc comments are canonical
// comments on the default channel; each declaration KDoc documents is a labeled unit alternative
// with its Why, its What, and its How; a KDoc comment the grammar accepts but binds to nothing is
// an orphan. A top-level declaration is public unless it says otherwise and holds the empty rule
// publicByDefault, labeled required; the members of a class, an interface, an object, and an enum
// are labeled inherited; private, internal, override, and actual are labeled optional, which wins.
// Every change from the plain grammar is marked canon: and listed in grammars/kotlin/README.md.

// canon: a KDoc comment above the package directive or the file annotations is the file's Why; one
// before an import or after the last declaration binds to nothing.
kotlinFile
    : shebangLine? NL* (
        ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment NL*) (
            fileAnnotation+ packageHeader
            | packageDirective
        )
        | fileAnnotation* packageHeader
    ) importList topLevelObject* (orphan = canonicalComment NL*)* EOF
    ;

// canon: a package directive that is present, which a file's Why may stand above.
packageDirective
    : 'package' identifier semi?
    ;

script
    : shebangLine? NL* fileAnnotation* packageHeader importList (statement semi)* EOF
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
    : (orphan = canonicalComment NL*)* 'import' identifier ('.' '*' | importAlias)? semi?
    ;

importAlias
    : 'as' simpleIdentifier
    ;

topLevelObject
    : declaration semis?
    ;

classDeclaration
    : modifiers? ('class' | 'interface') NL* what = simpleIdentifier (NL* typeParameters)? (
        NL* primaryConstructor
    )? (NL* ':' NL* delegationSpecifiers)? (NL* typeConstraints)? (
        NL* how = classBody
        | NL* how = enumClassBody
    )?
    ;

// canon: the modifiers of a primary constructor are not the class's, so a private constructor does
// not make its class optional.
primaryConstructor
    : (innerModifiers? 'constructor' NL*)? classParameters
    ;

classParameters
    : '(' NL* (classParameter (NL* ',' NL* classParameter)*)? NL* ','? ')'
    ;

// canon: a parameter declared val or var is a property, which a KDoc comment may document; its
// class may document it instead with @property, so it is not inherited. A KDoc comment on a plain
// parameter binds to nothing; the class documents it with @param.
classParameter
    : ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) modifiers? ('val' | 'var') NL* what = simpleIdentifier ':' NL* type_ (
        NL* '=' NL* expression
    )? # property
    | (orphan = canonicalComment NL*)* modifiers? NL* simpleIdentifier ':' NL* type_ (NL* '=' NL* expression)?
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

// canon: the members of a class, an interface, or an object need a comment when it does.
classBody
    : '{' NL* inherited = classMemberDeclarations NL* '}'
    ;

// canon: a KDoc comment after the last member binds to nothing.
classMemberDeclarations
    : (classMemberDeclaration semis?)* (orphan = canonicalComment NL*)*
    ;

// canon: each kind of member is a unit alternative whose Why is the KDoc comment above its
// annotations and modifiers, of which the last of several in a row binds. A KDoc comment before an
// initializer block binds to nothing.
classMemberDeclaration
    : ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) classDeclaration # class
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) objectDeclaration # object
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) functionDeclaration # function
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) propertyDeclaration # property
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) typeAlias # type
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) companionObject # object
    | (orphan = canonicalComment NL*)* anonymousInitializer
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) secondaryConstructor # constructor
    ;

anonymousInitializer
    : 'init' NL* block
    ;

secondaryConstructor
    : modifiers? what = 'constructor' NL* functionValueParameters (NL* ':' NL* constructorDelegationCall)? NL* block?
    ;

constructorDelegationCall
    : 'this' NL* valueArguments
    | 'super' NL* valueArguments
    ;

// canon: the entries and members of an enum need a comment when it does.
enumClassBody
    : '{' NL* (inherited = enumEntries)? (NL* ';' NL* inherited = classMemberDeclarations)? NL* '}'
    ;

enumEntries
    : enumEntry (NL* ',' NL* enumEntry)* NL* ','?
    ;

// canon: an enum entry is a unit.
enumEntry
    : ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) (modifiers NL*)? what = simpleIdentifier (NL* valueArguments)? (NL* classBody)? # entry
    ;

functionDeclaration
    : modifiers? 'fun' (NL* typeParameters)? (NL* receiverType NL* '.')? NL* what = simpleIdentifier NL* functionValueParameters (
        NL* ':' NL* type_
    )? (NL* typeConstraints)? (NL* how = functionBody)?
    ;

functionValueParameters
    : '(' NL* (functionValueParameter (NL* ',' NL* functionValueParameter)*)? NL* ','? ')'
    ;

// canon: a KDoc comment on a parameter binds to nothing; the function documents it with @param.
functionValueParameter
    : (orphan = canonicalComment NL*)* modifiers? parameter (NL* '=' NL* expression)?
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
    : modifiers? 'object' NL* what = simpleIdentifier (NL* ':' NL* delegationSpecifiers)? (NL* how = classBody)?
    ;

// canon: a companion object without a name is named by its companion keyword.
companionObject
    : modifiers? 'companion' NL* 'object' NL* what = simpleIdentifier (
        NL* ':' NL* delegationSpecifiers
    )? (NL* how = classBody)?
    | modifiers? what = 'companion' NL* 'object' (NL* ':' NL* delegationSpecifiers)? (
        NL* how = classBody
    )?
    ;

// canon: the name a property declares is its What; a destructuring declaration, which only a
// local may be, has none.
propertyDeclaration
    : modifiers? ('val' | 'var') (NL* typeParameters)? (NL* receiverType NL* '.')? (
        NL* (multiVariableDeclaration | annotation* NL* what = simpleIdentifier (NL* ':' NL* type_)?)
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

multiVariableDeclaration
    : '(' NL* variableDeclaration (NL* ',' NL* variableDeclaration)* NL* ')'
    ;

variableDeclaration
    : annotation* NL* simpleIdentifier (NL* ':' NL* type_)?
    ;

propertyDelegate
    : 'by' NL* expression
    ;

// canon: a KDoc comment on an accessor binds to nothing; the property documents it. An accessor's
// modifiers are not the property's, so a private setter does not make its property optional.
getter
    : (orphan = canonicalComment NL*)* innerModifiers? 'get'
    | (orphan = canonicalComment NL*)* innerModifiers? 'get' NL* '(' NL* ')' (NL* ':' NL* type_)? NL* functionBody
    ;

setter
    : (orphan = canonicalComment NL*)* innerModifiers? 'set'
    | (orphan = canonicalComment NL*)* innerModifiers? 'set' NL* '(' (annotation | parameterModifier)* setterParameter ')' (
        NL* ':' NL* type_
    )? NL* functionBody
    ;

typeAlias
    : modifiers? 'typealias' NL* what = simpleIdentifier (NL* typeParameters)? NL* '=' NL* type_
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

type_
    : typeModifiers? (parenthesizedType | nullableType | typeReference | functionType)
    ;

typeModifiers
    : typeModifier+
    ;

typeModifier
    : annotation
    | 'suspend' NL*
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

functionTypeParameters
    : '(' NL* (parameter | type_)? (NL* ',' NL* (parameter | type_))* NL* ')'
    ;

typeConstraints
    : 'where' NL* typeConstraint (NL* ',' NL* typeConstraint)*
    ;

typeConstraint
    : annotation* simpleIdentifier NL* ':' NL* type_
    ;

// canon: a KDoc comment after the last statement of a block binds to nothing.
block
    : '{' NL* statements NL* (orphan = canonicalComment NL*)* '}'
    ;

statements
    : (statement ((';' | NL)+ statement)* semis?)?
    ;

// canon: a KDoc comment before a statement or among its annotations binds to nothing, a local
// declaration's included, since KDoc documents only what a file or a class declares.
statement
    : (label | annotation | orphan = canonicalComment NL*)* (
        localDeclaration
        | assignment
        | loopStatement
        | expression
    )
    ;

// canon: a declaration at the top of a file is a unit alternative whose Why is the KDoc comment
// above its annotations and modifiers, of which the last of several in a row binds.
declaration
    : ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) required = publicByDefault classDeclaration # class
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) required = publicByDefault objectDeclaration # object
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) required = publicByDefault functionDeclaration # function
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) required = publicByDefault propertyDeclaration # property
    | ((orphan = canonicalComment NL*)+ why = canonicalComment NL* | why = canonicalComment? NL*) required = publicByDefault typeAlias # type
    ;

// canon: a declaration inside a function body, which is not a unit.
localDeclaration
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

rangeExpression
    : additiveExpression (/* NO NL! */ '..' NL* additiveExpression)*
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

lineStringExpression
    : LineStrExprStart expression '}'
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

// canon: the members of an object expression are local to it, so they do not inherit a requirement.
objectLiteral
    : 'object' NL* ':' NL* delegationSpecifiers (NL* objectLiteralBody)?
    | 'object' NL* objectLiteralBody
    ;

// canon: the body of an object expression.
objectLiteralBody
    : '{' NL* classMemberDeclarations NL* '}'
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

whenEntry
    : whenCondition (NL* ',' NL* whenCondition)* NL* '->' NL* controlStructureBody semi?
    | 'else' NL* '->' NL* controlStructureBody semi?
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

// canon: a KDoc comment among a declaration's annotations and modifiers, after the first of them,
// binds to nothing.
modifiers
    : (annotation | modifier) (annotation | modifier | orphan = canonicalComment NL*)*
    ;

// canon: the modifiers of a primary constructor or an accessor, which carry no labels.
innerModifiers
    : (annotation | innerModifier)+
    ;

// canon: a modifier an accessor or a primary constructor may carry.
innerModifier
    : ('public' | 'private' | 'internal' | 'protected' | functionModifier | inheritanceModifier | platformModifier) NL*
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
    ) NL*
    ;

classModifier
    : 'enum'
    | 'sealed'
    | 'annotation'
    | 'data'
    | 'inner'
    ;

// canon: an override is documented by the declaration it overrides, so it is labeled optional.
memberModifier
    : optional = 'override'
    | 'lateinit'
    ;

// canon: private and internal are labeled optional, because what is not visible outside its module
// is not the API that Kotlin's explicit API mode and Dokka document.
visibilityModifier
    : 'public'
    | optional = 'private'
    | optional = 'internal'
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

// canon: an actual declaration is documented by the expect declaration it implements, so it is
// labeled optional.
platformModifier
    : 'expect'
    | optional = 'actual'
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

// canon: a Kotlin declaration is public unless it says otherwise, so a top-level declaration holds
// this empty rule, labeled required; private and internal are labeled optional, which wins.
publicByDefault
    :
    ;

// canon: a canonical comment, a KDoc comment, holding prose, reference citations, and license
// citations.
canonicalComment
    : DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: one piece of a canonical comment.
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
