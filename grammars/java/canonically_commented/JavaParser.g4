/*
 [The "BSD licence"]
 Copyright (c) 2013 Terence Parr, Sam Harwell
 Copyright (c) 2017 Ivan Kochurkin (upgrade to Java 8)
 Copyright (c) 2021 Michał Lorek (upgrade to Java 11)
 Copyright (c) 2022 Michał Lorek (upgrade to Java 17)
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 3. The name of the author may not be used to endorse or promote products
    derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $antlr-format alignTrailingComments true, columnLimit 150, minEmptyLines 1, maxEmptyLinesToKeep 1, reflowComments false, useTab false
// $antlr-format allowShortRulesOnASingleLine false, allowShortBlocksOnASingleLine true, alignSemicolons hanging, alignColons hanging

parser grammar JavaParser;

// Insert here @header.

options {
    tokenVocab = JavaLexer;
    superClass = JavaParserBase;
}

compilationUnit
    : (why = canonicalComment? packageDeclaration)? ((orphan = canonicalComment)* importDeclaration | ';')* (typeDeclaration | ';')* EOF # package
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) modularCompulationUnit EOF # module
    ;

modularCompulationUnit
    : importDeclaration* moduleDeclaration
    ;

packageDeclaration
    : annotation* PACKAGE what = qualifiedName ';'
    ;

importDeclaration
    : IMPORT STATIC? qualifiedName ('.' '*')? ';'
    ;

typeDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | classOrInterfaceModifier | orphan = canonicalComment)* classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | classOrInterfaceModifier | orphan = canonicalComment)* enumDeclaration # enum
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | classOrInterfaceModifier | orphan = canonicalComment)* interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | classOrInterfaceModifier | orphan = canonicalComment)* annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | classOrInterfaceModifier | orphan = canonicalComment)* recordDeclaration # record
    ;

modifier
    : classOrInterfaceModifier
    | NATIVE
    | SYNCHRONIZED
    | TRANSIENT
    | VOLATILE
    ;

classOrInterfaceModifier
    : annotation
    | PUBLIC
    | PROTECTED
    | PRIVATE
    | STATIC
    | ABSTRACT
    | FINAL // FINAL for class only -- does not apply to interfaces
    | STRICTFP
    | SEALED
    | NON_SEALED
    ;

variableModifier
    : FINAL
    | annotation
    ;

classDeclaration
    : CLASS what = identifier typeParameters? (EXTENDS typeType)? (IMPLEMENTS typeList)? (
        PERMITS typeList
    )?
    how = classBody
    ;

typeParameters
    : '<' typeParameter (',' typeParameter)* '>'
    ;

typeParameter
    : annotation* identifier (EXTENDS annotation* typeBound)?
    ;

typeBound
    : typeType ('&' typeType)*
    ;

enumDeclaration
    : ENUM what = identifier (IMPLEMENTS typeList)? '{' enumConstants? ','? enumBodyDeclarations? '}'
    ;

enumConstants
    : enumConstant (',' enumConstant)*
    ;

enumConstant
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) annotation* what = identifier arguments? classBody? # enumConstant
    ;

enumBodyDeclarations
    : ';' classBodyDeclaration*
    ;

interfaceDeclaration
    : INTERFACE what = identifier typeParameters? (EXTENDS typeList)? (PERMITS typeList)? how = interfaceBody
    ;

classBody
    : '{' classBodyDeclaration* '}'
    ;

interfaceBody
    : '{' interfaceBodyDeclaration* '}'
    ;

classBodyDeclaration
    : ';' # emptyMember
    | (orphan = canonicalComment)* STATIC? block # initializer
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* recordDeclaration # record
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* methodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* genericMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* fieldDeclaration # field
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* constructorDeclaration # constructor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* genericConstructorDeclaration # constructor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* enumDeclaration # enum
    ;

memberDeclaration
    : recordDeclaration
    | methodDeclaration
    | genericMethodDeclaration
    | fieldDeclaration
    | constructorDeclaration
    | genericConstructorDeclaration
    | interfaceDeclaration
    | annotationTypeDeclaration
    | classDeclaration
    | enumDeclaration
    ;

/* We use rule this even for void methods which cannot have [] after parameters.
   This simplifies grammar and we can consider void to be a type, which
   renders the [] matching as a context-sensitive issue or a semantic check
   for invalid return type after parsing.
 */
methodDeclaration
    : typeTypeOrVoid what = identifier formalParameters ('[' ']')* (THROWS qualifiedNameList)? how = methodBody
    ;

methodBody
    : block
    | ';'
    ;

typeTypeOrVoid
    : typeType
    | VOID
    ;

genericMethodDeclaration
    : typeParameters methodDeclaration
    ;

genericConstructorDeclaration
    : typeParameters constructorDeclaration
    ;

constructorDeclaration
    : what = identifier formalParameters (THROWS qualifiedNameList)? how = block
    ;

compactConstructorDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = PUBLIC | modifier | orphan = canonicalComment)* what = identifier how = block # compactConstructor
    ;

fieldDeclaration
    : typeType variableDeclarators ';'
    ;

interfaceBodyDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = recordDeclaration # record
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = constDeclaration # constant
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = interfaceMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = genericInterfaceMethodDeclaration # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = interfaceDeclaration # interface
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = annotationTypeDeclaration # annotationType
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = classDeclaration # class
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = enumDeclaration # enum
    | ';' # emptyMember
    ;

interfaceMemberDeclaration
    : recordDeclaration
    | constDeclaration
    | interfaceMethodDeclaration
    | genericInterfaceMethodDeclaration
    | interfaceDeclaration
    | annotationTypeDeclaration
    | classDeclaration
    | enumDeclaration
    ;

constDeclaration
    : typeType constantDeclarator (',' constantDeclarator)* ';'
    ;

constantDeclarator
    : what = identifier ('[' ']')* '=' variableInitializer
    ;

// Early versions of Java allows brackets after the method name, eg.
// public int[] return2DArray() [] { ... }
// is the same as
// public int[][] return2DArray() { ... }
interfaceMethodDeclaration
    : interfaceMethodModifier* interfaceCommonBodyDeclaration
    ;

interfaceMethodModifier
    : annotation
    | PUBLIC
    | ABSTRACT
    | DEFAULT
    | STATIC
    | STRICTFP
    ;

genericInterfaceMethodDeclaration
    : interfaceMethodModifier* typeParameters interfaceCommonBodyDeclaration
    ;

interfaceCommonBodyDeclaration
    : annotation* typeTypeOrVoid what = identifier formalParameters ('[' ']')* (THROWS qualifiedNameList)? how = methodBody
    ;

variableDeclarators
    : variableDeclarator (',' variableDeclarator)*
    ;

variableDeclarator
    : variableDeclaratorId ('=' variableInitializer)?
    ;

variableDeclaratorId
    : what = identifier ('[' ']')*
    ;

variableInitializer
    : arrayInitializer
    | expression
    ;

arrayInitializer
    : '{' (variableInitializer (',' variableInitializer)* ','?)? '}'
    ;

classType:
    (
      ( packageName '.' annotation* )? typeIdentifier typeArguments?
    )+ ( '.' annotation* typeIdentifier typeArguments? )*
    ;

packageName:
    identifier ('.' identifier)*
    ;

typeArgument
    : typeType
    | annotation* '?' ((EXTENDS | SUPER) typeType)?
    ;

qualifiedNameList
    : qualifiedName (',' qualifiedName)*
    ;

formalParameters
    : '(' (
       ( receiverParameter | formalParameter ) (',' formalParameterList)*
    )? ')'
    ;

receiverParameter
    : typeType (identifier '.')* THIS
    ;

formalParameterList
    : formalParameter (',' formalParameter)*
    ;

formalParameter
    : variableModifier* typeType (annotation* '...')? variableDeclaratorId
    ;

// local variable type inference
lambdaLVTIList
    : lambdaLVTIParameter (',' lambdaLVTIParameter)*
    ;

lambdaLVTIParameter
    : variableModifier* VAR identifier
    ;

qualifiedName
    : identifier ('.' identifier)*
    ;

literal
    : integerLiteral
    | floatLiteral
    | CHAR_LITERAL
    | STRING_LITERAL
    | BOOL_LITERAL
    | NULL_LITERAL
    | TEXT_BLOCK
    ;

integerLiteral
    : DECIMAL_LITERAL
    | HEX_LITERAL
    | OCT_LITERAL
    | BINARY_LITERAL
    ;

floatLiteral
    : FLOAT_LITERAL
    | HEX_FLOAT_LITERAL
    ;

// ANNOTATIONS
altAnnotationQualifiedName
    : (identifier DOT)* '@' identifier
    ;

//annotation
//    : ('@' qualifiedName /* | altAnnotationQualifiedName */) ( '(' ( elementValuePairs | elementValue)? ')')?
//    ;

annotation :
    ('@' qualifiedName /* | altAnnotationQualifiedName */) annotationFieldValues?
    ;

annotationFieldValues:
	'(' ( annotationFieldValue ( ',' annotationFieldValue )* )? ')'
	;

annotationFieldValue:
	{ this.IsNotIdentifierAssign() }? annotationValue
	| identifier '=' annotationValue
	;

annotationValue:
	expression //conditionalExpression
	| annotation
	| '{' ( annotationValue ( ',' annotationValue )* )? ','? '}'
	;

//elementValuePairs
//    : elementValuePair (',' elementValuePair)*
//    ;

//elementValuePair
//    : identifier '=' elementValue
//    ;

elementValue
    : expression
    | annotation
    | elementValueArrayInitializer
    ;

elementValueArrayInitializer
    : '{' (elementValue (',' elementValue)*)? ','? '}'
    ;

annotationTypeDeclaration
    : '@' INTERFACE what = identifier how = annotationTypeBody
    ;

annotationTypeBody
    : '{' annotationTypeElementDeclaration* '}'
    ;

annotationTypeElementDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (modifier | orphan = canonicalComment)* required = annotationTypeElementRest # annotationElement
    | ';' # emptyElement // this is not allowed by the grammar, but apparently allowed by the actual compiler
    ;

annotationTypeElementRest
    : typeType annotationMethodOrConstantRest ';'
    | classDeclaration ';'?
    | interfaceDeclaration ';'?
    | enumDeclaration ';'?
    | annotationTypeDeclaration ';'?
    | recordDeclaration ';'?
    ;

annotationMethodOrConstantRest
    : annotationMethodRest
    | annotationConstantRest
    ;

annotationMethodRest
    : what = identifier '(' ')' defaultValue?
    ;

annotationConstantRest
    : variableDeclarators
    ;

defaultValue
    : DEFAULT elementValue
    ;

moduleDeclaration
    : annotation* OPEN? MODULE what = qualifiedName '{' moduleDirective* '}'
    ;

moduleDirective
    : REQUIRES requiresModifier* qualifiedName ';'
    | EXPORTS qualifiedName (TO qualifiedName (',' qualifiedName)* )? ';'
    | OPENS qualifiedName (TO qualifiedName (',' qualifiedName)* )? ';'
    | USES qualifiedName ';'
    | PROVIDES qualifiedName WITH qualifiedName (',' qualifiedName)* ';'
    ;

requiresModifier
    : TRANSITIVE
    | STATIC
    ;

recordDeclaration
    : RECORD what = identifier typeParameters? recordHeader (IMPLEMENTS typeList)? how = recordBody
    ;

recordHeader
    : '(' recordComponentList? ')'
    ;

recordComponentList
    : recordComponent (',' recordComponent)* { this.DoLastRecordComponent() }?
    ;

recordComponent
    : annotation* typeType (annotation* ELLIPSIS)? identifier
    ;

recordBody
    : '{' (classBodyDeclaration | compactConstructorDeclaration)* '}'
    ;

// STATEMENTS / BLOCKS

block
    : '{' blockStatement* '}'
    ;

blockStatement
    : (orphan = canonicalComment)* localVariableDeclaration ';'
    | (orphan = canonicalComment)* localTypeDeclaration
    | (orphan = canonicalComment)* statement
    ;

localVariableDeclaration
    : variableModifier* (VAR identifier '=' expression | typeType variableDeclarators)
    ;

identifier
    : IDENTIFIER
    | MODULE
    | OPEN
    | REQUIRES
    | EXPORTS
    | OPENS
    | TO
    | USES
    | PROVIDES
    | WHEN
    | WITH
    | TRANSITIVE
    | YIELD
    | SEALED
    | PERMITS
    | RECORD
    | VAR
    ;

typeIdentifier // Identifiers that are not restricted for type declarations
    : IDENTIFIER
    | MODULE
    | OPEN
    | REQUIRES
    | EXPORTS
    | OPENS
    | TO
    | USES
    | PROVIDES
    | WITH
    | TRANSITIVE
    | SEALED
    ;

localTypeDeclaration
    : classOrInterfaceModifier* (classDeclaration | interfaceDeclaration | recordDeclaration | enumDeclaration)
    ;

statement
    : blockLabel = block
    | ASSERT expression (':' expression)? ';'
    | IF '(' expression ')' statement (ELSE statement)?
    | FOR '(' forControl ')' statement
    | WHILE '(' expression ')' statement
    | DO statement WHILE '(' expression ')' ';'
    | TRY block (catchClause+ finallyBlock? | finallyBlock)
    | TRY resourceSpecification block catchClause* finallyBlock?
    | SWITCH '(' expression ')' '{' switchBlockStatementGroup* switchLabel* '}'
    | SYNCHRONIZED '(' expression ')' block
    | RETURN expression? ';'
    | THROW expression ';'
    | BREAK identifier? ';'
    | CONTINUE identifier? ';'
    | YIELD expression ';'
    | SEMI
    | statementExpression = expression ';'
    | switchExpression ';'?
    | identifierLabel = identifier ':' statement
    ;

catchClause
    : CATCH '(' variableModifier* catchType identifier ')' block
    ;

catchType
    : qualifiedName ('|' qualifiedName)*
    ;

finallyBlock
    : FINALLY block
    ;

resourceSpecification
    : '(' resources ';'? ')'
    ;

resources
    : resource (';' resource)*
    ;

resource
    : variableModifier* (classOrInterfaceType variableDeclaratorId | VAR identifier) '=' expression
    | qualifiedName
    ;

/** Matches cases then statements, both of which are mandatory.
 *  To handle empty cases at the end, we add switchLabel* to statement.
 */
switchBlockStatementGroup
    : (switchLabel ':')+ blockStatement+
    ;

switchLabel
    : CASE (
        constantExpression = expression
        | enumConstantName = IDENTIFIER
        | typeType varName = identifier
    )
    | DEFAULT
    ;

forControl
    : enhancedForControl
    | forInit? ';' expression? ';' forUpdate = expressionList?
    ;

forInit
    : localVariableDeclaration
    | expressionList
    ;

enhancedForControl
    : variableModifier* (typeType | VAR) variableDeclaratorId ':' expression
    ;

// EXPRESSIONS

expressionList
    : expression (',' expression)*
    ;

methodCall
    : (identifier | THIS | SUPER) arguments
    ;

expression
    // Expression order in accordance with https://introcs.cs.princeton.edu/java/11precedence/
    // Level 16, Primary, array and member access
    : primary                                                       #PrimaryExpression
    | expression '[' expression ']'                                 #SquareBracketExpression
    | expression bop = '.' (
        identifier
        | methodCall
        | THIS
        | NEW nonWildcardTypeArguments? innerCreator
        | SUPER superSuffix
        | explicitGenericInvocation
    )                                                               #MemberReferenceExpression
    // Method calls and method references are part of primary, and hence level 16 precedence
    | methodCall                                                    #MethodCallExpression
    | expression '::' typeArguments? identifier                     #MethodReferenceExpression
    | typeType '::' (typeArguments? identifier | NEW)               #MethodReferenceExpression
    | classType '::' typeArguments? NEW                             #MethodReferenceExpression
    
    | switchExpression                                              #ExpressionSwitch

    // Level 15 Post-increment/decrement operators
    | expression postfix = ('++' | '--')                            #PostIncrementDecrementOperatorExpression

    // Level 14, Unary operators
    | prefix = ('+' | '-' | '++' | '--' | '~' | '!') expression     #UnaryOperatorExpression

    // Level 13 Cast and object creation
    | '(' annotation* typeType ('&' typeType)* ')' expression       #CastExpression
    | NEW creator                                                   #ObjectCreationExpression

    // Level 12 to 1, Remaining operators
    // Level 12, Multiplicative operators
    | expression bop = ('*' | '/' | '%') expression           #BinaryOperatorExpression
    // Level 11, Additive operators
    | expression bop = ('+' | '-') expression                 #BinaryOperatorExpression
    // Level 10, Shift operators
    | expression ('<' '<' | '>' '>' '>' | '>' '>') expression #BinaryOperatorExpression
    // Level 9, Relational operators
    | expression bop = ('<=' | '>=' | '>' | '<') expression   #BinaryOperatorExpression
    | expression bop = INSTANCEOF (typeType | pattern)        #InstanceOfOperatorExpression
    // Level 8, Equality Operators
    | expression bop = ('==' | '!=') expression               #BinaryOperatorExpression
    // Level 7, Bitwise AND
    | expression bop = '&' expression                         #BinaryOperatorExpression
    // Level 6, Bitwise XOR
    | expression bop = '^' expression                         #BinaryOperatorExpression
    // Level 5, Bitwise OR
    | expression bop = '|' expression                         #BinaryOperatorExpression
    // Level 4, Logic AND
    | expression bop = '&&' expression                        #BinaryOperatorExpression
    // Level 3, Logic OR
    | expression bop = '||' expression                        #BinaryOperatorExpression
    // Level 2, Ternary
    | <assoc = right> expression bop = '?' expression ':' expression #TernaryExpression
    // Level 1, Assignment
    | <assoc = right> expression bop = (
        '='
        | '+='
        | '-='
        | '*='
        | '/='
        | '&='
        | '|='
        | '^='
        | '>>='
        | '>>>='
        | '<<='
        | '%='
    ) expression                                              #BinaryOperatorExpression

    // Level 0, Lambda Expression
    | lambdaExpression                                        #ExpressionLambda
    ;

pattern
    : variableModifier* typeType annotation* variableDeclarators
    | typeType '(' componentPatternList? ')'
    ;

componentPatternList :
    componentPattern ( ',' componentPattern )*
    ;

componentPattern :
    pattern
    ;

lambdaExpression
    : lambdaParameters '->' lambdaBody
    ;

lambdaParameters
    : identifier
    | '(' formalParameterList? ')'
    | '(' identifier (',' identifier)* ')'
    | '(' lambdaLVTIList? ')'
    ;

lambdaBody
    : expression
    | block
    ;

primary
    : '(' expression ')'
    | THIS
    | SUPER
    | literal
    | identifier
    | typeTypeOrVoid '.' CLASS
    | nonWildcardTypeArguments (explicitGenericInvocationSuffix | THIS arguments)
    ;

switchExpression
    : SWITCH '(' expression ')' '{' switchLabeledRule* '}'
    ;

switchLabeledRule
    : CASE (
	expressionList
	| NULL_LITERAL (',' DEFAULT)?
	| casePattern (',' casePattern)* guard?
	) (ARROW | COLON) switchRuleOutcome
    | DEFAULT (ARROW | COLON) switchRuleOutcome
    ;

guard 
    : 'when' expression
    ;

casePattern
    : pattern
    ;

switchRuleOutcome
    : block
    | blockStatement* // is *-operator correct??? I don't think so. https://docs.oracle.com/javase/specs/jls/se24/html/jls-14.html#jls-BlockStatements
    ;

classOrInterfaceType
    : classType // classType, interfaceType are all essentially identical to classOrInterfaceType because of no symbol table.
    ;

creator
    : nonWildcardTypeArguments? createdName classCreatorRest
    | createdName arrayCreatorRest
    ;

createdName
    : identifier typeArgumentsOrDiamond? ('.' identifier typeArgumentsOrDiamond?)*
    | primitiveType
    ;

innerCreator
    : identifier nonWildcardTypeArgumentsOrDiamond? classCreatorRest
    ;

arrayCreatorRest
    : ('[' ']')+ arrayInitializer
    | ('[' expression ']')+ ('[' ']')*
    ;

classCreatorRest
    : arguments classBody?
    ;

explicitGenericInvocation
    : nonWildcardTypeArguments explicitGenericInvocationSuffix
    ;

typeArgumentsOrDiamond
    : '<' '>'
    | typeArguments
    ;

nonWildcardTypeArgumentsOrDiamond
    : '<' '>'
    | nonWildcardTypeArguments
    ;

nonWildcardTypeArguments
    : '<' typeList '>'
    ;

typeList
    : typeType (',' typeType)*
    ;

typeType
    : annotation* (classOrInterfaceType | primitiveType) (annotation* '[' ']')*
    ;

primitiveType
    : BOOLEAN
    | CHAR
    | BYTE
    | SHORT
    | INT
    | LONG
    | FLOAT
    | DOUBLE
    ;

typeArguments
    : '<' typeArgument (',' typeArgument)* '>'
    ;

superSuffix
    : arguments
    | '.' typeArguments? identifier arguments?
    ;

explicitGenericInvocationSuffix
    : SUPER superSuffix
    | identifier arguments
    ;

arguments
    : '(' expressionList? ')'
    ;

/** A canonical comment: the Why of the unit it precedes, holding prose, reference citations, and license citations between its delimiters. A comment the grammar accepts but binds to nothing is labeled orphan and reported. ref:DEC-comment-reasons ref:DEC-grammar-carries-extraction-rules */
canonicalComment
    : DOC_OPEN docPart* DOC_CLOSE
    ;

/** One piece of a canonical comment: a reference citation, a license citation, or prose. ref:DEC-grammar-carries-extraction-rules */
docPart
    : ref = DOC_REF
    | license = DOC_LICENSE
    | DOC_WORD
    | DOC_PUNCT
    ;
