// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/learn/coordinate_training_stats.dart';

void main() {
  test('tracks timed records separately from untimed practice', () {
    final CoordinateTrainingStats stats = const CoordinateTrainingStats()
        .recordSession(isThirtySeconds: true, correct: 10, attempts: 20)
        .recordSession(isThirtySeconds: false, correct: 100, attempts: 100)
        .recordSession(isThirtySeconds: true, correct: 14, attempts: 20);

    expect(stats.trainingSessions, 3);
    expect(stats.thirtySecondSessions, 2);
    expect(stats.thirtySecondBestCorrect, 14);
    expect(stats.thirtySecondAverageCorrect, 12);
    expect(stats.totalCorrect, 124);
    expect(stats.totalAttempts, 140);
    expect(stats.overallAccuracy, closeTo(124 / 140, 0.0001));
  });

  test('round-trips versioned coordinate training statistics', () {
    final CoordinateTrainingStats original = const CoordinateTrainingStats()
        .recordSession(isThirtySeconds: true, correct: 8, attempts: 12);

    final CoordinateTrainingStats restored = CoordinateTrainingStats.fromJson(
      original.toJson(),
    );

    expect(restored.trainingSessions, original.trainingSessions);
    expect(restored.thirtySecondSessions, original.thirtySecondSessions);
    expect(restored.thirtySecondBestCorrect, original.thirtySecondBestCorrect);
    expect(
      restored.thirtySecondTotalCorrect,
      original.thirtySecondTotalCorrect,
    );
    expect(restored.totalCorrect, original.totalCorrect);
    expect(restored.totalAttempts, original.totalAttempts);
  });

  test('rejects unknown statistics versions', () {
    expect(
      () => CoordinateTrainingStats.fromJson(const <String, dynamic>{
        'version': 2,
      }),
      throwsFormatException,
    );
  });
}
