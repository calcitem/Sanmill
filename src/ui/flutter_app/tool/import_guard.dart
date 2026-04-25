// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

const List<String> guardedRoots = <String>[
  'lib/game_platform/',
  'lib/game_shell/',
  'lib/shared/',
];

const List<String> forbiddenImports = <String>[
  "game_page/services/mill.dart",
  "games/mill/",
];

const Set<String> legacyAllowedFiles = <String>{
  'lib/shared/database/settings_side_effect_coordinator.dart',
  'lib/shared/services/ai_chat_service.dart',
  'lib/shared/services/screenshot_service.dart',
};

void main() {
  final Directory libDir = Directory('lib');
  assert(libDir.existsSync(), 'Run this tool from src/ui/flutter_app.');

  final List<String> violations = <String>[];
  for (final FileSystemEntity entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final String normalizedPath = entity.path.replaceAll(r'\', '/');
    if (legacyAllowedFiles.contains(normalizedPath)) {
      continue;
    }
    if (!guardedRoots.any(normalizedPath.startsWith)) {
      continue;
    }
    final List<String> lines = entity.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final bool isImport = line.trimLeft().startsWith('import ');
      if (!isImport) {
        continue;
      }
      for (final String forbiddenImport in forbiddenImports) {
        if (line.contains(forbiddenImport)) {
          violations.add('$normalizedPath:${i + 1}: $line');
        }
      }
    }
  }

  if (violations.isEmpty) {
    return;
  }

  stderr.writeln('Forbidden game-specific imports found:');
  violations.forEach(stderr.writeln);
  exitCode = 1;
}
