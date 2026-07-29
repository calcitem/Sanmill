// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// daily_puzzle_service.dart
//
// Service for managing daily puzzle rotation and completion tracking

import 'package:flutter/foundation.dart';

import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';
import 'puzzle_manager.dart';
import 'puzzle_selection_service.dart';

/// Information about the daily puzzle
class DailyPuzzleInfo {
  DailyPuzzleInfo({
    required this.date,
    required this.puzzleId,
    required this.dayNumber,
    required this.completedToday,
    required this.totalCompleted,
  });

  final DateTime date;
  final String puzzleId;
  final int dayNumber;
  final bool completedToday;
  final int totalCompleted;
}

/// Service for managing daily puzzles
class DailyPuzzleService {
  factory DailyPuzzleService() => _instance;

  DailyPuzzleService._internal();

  static final DailyPuzzleService _instance = DailyPuzzleService._internal();

  static const String _tag = "[DailyPuzzleService]";

  @visibleForTesting
  static DateTime Function()? debugNowOverride;

  /// Epoch date for day number calculation (January 1, 2025)
  static final DateTime _epochDate = DateTime(2025);

  static const PuzzleSelectionService _selectionService =
      PuzzleSelectionService();

  /// Get today's puzzle information
  Future<DailyPuzzleInfo> getTodaysPuzzle() async {
    final DateTime today = _normalizeDate(_now());
    final String todayKey = today.toIso8601String();
    final int dayNumber = _getDayNumber(today);
    final DailyPuzzleStats stats = _getStats();
    final bool completedToday = stats.completedDates.contains(todayKey);

    final PuzzleManager puzzleManager = PuzzleManager();
    final List<PuzzleInfo> builtInPuzzles = puzzleManager
        .getAllPuzzles()
        .where((PuzzleInfo puzzle) => !puzzle.isCustom)
        .toList();

    if (builtInPuzzles.isEmpty) {
      logger.w("$_tag No puzzles available for daily puzzle");
      return DailyPuzzleInfo(
        date: today,
        puzzleId: '',
        dayNumber: dayNumber,
        completedToday: completedToday,
        totalCompleted: stats.completedDates.length,
      );
    }

    PuzzleInfo? todaysPuzzle = _findPuzzleById(
      builtInPuzzles,
      stats.puzzleAssignments[todayKey],
    );
    if (todaysPuzzle == null) {
      todaysPuzzle = _selectPuzzle(
        puzzles: builtInPuzzles,
        puzzleManager: puzzleManager,
        stats: stats,
        today: today,
        dayNumber: dayNumber,
      );
      stats.puzzleAssignments[todayKey] = todaysPuzzle.id;
      await _saveStats(stats);
    }

    return DailyPuzzleInfo(
      date: today,
      puzzleId: todaysPuzzle.id,
      dayNumber: dayNumber,
      completedToday: completedToday,
      totalCompleted: stats.completedDates.length,
    );
  }

  PuzzleInfo? _findPuzzleById(List<PuzzleInfo> puzzles, String? id) {
    if (id == null) {
      return null;
    }
    for (final PuzzleInfo puzzle in puzzles) {
      if (puzzle.id == id) {
        return puzzle;
      }
    }
    return null;
  }

  PuzzleInfo _selectPuzzle({
    required List<PuzzleInfo> puzzles,
    required PuzzleManager puzzleManager,
    required DailyPuzzleStats stats,
    required DateTime today,
    required int dayNumber,
  }) {
    final int priorDailyCompletions = stats.completedDates
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .map(_normalizeDate)
        .where((DateTime date) => date.isBefore(today))
        .toSet()
        .length;
    final int completedPuzzles =
        puzzleManager.settingsNotifier.value.totalCompleted;
    final int experience = priorDailyCompletions > completedPuzzles
        ? priorDailyCompletions
        : completedPuzzles;

    final List<PuzzleInfo> candidates = _selectionService
        .candidatesForExperience(
          puzzles,
          experience: experience,
          userRating: puzzleManager.settingsNotifier.value.userRating,
        );

    final Set<String> previouslyAssigned = stats.puzzleAssignments.values
        .toSet();
    final List<PuzzleInfo> unseenCandidates = candidates
        .where((PuzzleInfo puzzle) => !previouslyAssigned.contains(puzzle.id))
        .toList();
    final List<PuzzleInfo> selectionPool = unseenCandidates.isNotEmpty
        ? unseenCandidates
        : List<PuzzleInfo>.from(candidates);
    selectionPool.sort((PuzzleInfo a, PuzzleInfo b) => a.id.compareTo(b.id));

    return selectionPool[dayNumber % selectionPool.length];
  }

  /// Record completion of today's puzzle
  Future<void> recordCompletion() async {
    final DateTime today = _normalizeDate(_now());
    final DailyPuzzleStats stats = _getStats();

    if (!stats.completedDates.contains(today.toIso8601String())) {
      stats.completedDates.add(today.toIso8601String());
      await _saveStats(stats);
      logger.i("$_tag Recorded daily puzzle completion for $today");
    }
  }

  /// Get puzzle statistics
  DailyPuzzleStats _getStats() {
    // Load from database
    final dynamic data = DB().puzzleAnalyticsBox.get('dailyPuzzleStats');
    if (data == null) {
      return DailyPuzzleStats(completedDates: <String>[], longestStreak: 0);
    }

    try {
      final Map<String, dynamic> map = Map<String, dynamic>.from(
        data as Map<dynamic, dynamic>,
      );
      final Map<String, String> puzzleAssignments = <String, String>{};
      final dynamic rawAssignments = map['puzzleAssignments'];
      if (rawAssignments is Map<dynamic, dynamic>) {
        for (final MapEntry<dynamic, dynamic> entry in rawAssignments.entries) {
          if (entry.key is String && entry.value is String) {
            puzzleAssignments[entry.key as String] = entry.value as String;
          }
        }
      }
      return DailyPuzzleStats(
        completedDates: List<String>.from(
          map['completedDates'] as List<dynamic>? ?? <dynamic>[],
        ),
        longestStreak: map['longestStreak'] as int? ?? 0,
        puzzleAssignments: puzzleAssignments,
      );
    } catch (e) {
      logger.e("$_tag Failed to load daily puzzle stats: $e");
      return DailyPuzzleStats(completedDates: <String>[], longestStreak: 0);
    }
  }

  /// Save puzzle statistics
  Future<void> _saveStats(DailyPuzzleStats stats) async {
    // Save to database
    try {
      await DB().puzzleAnalyticsBox.put('dailyPuzzleStats', <String, dynamic>{
        'completedDates': stats.completedDates,
        'longestStreak': stats.longestStreak,
        'puzzleAssignments': stats.puzzleAssignments,
      });
      logger.i(
        "$_tag Saved daily puzzle stats: ${stats.completedDates.length} completed",
      );
    } catch (e) {
      logger.e("$_tag Failed to save daily puzzle stats: $e");
    }
  }

  /// Get day number since epoch
  int _getDayNumber(DateTime date) {
    final DateTime normalized = _normalizeDate(date);
    final Duration diff = normalized.difference(_epochDate);
    return diff.inDays;
  }

  /// Normalize date to midnight UTC
  DateTime _normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  DateTime _now() => debugNowOverride?.call() ?? DateTime.now();
}

/// Statistics for daily puzzles
class DailyPuzzleStats {
  DailyPuzzleStats({
    required this.completedDates,
    required this.longestStreak,
    Map<String, String> puzzleAssignments = const <String, String>{},
  }) : puzzleAssignments = Map<String, String>.from(puzzleAssignments);

  List<String> completedDates;

  /// Retained only so existing streak history is not destroyed on save.
  int longestStreak;

  /// Stable puzzle IDs keyed by normalized UTC date.
  final Map<String, String> puzzleAssignments;
}
