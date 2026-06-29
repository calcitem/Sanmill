// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/database/database.dart';

class SavedGameSummary {
  const SavedGameSummary({
    required this.path,
    required this.filename,
    required this.modified,
  });

  final String path;
  final String filename;
  final DateTime modified;

  String get displayName => p.basenameWithoutExtension(filename);
}

const SavedGameCatalog savedGameCatalog = SavedGameCatalog();

final class SavedGameCatalog {
  const SavedGameCatalog();

  Future<Directory?> recordsDirectory({bool create = true}) async {
    if (kIsWeb) {
      return null;
    }

    final bool isMobilePlatform = Platform.isAndroid || Platform.isIOS;

    if (!isMobilePlatform) {
      final String lastDirectory = DB().generalSettings.lastPgnSaveDirectory;
      if (lastDirectory.isNotEmpty) {
        final Directory lastDir = Directory(lastDirectory);
        if (lastDir.existsSync()) {
          return lastDir;
        }
      }
    }

    final Directory? base = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    if (base == null) {
      return null;
    }

    final Directory records = Directory(p.join(base.path, 'records'));
    if (!records.existsSync()) {
      if (!create) {
        return null;
      }
      await records.create(recursive: true);
    }
    return records;
  }

  Future<List<SavedGameSummary>> listRecent({int? limit}) async {
    assert(limit == null || limit > 0, 'Recent game limit must be positive.');
    final Directory? dir = await recordsDirectory(create: false);
    if (dir == null || !dir.existsSync()) {
      return const <SavedGameSummary>[];
    }

    final List<File> files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.pgn'))
        .toList();

    files.sort((File a, File b) {
      return b.lastModifiedSync().compareTo(a.lastModifiedSync());
    });

    final Iterable<File> selected = limit == null ? files : files.take(limit);
    return selected
        .map(
          (File file) => SavedGameSummary(
            path: file.path,
            filename: p.basename(file.path),
            modified: file.lastModifiedSync(),
          ),
        )
        .toList(growable: false);
  }
}
