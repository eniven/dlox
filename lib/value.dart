import 'dart:io';
import 'package:dlox/object.dart';
import 'package:sprintf/sprintf.dart';

class Nil {}

void printValue(Object value) {
  if (value is double) {
    stdout.write(sprintf("%g", [value]));
  } else if (value is Nil) {
    stdout.write("nil");
  } else if (value is bool) {
    stdout.write(value);
  } else if (value is String) {
    stdout.write(value);
  } else if (value is ObjFunction) {
    value.print();
  } else if (value is ObjClosure) {
    value.print();
  } else if (value is ObjNative) {
    value.print();
  } else if (value is ObjClass) {
    value.print();
  } else if (value is ObjInstance) {
    value.print();
  } else if (value is ObjUpvalue) {
    stdout.write("upvalue");
  } else if (value is ObjBoundMethod) {
    value.method.function.print();
  } else if (value is int) {
    stdout.write(value);
  } else {
    stdout.write("UNKNOWN TYPE in PrintValue: ");
    stdout.write(value.runtimeType);
  }
}

bool valuesEqual(Object a, Object b) {
  return a == b;
}
