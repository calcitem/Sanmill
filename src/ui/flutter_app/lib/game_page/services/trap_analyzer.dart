// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// trap_analyzer.dart

part of 'mill.dart';

/// Utility class for trap awareness analysis in Perfect Database scenarios.
///
/// Provides reusable logic for:
/// - Detecting aggressive moves (forming or blocking mills)
/// - Identifying trap scenarios based on Perfect DB outcomes
/// - Showing trap awareness snackbars
abstract class TrapAnalyzer {
  // Private constructor to prevent instantiation
  TrapAnalyzer._();

  /// Check if a move is aggressive (forms own mill or blocks opponent's mill)
  static bool isAggressive(MoveAnalysisResult moveResult, Position position) {
    if (moveResult.toSquare == null) {
      return false;
    }

    final int to = ExtMove._standardNotationToSquare(moveResult.toSquare.name);
    if (to < 0) {
      return false;
    }

    final int from = moveResult.fromSquare != null
        ? ExtMove._standardNotationToSquare(moveResult.fromSquare!.name)
        : 0;

    final PieceColor sideToMove = position.sideToMove;

    // Check if move forms own mill or blocks opponent's mill
    return position._potentialMillsCount(to, sideToMove, from: from) > 0 ||
        position._potentialMillsCount(to, sideToMove.opponent, from: from) > 0;
  }

  /// Analyze position for traps and return trap move notations
  static List<String> findTrapMoves(
      PositionAnalysisResult analysisResult, Position position) {
    if (!analysisResult.isValid || analysisResult.possibleMoves.isEmpty) {
      return <String>[];
    }

    final List<MoveAnalysisResult> moves = analysisResult.possibleMoves;

    // Check outcome distribution
    final bool anyWin =
        moves.any((MoveAnalysisResult e) => e.outcome == GameOutcome.win);
    final bool anyDraw =
        moves.any((MoveAnalysisResult e) => e.outcome == GameOutcome.draw);
    final bool anyLoss =
        moves.any((MoveAnalysisResult e) => e.outcome == GameOutcome.loss);

    // Do not report traps if all moves have same outcome (all draw or all loss)
    final bool allDraw = !anyWin && anyDraw && !anyLoss;
    final bool allLoss = !anyWin && anyLoss && !anyDraw;
    if (allDraw || allLoss) {
      return <String>[];
    }

    // Find aggressive moves that are trap candidates
    final List<String> trapMoves = <String>[];

    for (final MoveAnalysisResult move in moves) {
      if (!isAggressive(move, position)) {
        continue;
      }

      // Check if this aggressive move is worse than alternatives:
      // - Loss when there are win/draw alternatives, OR
      // - Draw when there are win alternatives
      final bool isWorseChoice = (move.outcome == GameOutcome.loss &&
              moves.any((MoveAnalysisResult other) =>
                  other != move &&
                  (other.outcome == GameOutcome.win ||
                      other.outcome == GameOutcome.draw))) ||
          (move.outcome == GameOutcome.draw &&
              moves.any((MoveAnalysisResult other) =>
                  other != move && other.outcome == GameOutcome.win));

      if (isWorseChoice) {
        trapMoves.add(move.move);
      }
    }

    return trapMoves;
  }

  /// Show trap awareness snackbar if traps exist or player fell into trap
  static Future<void> showTrapSnackbarIfNeeded(
    PositionAnalysisResult analysisResult,
    Position position,
    GameRecorder gameRecorder,
  ) async {
    final List<String> trapMoves = findTrapMoves(analysisResult, position);
    if (trapMoves.isEmpty) {
      return;
    }

    // Check if the last move was a trap move
    final String lastMoveStr = gameRecorder.mainlineMoves.isNotEmpty
        ? gameRecorder.mainlineMoves.last.move
        : "";
    final bool fellIntoTrap = trapMoves.contains(lastMoveStr);

    final BuildContext? context = rootScaffoldMessengerKey.currentContext;
    if (context == null) {
      return;
    }

    final String riskyMovesStr = trapMoves.join(', ');
    final String message = fellIntoTrap
        ? S.of(context).trapSprung(riskyMovesStr)
        : S.of(context).trapExists(riskyMovesStr);

    rootScaffoldMessengerKey.currentState!
        .showSnackBar(CustomSnackBar(message));
  }

  /// Check if trap awareness should be triggered for current game mode
  static bool shouldShowTrapAwareness(GameMode gameMode) {
    return DB().generalSettings.trapAwareness &&
        gameMode != GameMode.aiVsAi &&
        DB().generalSettings.usePerfectDatabase &&
        isRuleSupportingPerfectDatabase();
  }
}
