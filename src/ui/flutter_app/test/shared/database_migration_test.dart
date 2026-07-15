// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory applicationDirectory;

  setUpAll(() async {
    applicationDirectory = Directory.systemTemp.createTempSync(
      'sanmill_database_migration_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          return switch (methodCall.method) {
            'getApplicationDocumentsDirectory' ||
            'getApplicationSupportDirectory' ||
            'getTemporaryDirectory' => applicationDirectory.path,
            _ => null,
          };
        });
    await DB.init();
  });

  tearDownAll(() async {
    await Hive.close();
    DB.instance = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    applicationDirectory.deleteSync(recursive: true);
  });

  test(
    'version 2 migrates the legacy human clock to a no-increment control',
    () async {
      DB().generalSettings = const GeneralSettings(
        humanMoveTime: 42,
        offlineBoardTimeSeconds: 300,
        offlineBoardIncrementSeconds: 3,
      );
      final Box<dynamic> versionBox = await Hive.openBox<dynamic>('database');
      await versionBox.put('version', 2);
      await versionBox.close();

      final bool migrated = await DB.runMigrationsForTesting();

      expect(migrated, isTrue);
      expect(DB().generalSettings.humanMoveTime, 42);
      expect(DB().generalSettings.offlineBoardTimeSeconds, 42);
      expect(DB().generalSettings.offlineBoardIncrementSeconds, 0);

      final Box<dynamic> migratedVersionBox = await Hive.openBox<dynamic>(
        'database',
      );
      expect(migratedVersionBox.get('version'), 3);
      await migratedVersionBox.close();
    },
  );
}
