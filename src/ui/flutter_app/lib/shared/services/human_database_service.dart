// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

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
    assert(normalizedPath.isNotEmpty, 'Human DB path must not be empty.');

    if (kIsWeb || normalizedPath.isEmpty) {
      return HumanDatabaseReadyResult(
        ready: false,
        status: tgf.millHumanDbStatus(path: normalizedPath),
      );
    }

    final File file = File(normalizedPath);
    if (!file.existsSync()) {
      logger.w('Human DB file does not exist: $normalizedPath');
      return HumanDatabaseReadyResult(
        ready: false,
        status: tgf.millHumanDbStatus(path: normalizedPath),
      );
    }

    final tgf.MillHumanDatabaseStatus currentStatus = tgf.millHumanDbStatus(
      path: normalizedPath,
    );
    if (!currentStatus.readable) {
      logger.w('Human DB is not readable: ${currentStatus.error}');
      return HumanDatabaseReadyResult(ready: false, status: currentStatus);
    }

    if (_initializedPath == normalizedPath && currentStatus.initialized) {
      return HumanDatabaseReadyResult(ready: true, status: currentStatus);
    }

    final bool initialized = tgf.millHumanDbInit(path: normalizedPath);
    if (!initialized) {
      logger.w('Human DB initialization was rejected by Rust.');
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

  void disable() {
    _initializedPath = null;
    if (!kIsWeb) {
      tgf.millHumanDbDeinit();
    }
  }
}
