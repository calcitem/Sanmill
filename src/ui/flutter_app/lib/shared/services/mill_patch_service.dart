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
///
/// Re-copies whenever the bundled asset's bytes differ from what is already
/// on disk, so an app update that ships an improved `std.mill_patch`
/// replaces a stale copy left over from a previous install instead of that
/// copy being kept forever (the on-disk file name never changes across
/// versions, so nothing else would ever trigger a refresh).
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
    final ByteData byteData = await rootBundle.load(_millPatchAsset);
    final Uint8List bundledBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    if (force || !await bundledAssetMatchesOnDisk(file, bundledBytes)) {
      await file.writeAsBytes(bundledBytes);
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

/// Cheap staleness check for the copy already on disk: compares length
/// first (a single stat call, covering the common case of an unchanged
/// bundled asset across repeated launches of the same app version) before
/// falling back to a full byte comparison, so a same-length-but-different-
/// content update is still detected correctly.
@visibleForTesting
Future<bool> bundledAssetMatchesOnDisk(
  File file,
  Uint8List bundledBytes,
) async {
  if (!file.existsSync()) {
    return false;
  }
  if (await file.length() != bundledBytes.length) {
    return false;
  }
  final Uint8List onDiskBytes = await file.readAsBytes();
  for (int i = 0; i < bundledBytes.length; i++) {
    if (onDiskBytes[i] != bundledBytes[i]) {
      return false;
    }
  }
  return true;
}

void disableMillPatch() {
  if (kIsWeb) {
    return;
  }
  tgf.millPatchDeinit();
}
