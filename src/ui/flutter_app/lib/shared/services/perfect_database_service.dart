// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_database_service.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/simple.dart' as tgf;
import 'logger.dart';
import 'perfect_database_assets.dart';

// Track copying state to prevent concurrent calls
bool _isCopying = false;
bool _hasCopied = false;

Future<Directory?> _perfectDatabaseDirectory() async {
  if (kIsWeb) {
    return null;
  }
  try {
    return Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
  } catch (e) {
    logger.e('Failed to get directory: $e');
    return null;
  }
}

Future<String?> perfectDatabaseStoragePath() async {
  final Directory? dir = await _perfectDatabaseDirectory();
  if (dir == null) {
    return null;
  }
  return '${dir.path}/strong';
}

Future<bool> copyPerfectDatabaseFiles({bool force = false}) async {
  // Prevent concurrent executions
  if (_isCopying) {
    logger.w('Perfect database copy already in progress, skipping...');
    return false;
  }

  // Skip if already copied successfully (unless forced)
  if (_hasCopied && !force) {
    logger.i('Perfect database files already copied, skipping...');
    return true;
  }

  _isCopying = true;

  try {
    final Directory? dir = await _perfectDatabaseDirectory();
    if (dir == null) {
      logger.e(
        'Failed to resolve a storage directory for perfect database files.',
      );
      return false;
    }

    logger.i('Directory obtained: ${dir.path}');

    final String perfectDatabasePath = '${dir.path}/strong';
    final Directory directory = Directory(perfectDatabasePath);

    try {
      if (!await _exists(directory)) {
        await directory.create(recursive: true);
        logger.i('Created directory at $perfectDatabasePath');
      }
    } catch (e) {
      logger.e('Error creating directory $perfectDatabasePath: $e');
      return false;
    }

    for (final String fileName in bundledPerfectDatabaseFileNames) {
      final String asset = perfectDatabaseAssetPath(fileName);
      try {
        final File file = File('${directory.path}/$fileName');
        final bool exists = await _exists(file);
        if (!exists || force) {
          final ByteData byteData = await rootBundle.load(asset);
          final ByteBuffer buffer = byteData.buffer;
          await file.writeAsBytes(
            buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          );
          logger.i('${exists ? 'Updated' : 'Copied'} file at ${file.path}');
        }
      } catch (e) {
        logger.e('Failed to copy asset $asset: $e');
        return false;
      }
    }

    _hasCopied = true;
    return true;
  } finally {
    _isCopying = false;
  }
}

/// Copy bundled database assets to device storage and initialize the Rust
/// perfect-database bridge.  Returns false when copy or init fails.
Future<bool> ensurePerfectDatabaseReady() async {
  if (kIsWeb) {
    return false;
  }
  final bool copied = await copyPerfectDatabaseFiles();
  if (!copied) {
    return false;
  }
  final String? path = await perfectDatabaseStoragePath();
  assert(
    path != null,
    'perfect database path must exist after a successful copy',
  );
  if (path == null) {
    return false;
  }
  final tgf.MillPerfectDatabaseStatus status = tgf.millPerfectDbStatus(
    path: path,
  );
  if (!status.readable) {
    logger.e('Perfect database directory is not readable: ${status.error}');
    return false;
  }
  if (!status.hasMetadata) {
    logger.w('Perfect database directory has no supported secval metadata.');
    return false;
  }
  if (!status.hasAvailableSectors) {
    logger.w(
      'Perfect database directory has secval metadata but no available sec2 files.',
    );
    return false;
  }

  final bool initialized = tgf.millPerfectDbInit(path: path);
  if (!initialized) {
    logger.w('Perfect database initialization was rejected by Rust.');
  }
  return initialized;
}

void disablePerfectDatabase() {
  if (kIsWeb) {
    return;
  }
  tgf.millPerfectDbDeinit();
}

Future<bool> _exists(FileSystemEntity entity) async {
  return entity.exists();
}
