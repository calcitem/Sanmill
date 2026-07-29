// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../../game_page/widgets/mini_board.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../models/puzzle_models.dart';
import '../services/puzzle_rule_engine.dart';

@immutable
class PuzzleSolutionMovePreview {
  const PuzzleSolutionMovePreview({
    required this.move,
    required this.boardLayout,
  });

  final PuzzleMove move;
  final String boardLayout;
}

/// Replays [solution] without touching the live puzzle session and captures
/// the board immediately after every atomic action.
List<PuzzleSolutionMovePreview> buildSolutionMovePreviews(
  PuzzleSolution solution, {
  required String initialPosition,
  required RuleSettings ruleSettings,
}) {
  final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(
    initialPosition,
    rules: ruleSettings,
  );
  if (engine == null) {
    throw StateError('Cannot load the puzzle position for solution previews.');
  }

  try {
    final List<PuzzleSolutionMovePreview> previews =
        <PuzzleSolutionMovePreview>[];
    for (final PuzzleMove move in solution.moves) {
      if (!engine.applyMove(move.notation)) {
        throw StateError(
          'Cannot replay puzzle solution action "${move.notation}".',
        );
      }

      final String? fen = engine.view.fen;
      if (fen == null) {
        throw StateError(
          'The puzzle engine did not export a position after '
          '"${move.notation}".',
        );
      }
      final String boardLayout = fen.split(' ').first;
      final List<String> rings = boardLayout.split('/');
      if (rings.length != 3 || rings.any((String ring) => ring.length != 8)) {
        throw StateError(
          'The puzzle engine exported an invalid board layout after '
          '"${move.notation}".',
        );
      }

      previews.add(
        PuzzleSolutionMovePreview(move: move, boardLayout: boardLayout),
      );
    }
    return previews;
  } finally {
    engine.dispose();
  }
}

/// Builds the solution list with a board preview beside every atomic action.
List<Widget> buildSolutionMoves(
  PuzzleSolution solution,
  BuildContext context, {
  required String initialPosition,
  required RuleSettings ruleSettings,
  required String keyPrefix,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme colorScheme = theme.colorScheme;
  final List<PuzzleSolutionMovePreview> previews = buildSolutionMovePreviews(
    solution,
    initialPosition: initialPosition,
    ruleSettings: ruleSettings,
  );

  return previews.asMap().entries.map((
    MapEntry<int, PuzzleSolutionMovePreview> entry,
  ) {
    final int moveIndex = entry.key;
    final PuzzleSolutionMovePreview preview = entry.value;
    final PuzzleMove move = preview.move;
    final ExtMove highlightedMove = ExtMove(
      move.notation,
      side: move.side,
      boardLayout: preview.boardLayout,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        key: Key('${keyPrefix}_move_$moveIndex'),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: 92,
              child: IgnorePointer(
                child: MiniBoard(
                  key: Key('${keyPrefix}_miniboard_$moveIndex'),
                  boardLayout: preview.boardLayout,
                  extMove: highlightedMove,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${moveIndex + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          move.notation,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    move.side == PieceColor.white ? '⚪' : '⚫',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (move.comment != null &&
                      move.comment!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      move.comment!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }).toList();
}

/// Widget to display solution moves
class PuzzleSolutionView extends StatelessWidget {
  const PuzzleSolutionView({
    required this.solution,
    required this.initialPosition,
    required this.ruleSettings,
    this.showMoveNumbers = true,
    super.key,
  });

  final PuzzleSolution solution;
  final String initialPosition;
  final RuleSettings ruleSettings;
  final bool showMoveNumbers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: buildSolutionMoves(
        solution,
        context,
        initialPosition: initialPosition,
        ruleSettings: ruleSettings,
        keyPrefix: 'puzzle_solution_view',
      ),
    );
  }
}
