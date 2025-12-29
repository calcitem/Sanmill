// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// puzzle_solution.dart

part of 'puzzle_models.dart';

/// Represents a single move in a puzzle solution
///
/// Contains the move notation and metadata about which side plays the move.
/// This provides clarity about the expected sequence of player and opponent moves.
@immutable
@HiveType(typeId: 36)
class PuzzleMove {
  const PuzzleMove({required this.notation, required this.side, this.comment});

  /// Create from JSON
  factory PuzzleMove.fromJson(Map<String, dynamic> json) {
    return PuzzleMove(
      notation: json['notation'] as String,
      side: PieceColor.values.firstWhere(
        (PieceColor e) => e.name == json['side'],
      ),
      comment: json['comment'] as String?,
    );
  }

  /// Move notation in algebraic format (e.g., "a1", "a1-d4", "xa4")
  @HiveField(0)
  final String notation;

  /// Which side plays this move (white or black)
  @HiveField(1)
  final PieceColor side;

  /// Optional comment explaining the move (for hints or annotations)
  @HiveField(2)
  final String? comment;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'notation': notation,
      'side': side.name,
      if (comment != null) 'comment': comment,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PuzzleMove &&
          runtimeType == other.runtimeType &&
          notation == other.notation &&
          side == other.side &&
          comment == other.comment;

  @override
  int get hashCode => Object.hash(notation, side, comment);

  @override
  String toString() => 'PuzzleMove($notation by $side)';
}

/// Represents a complete solution sequence for a puzzle
///
/// Contains the full sequence of moves from initial position to solution.
/// Multiple PuzzleSolution instances can exist for a puzzle if there are
/// alternative ways to solve it.
@immutable
@HiveType(typeId: 37)
class PuzzleSolution {
  const PuzzleSolution({
    required this.moves,
    this.description,
    this.isOptimal = true,
  });

  /// Create from JSON
  factory PuzzleSolution.fromJson(Map<String, dynamic> json) {
    return PuzzleSolution(
      moves: (json['moves'] as List<dynamic>)
          .map((dynamic e) => PuzzleMove.fromJson(e as Map<String, dynamic>))
          .toList(),
      description: json['description'] as String?,
      isOptimal: json['isOptimal'] as bool? ?? true,
    );
  }

  /// Sequence of moves from start to finish
  @HiveField(0)
  final List<PuzzleMove> moves;

  /// Optional description of this solution (e.g., "Main line", "Quick win")
  @HiveField(1)
  final String? description;

  /// Whether this is the optimal solution (shortest move count)
  @HiveField(2)
  final bool isOptimal;

  /// Get only the player moves (excluding opponent responses)
  List<PuzzleMove> getPlayerMoves(PieceColor playerSide) {
    return moves.where((PuzzleMove m) => m.side == playerSide).toList();
  }

  /// Get only the opponent moves
  List<PuzzleMove> getOpponentMoves(PieceColor playerSide) {
    return moves.where((PuzzleMove m) => m.side != playerSide).toList();
  }

  /// Get the number of player moves (for star rating calculation)
  int getPlayerMoveCount(PieceColor playerSide) {
    return getPlayerMoves(playerSide).length;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'moves': moves.map((PuzzleMove m) => m.toJson()).toList(),
      if (description != null) 'description': description,
      'isOptimal': isOptimal,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PuzzleSolution &&
          runtimeType == other.runtimeType &&
          const ListEquality<PuzzleMove>().equals(moves, other.moves) &&
          description == other.description &&
          isOptimal == other.isOptimal;

  @override
  int get hashCode => Object.hash(
    const ListEquality<PuzzleMove>().hash(moves),
    description,
    isOptimal,
  );

  @override
  String toString() =>
      'PuzzleSolution(${moves.length} moves${isOptimal ? ', optimal' : ''})';
}
