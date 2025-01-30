// find_duplicate_keys.dart

import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Usage: dart run bin/find_duplicate_keys.dart <path_to_flutter_project_lib>');
    exit(1);
  }

  final directory = Directory(arguments[0]);
  if (!directory.existsSync()) {
    print('Directory does not exist: ${arguments[0]}');
    exit(1);
  }

  final keyOccurrences = <String, List<String>>{};

  for (var file in directory.listSync(recursive: true)) {
    if (file is File && p.extension(file.path) == '.dart') {
      final content = file.readAsStringSync();
      final result = parseString(content: content, path: file.path);
      final unit = result.unit;

      unit.visitChildren(KeyVisitor(keyOccurrences, file.path));
    }
  }

  // Find duplicate Keys
  final duplicates = keyOccurrences.entries
      .where((entry) => entry.value.length > 1)
      .toList();

  if (duplicates.isEmpty) {
    print('No duplicate Keys.');
  } else {
    print('Found ${duplicates.length} duplicate Keys:');
    for (var entry in duplicates) {
      print('Key: "${entry.key}"');
      for (var location in entry.value) {
        print('  - $location');
      }
    }
  }
}

class KeyVisitor extends RecursiveAstVisitor<void> {
  final Map<String, List<String>> keyOccurrences;
  final String filePath;

  KeyVisitor(this.keyOccurrences, this.filePath);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type;
    if (typeName is NamedType) {
      final constructorName = typeName.name2.lexeme;
      if (constructorName == 'Key' || constructorName == 'ValueKey') {
        if (node.argumentList.arguments.isNotEmpty) {
          final arg = node.argumentList.arguments.first;
          if (arg is StringLiteral) {
            final keyValue = arg.stringValue;
            if (keyValue != null) {
              keyOccurrences.putIfAbsent(keyValue, () => []).add(filePath);
            }
          }
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
