// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_collection.dart
//
// Puzzle collection management - groups puzzles by rule variant

import 'puzzle_models.dart';

/// A collection of puzzles for a specific rule variant
///
/// This groups puzzles that are designed for the same rule set.
/// Puzzles within a collection can be sorted by difficulty, category, rating, etc.
class PuzzleCollection {
  PuzzleCollection({required this.variant, required this.puzzles});

  /// The rule variant for this collection
  final RuleVariant variant;

  /// All puzzles in this collection
  final List<PuzzleInfo> puzzles;

  /// Get puzzles filtered by difficulty
  List<PuzzleInfo> getPuzzlesByDifficulty(PuzzleDifficulty difficulty) {
    return puzzles.where((PuzzleInfo p) => p.difficulty == difficulty).toList();
  }

  /// Get puzzles filtered by category
  List<PuzzleInfo> getPuzzlesByCategory(PuzzleCategory category) {
    return puzzles.where((PuzzleInfo p) => p.category == category).toList();
  }

  /// Get puzzles filtered by rating range
  List<PuzzleInfo> getPuzzlesByRatingRange(int minRating, int maxRating) {
    return puzzles
        .where(
          (PuzzleInfo p) =>
              p.rating != null &&
              p.rating! >= minRating &&
              p.rating! <= maxRating,
        )
        .toList();
  }

  /// Get custom puzzles only
  List<PuzzleInfo> getCustomPuzzles() {
    return puzzles.where((PuzzleInfo p) => p.isCustom).toList();
  }

  /// Get built-in puzzles only
  List<PuzzleInfo> getBuiltInPuzzles() {
    return puzzles.where((PuzzleInfo p) => !p.isCustom).toList();
  }

  /// Get puzzles sorted by difficulty (easiest first)
  List<PuzzleInfo> getSortedByDifficulty() {
    final List<PuzzleInfo> sorted = List<PuzzleInfo>.from(puzzles);
    sorted.sort(
      (PuzzleInfo a, PuzzleInfo b) =>
          a.difficulty.index.compareTo(b.difficulty.index),
    );
    return sorted;
  }

  /// Get puzzles sorted by rating (lowest first)
  List<PuzzleInfo> getSortedByRating() {
    final List<PuzzleInfo> sorted = puzzles
        .where((PuzzleInfo p) => p.rating != null)
        .toList();
    sorted.sort((PuzzleInfo a, PuzzleInfo b) => a.rating!.compareTo(b.rating!));
    return sorted;
  }

  /// Get statistics for this collection
  PuzzleCollectionStats get stats {
    return PuzzleCollectionStats(
      totalPuzzles: puzzles.length,
      customPuzzles: puzzles.where((PuzzleInfo p) => p.isCustom).length,
      builtInPuzzles: puzzles.where((PuzzleInfo p) => !p.isCustom).length,
      byDifficulty: _countByDifficulty(),
      byCategory: _countByCategory(),
      averageRating: _calculateAverageRating(),
    );
  }

  Map<PuzzleDifficulty, int> _countByDifficulty() {
    final Map<PuzzleDifficulty, int> counts = <PuzzleDifficulty, int>{};
    for (final PuzzleDifficulty diff in PuzzleDifficulty.values) {
      counts[diff] = puzzles
          .where((PuzzleInfo p) => p.difficulty == diff)
          .length;
    }
    return counts;
  }

  Map<PuzzleCategory, int> _countByCategory() {
    final Map<PuzzleCategory, int> counts = <PuzzleCategory, int>{};
    for (final PuzzleCategory cat in PuzzleCategory.values) {
      counts[cat] = puzzles.where((PuzzleInfo p) => p.category == cat).length;
    }
    return counts;
  }

  double? _calculateAverageRating() {
    final List<PuzzleInfo> rated = puzzles
        .where((PuzzleInfo p) => p.rating != null)
        .toList();
    if (rated.isEmpty) {
      return null;
    }

    final int sum = rated.fold<int>(
      0,
      (int sum, PuzzleInfo p) => sum + p.rating!,
    );
    return sum / rated.length;
  }
}

/// Statistics for a puzzle collection
class PuzzleCollectionStats {
  PuzzleCollectionStats({
    required this.totalPuzzles,
    required this.customPuzzles,
    required this.builtInPuzzles,
    required this.byDifficulty,
    required this.byCategory,
    this.averageRating,
  });

  final int totalPuzzles;
  final int customPuzzles;
  final int builtInPuzzles;
  final Map<PuzzleDifficulty, int> byDifficulty;
  final Map<PuzzleCategory, int> byCategory;
  final double? averageRating;
}

/// Manager for multiple puzzle collections
class PuzzleCollectionManager {
  PuzzleCollectionManager(this._allPuzzles) {
    _buildCollections();
  }

  final List<PuzzleInfo> _allPuzzles;
  final Map<String, PuzzleCollection> _collections =
      <String, PuzzleCollection>{};

  /// Build collections grouped by rule variant
  ///
  /// Automatically handles migration of old variant IDs to new ones
  void _buildCollections() {
    _collections.clear();

    // Group puzzles by rule variant ID (with migration support)
    final Map<String, List<PuzzleInfo>> groupedPuzzles =
        <String, List<PuzzleInfo>>{};
    for (final PuzzleInfo puzzle in _allPuzzles) {
      // Get the current variant ID (may be migrated from old hash)
      final String variantId = _getMigratedVariantId(puzzle.ruleVariantId);

      groupedPuzzles.putIfAbsent(variantId, () => <PuzzleInfo>[]).add(puzzle);
    }

    // Create collections
    for (final MapEntry<String, List<PuzzleInfo>> entry
        in groupedPuzzles.entries) {
      final String variantId = entry.key;
      final List<PuzzleInfo> puzzles = entry.value;

      // Get variant info (use predefined or create generic)
      final RuleVariant? variant = PredefinedVariants.getById(variantId);
      if (variant != null) {
        _collections[variantId] = PuzzleCollection(
          variant: variant,
          puzzles: puzzles,
        );
      }
    }
  }

  /// Get migrated variant ID if migration is needed
  ///
  /// This ensures old puzzles are still accessible after schema changes
  String _getMigratedVariantId(String originalId) {
    // Check if this ID needs migration
    const RuleMigrationManager migrationManager = RuleMigrationManager();

    if (migrationManager.needsMigration(originalId)) {
      final String? migratedId = migrationManager.migrate(originalId);
      if (migratedId != null) {
        return migratedId;
      }
    }

    return originalId;
  }

  /// Get collection for a specific rule variant
  PuzzleCollection? getCollection(String variantId) {
    return _collections[variantId];
  }

  /// Get all available collections
  List<PuzzleCollection> get allCollections => _collections.values.toList();

  /// Get all available rule variants (that have puzzles)
  List<RuleVariant> get availableVariants {
    return _collections.values.map((PuzzleCollection c) => c.variant).toList();
  }

  /// Refresh collections (call after adding/removing puzzles)
  void refresh(List<PuzzleInfo> allPuzzles) {
    _allPuzzles.clear();
    _allPuzzles.addAll(allPuzzles);
    _buildCollections();
  }
}
