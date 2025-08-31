// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_piece_reveal_dialog.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/mill.dart';

/// Dialog to reveal special piece selections for Zhuolu Chess
class SpecialPieceRevealDialog extends StatelessWidget {
  const SpecialPieceRevealDialog({
    super.key,
    required this.specialPieceSelection,
  });

  final SpecialPieceSelection specialPieceSelection;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.of(context).zhuolu),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'White Player Special Pieces:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...specialPieceSelection.whiteSelection.map(
              (SpecialPiece piece) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Text(
                      piece.localizedName(context),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text('(${piece.englishName})'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Black Player Special Pieces:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...specialPieceSelection.blackSelection.map(
              (SpecialPiece piece) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Text(
                      piece.localizedName(context),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text('(${piece.englishName})'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).ok),
        ),
      ],
    );
  }
}

/// Show special piece reveal dialog
Future<void> showSpecialPieceRevealDialog(
  BuildContext context,
  SpecialPieceSelection selection,
) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => SpecialPieceRevealDialog(
      specialPieceSelection: selection,
    ),
  );
}
