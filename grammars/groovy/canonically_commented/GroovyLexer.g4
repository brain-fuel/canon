/*
 * This file is adapted from the Antlr4 Java grammar which has the following license
 *
 *  Copyright (c) 2013 Terence Parr, Sam Harwell
 *  All rights reserved.
 *  [The "BSD licence"]
 *
 *    http://www.opensource.org/licenses/bsd-license.php
 *
 * Subsequent modifications by the Groovy community have been done under the Apache License v2:
 *
 *  Licensed to the Apache Software Foundation (ASF) under one
 *  or more contributor license agreements.  See the NOTICE file
 *  distributed with this work for additional information
 *  regarding copyright ownership.  The ASF licenses this file
 *  to you under the Apache License, Version 2.0 (the
 *  "License"); you may not use this file except in compliance
 *  with the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

/**
 * The Groovy grammar is based on the optimized Java grammar:
 * https://github.com/antlr/grammars-v4/tree/master/java/java
 */
lexer grammar GroovyLexer;

// canon: the canonically commented dialect of the Groovy lexer. A Groovydoc comment, /** ... */, is
// a canonical comment on the default channel, tokenized in the DocBlock mode into prose, ref:KEY,
// and license:KEY; every change from the plain grammar is marked canon: and listed in
// grammars/groovy/README.md.

// canon: the superclass is named GroovyLexerBase rather than upstream's AbstractLexer, so the hook canon
// selects by that name cannot be chosen by another grammar whose superclass has the generic name.
options {
    superClass = GroovyLexerBase;
}

@header {
    import java.util.*;
    import java.util.function.Supplier;
    import org.apache.groovy.util.Maps;
    import static org.apache.groovy.parser.antlr4.SemanticPredicates.*;
}

@members {
    private boolean errorIgnored;
    private long tokenIndex;
    private int  lastTokenType;

    /**
     * When {@code false}, the {@code val} keyword is treated as a regular
     * identifier (lexed as IDENTIFIER, not VAL). This can be used as a porting
     * aid for migrating to Groovy 6 if affected by the known breaking edge cases.
     * Controlled by system property {@code groovy.val.enabled} (default: {@code true}).
     */
    private static final boolean VAL_ENABLED =
            Boolean.parseBoolean(System.getProperty("groovy.val.enabled", "true"));
    private boolean isValEnabled() { return VAL_ENABLED; }

    /**
     * Record the index and token type of the current token while emitting tokens.
     */
    @Override
    public void emit(Token token) {
        this.tokenIndex++;

        int tokenType = token.getType();
        if (Token.DEFAULT_CHANNEL == token.getChannel()) {
            this.lastTokenType = tokenType;
        }

        if (RollBackOne == tokenType) {
            this.rollbackOneChar();
        }

        super.emit(token);
    }

    /**
     * Token types after which {@code /.../} must not be treated as a slashy string
     * (e.g. {@code a++ / b}, {@code list[i] / n}). {@link java.util.BitSet} gives
     * O(1) membership tests on this hot decision.
     */
    private static final BitSet REGEX_CHECK_SET = new BitSet();
    static {
        int[] regexCheckTypes = {
            DEC,
            INC,
            THIS,
            RBRACE,
            RBRACK,
            RPAREN,
            GStringEnd,
            NullLiteral,
            StringLiteral,
            BooleanLiteral,
            IntegerLiteral,
            FloatingPointLiteral,
            Identifier, CapitalizedIdentifier
        };
        for (int t : regexCheckTypes) {
            REGEX_CHECK_SET.set(t);
        }
    }

    private boolean isRegexAllowed() {
        return !REGEX_CHECK_SET.get(this.lastTokenType);
    }

    /**
     * just a hook, which will be overrided by GroovyLangLexer
     */
    protected void rollbackOneChar() {}

    private static class Paren {
        private String text;
        private int lastTokenType;
        private int line;
        private int column;

        public Paren(String text, int lastTokenType, int line, int column) {
            this.text = text;
            this.lastTokenType = lastTokenType;
            this.line = line;
            this.column = column;
        }

        public String getText() {
            return this.text;
        }

        public int getLastTokenType() {
            return this.lastTokenType;
        }

        @SuppressWarnings("unused")
        public int getLine() {
            return line;
        }

        @SuppressWarnings("unused")
        public int getColumn() {
            return column;
        }

        @Override
        public int hashCode() {
            return (int) (text.hashCode() * line + column);
        }

        @Override
        public boolean equals(Object obj) {
            if (!(obj instanceof Paren)) {
                return false;
            }

            Paren other = (Paren) obj;

            return this.text.equals(other.text) && (this.line == other.line && this.column == other.column);
        }
    }

    protected void enterParenCallback(String text) {}

    protected void exitParenCallback(String text) {}

    private final Deque<Paren> parenStack = new ArrayDeque<>(32);

    private void enterParen() {
        String text = getText();
        enterParenCallback(text);

        parenStack.push(new Paren(text, this.lastTokenType, getLine(), getCharPositionInLine()));
    }

    private void exitParen() {
        String text = getText();
        exitParenCallback(text);

        Paren paren = parenStack.peek();
        if (null == paren) return;
        parenStack.pop();
    }
    private boolean isInsideParens() {
        Paren paren = parenStack.peek();

        // We just care about "(", "[" and "?[", inside which the new lines will be ignored.
        // Notice: the new lines between "{" and "}" can not be ignored.
        if (null == paren) {
            return false;
        }

        String text = paren.getText();

        return ("(".equals(text) && TRY != paren.getLastTokenType()) // we don't treat try-paren(i.e. try (....)) as parenthesis
                    || "[".equals(text) || "?[".equals(text);
    }
    private void ignoreTokenInsideParens() {
        if (!this.isInsideParens()) {
            return;
        }

        this.setChannel(Token.HIDDEN_CHANNEL);
    }
    private void ignoreMultiLineCommentConditionally() {
        if (!this.isInsideParens() && isFollowedByWhiteSpaces(_input)) {
            return;
        }

        this.setChannel(Token.HIDDEN_CHANNEL);
    }

    @Override
    public int getSyntaxErrorSource() {
        return GroovySyntaxError.LEXER;
    }

    @Override
    public int getErrorLine() {
        return getLine();
    }

    @Override
    public int getErrorColumn() {
        return getCharPositionInLine() + 1;
    }

    @Override
    public int popMode() {
        try {
            return super.popMode();
        } catch (EmptyStackException ignore) { // raised when parens are unmatched: too many ), ], or }
        }

        return Integer.MIN_VALUE;
    }

    private void addComment(int type) {
        Supplier<String> textSupplier = () -> _input.getText(Interval.of(_tokenStartCharIndex, getCharIndex() - 1));
        handleComment(type, textSupplier);
    }

    protected void handleComment(int type, Supplier<String> textSupplier) {
    }

    private static boolean isJavaIdentifierStartAndNotIdentifierIgnorable(int codePoint) {
        return Character.isJavaIdentifierStart(codePoint) && !Character.isIdentifierIgnorable(codePoint);
    }

    private static boolean isJavaIdentifierPartAndNotIdentifierIgnorable(int codePoint) {
        return Character.isJavaIdentifierPart(codePoint) && !Character.isIdentifierIgnorable(codePoint);
    }

    /**
     * Code point just consumed. After a UTF-16 surrogate pair, {@code LA(-1)}
     * is the low surrogate and is never uppercase — {@code Character.isUpperCase}
     * must see the pair (GROOVY-12398).
     */
    private int lastConsumedCodePoint() {
        int c1 = _input.LA(-1);
        int c2 = _input.LA(-2);
        if (c1 >= Character.MIN_LOW_SURROGATE && c1 <= Character.MAX_LOW_SURROGATE
                && c2 >= Character.MIN_HIGH_SURROGATE && c2 <= Character.MAX_HIGH_SURROGATE) {
            return Character.toCodePoint((char) c2, (char) c1);
        }
        return c1;
    }

    private boolean isSupplementaryCapitalizedIdentifierStart() {
        int cp = lastConsumedCodePoint();
        return Character.isJavaIdentifierStart(cp) && Character.isUpperCase(cp);
    }

    private boolean isSupplementaryUncapitalizedIdentifierStart() {
        int cp = lastConsumedCodePoint();
        return Character.isJavaIdentifierStart(cp) && !Character.isUpperCase(cp);
    }

    public boolean isErrorIgnored() {
        return errorIgnored;
    }

    public void setErrorIgnored(boolean errorIgnored) {
        this.errorIgnored = errorIgnored;
    }
}


// §3.10.5 String Literals
// canon: the predicates that looked ahead in the character stream are written as characters: a
// slashy string's first character is not a star, one or two quotes before the closing quotes of a
// triple-quoted string belong to it, a dollar before a slashy string's closing slash belongs to it,
// and slashes before a dollar slashy string's closing /$ belong to it. A slashy string may hold only
// dollars, as /$/ does, and a dollar slashy string may end in a dollar or a $/ escape before its
// closing /$, as $/a$/$ and $/a$//$ do, since neither dollar starts a value. isRegexAllowed is
// decided by the Canon.Antlr4.Lex.Groovy hook.
StringLiteral
    :   GStringQuotationMark  DqStringCharacter*  GStringQuotationMark
    |   SqStringQuotationMark  SqStringCharacter*  SqStringQuotationMark
    |   Slash { this.isRegexAllowed() }?  (SlashyStringFirstCharacter SlashyStringCharacter* Dollar* | Dollar+) Slash

    |   TdqStringQuotationMark  TdqStringCharacter* GStringQuotationMark? GStringQuotationMark? TdqStringQuotationMark
    |   TsqStringQuotationMark  TsqStringCharacter* SqStringQuotationMark? SqStringQuotationMark? TsqStringQuotationMark
    |   DollarSlashyGStringQuotationMarkBegin  (DollarSlashyStringCharacter+ (DollarSlashEscape | Dollar+)? | DollarSlashEscape | Dollar+) Slash* DollarSlashyGStringQuotationMarkEnd
    ;

GStringBegin
    :   GStringQuotationMark DqStringCharacter* Dollar -> pushMode(DQ_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
// canon: a dollar the string's characters do not take is followed by a letter or a brace, so the
// isFollowedByJavaLetterInGString predicates are dropped; see the character fragments below.
TdqGStringBegin
    :   TdqStringQuotationMark   TdqStringCharacter* GStringQuotationMark? GStringQuotationMark? Dollar -> type(GStringBegin), pushMode(TDQ_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
SlashyGStringBegin
    :   Slash { this.isRegexAllowed() }? (SlashyStringFirstCharacter SlashyStringCharacter*)? Dollar+ -> type(GStringBegin), pushMode(SLASHY_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
DollarSlashyGStringBegin
    :   DollarSlashyGStringQuotationMarkBegin DollarSlashyStringCharacter* Dollar -> type(GStringBegin), pushMode(DOLLAR_SLASHY_GSTRING_MODE), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;

// canon: the string modes moved to the end of the grammar, and mode DEFAULT_MODE no longer
// reopens the default mode, because canon reads each mode section as a whole mode and the second
// DEFAULT_MODE section would replace the rules above it.
// character in the double quotation string. e.g. "a"
fragment
DqStringCharacter
    :   ~["\r\n\\$]
    |   EscapeSequence
    ;

// character in the single quotation string. e.g. 'a'
fragment
SqStringCharacter
    :   ~['\r\n\\]
    |   EscapeSequence
    ;

// canon: canon's lexer predicates see the characters matched, not the ones ahead, so each predicate
// that looked ahead is written as the characters it allowed. One or two quotes are a character of
// a triple-quoted string when a character other than a quote follows them; a dollar is a character
// of a slashy string when a character that cannot start a GString value follows it, and is read
// with that character; a slash in a dollar slashy string is a character when anything but a dollar
// follows it. DollarSlashDollarEscape keeps its predicate, which looks behind, and the hook decides
// it.

// character in the triple double quotation string. e.g. """a"""
fragment TdqStringCharacter
    :   ~["\\$]
    |   GStringQuotationMark GStringQuotationMark? (~["\\$] | EscapeSequence)
    |   EscapeSequence
    ;

// character in the triple single quotation string. e.g. '''a'''
fragment TsqStringCharacter
    :   ~['\\]
    |   SqStringQuotationMark SqStringQuotationMark? (~['\\] | EscapeSequence)
    |   EscapeSequence
    ;

// character in the slashy string. e.g. /a/
fragment SlashyStringCharacter
    :   SlashEscape
    |   Dollar+ (SlashEscape | NotGStringValueStart)
    |   ~[/$\u0000]
    ;

// canon: the first character of a slashy string, which is not a star, so /* opens a comment.
fragment SlashyStringFirstCharacter
    :   SlashEscape
    |   Dollar+ (SlashEscape | NotGStringValueStart)
    |   ~[/$*\u0000]
    ;

// canon: a character after a dollar that does not make the dollar start a GString value: an ASCII
// character other than a letter, an underscore, or a brace, or a character beyond ASCII that cannot
// start a Java identifier, as upstream's isFollowedByJavaLetterInGString decided; the hook reads
// the character just matched, so a supplementary letter such as U+1D49C starts a value too.
fragment NotGStringValueStart
    :   ~[/$\u0000{a-zA-Z_\u0080-\u{10FFFF}]
    |   [\u0080-\u{10FFFF}] { !this.isJavaLetterInGString(_input.LA(-1)) }?
    ;

// character in the dollar slashy string. e.g. $/a/$
fragment DollarSlashyStringCharacter
    :   DollarDollarEscape
    |   DollarSlashDollarEscape { _input.LA(-4) != '$' }?
    |   DollarSlashEscape ~[$\u0000]
    |   Slash+ ~[$/\u0000]
    |   Dollar NotGStringValueStart
    |   ~[/$\u0000]
    ;

// Groovy keywords
AS              : 'as';
DEF             : 'def';
IN              : 'in';
TRAIT           : 'trait';
THREADSAFE      : 'threadsafe'; // reserved keyword
ASYNC           : 'async';
AWAIT           : 'await';
DEFER           : 'defer';

// §3.9 Keywords
BuiltInPrimitiveType
    :   BOOLEAN
    |   CHAR
    |   BYTE
    |   SHORT
    |   INT
    |   LONG
    |   FLOAT
    |   DOUBLE
    ;

ABSTRACT      : 'abstract';
ASSERT        : 'assert';

fragment
BOOLEAN       : 'boolean';

BREAK         : 'break';

fragment
BYTE          : 'byte';

CASE          : 'case';
CATCH         : 'catch';

fragment
CHAR          : 'char';

CLASS         : 'class';
CONST         : 'const';
CONTINUE      : 'continue';
DEFAULT       : 'default';
DO            : 'do';

fragment
DOUBLE        : 'double';

ELSE          : 'else';
ENUM          : 'enum';
EXTENDS       : 'extends';
FINAL         : 'final';
FINALLY       : 'finally';

fragment
FLOAT         : 'float';

FOR           : 'for';
IF            : 'if';
GOTO          : 'goto';
IMPLEMENTS    : 'implements';
IMPORT        : 'import';
INSTANCEOF    : 'instanceof';
INTERFACE     : 'interface';

fragment
INT           : 'int';

fragment
LONG          : 'long';

MODULE        : 'module';
NATIVE        : 'native';
NEW           : 'new';
NON_SEALED    : 'non-sealed';
PACKAGE       : 'package';
PERMITS       : 'permits';
PRIVATE       : 'private';
PROTECTED     : 'protected';
PUBLIC        : 'public';
RECORD        : 'record';
RETURN        : 'return';
SEALED        : 'sealed';

fragment
SHORT         : 'short';

STATIC        : 'static';
STRICTFP      : 'strictfp';
SUPER         : 'super';
SWITCH        : 'switch';
SYNCHRONIZED  : 'synchronized';
THIS          : 'this';
THROW         : 'throw';
THROWS        : 'throws';
TRANSIENT     : 'transient';
TRY           : 'try';
VAL           : 'val' {isValEnabled()}?;
VAR           : 'var';
VOID          : 'void';
VOLATILE      : 'volatile';
WHILE         : 'while';
YIELD         : 'yield';

// §3.10.1 Integer Literals
// Digit sequences use character classes (optimized Java grammar style) so the
// lexer DFA does not walk a chain of one-character fragment rules. The invalid
// octal alt validates once at the end rather than counting digits in an action
// loop, which would prevent DFA compilation of this token.

IntegerLiteral
    :   (   DecimalIntegerLiteral
        |   HexIntegerLiteral
        |   OctalIntegerLiteral
        |   BinaryIntegerLiteral
        ) (Underscore { require(errorIgnored, "Number ending with underscores is invalid", -1, false); })?

    // !!! Error Alternative !!!
    |   '0' [0-9]+ { requireInvalidOctal(errorIgnored); } IntegerTypeSuffix?
    ;

fragment
DecimalIntegerLiteral
    :   DecimalNumeral IntegerTypeSuffix?
    ;

fragment
HexIntegerLiteral
    :   HexNumeral IntegerTypeSuffix?
    ;

fragment
OctalIntegerLiteral
    :   OctalNumeral IntegerTypeSuffix?
    ;

fragment
BinaryIntegerLiteral
    :   BinaryNumeral IntegerTypeSuffix?
    ;

fragment
IntegerTypeSuffix
    :   [lLiIgG]
    ;

fragment
DecimalNumeral
    :   '0'
    |   [1-9] (Digits? | Underscores Digits)
    ;

fragment
Digits
    :   [0-9] ([0-9_]* [0-9])?
    ;

fragment
Underscores
    :   '_'+
    ;

fragment
Underscore
    :   '_'
    ;

fragment
HexNumeral
    :   '0' [xX] HexDigits
    ;

fragment
HexDigits
    :   HexDigit ([0-9a-fA-F_]* HexDigit)?
    ;

fragment
HexDigit
    :   [0-9a-fA-F]
    ;

fragment
OctalNumeral
    :   '0' '_'* OctalDigits
    ;

fragment
OctalDigits
    :   [0-7] ([0-7_]* [0-7])?
    ;

fragment
BinaryNumeral
    :   '0' [bB] BinaryDigits
    ;

fragment
BinaryDigits
    :   [01] ([01_]* [01])?
    ;

// §3.10.2 Floating-Point Literals

FloatingPointLiteral
    :   (   DecimalFloatingPointLiteral
        |   HexadecimalFloatingPointLiteral
        ) (Underscore { require(errorIgnored, "Number ending with underscores is invalid", -1, false); })?
    ;

fragment
DecimalFloatingPointLiteral
    :   Digits? '.' Digits ExponentPart? FloatTypeSuffix?
    |   Digits ExponentPart FloatTypeSuffix?
    |   Digits FloatTypeSuffix
    ;

fragment
ExponentPart
    :   [eE] [+\-]? Digits
    ;

fragment
FloatTypeSuffix
    :   [fFdDgG]
    ;

fragment
HexadecimalFloatingPointLiteral
    :   HexSignificand BinaryExponent FloatTypeSuffix?
    ;

fragment
HexSignificand
    :   HexNumeral '.'?
    |   '0' [xX] HexDigits? '.' HexDigits
    ;

fragment
BinaryExponent
    :   [pP] [+\-]? Digits
    ;

// §3.10.3 Boolean Literals

BooleanLiteral
    :   'true'
    |   'false'
    ;


// §3.10.6 Escape Sequences for Character and String Literals

fragment
EscapeSequence
    :   Backslash [btnfrs"'\\]
    |   OctalEscape
    |   UnicodeEscape
    |   DollarEscape
    |   LineEscape
    ;


fragment
OctalEscape
    :   Backslash [0-7]
    |   Backslash [0-7] [0-7]
    |   Backslash [0-3] [0-7] [0-7]
    ;

// Groovy allows 1 or more u's after the backslash
fragment
UnicodeEscape
    :   Backslash 'u' HexDigit HexDigit HexDigit HexDigit
    ;

// Groovy Escape Sequences

fragment
DollarEscape
    :   Backslash Dollar
    ;

fragment
LineEscape
    :   Backslash LineTerminator
    ;

fragment
LineTerminator
    :   '\r'? '\n' | '\r'
    ;

fragment
SlashEscape
    :   Backslash Slash
    ;

fragment
Backslash
    :   '\\'
    ;

fragment
Slash
    :   '/'
    ;

fragment
Dollar
    :   '$'
    ;

fragment
GStringQuotationMark
    :   '"'
    ;

fragment
SqStringQuotationMark
    :   '\''
    ;

fragment
TdqStringQuotationMark
    :   '"""'
    ;

fragment
TsqStringQuotationMark
    :   '\'\'\''
    ;

fragment
DollarSlashyGStringQuotationMarkBegin
    :   '$/'
    ;

fragment
DollarSlashyGStringQuotationMarkEnd
    :   '/$'
    ;

// escaped forward slash
fragment
DollarSlashEscape
    :   '$/'
    ;

// escaped dollar sign
fragment
DollarDollarEscape
    :   '$$'
    ;

// escaped dollar slashy string delimiter
fragment
DollarSlashDollarEscape
    :   '$/$'
    ;

// §3.10.7 The Null Literal
NullLiteral
    :   'null'
    ;

// Groovy Operators

RANGE_INCLUSIVE         : '..';
RANGE_EXCLUSIVE_LEFT    : '<..';
RANGE_EXCLUSIVE_RIGHT   : '..<';
RANGE_EXCLUSIVE_FULL    : '<..<';
SPREAD_DOT              : '*.';
SAFE_DOT                : '?.';
SAFE_INDEX              : '?[' { this.enterParen();     } -> pushMode(DEFAULT_MODE);
SAFE_CHAIN_DOT          : '??.';
ELVIS                   : '?:';
METHOD_POINTER          : '.&';
METHOD_REFERENCE        : '::';
REGEX_FIND              : '=~';
REGEX_MATCH             : '==~';
POWER                   : '**';
POWER_ASSIGN            : '**=';
SPACESHIP               : '<=>';
IDENTICAL               : '===';
IMPLIES                 : '==>';
NOT_IDENTICAL           : '!==';
ARROW                   : '->';

// !internalPromise will be parsed as !in ternalPromise, so semantic predicates are necessary
// canon: canon's lexer predicates cannot look ahead, so NOT_IN takes the letters after !in and the
// Canon.Antlr4.Lex.Groovy hook splits !internalPromise back into ! and an identifier, as upstream's
// isFollowedBy predicates decided.
NOT_INSTANCEOF      : '!instanceof';
NOT_IN              : '!in' JavaLetterOrDigit*;


// §3.11 Separators

LPAREN          : '('  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RPAREN          : ')'  { this.exitParen();      } -> popMode;

LBRACE          : '{'  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RBRACE          : '}'  { this.exitParen();      } -> popMode;

LBRACK          : '['  { this.enterParen();     } -> pushMode(DEFAULT_MODE);
RBRACK          : ']'  { this.exitParen();      } -> popMode;

SEMI            : ';';
COMMA           : ',';
DOT             : '.';

// §3.12 Operators

ASSIGN          : '=';
GT              : '>';
LT              : '<';
NOT             : '!';
BITNOT          : '~';
QUESTION        : '?';
COLON           : ':';
EQUAL           : '==';
LE              : '<=';
GE              : '>=';
NOTEQUAL        : '!=';
AND             : '&&';
OR              : '||';
INC             : '++';
DEC             : '--';
ADD             : '+';
SUB             : '-';
MUL             : '*';
DIV             : Slash;
BITAND          : '&';
BITOR           : '|';
XOR             : '^';
MOD             : '%';


ADD_ASSIGN      : '+=';
SUB_ASSIGN      : '-=';
MUL_ASSIGN      : '*=';
DIV_ASSIGN      : '/=';
AND_ASSIGN      : '&=';
OR_ASSIGN       : '|=';
XOR_ASSIGN      : '^=';
MOD_ASSIGN      : '%=';
LSHIFT_ASSIGN   : '<<=';
RSHIFT_ASSIGN   : '>>=';
URSHIFT_ASSIGN  : '>>>=';
ELVIS_ASSIGN    : '?=';


// §3.8 Identifiers (must appear after all keywords in the grammar)
// ASCII is a pure-DFA split ([A-Z] vs [a-z$_]) — no predicate on that hot path.
// BMP non-ASCII still uses LA(-1). Supplementary-plane letters must use the
// decoded code point: LA(-1) after a surrogate pair is the low surrogate,
// which is never uppercase, so the old isUpperCase(LA(-1)) test silently
// classified every supplementary identifier as Identifier (GROOVY-12398).
CapitalizedIdentifier
    :   [A-Z] JavaLetterOrDigit*
    |   ~[\u0000-\u007F\uD800-\uDBFF]
        { isJavaIdentifierStartAndNotIdentifierIgnorable(_input.LA(-1)) && Character.isUpperCase(_input.LA(-1)) }?
        JavaLetterOrDigit*
    |   [\uD800-\uDBFF] [\uDC00-\uDFFF]
        { isSupplementaryCapitalizedIdentifierStart() }?
        JavaLetterOrDigit*
    ;

Identifier
    :   [a-z$_] JavaLetterOrDigit*
    |   ~[\u0000-\u007F\uD800-\uDBFF]
        { isJavaIdentifierStartAndNotIdentifierIgnorable(_input.LA(-1)) && !Character.isUpperCase(_input.LA(-1)) }?
        JavaLetterOrDigit*
    |   [\uD800-\uDBFF] [\uDC00-\uDFFF]
        { isSupplementaryUncapitalizedIdentifierStart() }?
        JavaLetterOrDigit*
    ;

fragment
IdentifierInGString
    :   JavaLetterInGString JavaLetterOrDigitInGString*
    ;

fragment
JavaLetter
    :   [a-zA-Z$_] // these are the "java letters" below 0x7F
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        { isJavaIdentifierStartAndNotIdentifierIgnorable(_input.LA(-1)) }?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        { Character.isJavaIdentifierStart(Character.toCodePoint((char) _input.LA(-2), (char) _input.LA(-1))) }?
    ;

fragment
JavaLetterInGString
    :   JavaLetter { _input.LA(-1) != '$' }?
    ;

fragment
JavaLetterOrDigit
    :   [a-zA-Z0-9$_] // these are the "java letters or digits" below 0x7F
    |   // covers all characters above 0x7F which are not a surrogate
        ~[\u0000-\u007F\uD800-\uDBFF]
        { isJavaIdentifierPartAndNotIdentifierIgnorable(_input.LA(-1)) }?
    |   // covers UTF-16 surrogate pairs encodings for U+10000 to U+10FFFF
        [\uD800-\uDBFF] [\uDC00-\uDFFF]
        { Character.isJavaIdentifierPart(Character.toCodePoint((char) _input.LA(-2), (char) _input.LA(-1))) }?
    ;

fragment
JavaLetterOrDigitInGString
    :   JavaLetterOrDigit  { _input.LA(-1) != '$' }?
    ;

fragment
ShCommand
    :   ~[\r\n\uFFFF]*
    ;

//
// Additional symbols not defined in the lexical specification
//

AT : '@';
ELLIPSIS : '...';

//
// Whitespace, line escape and comments
//
WS  : ([ \t]+ | LineEscape+) -> skip
    ;

// Inside (...) and [...] but not {...}, ignore newlines.
NL  : LineTerminator   { ignoreTokenInsideParens(); }
    ;

// Multiple-line comments (including groovydoc comments).
// One outermost alt so `-> type(NL)` is legal. `.*?` then (`*/` | EOF) stops
// at the first closer; a *separate* lexer rule for unclosed comments would
// win by longest-match and swallow trailing source. javac reports
// "unclosed comment" at the opener; requireUnclosedComment keeps the caret there.
// canon: comments are hidden. Upstream made a comment a newline unless it was inside parentheses
// or code followed it on its line, which needs the characters ahead; a comment that ends its line
// is followed by the newline token itself, so hiding it leaves the parser the same separators.
// canon: /** opens a Groovydoc comment; a plain comment may not start with two stars, so /**/ and
// /*** stay plain by the longest match.
DOC_BLOCK_OPEN
    :   '/**' -> pushMode(DocBlock)
    ;

ML_COMMENT
    :   '/*' (~'*' .*? | '**' .*?)? ('*/' | EOF { requireUnclosedComment(errorIgnored); })
        { addComment(0); } -> channel(HIDDEN)
    ;

// Single-line comments
SL_COMMENT
    :   '//' ~[\r\n\uFFFF]* { addComment(1); }             -> channel(HIDDEN)
    ;

// Script-header comments.
// The very first characters of the file may be "#!".  If so, ignore the first line.
SH_COMMENT
    :   '#!' { require(errorIgnored || 0 == this.tokenIndex, "Shebang comment should appear at the first line", -2, false); } ShCommand (LineTerminator '#!' ShCommand)* -> skip
    ;

// Unexpected characters (and unclosed quotes / illegal string escapes).
// Display goes through AbstractLexer#getCharErrorDisplay. An unexpected
// quote is an unclosed string unless a scan-ahead finds an illegal escape
// in an otherwise closed literal (e.g. "C:\Users\me").
UNEXPECTED_CHAR
    :   . { requireUnexpectedCharacter(errorIgnored); }
    ;


// canon: a Groovydoc comment, closed by */; a star that decorates a line is dropped.
mode DocBlock;

DOC_BLOCK_CLOSE : '*/' -> popMode;
DOC_REF         : 'ref:' DocKey;
DOC_LICENSE     : 'license:' DocKey;
DOC_BLOCK_STAR  : '*' -> skip;
DOC_BLOCK_WS    : [ \t\r\n\u000C]+ -> skip;
DOC_PUNCT       : [,.;:()!?[\]{}"'`<>=+|/];
DOC_WORD        : ~[ \t\r\n\u000C*,.;:()!?[\]{}"'`<>=+|/]+;

fragment DocKey : [A-Za-z0-9] ([A-Za-z0-9._-]* [A-Za-z0-9])?;

// canon: the string modes, moved here from after GStringBegin's siblings above.
mode DQ_GSTRING_MODE;
GStringEnd
    :   GStringQuotationMark     -> popMode
    ;
GStringPart
    :   Dollar  -> pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
GStringCharacter
    :   DqStringCharacter -> more
    ;

mode TDQ_GSTRING_MODE;
// canon: one or two quotes before the closing quotes or before a dollar belong to the string,
// which upstream decided by looking ahead from each quote.
TdqGStringEnd
    :   GStringQuotationMark? GStringQuotationMark? TdqStringQuotationMark    -> type(GStringEnd), popMode
    ;
TdqGStringPart
    :   GStringQuotationMark? GStringQuotationMark? Dollar   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
TdqGStringCharacter
    :   TdqStringCharacter -> more
    ;

mode SLASHY_GSTRING_MODE;
// canon: every dollar before the closing slash belongs to the end, as $$/ does, since upstream read
// each such dollar as a character of the string.
SlashyGStringEnd
    :   Dollar* Slash  -> type(GStringEnd), popMode
    ;
// canon: a dollar that is not followed by a letter or a brace is a character of the string, and
// SlashyStringCharacter takes it with the character after it, so a part is any run of dollars the
// characters leave, which upstream decided with isFollowedByJavaLetterInGString.
SlashyGStringPart
    :   Dollar+   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
SlashyGStringCharacter
    :   SlashyStringCharacter -> more
    ;

mode DOLLAR_SLASHY_GSTRING_MODE;
// canon: slashes before the closing /$ belong to the string, and so does a $/ escape just before
// them, as in $//$; a dollar that the characters do not take, which is one followed by a letter or
// a brace, is a part, which upstream decided by looking ahead.
DollarSlashyGStringEnd
    :   DollarSlashEscape? Slash* DollarSlashyGStringQuotationMarkEnd      -> type(GStringEnd), popMode
    ;
DollarSlashyGStringPart
    :   Dollar   -> type(GStringPart), pushMode(GSTRING_TYPE_SELECTOR_MODE)
    ;
DollarSlashyGStringCharacter
    :   DollarSlashyStringCharacter -> more
    ;

mode GSTRING_TYPE_SELECTOR_MODE;
GStringLBrace
    :   '{' { this.enterParen();  } -> type(LBRACE), popMode, pushMode(DEFAULT_MODE)
    ;
GStringIdentifier
    :   IdentifierInGString -> type(Identifier), popMode, pushMode(GSTRING_PATH_MODE)
    ;


mode GSTRING_PATH_MODE;
GStringPathPart
    :   '.' IdentifierInGString
    ;
// canon: upstream consumed the character after a GString path and rolled the lexer back over it,
// which canon's lexer cannot do; an empty match that leaves the mode reads the character again in
// the string's own mode, as the rollback did.
RollBackOne
    :   -> popMode, skip
    ;

