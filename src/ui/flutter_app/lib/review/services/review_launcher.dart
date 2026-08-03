// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../models/review_models.dart';
import '../widgets/review_page.dart';
import 'review_record_factory.dart';
import 'review_storage.dart';

typedef ReviewPageBuilder =
    Widget Function(
      BuildContext context,
      PrivateGameRecord record,
      ReviewStorage storage,
    );

abstract final class ReviewLauncher {
  static bool get canReviewCurrentGame =>
      GameController().gameRecorder.mainlineMoves.isNotEmpty;

  static Future<PrivateGameRecord?> archiveCurrentGame({
    required ReviewStorage storage,
    String? importedSourcePgn,
  }) async {
    if (!canReviewCurrentGame) {
      return null;
    }
    final PrivateGameRecord record = ReviewRecordFactory.fromCurrentGame(
      importedSourcePgn: importedSourcePgn,
    );
    await storage.saveGame(record);
    return record;
  }

  static Future<void> open(
    BuildContext context, {
    required PrivateGameRecord record,
    required ReviewStorage storage,
    ReviewPageBuilder? pageBuilder,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            pageBuilder?.call(context, record, storage) ??
            ReviewPage(record: record, storage: storage),
      ),
    );
  }
}
