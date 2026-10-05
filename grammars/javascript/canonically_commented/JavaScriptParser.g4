/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 by Bart Kiers (original author) and Alexandre Vitorelli (contributor -> ported to CSharp)
 * Copyright (c) 2017-2020 by Ivan Kochurkin (Positive Technologies):
    added ECMAScript 6 support, cleared and transformed to the universal grammar.
 * Copyright (c) 2018 by Juan Alvarez (contributor -> ported to Go)
 * Copyright (c) 2019 by Student Main (contributor -> ES2020)
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

parser grammar JavaScriptParser;

// canon: the canonically commented dialect of the JavaScript grammar. JSDoc comments are canonical
// comments on the default channel; each declaration a JSDoc comment documents is a labeled unit
// alternative with its Why, its What, and where it differs from the whole node its How; a JSDoc
// comment the grammar accepts but binds to nothing is an orphan. Every change from the plain grammar
// is marked canon: and listed in grammars/javascript/README.md.

// Insert here @header for C++ parser.

options {
    tokenVocab = JavaScriptLexer;
    superClass = JavaScriptParserBase;
}

// canon: the first JSDoc comment of a file is the file's Why when a blank line or an import follows
// it, or when it holds a file tag such as @file, @module, or @license; otherwise it documents the
// declaration below it. A JSDoc comment at the end of a file binds to nothing.
program
    : HashBangLine? (
        why = fileComment DOC_BLANK_LINE? importStatement
        | why = fileComment DOC_BLANK_LINE
        | why = taggedFileComment DOC_BLANK_LINE?
    )? moduleItem* (orphan = canonicalComment)* EOF
    ;

// canon: a statement at the top of a module, where a variable statement declares a binding the
// module may export, as a function or class declaration does anywhere.
moduleItem
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export)? varModifier what = assignable ('=' singleExpression)? (
        ',' variableDeclaration
    )* eos # variable
    | statement
    ;

sourceElement
    : statement
    ;

// canon: function and class declarations come first, so a JSDoc comment above one binds to it; a
// JSDoc comment above any other statement binds to nothing.
statement
    : functionDeclaration
    | classDeclaration
    | (orphan = canonicalComment)* block
    | (orphan = canonicalComment)* variableStatement
    | (orphan = canonicalComment)* importStatement
    | exportStatement
    | (orphan = canonicalComment)* emptyStatement_
    | (orphan = canonicalComment)* expressionStatement
    | (orphan = canonicalComment)* ifStatement
    | (orphan = canonicalComment)* iterationStatement
    | (orphan = canonicalComment)* continueStatement
    | (orphan = canonicalComment)* breakStatement
    | (orphan = canonicalComment)* returnStatement
    | (orphan = canonicalComment)* yieldStatement
    | (orphan = canonicalComment)* withStatement
    | (orphan = canonicalComment)* labelledStatement
    | (orphan = canonicalComment)* switchStatement
    | (orphan = canonicalComment)* throwStatement
    | (orphan = canonicalComment)* tryStatement
    | (orphan = canonicalComment)* debuggerStatement
    ;

// canon: a JSDoc comment after the last statement of a block binds to nothing.
block
    : '{' statementList? (orphan = canonicalComment)* '}'
    ;

statementList
    : statement+
    ;

importStatement
    : Import importFromBlock
    ;

importFromBlock
    : importDefault? (importNamespace | importModuleItems) importFrom eos
    | StringLiteral eos
    ;

importModuleItems
    : '{' (importAliasName ',')* (importAliasName ','?)? '}'
    ;

importAliasName
    : moduleExportName (As importedBinding)?
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
// module exports is its API. An exported declaration holds its export keyword itself, in
// moduleItem, functionDeclaration, and classDeclaration; a JSDoc comment above a list of exports
// binds to nothing.
exportStatement
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) required = Export what = Default singleExpression eos # export
    | (orphan = canonicalComment)* Export exportFromBlock eos # ExportDeclaration
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
    : variableDeclarationList eos
    ;

variableDeclarationList
    : varModifier variableDeclaration (',' variableDeclaration)*
    ;

singleVariableDeclaration
    : varModifier variableDeclaration
    ;

variableDeclaration
    : assignable ('=' singleExpression)? // ECMAScript 6: Array & Object Matching
    ;

emptyStatement_
    : SemiColon
    ;

expressionStatement
    : {this.notOpenBraceAndNotFunction()}? expressionSequence eos
    ;

ifStatement
    : If '(' expressionSequence ')' statement (Else statement)?
    ;

iterationStatement
    : Do statement While '(' expressionSequence ')' eos                                                                     # DoStatement
    | While '(' expressionSequence ')' statement                                                                            # WhileStatement
    | For '(' (expressionSequence | variableDeclarationList)? ';' expressionSequence? ';' expressionSequence? ')' statement # ForStatement
    | For '(' (singleExpression | singleVariableDeclaration) In expressionSequence ')' statement                            # ForInStatement
    | For Await? '(' (singleExpression | singleVariableDeclaration) Of expressionSequence ')' statement                     # ForOfStatement
    ;

varModifier // let, const - ECMAScript 6
    : Var
    | let_
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

// canon: a JSDoc comment before a case, a default, or the closing brace binds to nothing.
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
    : Catch ('(' assignable? ')')? block
    ;

finallyProduction
    : Finally block
    ;

debuggerStatement
    : Debugger eos
    ;

// canon: a function declaration is a unit wherever it stands; export and export default are part
// of it, and export is labeled required.
functionDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export Default?)? Async? Function_ '*'? what = identifier '(' formalParameterList? ')' how = functionBody # function
    ;

// canon: a class declaration is a unit wherever it stands. Its members are as exported as it is,
// so its tail is labeled inherited.
classDeclaration
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (required = Export Default?)? Class what = identifier inherited = classTail # class
    ;

// canon: a JSDoc comment after the last member binds to nothing.
classTail
    : (Extends singleExpression)? '{' classElement* (orphan = canonicalComment)* '}'
    ;

// canon: each method, accessor, and field is a unit; a static block is none.
classElement
    : ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (Static | {this.n("static")}? identifier)? accessorDefinition # accessor
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (Static | {this.n("static")}? identifier)? methodDefinition # method
    | ((orphan = canonicalComment)+ why = canonicalComment | why = canonicalComment?) (Static | {this.n("static")}? identifier)? fieldDefinition # field
    | (orphan = canonicalComment)* (Static | {this.n("static")}? identifier) block
    | (orphan = canonicalComment)* emptyStatement_
    ;

methodDefinition
    : (Async {this.notLineTerminator()}?)? '*'? what = classElementName '(' formalParameterList? ')' how = functionBody
    ;

// canon: the getter and setter alternatives of methodDefinition, a rule of their own so that an
// accessor is a unit of its own kind, named by get or set and its property, and a getter and setter
// pair are two units.
accessorDefinition
    : '*'? what = getter '(' ')' how = functionBody
    | '*'? what = setter '(' formalParameterList? ')' how = functionBody
    ;

fieldDefinition
    : what = classElementName initializer?
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
    : formalParameterArg (',' formalParameterArg)* (',' lastFormalParameterArg)?
    | lastFormalParameterArg
    ;

// canon: a JSDoc comment before a parameter, as an inline type, binds to nothing.
formalParameterArg
    : (orphan = canonicalComment)* assignable ('=' singleExpression)? // ECMAScript 6: Initialization
    ;

lastFormalParameterArg // ECMAScript 6: Rest Parameter
    : (orphan = canonicalComment)* Ellipsis singleExpression
    ;

// canon: a JSDoc comment after the last statement of a body binds to nothing.
functionBody
    : '{' sourceElements? (orphan = canonicalComment)* '}'
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

arrayElement
    : Ellipsis? singleExpression
    ;

// canon: an object literal is an expression, so a JSDoc comment on one of its properties binds to
// nothing.
propertyAssignment
    : (orphan = canonicalComment)* propertyName ':' singleExpression                                  # PropertyExpressionAssignment
    | (orphan = canonicalComment)* '[' singleExpression ']' ':' singleExpression                      # ComputedPropertyExpressionAssignment
    | (orphan = canonicalComment)* Async? '*'? propertyName '(' formalParameterList? ')' functionBody # FunctionProperty
    | (orphan = canonicalComment)* getter '(' ')' functionBody                                        # PropertyGetter
    | (orphan = canonicalComment)* setter '(' formalParameterArg ')' functionBody                     # PropertySetter
    | (orphan = canonicalComment)* Ellipsis? singleExpression                                         # PropertyShorthand
    ;

propertyName
    : identifierName
    | StringLiteral
    | numericLiteral
    | '[' singleExpression ']'
    ;

// canon: a JSDoc comment before the closing parenthesis binds to nothing.
arguments
    : '(' (argument (',' argument)* ','?)? (orphan = canonicalComment)* ')'
    ;

argument
    : (orphan = canonicalComment)* Ellipsis? (singleExpression | identifier)
    ;

expressionSequence
    : singleExpression (',' singleExpression)*
    ;

singleExpression
    : anonymousFunction                                                    # FunctionExpression
    | Class identifier? classTail                                          # ClassExpression
    | singleExpression '?.'? '[' expressionSequence ']'                    # MemberIndexExpression
    | singleExpression ('?.' | '.') '#'? identifierName                    # MemberDotExpression
    // Split to try `new Date()` first, then `new Date`.
    | New identifier arguments                                             # NewExpression
    | New singleExpression arguments                                       # NewExpression
    | New singleExpression                                                 # NewExpression
    | singleExpression '?.'? arguments                                     # ArgumentsExpression
    | New '.' identifier                                                   # MetaExpression // new.target
    | singleExpression {this.notLineTerminator()}? '++'                    # PostIncrementExpression
    | singleExpression {this.notLineTerminator()}? '--'                    # PostDecreaseExpression
    | Delete singleExpression                                              # DeleteExpression
    | Void singleExpression                                                # VoidExpression
    | Typeof singleExpression                                              # TypeofExpression
    | '++' singleExpression                                                # PreIncrementExpression
    | '--' singleExpression                                                # PreDecreaseExpression
    | '+' singleExpression                                                 # UnaryPlusExpression
    | '-' singleExpression                                                 # UnaryMinusExpression
    | '~' singleExpression                                                 # BitNotExpression
    | '!' singleExpression                                                 # NotExpression
    | Await singleExpression                                               # AwaitExpression
    | (orphan = canonicalComment) singleExpression                         # DocumentedExpression // canon: a JSDoc comment inside an expression, as a type cast, binds to nothing
    | <assoc = right> singleExpression '**' singleExpression               # PowerExpression
    | singleExpression ('*' | '/' | '%') singleExpression                  # MultiplicativeExpression
    | singleExpression ('+' | '-') singleExpression                        # AdditiveExpression
    | singleExpression '??' singleExpression                               # CoalesceExpression
    | singleExpression ('<<' | '>>' | '>>>') singleExpression              # BitShiftExpression
    | singleExpression ('<' | '>' | '<=' | '>=') singleExpression          # RelationalExpression
    | singleExpression Instanceof singleExpression                         # InstanceofExpression
    | singleExpression In singleExpression                                 # InExpression
    | singleExpression ('==' | '!=' | '===' | '!==') singleExpression      # EqualityExpression
    | singleExpression '&' singleExpression                                # BitAndExpression
    | singleExpression '^' singleExpression                                # BitXOrExpression
    | singleExpression '|' singleExpression                                # BitOrExpression
    | singleExpression '&&' singleExpression                               # LogicalAndExpression
    | singleExpression '||' singleExpression                               # LogicalOrExpression
    | singleExpression '?' singleExpression ':' singleExpression           # TernaryExpression
    | <assoc = right> singleExpression '=' singleExpression                # AssignmentExpression
    | <assoc = right> singleExpression assignmentOperator singleExpression # AssignmentOperatorExpression
    | Import '(' singleExpression ')'                                      # ImportExpression
    | Import '.' identifierName                                            # ImportMetaExpression // canon: import.meta
    | singleExpression templateStringLiteral                               # TemplateStringExpression // ECMAScript 6
    | yieldStatement                                                       # YieldExpression          // ECMAScript 6
    | This                                                                 # ThisExpression
    | identifier                                                           # IdentifierExpression
    | Super                                                                # SuperExpression
    | literal                                                              # LiteralExpression
    | arrayLiteral                                                         # ArrayLiteralExpression
    | objectLiteral                                                        # ObjectLiteralExpression
    | '(' expressionSequence ')'                                           # ParenthesizedExpression
    ;

initializer
    // TODO: must be `= AssignmentExpression` and we have such label alredy but it doesn't respect the specification.
    //  See https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#prod-Initializer
    : '=' singleExpression
    ;

assignable
    : identifier
    | keyword
    | arrayLiteral
    | objectLiteral
    ;

objectLiteral
    : '{' (propertyAssignment (',' propertyAssignment)* ','?)? (orphan = canonicalComment)* '}'
    ;

// canon: a named function expression is an expression, not a declaration, so it is no unit.
anonymousFunction
    : Async? Function_ '*'? identifier '(' formalParameterList? ')' functionBody # NamedFunction
    | Async? Function_ '*'? '(' formalParameterList? ')' functionBody # AnonymousFunctionDecl
    | Async? arrowFunctionParameters '=>' arrowFunctionBody           # ArrowFunction
    ;

arrowFunctionParameters
    : propertyName
    | '(' formalParameterList? ')'
    ;

arrowFunctionBody
    : singleExpression
    | functionBody
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
    | NonStrictLet
    | Async
    | As
    | From
    | Yield
    | Of
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
    | let_
    | Private
    | Public
    | Interface
    | Package
    | Protected
    | Static
    | Yield
    | YieldStar
    | Async
    | Await
    | From
    | As
    | Of
    ;

let_
    : NonStrictLet
    | StrictLet
    ;

eos
    : SemiColon
    | EOF
    | {this.lineTerminatorAhead()}?
    | {this.closeBrace()}?
    ;

// canon: a canonical comment, a JSDoc block, holding prose, reference citations, and license
// citations. The first JSDoc comment of a file may document the declaration below it.
canonicalComment
    : DOC_BLOCK_OPEN docPart* DOC_BLOCK_CLOSE
    | FILE_DOC_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: the first JSDoc comment of a file, when it may be the file's Why.
fileComment
    : FILE_DOC_OPEN docPart* DOC_BLOCK_CLOSE
    ;

// canon: the first JSDoc comment of a file holding a file tag, which is always the file's Why.
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