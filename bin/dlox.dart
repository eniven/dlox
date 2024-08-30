import 'dart:io';
import 'package:dlox/vm.dart';

void main(List<String> arguments) {
  initVM();

  if (arguments.isEmpty) {
    repl();
  } else if (arguments.length == 1) {
    runFile(arguments[0]);
  } else {
    print("usage: dlox [path]");
  }

  freeVM();
}

void repl() {
  for (;;) {
    stdout.write("> ");
    var line = stdin.readLineSync().toString();
    interpret(line);
  }
}

void runFile(String path) {
  var file = File(path);
  var source = file.readAsStringSync();
  interpret(source);
}
