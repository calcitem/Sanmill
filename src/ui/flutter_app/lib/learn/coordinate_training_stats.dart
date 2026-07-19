// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import '../shared/database/database.dart';

@immutable
class CoordinateTrainingStats {
  const CoordinateTrainingStats({
    this.trainingSessions = 0,
    this.thirtySecondSessions = 0,
    this.thirtySecondBestCorrect = 0,
    this.thirtySecondTotalCorrect = 0,
    this.totalCorrect = 0,
    this.totalAttempts = 0,
  });

  factory CoordinateTrainingStats.fromJson(Map<dynamic, dynamic> json) {
    final int version = json['version'] as int? ?? 1;
    if (version != 1) {
      throw FormatException(
        'Unsupported coordinate training stats version: $version',
      );
    }
    return CoordinateTrainingStats(
      trainingSessions: json['trainingSessions'] as int? ?? 0,
      thirtySecondSessions: json['thirtySecondSessions'] as int? ?? 0,
      thirtySecondBestCorrect: json['thirtySecondBestCorrect'] as int? ?? 0,
      thirtySecondTotalCorrect: json['thirtySecondTotalCorrect'] as int? ?? 0,
      totalCorrect: json['totalCorrect'] as int? ?? 0,
      totalAttempts: json['totalAttempts'] as int? ?? 0,
    );
  }

  final int trainingSessions;
  final int thirtySecondSessions;
  final int thirtySecondBestCorrect;
  final int thirtySecondTotalCorrect;
  final int totalCorrect;
  final int totalAttempts;

  double get thirtySecondAverageCorrect => thirtySecondSessions == 0
      ? 0
      : thirtySecondTotalCorrect / thirtySecondSessions;

  double get overallAccuracy =>
      totalAttempts == 0 ? 0 : totalCorrect / totalAttempts;

  CoordinateTrainingStats recordSession({
    required bool isThirtySeconds,
    required int correct,
    required int attempts,
  }) {
    assert(correct >= 0, 'Correct answers cannot be negative.');
    assert(attempts >= 0, 'Attempts cannot be negative.');
    assert(correct <= attempts, 'Correct answers cannot exceed attempts.');

    return CoordinateTrainingStats(
      trainingSessions: trainingSessions + 1,
      thirtySecondSessions: thirtySecondSessions + (isThirtySeconds ? 1 : 0),
      thirtySecondBestCorrect: isThirtySeconds
          ? correct > thirtySecondBestCorrect
                ? correct
                : thirtySecondBestCorrect
          : thirtySecondBestCorrect,
      thirtySecondTotalCorrect:
          thirtySecondTotalCorrect + (isThirtySeconds ? correct : 0),
      totalCorrect: totalCorrect + correct,
      totalAttempts: totalAttempts + attempts,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': 1,
      'trainingSessions': trainingSessions,
      'thirtySecondSessions': thirtySecondSessions,
      'thirtySecondBestCorrect': thirtySecondBestCorrect,
      'thirtySecondTotalCorrect': thirtySecondTotalCorrect,
      'totalCorrect': totalCorrect,
      'totalAttempts': totalAttempts,
    };
  }
}

abstract final class CoordinateTrainingStatsStore {
  static CoordinateTrainingStats load() {
    final dynamic raw = DB().puzzleAnalyticsBox.get(
      DB.coordinateTrainingStatsKey,
    );
    if (raw == null) {
      return const CoordinateTrainingStats();
    }
    if (raw is! Map<dynamic, dynamic>) {
      throw const FormatException(
        'Coordinate training stats must be stored as a map.',
      );
    }
    return CoordinateTrainingStats.fromJson(raw);
  }

  static Future<void> save(CoordinateTrainingStats stats) {
    return DB().puzzleAnalyticsBox.put(
      DB.coordinateTrainingStatsKey,
      stats.toJson(),
    );
  }
}
