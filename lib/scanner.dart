class Token {
  late TokenType type;
  late String lexeme;
  late int line;

  @override
  String toString() {
    return "$type $lexeme";
  }
}

class Scanner {
  late String source;
  late int start = 0;
  late int current = 0;
  late int line = 1;
}

Scanner scanner = Scanner();

void initScanner(String source) {
  scanner.source = source;
  scanner.current = 0;
  scanner.start = 0;
  scanner.line = 1;
}

Token scanToken() {
  skipWhitespace();
  scanner.start = scanner.current;

  if (isAtEnd()) return makeToken(TokenType.EOF);

  var c = advance();
  if (isAlpha(c)) return identifier();
  if (isDigit(c)) return number();

  switch (c) {
    case '(':
      return makeToken(TokenType.LEFT_PAREN);
    case ')':
      return makeToken(TokenType.RIGHT_PAREN);
    case '{':
      return makeToken(TokenType.LEFT_BRACE);
    case '}':
      return makeToken(TokenType.RIGHT_BRACE);
    case ',':
      return makeToken(TokenType.COMMA);
    case '.':
      return makeToken(TokenType.DOT);
    case '-':
      return makeToken(TokenType.MINUS);
    case '+':
      return makeToken(TokenType.PLUS);
    case ';':
      return makeToken(TokenType.SEMICOLON);
    case '*':
      return makeToken(TokenType.STAR);
    case '!':
      return makeToken(match('=') ? TokenType.BANG_EQUAL : TokenType.BANG);
    case '=':
      return makeToken(match('=') ? TokenType.EQUAL_EQUAL : TokenType.EQUAL);
    case '<':
      return makeToken(match('=') ? TokenType.LESS_EQUAL : TokenType.LESS);
    case '>':
      return makeToken(
          match('=') ? TokenType.GREATER_EQUAL : TokenType.GREATER);
    case '/':
      if (match('/')) {
        while (peek() != '\n' && !isAtEnd()) {
          advance();
        }
        return scanToken();
      } else {
        return makeToken(TokenType.SLASH);
      }
    case '"':
      return string();
  }

  return errorToken("Unexpected character.");
}

Token identifier() {
  while (isAlpha(peek()) || isDigit(peek())) {
    advance();
  }
  String text = scanner.source.substring(scanner.start, scanner.current);
  var type = keywords[text];

  if (type == null) {
    return makeToken(TokenType.IDENTIFIER);
  }
  return makeToken(type);
}

Token number() {
  while (isDigit(peek())) {
    advance();
  }

  //look for fractional part
  if (peek() == '.' && isDigit(peekNext())) {
    //consume the .
    advance();
  }
  while (isDigit(peek())) {
    advance();
  }

  return makeToken(TokenType.NUMBER);
}

bool isDigit(c) {
  return RegExp('[0-9]').hasMatch(c);
}

bool isAlpha(c) {
  return RegExp('[a-zA-Z_]').hasMatch(c);
}

Token string() {
  while (peek() != '"' && !isAtEnd()) {
    if (peek() == '\n') scanner.line++;
    advance();
  }

  if (isAtEnd()) {
    print("[line ${scanner.line}] Error: Unterminated string.");
  }

  advance();
  return makeToken(TokenType.STRING);
}

void skipWhitespace() {
  if (isAtEnd()) return;
  for (;;) {
    var c = peek();
    switch (c) {
      case ' ':
      case '\r':
      case '\t':
        advance();
      case '\n':
        scanner.line++;
        advance();
      default:
        return;
    }
  }
}

String peek() {
  if (isAtEnd()) {
    return '\x00';
  }
  return scanner.source[scanner.current];
}

String peekNext() {
  if (scanner.current + 1 >= scanner.source.length) return "\x00";
  return scanner.source[scanner.current + 1];
}

bool match(String expected) {
  if (isAtEnd()) return false;
  if (scanner.source[scanner.current] != expected) return false;
  scanner.current++;
  return true;
}

String advance() {
  return scanner.source[scanner.current++];
}

bool isAtEnd() {
  return scanner.current >= scanner.source.length;
}

Token makeToken(TokenType type) {
  Token token = Token();
  token.line = scanner.line;
  token.type = type;
  token.lexeme = scanner.source.substring(scanner.start, scanner.current);
  return token;
}

Token errorToken(String message) {
  Token token = Token();
  token.line = scanner.line;
  token.type = TokenType.ERROR;
  token.lexeme = message;
  return token;
}

enum TokenType {
  // Single-character tokens.
  LEFT_PAREN,
  RIGHT_PAREN,
  LEFT_BRACE,
  RIGHT_BRACE,
  COMMA,
  DOT,
  MINUS,
  PLUS,
  SEMICOLON,
  SLASH,
  STAR,

  // One or two character tokens.
  BANG,
  BANG_EQUAL,
  EQUAL,
  EQUAL_EQUAL,
  GREATER,
  GREATER_EQUAL,
  LESS,
  LESS_EQUAL,

  // Literals.
  IDENTIFIER,
  STRING,
  NUMBER,

  // Keywords.
  AND,
  CLASS,
  ELSE,
  FALSE,
  FUN,
  FOR,
  IF,
  NIL,
  OR,
  PRINT,
  RETURN,
  SUPER,
  THIS,
  TRUE,
  VAR,
  WHILE,
  ERROR,
  EOF,
  DUMMY
}

const keywords = <String, TokenType>{
  'and': TokenType.AND,
  'class': TokenType.CLASS,
  'else': TokenType.ELSE,
  'false': TokenType.FALSE,
  'for': TokenType.FOR,
  'fun': TokenType.FUN,
  'if': TokenType.IF,
  'nil': TokenType.NIL,
  'or': TokenType.OR,
  'print': TokenType.PRINT,
  'return': TokenType.RETURN,
  'super': TokenType.SUPER,
  'this': TokenType.THIS,
  'true': TokenType.TRUE,
  'var': TokenType.VAR,
  'while': TokenType.WHILE
};
