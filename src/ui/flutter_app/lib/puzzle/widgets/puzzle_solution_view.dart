// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/services/mill.dart';
import '../models/puzzle_models.dart';

/// Helper method to build solution moves list
List<Widget> buildSolutionMoves(PuzzleSolution solution, BuildContext context) {
  return solution.moves.asMap().entries.map((MapEntry<int, PuzzleMove> entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${entry.key + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.value.notation,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          // Show side indicator (subtle)
          Text(
            entry.value.side == PieceColor.white ? '⚪' : '⚫',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }).toList();
}

/// Widget to display solution moves
class PuzzleSolutionView extends StatelessWidget {
  const PuzzleSolutionView({
    required this.solution,
    this.showMoveNumbers = true,
    super.key,
  });

  final PuzzleSolution solution;
  final bool showMoveNumbers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: buildSolutionMoves(solution, context),
    );
  }
}
