// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/simple.dart' as tgf;
import 'logger.dart';

class HumanDatabaseReadyResult {
  const HumanDatabaseReadyResult({required this.ready, required this.status});

  final bool ready;
  final tgf.MillHumanDatabaseStatus status;
}

class HumanDatabaseService {
  HumanDatabaseService._();

  static final HumanDatabaseService instance = HumanDatabaseService._();

  String? _initializedPath;

  Future<HumanDatabaseReadyResult> ensureReady(String path) async {
    return ensureReadySync(path);
  }

  HumanDatabaseReadyResult ensureReadySync(String path) {
    final String normalizedPath = path.trim();
    assert(normalizedPath.isNotEmpty, 'Human Database path must not be empty.');

    if (kIsWeb || normalizedPath.isEmpty) {
      return HumanDatabaseReadyResult(
        ready: false,
        status: tgf.millHumanDbStatus(path: normalizedPath),
      );
    }

    final File file = File(normalizedPath);
    if (!file.existsSync()) {
      logger.w('Human Database file does not exist: $normalizedPath');
      return HumanDatabaseReadyResult(
        ready: false,
        status: tgf.millHumanDbStatus(path: normalizedPath),
      );
    }

    final tgf.MillHumanDatabaseStatus currentStatus = tgf.millHumanDbStatus(
      path: normalizedPath,
    );
    if (!currentStatus.readable) {
      logger.w('Human Database is not readable: ${currentStatus.error}');
      return HumanDatabaseReadyResult(ready: false, status: currentStatus);
    }

    if (_initializedPath == normalizedPath && currentStatus.initialized) {
      return HumanDatabaseReadyResult(ready: true, status: currentStatus);
    }

    final bool initialized = tgf.millHumanDbInit(path: normalizedPath);
    if (!initialized) {
      logger.w('Human Database initialization was rejected by Rust.');
      return HumanDatabaseReadyResult(
        ready: false,
        status: tgf.millHumanDbStatus(path: normalizedPath),
      );
    }

    _initializedPath = normalizedPath;
    return HumanDatabaseReadyResult(
      ready: true,
      status: tgf.millHumanDbStatus(path: normalizedPath),
    );
  }

  /// Copy a user-picked database file into app-private persistent storage and
  /// return the persisted path.
  ///
  /// `FilePicker` on Android returns a path under the OS cache
  /// (`cache/file_picker/<timestamp>/...`), which the system clears; persisting
  /// that path leaves the feature "enabled but file gone" after a restart.
  /// Copy into the external app-specific directory (matching the
  /// perfect-database / saved-games convention) so the import survives, and
  /// return the durable path for the caller to store in settings.
  Future<String> importDatabaseFile(
    String pickedPath, {
    Directory? storageRoot,
    @visibleForTesting bool Function(String path)? validateDatabase,
  }) async {
    assert(pickedPath.trim().isNotEmpty, 'picked path must not be empty');
    // `storageRoot` is a test seam; production resolves the app-specific
    // directory (external on Android, app documents elsewhere), matching the
    // perfect-database / saved-games storage convention.
    final Directory base =
        storageRoot ??
        (Platform.isAndroid
            ? await getExternalStorageDirectory()
            : await getApplicationDocumentsDirectory()) ??
        await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'human_database'));
    await dir.create(recursive: true);
    final String target = p.join(dir.path, p.basename(pickedPath));

    final File source = File(pickedPath);
    if (p.equals(source.absolute.path, File(target).absolute.path)) {
      // The picked file is already the persisted copy (re-import). Validate it
      // in place, but do not replace or prune anything.
      final bool compatible =
          validateDatabase?.call(target) ??
          tgf.millHumanDbStatus(path: target).readable;
      if (!compatible) {
        throw FileSystemException(
          'Selected file is not a compatible human game database.',
          target,
        );
      }
      return target;
    }

    // Copy to a unique staging file first. Validation must happen before the
    // current database is deinitialized or any prior import is removed: a
    // mistyped or incompatible selection must leave the working database
    // untouched.
    final int importId = DateTime.now().microsecondsSinceEpoch;
    final File staged = File(
      p.join(dir.path, '.${p.basename(pickedPath)}.$importId.importing'),
    );
    await source.copy(staged.path);

    File? backup;
    try {
      final bool compatible =
          validateDatabase?.call(staged.path) ??
          tgf.millHumanDbStatus(path: staged.path).readable;
      if (!compatible) {
        throw FileSystemException(
          'Selected file is not a compatible human game database.',
          pickedPath,
        );
      }

      // Release the current read-only SQLite handle only after the candidate
      // passed validation. Keep a same-name target as a temporary backup so a
      // failed rename can restore it.
      if (_initializedPath != null) {
        disable();
      }
      final File targetFile = File(target);
      if (targetFile.existsSync()) {
        backup = await targetFile.rename('$target.$importId.backup');
      }
      try {
        await staged.rename(target);
      } catch (_) {
        if (backup != null && backup.existsSync()) {
          await backup.rename(target);
          backup = null;
        }
        rethrow;
      }

      if (backup != null && backup.existsSync()) {
        try {
          await backup.delete();
        } catch (e) {
          logger.w('Could not remove Human Database import backup: $e');
        }
        backup = null;
      }
    } finally {
      if (staged.existsSync()) {
        await staged.delete();
      }
    }

    // Keep only the freshly imported database so prior (potentially very
    // large) imports do not accumulate.  Best-effort: a file still held by a
    // live read handle is skipped here and pruned on a later import.
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is File &&
          !p.equals(entity.absolute.path, File(target).absolute.path)) {
        try {
          await entity.delete();
        } catch (_) {
          // Ignore; stale-file cleanup must never fail the import.
        }
      }
    }
    return target;
  }

  void disable() {
    _initializedPath = null;
    if (!kIsWeb) {
      tgf.millHumanDbDeinit();
    }
  }
}
