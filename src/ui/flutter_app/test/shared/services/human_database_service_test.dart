// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sanmill/shared/services/human_database_service.dart';

// Covers HumanDatabaseService.importDatabaseFile, the fix for the field
// report where the Human Database path pointed at FilePicker's OS cache
// (cache/file_picker/<timestamp>/...) and the file vanished after the system
// cleared the cache.  Import now copies the picked file into durable
// app-private storage.  A test seam (storageRoot) injects a temp directory so
// these run without path_provider.
void main() {
  late Directory storageRoot;
  late Directory pickSource;

  setUp(() async {
    storageRoot = await Directory.systemTemp.createTemp('hdb_root');
    pickSource = await Directory.systemTemp.createTemp('hdb_src');
  });

  tearDown(() async {
    if (storageRoot.existsSync()) {
      await storageRoot.delete(recursive: true);
    }
    if (pickSource.existsSync()) {
      await pickSource.delete(recursive: true);
    }
  });

  test(
    'importDatabaseFile copies a picked file into persistent storage',
    () async {
      final File source = File(p.join(pickSource.path, 'my_human_db.sqlite'));
      await source.writeAsString('SQLITE-PAYLOAD');

      final String persisted = await HumanDatabaseService.instance
          .importDatabaseFile(source.path, storageRoot: storageRoot);

      expect(
        persisted,
        p.join(storageRoot.path, 'human_database', 'my_human_db.sqlite'),
      );
      expect(File(persisted).existsSync(), isTrue);
      expect(File(persisted).readAsStringSync(), 'SQLITE-PAYLOAD');
      // The user's original file must be left untouched.
      expect(source.existsSync(), isTrue);
    },
  );

  test('importDatabaseFile prunes a previous import', () async {
    final File first = File(p.join(pickSource.path, 'old.sqlite'));
    await first.writeAsString('OLD');
    await HumanDatabaseService.instance.importDatabaseFile(
      first.path,
      storageRoot: storageRoot,
    );

    final File second = File(p.join(pickSource.path, 'new.sqlite'));
    await second.writeAsString('NEW');
    final String persisted = await HumanDatabaseService.instance
        .importDatabaseFile(second.path, storageRoot: storageRoot);

    final Directory dir = Directory(p.join(storageRoot.path, 'human_database'));
    final List<String> names = dir
        .listSync()
        .whereType<File>()
        .map((File f) => p.basename(f.path))
        .toList();
    expect(names, <String>['new.sqlite']);
    expect(File(persisted).readAsStringSync(), 'NEW');
  });

  test(
    'importDatabaseFile re-importing the persisted copy is a no-op',
    () async {
      final File source = File(p.join(pickSource.path, 'human_db.sqlite'));
      await source.writeAsString('DATA');
      final String persisted = await HumanDatabaseService.instance
          .importDatabaseFile(source.path, storageRoot: storageRoot);

      // Picking the already-persisted file must keep it, not delete-then-fail to
      // copy a file onto itself.
      final String again = await HumanDatabaseService.instance
          .importDatabaseFile(persisted, storageRoot: storageRoot);

      expect(again, persisted);
      expect(File(again).existsSync(), isTrue);
      expect(File(again).readAsStringSync(), 'DATA');
    },
  );
}
