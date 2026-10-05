// canon: the TypeScript lexer of a .tsx file: TypeScriptLexer.g4 beside it, whose rules it imports,
// under the base class TypeScriptJsxLexerBase, whose hook reads JSX. A .ts file is read by
// TypeScriptLexer.g4 itself, where <T>x is a type assertion; TypeScript tells the two by the
// file's extension, and a profile does so by naming one lexer or the other. ref:DEC-javascript-jsx
lexer grammar TypeScriptJsxLexer;

import TypeScriptLexer;

channels {
    ERROR
}

tokens {
    MODULE_QUOTE,
    MODULE_NAME
}

options {
    superClass = TypeScriptJsxLexerBase;
}
