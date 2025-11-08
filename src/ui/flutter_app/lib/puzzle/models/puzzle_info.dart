// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_info.dart

part of 'puzzle_models.dart';

/// Represents complete information about a puzzle
@HiveType(typeId: 30)
class PuzzleInfo extends HiveObject {
  PuzzleInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.initialPosition,
    required this.solutionMoves,
    required this.optimalMoveCount,
    this.hint,
    this.tags = const <String>[],
  });

  /// Unique identifier for the puzzle
  @HiveField(0)
  final String id;

  /// Title of the puzzle
  @HiveField(1)
  final String title;

  /// Description/objective of the puzzle
  @HiveField(2)
  final String description;

  /// Category of the puzzle
  @HiveField(3)
  final PuzzleCategory category;

  /// Difficulty level
  @HiveField(4)
  final PuzzleDifficulty difficulty;

  /// Initial position in FEN-like notation
  @HiveField(5)
  final String initialPosition;

  /// List of solution move sequences (multiple solutions possible)
  /// Each move is in algebraic notation
  @HiveField(6)
  final List<List<String>> solutionMoves;

  /// Optimal number of moves to solve
  @HiveField(7)
  final int optimalMoveCount;

  /// Hint text (optional)
  @HiveField(8)
  final String? hint;

  /// Tags for filtering/searching
  @HiveField(9)
  final List<String> tags;

  /// Creates a copy with updated fields
  PuzzleInfo copyWith({
    String? id,
    String? title,
    String? description,
    PuzzleCategory? category,
    PuzzleDifficulty? difficulty,
    String? initialPosition,
    List<List<String>>? solutionMoves,
    int? optimalMoveCount,
    String? hint,
    List<String>? tags,
  }) {
    return PuzzleInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      initialPosition: initialPosition ?? this.initialPosition,
      solutionMoves: solutionMoves ?? this.solutionMoves,
      optimalMoveCount: optimalMoveCount ?? this.optimalMoveCount,
      hint: hint ?? this.hint,
      tags: tags ?? this.tags,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'category': category.name,
      'difficulty': difficulty.name,
      'initialPosition': initialPosition,
      'solutionMoves': solutionMoves,
      'optimalMoveCount': optimalMoveCount,
      'hint': hint,
      'tags': tags,
    };
  }

  /// Create from JSON
  factory PuzzleInfo.fromJson(Map<String, dynamic> json) {
    return PuzzleInfo(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: PuzzleCategory.values.firstWhere(
        (PuzzleCategory e) => e.name == json['category'],
      ),
      difficulty: PuzzleDifficulty.values.firstWhere(
        (PuzzleDifficulty e) => e.name == json['difficulty'],
      ),
      initialPosition: json['initialPosition'] as String,
      solutionMoves: (json['solutionMoves'] as List<dynamic>)
          .map((dynamic e) =>
              (e as List<dynamic>).map((dynamic m) => m as String).toList())
          .toList(),
      optimalMoveCount: json['optimalMoveCount'] as int,
      hint: json['hint'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((dynamic e) => e as String)
              .toList() ??
          const <String>[],
    );
  }
}
