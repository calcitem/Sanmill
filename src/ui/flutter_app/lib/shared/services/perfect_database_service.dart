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

    // List of asset files to copy
    final List<String> assetFiles = <String>[
      'assets/databases/std.secval',
      'assets/databases/std_0_0_9_9.sec2',
      'assets/databases/std_0_1_9_8.sec2',
      'assets/databases/std_1_1_8_8.sec2',
      'assets/databases/std_1_2_8_7.sec2',
      'assets/databases/std_1_3_7_6.sec2',
      'assets/databases/std_2_2_7_7.sec2',
      'assets/databases/std_2_3_6_6.sec2',
      'assets/databases/std_2_3_7_6.sec2',
      'assets/databases/std_2_4_6_5.sec2',
      'assets/databases/std_3_3_0_0.sec2',
      'assets/databases/std_3_3_5_5.sec2',
      'assets/databases/std_3_3_6_5.sec2',
      'assets/databases/std_3_3_6_6.sec2',
      'assets/databases/std_3_4_0_0.sec2',
      'assets/databases/std_3_4_5_5.sec2',
      'assets/databases/std_3_4_6_5.sec2',
      'assets/databases/std_4_3_0_0.sec2',
      'assets/databases/std_4_3_5_5.sec2',
      'assets/databases/std_4_4_5_5.sec2',
      'assets/databases/mora.secval',
      'assets/databases/mora_0_0_12_12.sec2',
      'assets/databases/mora_0_1_12_11.sec2',
      'assets/databases/mora_1_1_11_11.sec2',
      'assets/databases/mora_1_2_11_10.sec2',
      'assets/databases/mora_1_3_10_9.sec2',
      'assets/databases/mora_2_2_10_10.sec2',
    ];

    for (final String asset in assetFiles) {
      try {
        final File file = File('${directory.path}/${asset.split('/').last}');
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
  return tgf.millPerfectDbInit(path: path);
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
