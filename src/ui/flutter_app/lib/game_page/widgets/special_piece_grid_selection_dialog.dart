// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_piece_grid_selection_dialog.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/mill.dart';

/// Dialog for players to select their special pieces for Zhuolu Chess with 4x4 grid layout
class SpecialPieceGridSelectionDialog extends StatefulWidget {
  const SpecialPieceGridSelectionDialog({
    super.key,
    required this.playerColor,
    required this.onSelectionComplete,
  });

  final PieceColor playerColor;
  final Function(List<SpecialPiece>) onSelectionComplete;

  @override
  State<SpecialPieceGridSelectionDialog> createState() =>
      _SpecialPieceGridSelectionDialogState();
}

class _SpecialPieceGridSelectionDialogState
    extends State<SpecialPieceGridSelectionDialog> {
  final Set<SpecialPiece> _selectedPieces = <SpecialPiece>{};
  static const int _requiredSelections = 6;
  SpecialPiece?
      _hoveredPiece; // Currently hovered/focused piece for description

  @override
  Widget build(BuildContext context) {
    final String playerName =
        widget.playerColor == PieceColor.white ? '白方' : '黑方';

    return AlertDialog(
      title: Text('$playerName - 选择6个特殊棋子'),
      content: SizedBox(
        width: double.maxFinite,
        height: 600,
        child: Column(
          children: <Widget>[
            Text(
              '已选择: ${_selectedPieces.length}/$_requiredSelections',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 3, // Give more space to grid
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: SpecialPiece.values.length,
                itemBuilder: (BuildContext context, int index) {
                  final SpecialPiece piece = SpecialPiece.values[index];
                  final bool isSelected = _selectedPieces.contains(piece);
                  final bool canSelect =
                      _selectedPieces.length < _requiredSelections;

                  return Card(
                    elevation: isSelected ? 8 : 2,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: InkWell(
                      onTap: (isSelected || canSelect)
                          ? () {
                              setState(() {
                                if (isSelected) {
                                  _selectedPieces.remove(piece);
                                } else if (canSelect) {
                                  _selectedPieces.add(piece);
                                }
                                _hoveredPiece =
                                    piece; // Set hovered piece for description
                              });
                            }
                          : null,
                      onHover: (bool isHovering) {
                        if (isHovering) {
                          setState(() {
                            _hoveredPiece = piece;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(
                            4.0), // Reduced padding for more space
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            // Large Chinese name in circle - increased size for better text display
                            Expanded(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outline,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    piece.localizedName(context),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                      fontSize:
                                          24, // Increased font size for better readability
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Description area for hovered/selected piece
            Container(
              height: 80, // Fixed height for description area
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3),
                ),
              ),
              child: _buildDescriptionArea(context),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            // Auto-select random pieces to fill remaining slots
            final List<SpecialPiece> remaining = SpecialPiece.values
                .where((SpecialPiece p) => !_selectedPieces.contains(p))
                .toList()
              ..shuffle();

            while (_selectedPieces.length < _requiredSelections &&
                remaining.isNotEmpty) {
              _selectedPieces.add(remaining.removeAt(0));
            }

            setState(() {});
          },
          child: const Text('随机填充'),
        ),
        TextButton(
          onPressed: _selectedPieces.length == _requiredSelections
              ? () {
                  widget.onSelectionComplete(_selectedPieces.toList());
                  Navigator.of(context).pop();
                }
              : null,
          child: Text(S.of(context).ok),
        ),
      ],
    );
  }

  /// Build the description area showing details of the hovered/focused piece
  Widget _buildDescriptionArea(BuildContext context) {
    if (_hoveredPiece == null) {
      return Center(
        child: Text(
          '点击或悬停在棋子上查看详细说明',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final SpecialPiece piece = _hoveredPiece!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              piece.localizedName(context),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${piece.englishName})',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              piece.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// Show special piece selection dialog and return selected pieces (4x4 grid)
Future<List<SpecialPiece>?> showSpecialPieceGridSelectionDialog(
  BuildContext context,
  PieceColor playerColor,
) async {
  List<SpecialPiece>? selectedPieces;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => SpecialPieceGridSelectionDialog(
      playerColor: playerColor,
      onSelectionComplete: (List<SpecialPiece> pieces) {
        selectedPieces = pieces;
      },
    ),
  );

  return selectedPieces;
}
