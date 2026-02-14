// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// puzzle_validation_report_test.dart
//
// Tests for PuzzleValidationReport and DailyPuzzleInfo/DailyPuzzleStats.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/puzzle/services/daily_puzzle_service.dart';
import 'package:sanmill/puzzle/services/puzzle_validation_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PuzzleValidationReport
  // ---------------------------------------------------------------------------
  group('PuzzleValidationReport', () {
    test('default constructor should have empty lists', () {
      const PuzzleValidationReport report = PuzzleValidationReport();

      expect(report.errors, isEmpty);
      expect(report.warnings, isEmpty);
    });

    test('isValid should be true when no errors', () {
      const PuzzleValidationReport report = PuzzleValidationReport();
      expect(report.isValid, isTrue);
    });

    test('isValid should be false when errors exist', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        errors: <String>['Missing title'],
      );
      expect(report.isValid, isFalse);
    });

    test('hasIssues should be false when no errors or warnings', () {
      const PuzzleValidationReport report = PuzzleValidationReport();
      expect(report.hasIssues, isFalse);
    });

    test('hasIssues should be true when only warnings', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        warnings: <String>['Title is short'],
      );
      expect(report.hasIssues, isTrue);
    });

    test('hasIssues should be true when only errors', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        errors: <String>['Missing title'],
      );
      expect(report.hasIssues, isTrue);
    });

    test('hasIssues should be true when both errors and warnings', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        errors: <String>['Missing title'],
        warnings: <String>['Title is short'],
      );
      expect(report.hasIssues, isTrue);
    });

    test('toString should show OK when no issues', () {
      const PuzzleValidationReport report = PuzzleValidationReport();
      expect(report.toString(), contains('OK'));
    });

    test('toString should show errors when present', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        errors: <String>['Error 1', 'Error 2'],
      );

      final String str = report.toString();
      expect(str, contains('Errors: 2'));
      expect(str, contains('Error 1'));
      expect(str, contains('Error 2'));
    });

    test('toString should show warnings when present', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        warnings: <String>['Warning 1'],
      );

      final String str = report.toString();
      expect(str, contains('Warnings: 1'));
      expect(str, contains('Warning 1'));
    });

    test('toString should show both errors and warnings', () {
      const PuzzleValidationReport report = PuzzleValidationReport(
        errors: <String>['Error A'],
        warnings: <String>['Warning B'],
      );

      final String str = report.toString();
      expect(str, contains('Errors'));
      expect(str, contains('Warnings'));
    });
  });

  // ---------------------------------------------------------------------------
  // DailyPuzzleInfo
  // ---------------------------------------------------------------------------
  group('DailyPuzzleInfo', () {
    test('should store all fields', () {
      final DateTime today = DateTime(2026, 2, 14);
      final DailyPuzzleInfo info = DailyPuzzleInfo(
        date: today,
        puzzleId: 'puzzle-42',
        dayNumber: 411,
        currentStreak: 5,
        longestStreak: 10,
        totalCompleted: 30,
      );

      expect(info.date, today);
      expect(info.puzzleId, 'puzzle-42');
      expect(info.dayNumber, 411);
      expect(info.currentStreak, 5);
      expect(info.longestStreak, 10);
      expect(info.totalCompleted, 30);
    });
  });

  // ---------------------------------------------------------------------------
  // DailyPuzzleStats
  // ---------------------------------------------------------------------------
  group('DailyPuzzleStats', () {
    test('should store completed dates and longest streak', () {
      final DailyPuzzleStats stats = DailyPuzzleStats(
        completedDates: <String>[
          '2026-02-12',
          '2026-02-13',
          '2026-02-14',
        ],
        longestStreak: 3,
      );

      expect(stats.completedDates.length, 3);
      expect(stats.longestStreak, 3);
    });

    test('empty stats', () {
      final DailyPuzzleStats stats = DailyPuzzleStats(
        completedDates: <String>[],
        longestStreak: 0,
      );

      expect(stats.completedDates, isEmpty);
      expect(stats.longestStreak, 0);
    });

    test('should be mutable', () {
      final DailyPuzzleStats stats = DailyPuzzleStats(
        completedDates: <String>[],
        longestStreak: 0,
      );

      stats.completedDates.add('2026-02-14');
      stats.longestStreak = 1;

      expect(stats.completedDates.length, 1);
      expect(stats.longestStreak, 1);
    });
  });
}
