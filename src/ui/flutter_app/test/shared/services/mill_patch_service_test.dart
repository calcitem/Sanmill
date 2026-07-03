// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_patch_service_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/mill_patch_service.dart';

void main() {
  group('bundledAssetMatchesOnDisk', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'mill_patch_service_test',
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('is false when the on-disk file does not exist', () async {
      final File missing = File('${tempDir.path}/missing.mill_patch');
      final Uint8List bundled = Uint8List.fromList(<int>[1, 2, 3]);

      expect(await bundledAssetMatchesOnDisk(missing, bundled), isFalse);
    });

    test('is true when the on-disk file has identical bytes', () async {
      final File file = File('${tempDir.path}/same.mill_patch');
      final Uint8List bundled = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      await file.writeAsBytes(bundled);

      expect(await bundledAssetMatchesOnDisk(file, bundled), isTrue);
    });

    test(
      'is false when lengths differ (the cheap common-case check)',
      () async {
        final File file = File('${tempDir.path}/shorter.mill_patch');
        await file.writeAsBytes(<int>[1, 2, 3]);
        final Uint8List bundled = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

        expect(await bundledAssetMatchesOnDisk(file, bundled), isFalse);
      },
    );

    test('is false when lengths match but content differs (an app update '
        'that ships a same-length patch must still be detected)', () async {
      final File file = File('${tempDir.path}/same-length.mill_patch');
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      final Uint8List bundled = Uint8List.fromList(<int>[1, 2, 9, 4, 5]);

      expect(await bundledAssetMatchesOnDisk(file, bundled), isFalse);
    });

    test('is true for empty content on both sides', () async {
      final File file = File('${tempDir.path}/empty.mill_patch');
      await file.writeAsBytes(<int>[]);
      final Uint8List bundled = Uint8List.fromList(<int>[]);

      expect(await bundledAssetMatchesOnDisk(file, bundled), isTrue);
    });
  });
}
