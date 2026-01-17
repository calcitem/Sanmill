// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// perfect_database_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

// Track copying state to prevent concurrent calls
bool _isCopying = false;
bool _hasCopied = false;

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
    Directory? dir;
    try {
      dir = (!kIsWeb && Platform.isAndroid)
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
    } catch (e) {
      logger.e('Failed to get directory: $e');
      return false;
    }

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
      'assets/databases/std_3_3_5_5.sec2',
      'assets/databases/std_3_3_6_5.sec2',
      'assets/databases/std_3_3_6_6.sec2',
      'assets/databases/std_3_4_5_5.sec2',
      'assets/databases/std_3_4_6_5.sec2',
      'assets/databases/std_4_3_5_5.sec2',
      'assets/databases/std_4_4_5_5.sec2',
    ];

    for (final String asset in assetFiles) {
      try {
        final File file = File('${directory.path}/${asset.split('/').last}');
        if (!await _exists(file)) {
          final ByteData byteData = await rootBundle.load(asset);
          final ByteBuffer buffer = byteData.buffer;
          await file.writeAsBytes(
            buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          );
          logger.i('Copied file to ${file.path}');
        } else {
          // Reduce log noise - only log once per file check session
          if (force) {
            logger.i(
              'File already exists and was not overwritten: ${file.path}',
            );
          }
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

Future<bool> _exists(FileSystemEntity entity) async {
  return entity.exists();
}
