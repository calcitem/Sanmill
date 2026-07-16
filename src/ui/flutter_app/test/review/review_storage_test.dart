// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_storage.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box<dynamic> box;
  late ReviewStorage storage;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('sanmill_review_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('review_storage');
    storage = ReviewStorage.forTesting(box);
  });
  setUp(() => box.clear());
  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  test(
    'private history deduplicates and retains the newest 100 games',
    () async {
      final DateTime start = DateTime.utc(2026, 1, 1);
      for (int index = 0; index <= ReviewStorage.maxPrivateGames; index++) {
        await storage.saveGame(
          _record(index, start.add(Duration(minutes: index))),
        );
      }

      expect(storage.listGames(), hasLength(ReviewStorage.maxPrivateGames));
      expect(
        storage.listGames().any(
          (PrivateGameRecord game) => game.moveCount == 0,
        ),
        isFalse,
      );

      final PrivateGameRecord newestAgain = _record(
        ReviewStorage.maxPrivateGames,
        start.add(const Duration(days: 1)),
      );
      await storage.saveGame(newestAgain);
      expect(storage.listGames(), hasLength(ReviewStorage.maxPrivateGames));
      expect(storage.listGames().first.completedAt, newestAgain.completedAt);
    },
  );

  test(
    'review cache is a 100-entry LRU keyed by analysis dimensions',
    () async {
      final DateTime start = DateTime.utc(2026, 1, 1);
      final List<ReviewReport> reports = <ReviewReport>[];
      for (int index = 0; index < ReviewStorage.maxReviewReports; index++) {
        final ReviewReport report = _report(
          index,
          start.add(Duration(minutes: index)),
        );
        reports.add(report);
        await storage.saveReport(report);
      }

      await storage.touchReport(reports.first);
      await storage.saveReport(
        _report(
          ReviewStorage.maxReviewReports,
          start.add(const Duration(days: 1)),
        ),
      );

      final List<ReviewReport> retained = storage.listReports();
      expect(retained, hasLength(ReviewStorage.maxReviewReports));
      expect(
        retained.any(
          (ReviewReport report) => report.cacheKey == reports.first.cacheKey,
        ),
        isTrue,
      );
      expect(
        retained.any(
          (ReviewReport report) => report.cacheKey == reports[1].cacheKey,
        ),
        isFalse,
      );
    },
  );
}

PrivateGameRecord _record(int index, DateTime completedAt) {
  return PrivateGameRecord.create(
    sourcePgn: '1. a7 {game $index} *',
    initialFen: null,
    result: '*',
    rules: const RuleSettings(),
    completedAt: completedAt,
    white: 'Human',
    black: 'AI',
    humanSides: const <ReviewSide>{ReviewSide.white},
    finalBoardLayout: null,
    moveCount: index,
  );
}

ReviewReport _report(int index, DateTime accessedAt) {
  return ReviewReport(
    recordId: 'record-$index',
    pgnHash: 'pgn-$index',
    rulesHash: 'rules',
    engineVersion: reviewEngineVersion,
    profile: ReviewProfile.quick,
    status: ReviewStatus.complete,
    actions: const <ReviewActionEvaluation>[],
    turns: const <ReviewTurnBoundary>[],
    variationCount: 0,
    userNagOverrides: const <int, int?>{},
    includeAnnotationsOnExport: false,
    createdAt: accessedAt,
    updatedAt: accessedAt,
    lastAccessedAt: accessedAt,
  );
}
