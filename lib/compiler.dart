import 'dart:io';

import 'debug.dart';
import 'object.dart';

import 'common.dart';
import 'scanner.dart';
import 'chunk.dart';

enum Precedence {
  NONE,
  ASSIGNMENT, // =
  OR, // or
  AND, // and
  EQUALITY, // == !=
  COMPARISON, // < > <= >=
  TERM, // + -
  FACTOR, // * /
  UNARY, // ! -
  CALL, // . ()
  PRIMARY
}

enum FunctionType {
  FUNCTION,
  SCRIPT,
  METHOD,
  INITIALIZER,
}

typedef ParseFn = void Function(bool canAssign)?;

class ParseRule {
  ParseFn prefix;
  ParseFn infix;
  Precedence precedence;
  ParseRule(this.prefix, this.infix, this.precedence);
}

class Local {
  late Token name;
  late int depth;
  late bool isCaptured;
}

class Upvalue {
  late int index;
  late bool isLocal;
}

class Compiler {
  Compiler? enclosing;
  late ObjFunction function;
  late FunctionType type;
  List<Local> locals = [];
  List<Upvalue> upvalues = [];
  late int scopeDepth;
}

class ClassCompiler {
  late ClassCompiler? enclosing;
  late bool hasSuperClass;
}

class Parser {
  late Token current;
  late Token previous;
  late bool panicMode;
  late bool hadError;
}

Parser parser = Parser();
Compiler current = Compiler();
ClassCompiler? currentClass;
Chunk? compilingChunk;

void initCompiler(Compiler compiler, FunctionType type) {
  compiler.enclosing = current;
  compiler.function = newFunction();
  compiler.type = type;
  compiler.locals.length = 0;
  compiler.scopeDepth = 0;
  current = compiler;
  if (type != FunctionType.SCRIPT) {
    current.function.name = parser.previous.lexeme;
  }

  Local local = Local();
  local.depth = 0;
  local.isCaptured = false;
  if (type != FunctionType.FUNCTION) {
    local.name = Token();
    local.name.lexeme = "this";
  } else {
    local.name = Token();
    local.name.lexeme = "";
  }

  compiler.locals.add(local);
}

ObjFunction? compile(String source) {
  initScanner(source);
  Compiler compiler = Compiler();
  initCompiler(compiler, FunctionType.SCRIPT);

  parser.hadError = false;
  parser.panicMode = false;
  parser.current = makeToken(TokenType.DUMMY);

  advance();
  while (!match(TokenType.EOF)) {
    declaration();
  }

  ObjFunction function = endCompiler();
  return parser.hadError ? null : function;
}

void addLocal(Token name) {
  Local local = Local();
  local.name = name;
  local.depth = -1;
  local.isCaptured = false;
  current.locals.add(local);
}

int addUpvalue(Compiler compiler, int index, bool isLocal) {
  int upvalueCount = compiler.function.upvalueCount;

  for (int i = 0; i < upvalueCount; i++) {
    Upvalue upvalue = compiler.upvalues[i];
    if (upvalue.index == index && upvalue.isLocal == isLocal) {
      return i;
    }
  }
  Upvalue upvalue = Upvalue();
  upvalue.isLocal = isLocal;
  upvalue.index = index;
  compiler.upvalues.add(upvalue);
  return compiler.function.upvalueCount++;
}

void advance() {
  parser.previous = parser.current;

  for (;;) {
    parser.current = scanToken();
    if (parser.current.type != TokenType.ERROR) {
      break;
    }
    errorAtCurrent(parser.current.lexeme);
  }
}

void and(bool canAssign) {
  int endJump = emitJump(OP_JUMP_IF_FALSE);

  emitByte(OP_POP);
  parsePrecedence(Precedence.AND);

  patchJump(endJump);
}

int argumentList() {
  int argCount = 0;
  if (!check(TokenType.RIGHT_PAREN)) {
    do {
      expression();
      if (argCount == 255) {
        error("Can't have more than 255 arguments.");
      }
      argCount++;
    } while (match(TokenType.COMMA));
  }
  consume(TokenType.RIGHT_PAREN, "Expected ')' after arguments.");
  return argCount;
}

void beginScope() {
  current.scopeDepth++;
}

void binary(bool canAssign) {
  TokenType operatorType = parser.previous.type;
  ParseRule rule = getRule(operatorType);
  parsePrecedence(Precedence.values[rule.precedence.index + 1]);

  switch (operatorType) {
    case TokenType.PLUS:
      emitByte(OP_ADD);
    case TokenType.MINUS:
      emitByte(OP_SUBTRACT);
    case TokenType.STAR:
      emitByte(OP_MULTIPLY);
    case TokenType.SLASH:
      emitByte(OP_DIVIDE);
    case TokenType.BANG_EQUAL:
      emitBytes(OP_EQUAL, OP_NOT);
    case TokenType.EQUAL_EQUAL:
      emitByte(OP_EQUAL);
    case TokenType.GREATER:
      emitByte(OP_GREATER);
    case TokenType.GREATER_EQUAL:
      emitBytes(OP_LESS, OP_NOT);
    case TokenType.LESS:
      emitByte(OP_LESS);
    case TokenType.LESS_EQUAL:
      emitBytes(OP_GREATER, OP_NOT);
    default:
      return; // unreachable.
  }
}

void block() {
  while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
    declaration();
  }
  consume(TokenType.RIGHT_BRACE, "Expected '}' after block.");
}

void call(bool canAssign) {
  int argCount = argumentList();
  emitBytes(OP_CALL, argCount);
}

bool check(TokenType type) {
  return parser.current.type == type;
}

void classDeclaration() {
  consume(TokenType.IDENTIFIER, "Expected class name.");
  Token className = parser.previous;
  int nameConstant = identifierConstant(parser.previous);
  declareVariable();

  emitBytes(OP_CLASS, nameConstant);
  defineVariable(nameConstant);

  ClassCompiler? classCompiler = ClassCompiler();
  classCompiler.enclosing = currentClass;
  classCompiler.hasSuperClass = false;
  currentClass = classCompiler;

  if (match(TokenType.LESS)) {
    consume(TokenType.IDENTIFIER, "Expected superclass name.");
    variable(false);

    if (className.lexeme == parser.previous.lexeme) {
      error("A class can't inherit from itself.");
    }

    beginScope();
    Token token = Token();
    token.lexeme = "super";
    addLocal(token);
    defineVariable(0);

    namedVariable(className, false);
    emitByte(OP_INHERIT);
    classCompiler.hasSuperClass = true;
  }

  namedVariable(className, false);
  consume(TokenType.LEFT_BRACE, "Expected '{' before class body.");
  while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
    method();
  }

  consume(TokenType.RIGHT_BRACE, "Expected '}' after class body.");
  emitByte(OP_POP);
  if (classCompiler.hasSuperClass) {
    endScope();
  }
  currentClass = currentClass!.enclosing;
}

void consume(TokenType type, String message) {
  if (parser.current.type == type) {
    advance();
    return;
  }
  errorAtCurrent(message);
}

Chunk currentChunk() {
  return current.function.chunk;
}

void declaration() {
  if (match(TokenType.VAR)) {
    varDeclaration();
  } else if (match(TokenType.FUN)) {
    funDeclaration();
  } else if (match(TokenType.CLASS)) {
    classDeclaration();
  } else {
    statement();
  }

  if (parser.panicMode) synchronize();
}

void declareVariable() {
  if (current.scopeDepth == 0) return;

  Token name = parser.previous;
  for (int i = current.locals.length - 1; i >= 0; i--) {
    Local local = current.locals[i];
    if (local.depth != -1 && local.depth < current.scopeDepth) {
      break;
    }

    if (name.lexeme == local.name.lexeme) {
      error("Already a variable with this name in this scope.");
    }
  }
  addLocal(name);
}

void defineVariable(int global) {
  if (current.scopeDepth > 0) {
    markInitialized();
    return;
  }
  emitBytes(OP_DEFINE_GLOBAL, global);
}

void dot(bool canAssign) {
  consume(TokenType.IDENTIFIER, "Expected property name after '.'.");
  int name = identifierConstant(parser.previous);

  if (canAssign && match(TokenType.EQUAL)) {
    expression();
    emitBytes(OP_SET_PROPERTY, name);
  } else if (match(TokenType.LEFT_PAREN)) {
    int argCount = argumentList();
    emitBytes(OP_INVOKE, name);
    emitByte(argCount);
  } else {
    emitBytes(OP_GET_PROPERTY, name);
  }
}

void emitByte(int byte) {
  writeChunk(currentChunk(), byte, parser.previous.line);
}

void emitBytes(int byte1, int byte2) {
  emitByte(byte1);
  emitByte(byte2);
}

void emitConstant(Object value) {
  emitBytes(OP_CONSTANT, makeConstant(value));
}

int emitJump(int instruction) {
  emitByte(instruction);
  emitByte(0xff);
  emitByte(0xff);
  return currentChunk().code.length - 2;
}

void emitLoop(int loopStart) {
  emitByte(OP_LOOP);

  int offset = currentChunk().code.length - loopStart + 2;

  emitByte((offset >> 8) & 0xff);
  emitByte(offset & 0xff);
}

void emitReturn() {
  if (current.type == FunctionType.INITIALIZER) {
    emitBytes(OP_GET_LOCAL, 0);
  } else {
    emitByte(OP_NIL);
  }
  emitByte(OP_RETURN);
}

ObjFunction endCompiler() {
  emitReturn();
  ObjFunction function = current.function;
  if (debugPrintCode) {
    if (!parser.hadError) {
      disassembleChunk(currentChunk(), function.name ?? "<script>");
    }
  }
  current = current.enclosing!;
  return function;
}

void endScope() {
  current.scopeDepth--;

  while (current.locals.isNotEmpty &&
      current.locals.last.depth > current.scopeDepth) {
    if (current.locals[current.locals.length - 1].isCaptured) {
      emitByte(OP_CLOSE_UPVALUE);
    } else {
      emitByte(OP_POP);
    }

    current.locals.removeLast();
  }
}

void error(String message) {
  errorAt(parser.previous, message);
}

void errorAt(Token token, String? message) {
  if (parser.panicMode) return;
  parser.panicMode = true;

  stdout.write("[Line ${token.line}] Error");

  if (token.type == TokenType.EOF) {
    stdout.write(" at end ");
  } else if (token.type == TokenType.ERROR) {
    // nothing
  } else {
    stdout.write(" at '${token.lexeme}': ");
  }
  stdout.writeln(message);
  parser.hadError = true;
}

void errorAtCurrent(String? message) {
  errorAt(parser.current, message);
}

void expression() {
  parsePrecedence(Precedence.ASSIGNMENT);
}

void expressionStatement() {
  expression();
  consume(TokenType.SEMICOLON, "Expected ';' after expression.");
  emitByte(OP_POP);
}

void forStatement() {
  beginScope();
  consume(TokenType.LEFT_PAREN, "Expected '(' after 'for'.");
  if (match(TokenType.SEMICOLON)) {
    // No initializer.
  } else if (match(TokenType.VAR)) {
    varDeclaration();
  } else {
    expressionStatement();
  }

  int loopStart = currentChunk().code.length;
  int exitJump = -1;
  if (!match(TokenType.SEMICOLON)) {
    expression();
    consume(TokenType.SEMICOLON, "Expected ';' after loop condition.");

    // Jump out of the loop if the condition is false.
    exitJump = emitJump(OP_JUMP_IF_FALSE);
    emitByte(OP_POP); // Condition.
  }

  if (!match(TokenType.RIGHT_PAREN)) {
    int bodyJump = emitJump(OP_JUMP);
    int incrementStart = currentChunk().code.length;
    expression();
    emitByte(OP_POP);
    consume(TokenType.RIGHT_PAREN, "Expected ')' after for clauses.");

    emitLoop(loopStart);
    loopStart = incrementStart;
    patchJump(bodyJump);
  }

  statement();
  emitLoop(loopStart);

  if (exitJump != -1) {
    patchJump(exitJump);
    emitByte(OP_POP); // Condition.
  }

  endScope();
}

void function(FunctionType type) {
  Compiler compiler = Compiler();
  initCompiler(compiler, type);
  beginScope();

  consume(TokenType.LEFT_PAREN, "Expected '(' after function name.");

  if (!check(TokenType.RIGHT_PAREN)) {
    do {
      current.function.arity++;
      if (current.function.arity > 255) {
        errorAtCurrent("Can't have more than 255 parameters.");
      }
      int constant = parseVariable("Expected parameter name.");
      defineVariable(constant);
    } while (match(TokenType.COMMA));
  }

  consume(TokenType.RIGHT_PAREN, "Expected ')' after function parameters.");
  consume(TokenType.LEFT_BRACE, "Expected '{' before function body.");
  block();

  ObjFunction function = endCompiler();
  emitBytes(OP_CLOSURE, makeConstant(function));
  for (int i = 0; i < function.upvalueCount; i++) {
    emitByte(compiler.upvalues[i].isLocal ? 1 : 0);
    emitByte(compiler.upvalues[i].index);
  }
}

void funDeclaration() {
  int global = parseVariable("Expected function name.");
  markInitialized();
  function(FunctionType.FUNCTION);
  defineVariable(global);
}

ParseRule getRule(TokenType type) {
  return rules[type]!;
}

void grouping(bool canAssign) {
  expression();
  consume(TokenType.RIGHT_PAREN, "Expected ')' after expression.");
}

int identifierConstant(Token name) {
  return makeConstant(name.lexeme);
}

void ifStatement() {
  consume(TokenType.LEFT_PAREN, "Expected '(' after 'if'.");
  expression();
  consume(TokenType.RIGHT_PAREN, "Expected ')' after condition.");

  int thenJump = emitJump(OP_JUMP_IF_FALSE);
  emitByte(OP_POP);
  statement();

  int elseJump = emitJump(OP_JUMP);

  patchJump(thenJump);
  emitByte(OP_POP);

  if (match(TokenType.ELSE)) statement();
  patchJump(elseJump);
}

void literal(bool canAssign) {
  switch (parser.previous.type) {
    case TokenType.FALSE:
      emitByte(OP_FALSE);
    case TokenType.TRUE:
      emitByte(OP_TRUE);
    case TokenType.NIL:
      emitByte(OP_NIL);
    default:
      return;
    // unreachable
  }
}

int makeConstant(Object value) {
  int constant = addConstant(currentChunk(), value);
  return constant;
}

void markInitialized() {
  if (current.scopeDepth == 0) return;
  current.locals[current.locals.length - 1].depth = current.scopeDepth;
}

bool match(TokenType type) {
  if (!check(type)) return false;
  advance();
  return true;
}

void method() {
  consume(TokenType.IDENTIFIER, "Expected method name.");
  int constant = identifierConstant(parser.previous);
  FunctionType type = FunctionType.METHOD;
  if (parser.previous.lexeme == "init") {
    type = FunctionType.INITIALIZER;
  }
  function(type);

  emitBytes(OP_METHOD, constant);
}

void namedVariable(Token name, bool canAssign) {
  int getOp, setOp;
  int arg = resolveLocal(current, name);

  if (arg != -1) {
    getOp = OP_GET_LOCAL;
    setOp = OP_SET_LOCAL;
  } else if ((arg = resolveUpvalue(current, name)) != -1) {
    getOp = OP_GET_UPVALUE;
    setOp = OP_SET_UPVALUE;
  } else {
    arg = identifierConstant(name);
    getOp = OP_GET_GLOBAL;
    setOp = OP_SET_GLOBAL;
  }

  if (canAssign && match(TokenType.EQUAL)) {
    expression();
    emitBytes(setOp, arg);
  } else {
    emitBytes(getOp, arg);
  }
}

void number(bool canAssign) {
  double value = double.parse(parser.previous.lexeme);
  emitConstant(value);
}

void or(bool canAssign) {
  int elseJump = emitJump(OP_JUMP_IF_FALSE);
  int endJump = emitJump(OP_JUMP);

  patchJump(elseJump);
  emitByte(OP_POP);

  parsePrecedence(Precedence.OR);
  patchJump(endJump);
}

void parsePrecedence(Precedence precedence) {
  advance();
  ParseFn prefixRule = getRule(parser.previous.type).prefix;
  if (prefixRule == null) {
    error("Expected expression.");
    return;
  }
  bool canAssign = precedence.index <= Precedence.ASSIGNMENT.index;
  prefixRule(canAssign);

  while (precedence.index <= getRule(parser.current.type).precedence.index) {
    advance();
    ParseFn infixRule = getRule(parser.previous.type).infix;
    infixRule!(canAssign);
  }
  if (canAssign && match(TokenType.EQUAL)) {
    error("Invalid assignment target.");
  }
}

int parseVariable(String errorMessage) {
  consume(TokenType.IDENTIFIER, errorMessage);

  declareVariable();
  if (current.scopeDepth > 0) return 0;

  return identifierConstant(parser.previous);
}

void patchJump(int offset) {
  int jump = currentChunk().code.length - offset - 2;

  currentChunk().code[offset] = (jump >> 8) & 0xff;
  currentChunk().code[offset + 1] = jump & 0xff;
}

void printStatement() {
  expression();
  consume(TokenType.SEMICOLON, "Expected ';' after value in print statement.");
  emitByte(OP_PRINT);
}

int resolveLocal(Compiler compiler, Token name) {
  for (int i = compiler.locals.length - 1; i >= 0; i--) {
    Local local = compiler.locals[i];
    if (name.lexeme == local.name.lexeme) {
      if (local.depth == -1) {
        error("Can't read local variable in its own initializer.");
      }
      return i;
    }
  }
  return -1;
}

int resolveUpvalue(Compiler compiler, Token name) {
  if (compiler.enclosing == null) {
    return -1;
  }

  int local = resolveLocal(compiler.enclosing!, name);
  if (local != -1) {
    compiler.enclosing!.locals[local].isCaptured = true;
    return addUpvalue(compiler, local, true);
  }

  int upvalue = resolveUpvalue(compiler.enclosing!, name);
  if (upvalue != -1) {
    return addUpvalue(compiler, upvalue, false);
  }

  return -1;
}

void returnStatement() {
  if (current.type == FunctionType.SCRIPT) {
    error("Can't return from top-level code.");
  }

  if (match(TokenType.SEMICOLON)) {
    emitReturn();
  } else {
    if (current.type == FunctionType.INITIALIZER) {
      error("Can't return a value from an initializer.");
    }
    expression();
    consume(TokenType.SEMICOLON, "Expected ';' after return value.");
    emitByte(OP_RETURN);
  }
}

Map<TokenType, ParseRule> get rules => {
      TokenType.LEFT_PAREN: ParseRule(grouping, call, Precedence.CALL),
      TokenType.RIGHT_PAREN: ParseRule(null, null, Precedence.NONE),
      TokenType.LEFT_BRACE: ParseRule(null, null, Precedence.NONE),
      TokenType.RIGHT_BRACE: ParseRule(null, null, Precedence.NONE),
      TokenType.COMMA: ParseRule(null, null, Precedence.NONE),
      TokenType.DOT: ParseRule(null, dot, Precedence.CALL),
      TokenType.MINUS: ParseRule(unary, binary, Precedence.TERM),
      TokenType.PLUS: ParseRule(null, binary, Precedence.TERM),
      TokenType.SEMICOLON: ParseRule(null, null, Precedence.NONE),
      TokenType.SLASH: ParseRule(null, binary, Precedence.FACTOR),
      TokenType.STAR: ParseRule(null, binary, Precedence.FACTOR),
      TokenType.BANG: ParseRule(unary, null, Precedence.NONE),
      TokenType.BANG_EQUAL: ParseRule(null, null, Precedence.NONE),
      TokenType.EQUAL: ParseRule(null, null, Precedence.NONE),
      TokenType.EQUAL_EQUAL: ParseRule(null, binary, Precedence.EQUALITY),
      TokenType.GREATER: ParseRule(null, binary, Precedence.COMPARISON),
      TokenType.GREATER_EQUAL: ParseRule(null, binary, Precedence.COMPARISON),
      TokenType.LESS: ParseRule(null, binary, Precedence.COMPARISON),
      TokenType.LESS_EQUAL: ParseRule(null, binary, Precedence.COMPARISON),
      TokenType.IDENTIFIER: ParseRule(variable, null, Precedence.NONE),
      TokenType.STRING: ParseRule(string, null, Precedence.NONE),
      TokenType.NUMBER: ParseRule(number, null, Precedence.NONE),
      TokenType.AND: ParseRule(null, and, Precedence.AND),
      TokenType.CLASS: ParseRule(null, null, Precedence.NONE),
      TokenType.ELSE: ParseRule(null, null, Precedence.NONE),
      TokenType.FALSE: ParseRule(literal, null, Precedence.NONE),
      TokenType.FOR: ParseRule(null, null, Precedence.NONE),
      TokenType.FUN: ParseRule(null, null, Precedence.NONE),
      TokenType.IF: ParseRule(null, null, Precedence.NONE),
      TokenType.NIL: ParseRule(literal, null, Precedence.NONE),
      TokenType.OR: ParseRule(null, or, Precedence.OR),
      TokenType.PRINT: ParseRule(null, null, Precedence.NONE),
      TokenType.RETURN: ParseRule(null, null, Precedence.NONE),
      TokenType.SUPER: ParseRule(super_, null, Precedence.NONE),
      TokenType.THIS: ParseRule(this_, null, Precedence.NONE),
      TokenType.TRUE: ParseRule(literal, null, Precedence.NONE),
      TokenType.VAR: ParseRule(null, null, Precedence.NONE),
      TokenType.WHILE: ParseRule(null, null, Precedence.NONE),
      TokenType.ERROR: ParseRule(null, null, Precedence.NONE),
      TokenType.EOF: ParseRule(null, null, Precedence.NONE),
    };

void statement() {
  if (match(TokenType.PRINT)) {
    printStatement();
  } else if (match(TokenType.FOR)) {
    forStatement();
  } else if (match(TokenType.WHILE)) {
    whileStatement();
  } else if (match(TokenType.IF)) {
    ifStatement();
  } else if (match(TokenType.RETURN)) {
    returnStatement();
  } else if (match(TokenType.LEFT_BRACE)) {
    beginScope();
    block();
    endScope();
  } else {
    expressionStatement();
  }
}

void string(bool canAssign) {
  var substr =
      parser.previous.lexeme.substring(1, parser.previous.lexeme.length - 1);
  emitConstant(substr);
}

void super_(bool canAssign) {
  if (currentClass == null) {
    error("Can't use 'super' outside of a class.");
  } else if (!currentClass!.hasSuperClass) {
    error("Can't use 'super' in a class with no superclass.");
  }

  consume(TokenType.DOT, "Expected '.' after 'super'.");
  consume(TokenType.IDENTIFIER, "Expected superclass method name.");
  int name = identifierConstant(parser.previous);

  Token thisToken = Token();
  thisToken.lexeme = "this";
  Token superToken = Token();
  superToken.lexeme = "super";

  namedVariable(thisToken, false);
  if (match(TokenType.LEFT_PAREN)) {
    int argCount = argumentList();
    namedVariable(superToken, false);
    emitBytes(OP_SUPER_INVOKE, name);
    emitByte(argCount);
  } else {
    namedVariable(superToken, false);
    emitBytes(OP_GET_SUPER, name);
  }
}

void synchronize() {
  parser.panicMode = false;

  while (parser.current.type != TokenType.EOF) {
    if (parser.previous.type == TokenType.SEMICOLON) {
      return;
    }
    switch (parser.current.type) {
      case TokenType.CLASS:
      case TokenType.FUN:
      case TokenType.VAR:
      case TokenType.FOR:
      case TokenType.IF:
      case TokenType.WHILE:
      case TokenType.PRINT:
      case TokenType.RETURN:
        return;

      default:
      // Do nothing.
    }
    advance();
  }
}

void this_(bool canAssign) {
  if (currentClass == null) {
    error("Can't use 'this' outside of a class.");
    return;
  }
  variable(false);
}

void unary(bool canAssign) {
  TokenType operatorType = parser.previous.type;

  // compile the operand
  parsePrecedence(Precedence.UNARY);

  // emit the operator instruction.
  switch (operatorType) {
    case TokenType.MINUS:
      emitByte(OP_NEGATE);
    case TokenType.BANG:
      emitByte(OP_NOT);
    default:
      return; // unreachable
  }
}

void varDeclaration() {
  int global = parseVariable("Expected variable name.");

  if (match(TokenType.EQUAL)) {
    expression();
  } else {
    emitByte(OP_NIL);
  }
  consume(TokenType.SEMICOLON, "Expected ';' after variable declaration.");
  defineVariable(global);
}

void variable(bool canAssign) {
  namedVariable(parser.previous, canAssign);
}

void whileStatement() {
  int loopStart = currentChunk().code.length;
  consume(TokenType.LEFT_PAREN, "Expected '(' after 'while'.");
  expression();
  consume(TokenType.RIGHT_PAREN, "Expected ')' after condition.");

  int exitJump = emitJump(OP_JUMP_IF_FALSE);
  emitByte(OP_POP);
  statement();
  emitLoop(loopStart);

  patchJump(exitJump);
  emitByte(OP_POP);
}
