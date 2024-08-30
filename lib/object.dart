import 'dart:io';
import 'package:dlox/table.dart';
import 'value.dart';

import 'chunk.dart';

int hashString(String key) {
  var hash = 2166136261;
  for (var i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

abstract class Obj {
  void print();
}

class ObjFunction extends Obj {
  late int arity;
  late int upvalueCount;
  late Chunk chunk;
  late String? name;

  @override
  void print() {
    if (name != null) {
      stdout.write("<fn $name>");
    } else {
      stdout.write("<script>");
    }
  }
}

ObjFunction newFunction() {
  ObjFunction function = ObjFunction();
  function.arity = 0;
  function.upvalueCount = 0;
  function.name = null;
  function.chunk = Chunk();
  return function;
}

typedef NativeFn = Object Function(int argCount, List<Object> args);

class ObjNative extends Obj {
  late NativeFn function;

  @override
  void print() {
    stdout.write("<native fn>");
  }
}

ObjNative newNative(NativeFn function) {
  ObjNative native = ObjNative();
  native.function = function;
  return native;
}

class ObjClosure extends Obj {
  late ObjFunction function;
  late List<ObjUpvalue?> upvalues;
  int upvalueCount = 0;

  @override
  void print() {
    function.print();
  }
}

ObjClosure newClosure(ObjFunction function) {
  ObjClosure closure = ObjClosure();
  closure.function = function;
  closure.upvalues = [];
  for (int i = 0; i < function.upvalueCount; i++) {
    closure.upvalues.add(null);
  }
  closure.upvalueCount = function.upvalueCount;
  return closure;
}

class ObjUpvalue extends Obj {
  late int location;
  late ObjUpvalue? next;
  late Object closed;

  @override
  void print() {}
}

ObjUpvalue newUpvalue(int slot) {
  ObjUpvalue upvalue = ObjUpvalue();
  upvalue.location = slot;
  upvalue.next = null;
  upvalue.closed = Nil();
  return upvalue;
}

class ObjClass extends Obj {
  late String name;
  Table methods = Table();

  @override
  void print() {
    stdout.write(name);
  }
}

ObjClass newClass(String name) {
  ObjClass klass = ObjClass();
  klass.name = name;
  return klass;
}

class ObjInstance extends Obj {
  late ObjClass klass;
  Table fields = Table();

  @override
  void print() {
    stdout.write("${klass.name} instance");
  }
}

ObjInstance newInstance(ObjClass klass) {
  ObjInstance instance = ObjInstance();
  instance.klass = klass;
  return instance;
}

class ObjBoundMethod extends Obj {
  late Object receiver;
  late ObjClosure method;

  @override
  void print() {
    stdout.write("${method.function}");
  }
}

ObjBoundMethod newBoundMethod(Object reciever, ObjClosure method) {
  ObjBoundMethod bound = ObjBoundMethod();
  bound.receiver = reciever;
  bound.method = method;
  return bound;
}
