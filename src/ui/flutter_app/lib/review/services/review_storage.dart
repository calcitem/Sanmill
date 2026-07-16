// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../models/review_models.dart';

class ReviewStorage {
  const ReviewStorage._() : _box = null;

  @visibleForTesting
  const ReviewStorage.forTesting(Box<dynamic> box) : _box = box;

  static const ReviewStorage instance = ReviewStorage._();
  static const int maxPrivateGames = 100;
  static const int maxReviewReports = 100;
  static const String _historyKey = 'privateGameHistory';
  static const String _reportsKey = 'reviewReports';
  final Box<dynamic>? _box;

  Box<dynamic> get _dataBox => _box ?? DB().reviewDataBox;

  List<PrivateGameRecord> listGames() {
    final dynamic raw = _dataBox.get(_historyKey);
    if (raw is! List<dynamic>) {
      return const <PrivateGameRecord>[];
    }
    final List<PrivateGameRecord> records = raw
        .whereType<Map<dynamic, dynamic>>()
        .map(PrivateGameRecord.fromJson)
        .where(
          (PrivateGameRecord record) => record.version == reviewSchemaVersion,
        )
        .toList();
    records.sort(
      (PrivateGameRecord a, PrivateGameRecord b) =>
          b.completedAt.compareTo(a.completedAt),
    );
    return records;
  }

  Future<void> saveGame(PrivateGameRecord record) async {
    final List<PrivateGameRecord> records =
        List<PrivateGameRecord>.of(listGames())
          ..removeWhere((PrivateGameRecord value) => value.id == record.id)
          ..insert(0, record);
    if (records.length > maxPrivateGames) {
      records.removeRange(maxPrivateGames, records.length);
    }
    await _dataBox.put(
      _historyKey,
      records.map((PrivateGameRecord value) => value.toJson()).toList(),
    );
  }

  List<ReviewReport> listReports() {
    final dynamic raw = _dataBox.get(_reportsKey);
    if (raw is! List<dynamic>) {
      return const <ReviewReport>[];
    }
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(ReviewReport.fromJson)
        .where((ReviewReport report) => report.version == reviewSchemaVersion)
        .toList();
  }

  ReviewReport? reportFor(
    PrivateGameRecord record, {
    required ReviewProfile profile,
    required String engineVersion,
  }) {
    final String key = ReviewReport.cacheKeyFor(
      pgnHash: pgnFingerprint(record.sourcePgn),
      rulesHash: record.rulesFingerprint,
      engineVersion: engineVersion,
      profile: profile,
    );
    for (final ReviewReport report in listReports()) {
      if (report.cacheKey == key && report.status == ReviewStatus.complete) {
        return report;
      }
    }
    return null;
  }

  ReviewReport? latestReportForRecord(String recordId) {
    final List<ReviewReport> reports =
        listReports()
            .where((ReviewReport report) => report.recordId == recordId)
            .toList()
          ..sort(
            (ReviewReport a, ReviewReport b) =>
                b.updatedAt.compareTo(a.updatedAt),
          );
    return reports.isEmpty ? null : reports.first;
  }

  ReviewReport? latestReportForGame({
    required String sourcePgn,
    required RuleSettings rules,
  }) {
    final String pgnHash = pgnFingerprint(sourcePgn);
    final String rulesHash = ruleSettingsFingerprint(rules);
    final List<ReviewReport> reports =
        listReports()
            .where(
              (ReviewReport report) =>
                  report.pgnHash == pgnHash && report.rulesHash == rulesHash,
            )
            .toList()
          ..sort(
            (ReviewReport a, ReviewReport b) =>
                b.updatedAt.compareTo(a.updatedAt),
          );
    return reports.isEmpty ? null : reports.first;
  }

  Future<void> saveReport(ReviewReport report) async {
    final List<ReviewReport> reports = List<ReviewReport>.of(listReports())
      ..removeWhere(
        (ReviewReport existing) => existing.cacheKey == report.cacheKey,
      )
      ..add(report);
    reports.sort(
      (ReviewReport a, ReviewReport b) =>
          b.lastAccessedAt.compareTo(a.lastAccessedAt),
    );
    if (reports.length > maxReviewReports) {
      reports.removeRange(maxReviewReports, reports.length);
    }
    await _dataBox.put(
      _reportsKey,
      reports.map((ReviewReport value) => value.toJson()).toList(),
    );
  }

  Future<ReviewReport> touchReport(ReviewReport report) async {
    final ReviewReport touched = report.copyWith(
      lastAccessedAt: DateTime.now().toUtc(),
    );
    await saveReport(touched);
    return touched;
  }

  int completedGamesOn(DateTime localDay) {
    return listGames().where((PrivateGameRecord record) {
      final DateTime local = record.completedAt.toLocal();
      return record.humanSides.isNotEmpty &&
          local.year == localDay.year &&
          local.month == localDay.month &&
          local.day == localDay.day;
    }).length;
  }

  int completedReviewsOn(DateTime localDay) {
    final Set<String> reviewedRecords = <String>{};
    for (final ReviewReport report in listReports()) {
      if (report.status != ReviewStatus.complete) {
        continue;
      }
      final DateTime local = report.updatedAt.toLocal();
      final bool isToday =
          local.year == localDay.year &&
          local.month == localDay.month &&
          local.day == localDay.day;
      if (isToday &&
          report.actions.any((ReviewActionEvaluation a) => a.isHumanMove)) {
        reviewedRecords.add(report.recordId);
      }
    }
    return reviewedRecords.length;
  }
}
