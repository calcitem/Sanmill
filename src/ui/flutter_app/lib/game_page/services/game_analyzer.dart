// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../shared/services/logger.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import 'import_export/pgn.dart' as pgn;
import 'mill.dart';

/// Service class for analyzing chess games using perfect database
class GameAnalyzer {
  /// Analyze all moves in the game using perfect database
  static Future<void> analyzeGame({
    required BuildContext context,
    required List<pgn.PgnNode<ExtMove>> allNodes,
    required VoidCallback onAnalysisComplete,
  }) async {
    // Check if there are any moves to analyze
    if (allNodes.isEmpty || allNodes.length <= 1) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
        const SnackBar(content: Text('No moves to analyze')),
      );
      return;
    }

    // Control flag for canceling analysis
    bool shouldCancel = false;

    // Show progress dialog
    bool isAnalyzing = true;
    int currentMove = 0;
    final int totalMoves = allNodes.length - 1; // Exclude initial position

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            if (isAnalyzing) {
              // Start analysis after dialog is shown
              Future<void>.delayed(Duration.zero, () async {
                await _performAnalysis(
                  allNodes,
                  context, // Use parent page context to keep it mounted longer
                  (int progress) {
                    if (dialogContext.mounted) {
                      setState(() {
                        currentMove = progress;
                      });
                    }
                  },
                  () => shouldCancel, // pass cancel checker
                );
                if (dialogContext.mounted) {
                  setState(() {
                    isAnalyzing = false;
                  });
                  // Check if dialog can be popped before attempting to pop
                  if (Navigator.canPop(dialogContext)) {
                    Navigator.of(dialogContext).pop();
                  }
                  // Trigger UI refresh - additional safety check
                  try {
                    onAnalysisComplete();
                  } catch (e) {
                    logger.w("Error in onAnalysisComplete callback: $e");
                  }
                }
              });
            }

            return AlertDialog(
              title: const Text('Analyzing'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  LinearProgressIndicator(
                    value: totalMoves > 0 ? currentMove / totalMoves : 0,
                  ),
                  const SizedBox(height: 16),
                  Text(
                      '${totalMoves > 0 ? currentMove * 100 ~/ totalMoves : 0}%'),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    shouldCancel = true; // request cancel
                    // Check if dialog can be popped before attempting to pop
                    if (Navigator.canPop(dialogContext)) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Perform the actual analysis of moves
  static Future<void> _performAnalysis(
    List<pgn.PgnNode<ExtMove>> allNodes,
    BuildContext context,
    Function(int) onProgress,
    bool Function() shouldCancel,
  ) async {
    final GameController controller = GameController();

    // Save the current game state completely
    final pgn.PgnNode<ExtMove>? originalActiveNode =
        controller.gameRecorder.activeNode;
    final GameMode originalGameMode = controller.gameInstance.gameMode;

    try {
      // Temporarily set game mode to humanVsHuman for analysis
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Navigate to each position without using HistoryNavigator
      // Instead, we'll use direct node navigation and manual position setup
      for (int i = 1; i < allNodes.length; i++) {
        if (shouldCancel()) {
          logger.i("Analysis cancelled by user");
          break; // early cancel
        }

        // Check if context is still valid before proceeding
        if (!context.mounted) {
          logger.w("Context is not mounted, stopping analysis");
          break;
        }

        final pgn.PgnNode<ExtMove> node = allNodes[i];

        // Skip if not a regular move
        if (node.data == null ||
            node.data!.type == MoveType.none ||
            node.data!.type == MoveType.draw) {
          continue;
        }

        // Set up the position before this move by navigating to the previous node
        final pgn.PgnNode<ExtMove> previousNode = allNodes[i - 1];
        if (previousNode != null) {
          // Temporarily set the active node to get the position before this move
          controller.gameRecorder.activeNode = previousNode;

          // Rebuild the position to this point
          await _rebuildPositionToNode(controller, previousNode);

          // Get position analysis before this move
          final PositionAnalysisResult analysisResult =
              await controller.engine.analyzePosition();

          if (analysisResult.isValid &&
              analysisResult.possibleMoves.isNotEmpty) {
            // Analyze this move
            _analyzeSingleMove(node, analysisResult);
          }
        }

        // Update progress
        onProgress(i);
      }

      // Restore original game state completely
      controller.gameInstance.gameMode = originalGameMode;
      controller.gameRecorder.activeNode = originalActiveNode;

      // Rebuild to the original position
      if (originalActiveNode != null) {
        await _rebuildPositionToNode(controller, originalActiveNode);
        logger.i("Analysis completed, restored to original position");
      } else {
        logger.w("Original active node was null, cannot restore position");
      }
    } catch (e) {
      logger.e("Error during game analysis: $e");
      // Ensure we restore the original state even if an error occurs
      controller.gameInstance.gameMode = originalGameMode;
      controller.gameRecorder.activeNode = originalActiveNode;
      if (originalActiveNode != null) {
        await _rebuildPositionToNode(controller, originalActiveNode);
        logger.i(
            "Analysis error recovery completed, restored to original position");
      }
    }
  }

  /// Rebuild the game position to the specified node without affecting UI navigation
  static Future<void> _rebuildPositionToNode(
    GameController controller,
    pgn.PgnNode<ExtMove> targetNode,
  ) async {
    // Collect all moves from root to target node
    final List<ExtMove> pathMoves = <ExtMove>[];
    pgn.PgnNode<ExtMove>? current = targetNode;

    while (current != null && current.parent != null) {
      if (current.data != null) {
        pathMoves.insert(0, current.data!);
      }
      current = current.parent;
    }

    logger.d("Rebuilding position with ${pathMoves.length} moves");

    // Reset position to initial state
    controller.reset();
    posKeyHistory.clear();

    // Replay all moves to reach the target position
    int moveCount = 0;
    for (final ExtMove move in pathMoves) {
      if (!controller.gameInstance.doMove(move)) {
        logger.e("Failed to replay move ${moveCount + 1}: ${move.notation}");
        break;
      }
      moveCount++;
    }

    logger.d("Successfully replayed $moveCount moves to target position");
  }

  /// Analyze a single move and set its quality
  static void _analyzeSingleMove(
      pgn.PgnNode<ExtMove> moveNode, PositionAnalysisResult analysisResult) {
    final ExtMove? move = moveNode.data;
    if (move == null) {
      return;
    }

    // Find the actual move in the analysis results
    MoveAnalysisResult? actualMoveResult;
    for (final MoveAnalysisResult result in analysisResult.possibleMoves) {
      if (_isSameMove(move, result)) {
        actualMoveResult = result;
        break;
      }
    }

    if (actualMoveResult == null) {
      return;
    }

    // Check for bad moves and good moves
    final MoveQuality quality =
        _evaluateMoveQuality(actualMoveResult, analysisResult.possibleMoves);

    // Store the quality in the move data
    move.quality = quality;

    // Also ensure quality is reflected in NAGs for export consistency
    final int? qualityNag = ExtMove.moveQualityToNag(quality);
    if (qualityNag != null) {
      move.nags ??= <int>[];
      // Only add if not already present and no conflicting quality NAGs exist
      final bool hasQualityNags =
          move.nags!.any((int nag) => nag >= 1 && nag <= 4);
      if (!hasQualityNags && !move.nags!.contains(qualityNag)) {
        move.nags!.add(qualityNag);
      }
    }
  }

  /// Check if ExtMove and MoveAnalysisResult represent the same move
  static bool _isSameMove(ExtMove extMove, MoveAnalysisResult analysisResult) {
    // Convert ExtMove to standard notation for comparison
    final String extMoveStr = _extMoveToStandardNotation(extMove);
    return extMoveStr == analysisResult.move;
  }

  /// Convert ExtMove to standard notation string
  static String _extMoveToStandardNotation(ExtMove move) {
    if (move.type == MoveType.place) {
      // Place move: convert square index to notation like "a1"
      return squareToNotation(move.to);
    } else if (move.type == MoveType.move) {
      // Move: convert to "a1-a4" format
      return '${squareToNotation(move.from)}-${squareToNotation(move.to)}';
    } else if (move.type == MoveType.remove) {
      // Remove: convert to "xa1" format
      return 'x${squareToNotation(move.to)}';
    }
    return '';
  }

  /// Evaluate move quality based on perfect database results
  static MoveQuality _evaluateMoveQuality(
    MoveAnalysisResult actualMove,
    List<MoveAnalysisResult> allPossibleMoves,
  ) {
    // Find best outcomes
    bool hasWinningMove = false;
    bool hasDrawingMove = false;
    int? bestWinStepCount;

    for (final MoveAnalysisResult move in allPossibleMoves) {
      if (move.outcome.name == 'win') {
        hasWinningMove = true;
        if (move.outcome.stepCount != null) {
          if (bestWinStepCount == null ||
              move.outcome.stepCount! < bestWinStepCount) {
            bestWinStepCount = move.outcome.stepCount;
          }
        }
      } else if (move.outcome.name == 'draw') {
        hasDrawingMove = true;
      }
    }

    // Evaluate the actual move
    final String actualOutcome = actualMove.outcome.name;
    final int? actualStepCount = actualMove.outcome.stepCount;

    // Check for bad moves
    if (hasWinningMove && actualOutcome != 'win') {
      if (actualOutcome == 'draw') {
        return MoveQuality.minorBadMove; // Could win but chose draw
      } else if (actualOutcome == 'loss') {
        return MoveQuality.majorBadMove; // Could win but chose loss
      }
    }

    if (!hasWinningMove && hasDrawingMove && actualOutcome == 'loss') {
      return MoveQuality.majorBadMove; // Could draw but chose loss
    }

    // Check for good moves
    if (actualOutcome == 'win' &&
        bestWinStepCount != null &&
        actualStepCount != null) {
      if (actualStepCount == bestWinStepCount) {
        // This is the fastest winning move
        if (actualStepCount > 30) {
          return MoveQuality.majorGoodMove; // Long but optimal win (>30 steps)
        } else {
          return MoveQuality.minorGoodMove; // Quick optimal win (<=30 steps)
        }
      }
    }

    return MoveQuality.normal; // Neither particularly good nor bad
  }
}
