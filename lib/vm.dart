import 'dart:io';
import 'table.dart';
import 'package:sprintf/sprintf.dart';
import 'chunk.dart';
import 'value.dart';
import 'common.dart';
import 'debug.dart';
import 'compiler.dart';
import 'object.dart';

class CallFrame {
  late ObjClosure closure;
  late int ip;
  late int slotsIdx; // index in stack of the frame slot
}

class VM {
  List<CallFrame> frames = [];
  List<Object> stack = [];
  final Table strings = Table();
  final Table globals = Table();
  late ObjUpvalue? openUpvalues;
  VM();
}

enum InterpretResult {
  ok,
  compileError,
  runtimeError,
}

VM vm = VM();

void initVM() {
  resetStack();
  defineNative("clock", clockNative);
}

void resetStack() {
  vm.stack.length = 0;
  vm.frames.length = 0;
  vm.openUpvalues = null;
}

void freeVM() {
  vm.strings.data.clear();
  vm.globals.data.clear();
}

void push(Object value) {
  vm.stack.add(value);
}

Object pop() {
  return vm.stack.removeLast();
}

void runtimeError(String format, [List<Object>? args]) {
  var error = sprintf(format, args ?? []);
  stdout.write(error);
  stdout.write("\n");

  for (int i = vm.frames.length - 1; i >= 0; i--) {
    CallFrame frame = vm.frames[i];
    ObjFunction function = frame.closure.function;
    int instruction = frame.ip - 0 - 1;
    stdout.write("[Line ${function.chunk.lines[instruction]}] in ");
    if (function.name == null) {
      stdout.write("script\n");
    } else {
      stdout.write("${function.name}()\n");
    }
  }
  resetStack();
}

Object peek(int distance) {
  return vm.stack[vm.stack.length - 1 - distance];
}

bool isFalsey(Object value) {
  return value is Nil || (value is bool && !value);
}

bool call(ObjClosure closure, int argCount) {
  if (argCount != closure.function.arity) {
    runtimeError(
        "Expected ${closure.function.arity} arguments but got $argCount.");
    return false;
  }

  // did not include the check for stack over flow.

  CallFrame frame = CallFrame();
  frame.closure = closure;
  frame.ip = 0;
  frame.slotsIdx = vm.stack.length - argCount - 1;
  vm.frames.add(frame);
  return true;
}

Object clockNative(int argCount, List<Object> args) {
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

void defineNative(String name, NativeFn function) {
  ObjNative native = ObjNative();
  native.function = function;
  vm.globals.set(name, native);
}

bool callValue(Object callee, int argCount) {
  if (callee is Obj) {
    if (callee is ObjClosure) {
      return call(callee, argCount);
    } else if (callee is ObjBoundMethod) {
      ObjBoundMethod bound = callee;
      vm.stack[vm.stack.length - argCount - 1] = bound.receiver;
      return call(bound.method, argCount);
    } else if (callee is ObjClass) {
      ObjClass klass = callee;
      vm.stack[vm.stack.length - argCount - 1] = newInstance(klass);
      Object? initializer;
      initializer = klass.methods.get("init");
      if (initializer != null) {
        return call(initializer as ObjClosure, argCount);
      } else if (argCount != 0) {
        runtimeError("Expected 0 arguments but got $argCount.");
        return false;
      }
      return true;
    } else if (callee is ObjNative) {
      NativeFn native = callee.function;
      var result =
          native(argCount, [vm.stack.sublist(vm.stack.length - argCount)]);
      vm.stack.length -= argCount + 1;
      push(result);
      return true;
    }
  }
  runtimeError("Can only call funcitons and classes.");
  return false;
}

ObjUpvalue captureUpvalue(int localIdx) {
  ObjUpvalue? prevUpvalue;
  ObjUpvalue? upvalue = vm.openUpvalues;

  while (upvalue != null && upvalue.location > localIdx) {
    prevUpvalue = upvalue;
    upvalue = upvalue.next;
  }

  if (upvalue != null && upvalue.location == localIdx) {
    return upvalue;
  }

  ObjUpvalue createdUpvalue = newUpvalue(localIdx);
  createdUpvalue.next = upvalue;

  if (prevUpvalue == null) {
    vm.openUpvalues = createdUpvalue;
  } else {
    prevUpvalue.next = createdUpvalue;
  }

  return createdUpvalue;
}

void closeUpvalues(int lastIdx) {
  while (vm.openUpvalues != null && vm.openUpvalues!.location >= lastIdx) {
    ObjUpvalue upvalue = vm.openUpvalues!;
    upvalue.closed = vm.stack[upvalue.location];
    upvalue.location = -1;
    vm.openUpvalues = upvalue.next;
  }
}

void defineMethod(String name) {
  var method = peek(0);
  ObjClass klass = peek(1) as ObjClass;
  klass.methods.set(name, method);
  pop();
}

bool bindMethod(ObjClass klass, String name) {
  Object? method;
  method = klass.methods.get(name);
  if (method == null) {
    runtimeError("Undefined property@@ '$name'.");
    return false;
  }

  ObjBoundMethod bound = newBoundMethod(peek(0), method as ObjClosure);
  pop();
  push(bound);
  return true;
}

bool invoke(String name, int argCount) {
  var receiver = peek(argCount);

  if (receiver is! ObjInstance) {
    runtimeError("Only instances have methods.");
    return false;
  }

  ObjInstance instance = receiver;
  Object? value;
  value = instance.fields.get(name);
  if (value != null) {
    vm.stack[vm.stack.length - argCount - 1] = value;
    return callValue(value, argCount);
  }
  
  return invokeFromClass(instance.klass, name, argCount);
}

bool invokeFromClass(ObjClass klass, String name, int argCount) {
  Object? method;
  method = klass.methods.get(name);
  if (method == null) {
    runtimeError("Undefined property '$name'.");
    return false;
  }
  return call(method as ObjClosure, argCount);
}

InterpretResult run() {
  binaryOp(String op) {
    if (peek(0) is! double || peek(1) is! double) {
      runtimeError("Operands must be numbers.");
      return InterpretResult.runtimeError;
    }
    var b = pop() as double;
    var a = pop() as double;
    switch (op) {
      case "-":
        push(a - b);
      case "*":
        push(a * b);
      case "/":
        push(a / b);
      case ">":
        push(a > b);
      case "<":
        push(a < b);
      default:
        print("Unknown operator!");
    }
  }

  CallFrame frame = vm.frames[vm.frames.length - 1];

  readByte() {
    return frame.closure.function.chunk.code[frame.ip++];
  }

  readConstant() {
    return frame.closure.function.chunk.constants[readByte()];
  }

  readString() {
    return readConstant() as String;
  }

  readShort() {
    return (readByte() << 8) | readByte();
  }

  for (;;) {
    if (debugTraceExecution) {
      stdout.write("          ");
      for (Object slot in vm.stack) {
        stdout.write("[ ");
        printValue(slot);
        stdout.write(" ]");
      }
      stdout.write("\n");
      disassembleInstruction(frame.closure.function.chunk, frame.ip);
    }

    int instruction = readByte();
    switch (instruction) {
      case OP_CONSTANT:
        Object constant = readConstant();
        push(constant);

      case OP_NIL:
        push(Nil());

      case OP_TRUE:
        push(true);

      case OP_FALSE:
        push(false);

      case OP_POP:
        pop();

      case OP_GET_LOCAL:
        int slot = readByte();
        push(vm.stack[frame.slotsIdx + slot]);

      case OP_SET_LOCAL:
        int slot = readByte();
        vm.stack[frame.slotsIdx + slot] = peek(0);

      case OP_GET_GLOBAL:
        String name = readString();
        Object? value = vm.globals.get(name);
        if (value == null) {
          runtimeError("Undefined variable '$name'.");
          return InterpretResult.runtimeError;
        }
        push(value);

      case OP_DEFINE_GLOBAL:
        String name = readString();
        vm.globals.set(name, peek(0));
        pop();

      case OP_SET_GLOBAL:
        String name = readString();
        //var test = vm.globals.set(name, peek(0));
        //print(test);
        if (vm.globals.set(name, peek(0))) {
          vm.globals.delete(name);
          runtimeError("Undefined variable '$name'.");
          return InterpretResult.runtimeError;
        }

      case OP_GET_UPVALUE:
        int slot = readByte();
        var upvalue = frame.closure.upvalues[slot];
        if (upvalue!.location >= 0) {
          push(vm.stack[upvalue.location]);
        } else {
          push(upvalue.closed);
        }

      case OP_SET_UPVALUE:
        int slot = readByte();
        var upvalue = frame.closure.upvalues[slot];
        if (upvalue!.location >= 0) {
          vm.stack[upvalue.location] = peek(0);
        } else {
          upvalue.closed = peek(0);
        }

      case OP_GET_PROPERTY:
        if (peek(0) is! ObjInstance) {
          runtimeError("Only instances have properties.");
          return InterpretResult.runtimeError;
        }

        ObjInstance instance = peek(0) as ObjInstance;
        String name = readString();

        Object? value;
        value = instance.fields.get(name);
        if (value != null) {
          pop();
          push(value);
          break;
        }
        if (!bindMethod(instance.klass, name)) {
          return InterpretResult.runtimeError;
        }

      case OP_SET_PROPERTY:
        if (peek(1) is! ObjInstance) {
          runtimeError("Only instances have fields.");
          return InterpretResult.runtimeError;
        }

        ObjInstance instance = peek(1) as ObjInstance;
        instance.fields.set(readString(), peek(0));
        var value = pop();
        pop();
        push(value);

      case OP_GET_SUPER:
        String name = readString();
        ObjClass superclass = pop() as ObjClass;

        if (!bindMethod(superclass, name)) {
          return InterpretResult.runtimeError;
        }

      case OP_EQUAL:
        var b = pop();
        var a = pop();
        push(valuesEqual(a, b));

      case OP_GREATER:
        binaryOp('>');

      case OP_LESS:
        binaryOp('<');

      case OP_ADD:
        if (peek(0) is String && peek(1) is String) {
          String b = pop() as String;
          String a = pop() as String;
          push(a + b);
        } else if (peek(0) is double && peek(1) is double) {
          double b = pop() as double;
          double a = pop() as double;
          push(a + b);
        } else {
          runtimeError("Operands must be two numbers or two strings.");
          return InterpretResult.runtimeError;
        }

      case OP_SUBTRACT:
        binaryOp('-');

      case OP_MULTIPLY:
        binaryOp('*');

      case OP_DIVIDE:
        binaryOp('/');

      case OP_NOT:
        push(isFalsey(pop()));

      case OP_NEGATE:
        if (peek(0) is! double) {
          runtimeError("Operand must be a number.");
          return InterpretResult.runtimeError;
        }
        push(-(pop() as double));

      case OP_PRINT:
        printValue(pop());
        stdout.writeln();

      case OP_JUMP:
        int offset = readShort();
        frame.ip += offset;

      case OP_JUMP_IF_FALSE:
        int offset = readShort();
        if (isFalsey(peek(0))) frame.ip += offset;

      case OP_LOOP:
        int offset = readShort();
        frame.ip -= offset;

      case OP_CALL:
        int argCount = readByte();
        if (!callValue(peek(argCount), argCount)) {
          return InterpretResult.runtimeError;
        }
        frame = vm.frames[vm.frames.length - 1];

      case OP_INVOKE:
        String method = readString();
        int argCount = readByte();
        if (!invoke(method, argCount)) {
          return InterpretResult.runtimeError;
        }
        frame = vm.frames[vm.frames.length - 1];

      case OP_SUPER_INVOKE:
        String method = readString();
        int argCount = readByte();
        ObjClass superclass = pop() as ObjClass;
        if (!invokeFromClass(superclass, method, argCount)) {
          return InterpretResult.runtimeError;
        }
        frame = vm.frames[vm.frames.length - 1];

      case OP_CLOSURE:
        ObjFunction function = readConstant() as ObjFunction;
        ObjClosure closure = newClosure(function);
        push(closure);
        for (int i = 0; i < closure.upvalueCount; i++) {
          var isLocal = readByte();
          var index = readByte();

          if (isLocal == 1) {
            closure.upvalues[i] = captureUpvalue(frame.slotsIdx + index);
          } else {
            closure.upvalues[i] = frame.closure.upvalues[index];
          }
        }

      case OP_CLOSE_UPVALUE:
        closeUpvalues(vm.stack.length - 1);
        pop();

      case OP_RETURN:
        var result = pop();
        closeUpvalues(frame.slotsIdx);
        vm.frames.length--;
        if (vm.frames.isEmpty) {
          pop();
          return InterpretResult.ok;
        }
        vm.stack.length = frame.slotsIdx;
        push(result);
        frame = vm.frames[vm.frames.length - 1];

      case OP_CLASS:
        push(newClass(readString()));

      case OP_INHERIT:
        var superclass = peek(1);
        if (superclass is! ObjClass) {
          runtimeError("Superclass must be a class.");
          return InterpretResult.runtimeError;
        }

        ObjClass subclass = peek(0) as ObjClass;
        subclass.methods.addAll(superclass.methods);
        pop();

      case OP_METHOD:
        defineMethod(readString());
    }
  }
}

InterpretResult interpret(String source) {
  ObjFunction? function = compile(source);

  if (function == null) return InterpretResult.compileError;

  push(function);
  ObjClosure closure = newClosure(function);
  call(closure, 0);

  InterpretResult result = run();
  return result;
}
