// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// nnue_model_service.dart

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

/// Handles deploying NNUE model files bundled as Flutter assets to a readable
/// location on the device file system and returns the model path for the engine.
///
/// Usage:
/// - Declare your NNUE model in pubspec.yaml under assets, e.g.:
///   assets:
///     - assets/nnue/mill.nnue
/// - Call ensureNnueModelDeployed() to copy the asset to app storage and get the
///   absolute path. If no asset is found, returns null.
class NnueModelService {
  NnueModelService._();

  /// Candidate asset paths to probe. The first available will be used.
  ///
  /// Note: Flutter cannot list assets at runtime; we must try known paths.
  static const List<String> _candidateAssets = <String>[
    'assets/nnue/mill.nnue',
    'assets/nnue/nnue_model.nnue',
    'assets/nnue/model.nnue',
    'assets/nnue/net.nnue',
  ];

  /// Ensures an NNUE model asset is deployed to the app's writable storage and
  /// returns its absolute path. Returns null if no known asset is bundled.
  static Future<String?> ensureNnueModelDeployed() async {
    if (kIsWeb) return null;

    try {
      final Directory? dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (dir == null) return null;

      final String targetDir = '${dir.path}/nnue';
      await Directory(targetDir).create(recursive: true);

      for (final String asset in _candidateAssets) {
        final String fileName = asset.split('/').last;
        final String targetPath = '$targetDir/$fileName';
        try {
          // Try to load the asset. If it does not exist, this throws.
          final ByteData data = await rootBundle.load(asset);
          final File out = File(targetPath);

          // Write only if absent or size differs.
          final List<int> bytes = data.buffer.asUint8List();
          if (!await out.exists()) {
            await out.writeAsBytes(bytes, flush: true);
          } else {
            final int existingLen = await out.length();
            if (existingLen != bytes.length) {
              await out.writeAsBytes(bytes, flush: true);
            }
          }

          logger.i('[nnue] Deployed NNUE model to $targetPath');
          return targetPath;
        } catch (e) {
          // Asset not found or copy failure; try next candidate
          logger.w('[nnue] Asset not available or copy failed: $asset ($e)');
        }
      }
    } catch (e) {
      logger.e('[nnue] ensureNnueModelDeployed error: $e');
    }

    return null;
  }
}
