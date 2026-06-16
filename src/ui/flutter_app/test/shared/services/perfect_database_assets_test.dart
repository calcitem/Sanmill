// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_database_assets_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/perfect_database_assets.dart';

void main() {
  Set<String> declaredDatabaseAssets() {
    final File pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);

    final RegExp databaseAssetLine = RegExp(
      r'^\s*-\s+(assets/databases/[^#\s]+)\s*$',
    );

    return pubspec
        .readAsLinesSync()
        .map((String line) => databaseAssetLine.firstMatch(line)?.group(1))
        .whereType<String>()
        .toSet();
  }

  group('bundled Perfect Database assets', () {
    test('match the Flutter asset declarations', () {
      final Set<String> expected = bundledPerfectDatabaseFileNames
          .map(perfectDatabaseAssetPath)
          .toSet();

      expect(declaredDatabaseAssets(), expected);
    });

    test('exist on disk', () {
      for (final String fileName in bundledPerfectDatabaseFileNames) {
        final File file = File(perfectDatabaseAssetPath(fileName));

        expect(
          file.existsSync(),
          isTrue,
          reason: '${file.path} is listed as a bundled Perfect DB asset.',
        );
      }
    });
  });
}
