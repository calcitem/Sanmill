// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS builds can write files selected by the user', () {
    for (final String path in <String>[
      'macos/Runner/RunnerDebug.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final String entitlements = File(path).readAsStringSync();

      expect(
        entitlements,
        contains('com.apple.security.files.user-selected.read-write'),
        reason: '$path must allow file_picker.saveFile to write the PGN.',
      );
      expect(
        entitlements,
        isNot(contains('com.apple.security.files.user-selected.read-only')),
        reason: '$path must not downgrade user-selected files to read-only.',
      );
    }
  });
}
