// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mill_patch_service.dart
//
// The lightweight "error patch" (see docs on the mining pipeline) is a
// single small file mined offline against the full Perfect Database and
// bundled directly as a Flutter asset -- unlike the Perfect Database
// itself, it needs no multi-gigabyte download and is fully self-contained
// (it carries its own copy of the `.secval` identity data it needs).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/simple.dart' as tgf;
import 'logger.dart';

const String _millPatchAsset = 'assets/patches/std.mill_patch';
const String _millPatchFileName = 'std.mill_patch';

bool _isCopying = false;
bool _hasCopied = false;

Future<String?> _millPatchStoragePath() async {
  if (kIsWeb) {
    return null;
  }
  try {
    final Directory dir = Platform.isAndroid
        ? (await getExternalStorageDirectory())!
        : await getApplicationDocumentsDirectory();
    return '${dir.path}/$_millPatchFileName';
  } catch (e) {
    logger.e('Failed to resolve a storage directory for the error patch: $e');
    return null;
  }
}

/// Copy the bundled error-patch asset to device storage (once per process,
/// unless [force]) and initialize the Rust-side lookup. Returns `false` on
/// web, or when the copy or Rust init fails; the AI simply runs without the
/// patch in that case (both toggles that consume it are off by default).
Future<bool> ensureMillPatchReady({bool force = false}) async {
  if (kIsWeb) {
    return false;
  }
  if (_isCopying) {
    logger.w('Error patch copy already in progress, skipping...');
    return false;
  }
  if (_hasCopied && !force) {
    return tgf.millPatchStatus().loaded;
  }

  _isCopying = true;
  try {
    final String? path = await _millPatchStoragePath();
    if (path == null) {
      return false;
    }
    final File file = File(path);
    if (!file.existsSync() || force) {
      final ByteData byteData = await rootBundle.load(_millPatchAsset);
      final ByteBuffer buffer = byteData.buffer;
      await file.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
    }
    _hasCopied = true;
    final bool initialized = tgf.millPatchInit(path: path);
    if (!initialized) {
      logger.w('Error patch initialization was rejected by Rust.');
    }
    return initialized;
  } catch (e) {
    logger.e('Failed to prepare the error patch: $e');
    return false;
  } finally {
    _isCopying = false;
  }
}

void disableMillPatch() {
  if (kIsWeb) {
    return;
  }
  tgf.millPatchDeinit();
}
