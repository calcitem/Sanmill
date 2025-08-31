// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_piece_info_widget.dart

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/mill.dart';

/// Widget to display current special piece information for Zhuolu Chess
class SpecialPieceInfoWidget extends StatelessWidget {
  const SpecialPieceInfoWidget({
    super.key,
    required this.player,
  });

  final PieceColor player;

  @override
  Widget build(BuildContext context) {
    if (!DB().ruleSettings.zhuoluMode) {
      return const SizedBox.shrink();
    }

    final SpecialPiece? currentPiece = getCurrentSpecialPiece(player);
    final List<SpecialPiece> availablePieces =
        GameController().position.getAvailableSpecialPieces(player);

    if (currentPiece == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'No special pieces remaining',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Next: ',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  currentPiece.localizedName(context),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${currentPiece.englishName})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              currentPiece.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Remaining: ${availablePieces.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget to show all selected special pieces for a player
class SpecialPieceRosterWidget extends StatelessWidget {
  const SpecialPieceRosterWidget({
    super.key,
    required this.player,
  });

  final PieceColor player;

  @override
  Widget build(BuildContext context) {
    if (!DB().ruleSettings.zhuoluMode) {
      return const SizedBox.shrink();
    }

    final SpecialPieceSelection? selection =
        GameController().position.specialPieceSelection;
    if (selection == null || !selection.isRevealed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Special pieces not yet revealed',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final List<SpecialPiece> playerPieces = player == PieceColor.white
        ? selection.whiteSelection
        : selection.blackSelection;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${player == PieceColor.white ? "White" : "Black"} Special Pieces:',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: playerPieces.map((SpecialPiece piece) {
                final bool isUsed = !GameController()
                    .position
                    .getAvailableSpecialPieces(player)
                    .contains(piece);

                return Chip(
                  label: Text(
                    piece.localizedName(context),
                    style: TextStyle(
                      fontSize: 12,
                      color: isUsed
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  backgroundColor: isUsed
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.primaryContainer,
                  side: isUsed
                      ? BorderSide(color: Theme.of(context).colorScheme.outline)
                      : null,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
