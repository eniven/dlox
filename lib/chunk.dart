class Chunk {
  final List<int> code = [];
  final List<Object> constants = [];
  final List<int> lines = [];
  Chunk();
}

void writeChunk(Chunk chunk, int byte, int line) {
  chunk.code.add(byte);
  chunk.lines.add(line);
}

int addConstant(Chunk chunk, Object value) {
  chunk.constants.add(value);
  return chunk.constants.length - 1;
}

void freeChunk(Chunk chunk) {
  chunk.code.length = 0;
  chunk.lines.length = 0;
}

const int OP_CONSTANT = 0;
const int OP_NIL = 1;
const int OP_TRUE = 2;
const int OP_FALSE = 3;
const int OP_POP = 4;
const int OP_GET_LOCAL = 5;
const int OP_SET_LOCAL = 6;
const int OP_GET_GLOBAL = 7;
const int OP_DEFINE_GLOBAL = 8;
const int OP_SET_GLOBAL = 9;
const int OP_GET_UPVALUE = 10;
const int OP_SET_UPVALUE = 11;
const int OP_GET_PROPERTY = 12;
const int OP_SET_PROPERTY = 13;
const int OP_GET_SUPER = 14;
const int OP_EQUAL = 15;
const int OP_GREATER = 16;
const int OP_LESS = 17;
const int OP_ADD = 18;
const int OP_SUBTRACT = 19;
const int OP_MULTIPLY = 20;
const int OP_DIVIDE = 21;
const int OP_NOT = 22;
const int OP_NEGATE = 23;
const int OP_PRINT = 24;
const int OP_JUMP = 25;
const int OP_JUMP_IF_FALSE = 26;
const int OP_LOOP = 27;
const int OP_CALL = 28;
const int OP_INVOKE = 29;
const int OP_SUPER_INVOKE = 30;
const int OP_CLOSURE = 31;
const int OP_CLOSE_UPVALUE = 32;
const int OP_RETURN = 33;
const int OP_CLASS = 34;
const int OP_INHERIT = 35;
const int OP_METHOD = 36;
