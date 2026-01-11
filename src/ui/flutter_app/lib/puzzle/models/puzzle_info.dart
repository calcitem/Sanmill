// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
    required this.solutions,
    this.hint,
    this.completionMessage,
    this.tags = const <String>[],
    this.isCustom = false,
    this.author,
    DateTime? createdDate,
    this.version = 1, // Format version 1.0
    this.rating,
    this.ruleVariantId =
        'standard_9mm', // Default to standard Nine Men's Morris
    this.titleLocalizationKey,
    this.descriptionLocalizationKey,
    this.hintLocalizationKey,
    this.completionMessageLocalizationKey,
  }) : createdDate = createdDate ?? DateTime.now();

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
      solutions: (json['solutions'] as List<dynamic>)
          .map(
            (dynamic e) => PuzzleSolution.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      hint: json['hint'] as String?,
      completionMessage: json['completionMessage'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((dynamic e) => e as String)
              .toList() ??
          const <String>[],
      isCustom: json['isCustom'] as bool? ?? false,
      author: json['author'] as String?,
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'] as String)
          : DateTime.now(),
      version: json['version'] as int? ?? 1,
      rating: json['rating'] as int?,
      ruleVariantId: json['ruleVariantId'] as String? ?? 'standard_9mm',
      titleLocalizationKey: json['titleLocalizationKey'] as String?,
      descriptionLocalizationKey: json['descriptionLocalizationKey'] as String?,
      hintLocalizationKey: json['hintLocalizationKey'] as String?,
      completionMessageLocalizationKey:
          json['completionMessageLocalizationKey'] as String?,
    );
  }

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

  /// List of solution sequences (multiple solutions possible)
  /// Each PuzzleSolution contains a complete move sequence with side information.
  /// The first solution with isOptimal=true is considered the primary solution.
  @HiveField(6)
  final List<PuzzleSolution> solutions;

  /// Hint text (optional)
  @HiveField(8)
  final String? hint;

  /// Completion message shown after solving (optional)
  /// This can be used by puzzle authors to explain the tactic,
  /// provide educational context, or congratulate the solver.
  @HiveField(19)
  final String? completionMessage;

  /// Tags for filtering/searching
  @HiveField(9)
  final List<String> tags;

  /// Whether this is a user-created custom puzzle
  @HiveField(10)
  final bool isCustom;

  /// Author name (for custom puzzles)
  @HiveField(11)
  final String? author;

  /// Creation date
  @HiveField(12)
  final DateTime createdDate;

  /// Puzzle format version for compatibility
  @HiveField(13)
  final int version;

  /// Puzzle rating (ELO-based, optional)
  @HiveField(14)
  final int? rating;

  /// Rule variant ID this puzzle is designed for
  /// Examples: 'standard_9mm', 'twelve_mens_morris', 'russian_mill', etc.
  /// This ensures puzzles are only shown when the correct rule set is active.
  @HiveField(15)
  final String ruleVariantId;

  /// Optional localization key for the title.
  /// If provided, this key will be used to look up the localized title.
  /// Falls back to the `title` field if the key is not found or is null.
  @HiveField(16)
  final String? titleLocalizationKey;

  /// Optional localization key for the description.
  /// If provided, this key will be used to look up the localized description.
  /// Falls back to the `description` field if the key is not found or is null.
  @HiveField(17)
  final String? descriptionLocalizationKey;

  /// Optional localization key for the hint.
  /// If provided, this key will be used to look up the localized hint.
  /// Falls back to the `hint` field if the key is not found or is null.
  @HiveField(18)
  final String? hintLocalizationKey;

  /// Optional localization key for the completion message.
  /// If provided, this key will be used to look up the localized completion message.
  /// Falls back to the `completionMessage` field if the key is not found or is null.
  @HiveField(20)
  final String? completionMessageLocalizationKey;

  /// Get the player's side (who is solving the puzzle)
  /// This is determined by the side-to-move in the initial position
  PieceColor get playerSide {
    final Position tempPos = Position();
    tempPos.setFen(initialPosition);
    return tempPos.sideToMove;
  }

  /// Get the optimal solution (first solution marked as optimal)
  PuzzleSolution? get optimalSolution {
    final PuzzleSolution? optimal = solutions.firstWhereOrNull(
      (PuzzleSolution s) => s.isOptimal,
    );
    return optimal ?? (solutions.isNotEmpty ? solutions.first : null);
  }

  /// Get optimal move count (number of player moves in optimal solution)
  int get optimalMoveCount {
    final PuzzleSolution? optimal = optimalSolution;
    if (optimal == null) {
      return 0;
    }
    return optimal.getPlayerMoveCount(playerSide);
  }

  /// Creates a copy with updated fields
  PuzzleInfo copyWith({
    String? id,
    String? title,
    String? description,
    PuzzleCategory? category,
    PuzzleDifficulty? difficulty,
    String? initialPosition,
    List<PuzzleSolution>? solutions,
    String? hint,
    String? completionMessage,
    List<String>? tags,
    bool? isCustom,
    String? author,
    DateTime? createdDate,
    int? version,
    int? rating,
    String? ruleVariantId,
    String? titleLocalizationKey,
    String? descriptionLocalizationKey,
    String? hintLocalizationKey,
    String? completionMessageLocalizationKey,
  }) {
    return PuzzleInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      initialPosition: initialPosition ?? this.initialPosition,
      solutions: solutions ?? this.solutions,
      hint: hint ?? this.hint,
      completionMessage: completionMessage ?? this.completionMessage,
      tags: tags ?? this.tags,
      isCustom: isCustom ?? this.isCustom,
      author: author ?? this.author,
      createdDate: createdDate ?? this.createdDate,
      version: version ?? this.version,
      rating: rating ?? this.rating,
      ruleVariantId: ruleVariantId ?? this.ruleVariantId,
      titleLocalizationKey: titleLocalizationKey ?? this.titleLocalizationKey,
      descriptionLocalizationKey:
          descriptionLocalizationKey ?? this.descriptionLocalizationKey,
      hintLocalizationKey: hintLocalizationKey ?? this.hintLocalizationKey,
      completionMessageLocalizationKey:
          completionMessageLocalizationKey ??
          this.completionMessageLocalizationKey,
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
      'solutions': solutions.map((PuzzleSolution s) => s.toJson()).toList(),
      'hint': hint,
      'completionMessage': completionMessage,
      'tags': tags,
      'isCustom': isCustom,
      'author': author,
      'createdDate': createdDate.toIso8601String(),
      'version': version,
      'rating': rating,
      'ruleVariantId': ruleVariantId,
      'titleLocalizationKey': titleLocalizationKey,
      'descriptionLocalizationKey': descriptionLocalizationKey,
      'hintLocalizationKey': hintLocalizationKey,
      'completionMessageLocalizationKey': completionMessageLocalizationKey,
    };
  }

  /// Get the localized title, falling back to the raw title if no key is set.
  String getLocalizedTitle(BuildContext context) {
    // For now, return the raw title as localization key lookup
    // would require adding keys to ARB files
    // Future enhancement: if (titleLocalizationKey != null) {
    //   return S.of(context).puzzleTitles[titleLocalizationKey];
    // }
    return title;
  }

  /// Get the localized description, falling back to the raw description if no key is set.
  String getLocalizedDescription(BuildContext context) {
    // For now, return the raw description
    // Future enhancement: similar to getLocalizedTitle
    return description;
  }

  /// Get the localized hint, falling back to the raw hint if no key is set.
  String? getLocalizedHint(BuildContext context) {
    // For now, return the raw hint
    // Future enhancement: similar to getLocalizedTitle
    return hint;
  }

  /// Get the localized completion message, falling back to the raw message if no key is set.
  String? getLocalizedCompletionMessage(BuildContext context) {
    // For now, return the raw completion message
    // Future enhancement: similar to getLocalizedTitle
    return completionMessage;
  }
}
