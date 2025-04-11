// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// scan_keys.dart

// This script scans .dart files in the specified "lib" folder of a Flutter project,
// extracts all Key(...) / ValueKey(...) usages, collects their occurrences (including
// file path, line, and column), then generates a Markdown file ("keys_report.md")
// that presents the data in a tabular format.
//
// How to use:
//   dart run bin/scan_keys.dart <path_to_flutter_project_lib>
//
// Example:
//   dart run bin/scan_keys.dart ./lib
//
// After running, a "keys_report.md" file will appear in the project root directory,
// listing all the discovered Keys.
//
// Dependencies:
//   In pubspec.yaml, ensure you have:
//     dev_dependencies:
//       analyzer: ^5.12.0 (or a version compatible with your Dart SDK)

import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:analyzer/source/line_info.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Usage: dart run bin/scan_keys.dart <path_to_flutter_project_lib>');
    exit(1);
  }

  final libDir = Directory(arguments[0]);
  if (!libDir.existsSync()) {
    print('Directory does not exist: ${arguments[0]}');
    exit(1);
  }

  // A list to hold info about each found key.
  final allKeyInfos = <KeyInfo>[];

  // Recursively scan all .dart files in the lib folder.
  for (var entity in libDir.listSync(recursive: true)) {
    if (entity is File && p.extension(entity.path) == '.dart') {
      final content = entity.readAsStringSync();
      final parseResult = parseString(content: content, path: entity.path);
      final unit = parseResult.unit;

      // We'll collect line/column data using the lineInfo from parse result.
      final lineInfo = parseResult.lineInfo;
      unit.visitChildren(KeyScannerVisitor(entity.path, lineInfo, allKeyInfos));
    }
  }

  if (allKeyInfos.isEmpty) {
    print('No Keys found.');
    return;
  }

  // Sort results by KeyValue, then by file path, then by line.
  allKeyInfos.sort((a, b) {
    final keyComp = a.keyValue.compareTo(b.keyValue);
    if (keyComp != 0) return keyComp;
    final fileComp = a.filePath.compareTo(b.filePath);
    if (fileComp != 0) return fileComp;
    return a.line.compareTo(b.line);
  });

  // Group keys by their keyValue.
  final groupedKeys = <String, List<KeyInfo>>{};
  for (var keyInfo in allKeyInfos) {
    groupedKeys.putIfAbsent(keyInfo.keyValue, () => []).add(keyInfo);
  }

  // Generate the Markdown table.
  final buffer = StringBuffer();
  buffer.writeln('# Keys Report');
  buffer.writeln('');
  buffer.writeln('| Key Value | File Path | Line | Column |');
  buffer.writeln('| --------- | --------- | ---- | ------ |');

  for (var entry in groupedKeys.entries) {
    final key = _escapeForMarkdown(entry.key);
    for (var info in entry.value) {
      final filePath = _escapeForMarkdown(p.relative(info.filePath, from: libDir.path));
      buffer.writeln('| $key | $filePath | ${info.line} | ${info.column} |');
    }
  }

  // Write to a file named "keys_report.md" in the current directory.
  final outputFile = File('keys_report.md');
  outputFile.writeAsStringSync(buffer.toString());

  print('Keys report generated: ${outputFile.path}');
}

// Holds information about a discovered key.
class KeyInfo {
  final String keyValue;
  final String filePath;
  final int line;
  final int column;

  KeyInfo({
    required this.keyValue,
    required this.filePath,
    required this.line,
    required this.column,
  });
}

// Visits the AST to find Key(...) or ValueKey(...) constructor calls.
class KeyScannerVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final List<KeyInfo> allKeyInfos;

  KeyScannerVisitor(this.filePath, this.lineInfo, this.allKeyInfos);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type;
    if (constructorName is NamedType) {
      final nameLexeme = constructorName.name2.lexeme;
      if (nameLexeme == 'Key' || nameLexeme == 'ValueKey') {
        if (node.argumentList.arguments.isNotEmpty) {
          final arg = node.argumentList.arguments.first;
          if (arg is StringLiteral) {
            final keyValue = arg.stringValue;
            if (keyValue != null) {
              final location = lineInfo.getLocation(node.offset);
              allKeyInfos.add(KeyInfo(
                keyValue: keyValue,
                filePath: filePath,
                line: location.lineNumber,
                column: location.columnNumber,
              ));
            }
          }
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}

// Escape the vertical bar and other special chars if needed.
String _escapeForMarkdown(String input) {
  return input.replaceAll('|', '\\|');
}
