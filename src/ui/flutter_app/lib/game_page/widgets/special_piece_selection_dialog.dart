// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_piece_selection_dialog.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/database/database.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../services/mill.dart';

/// Dialog for players to select their special pieces for Zhuolu Chess
class SpecialPieceSelectionDialog extends StatefulWidget {
  const SpecialPieceSelectionDialog({
    super.key,
    required this.playerColor,
    required this.onSelectionComplete,
  });

  final PieceColor playerColor;
  final Function(List<SpecialPiece>) onSelectionComplete;

  @override
  State<SpecialPieceSelectionDialog> createState() =>
      _SpecialPieceSelectionDialogState();
}

class _SpecialPieceSelectionDialogState
    extends State<SpecialPieceSelectionDialog> {
  final Set<SpecialPiece> _selectedPieces = <SpecialPiece>{};
  static const int _requiredSelections = 6;

  @override
  Widget build(BuildContext context) {
    final String playerName = widget.playerColor == PieceColor.white
        ? 'White Player'
        : 'Black Player';

    return AlertDialog(
      title: Text('$playerName - Select 6 Special Pieces'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: <Widget>[
            Text(
              'Selected: ${_selectedPieces.length}/$_requiredSelections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: SpecialPiece.values.length,
                itemBuilder: (BuildContext context, int index) {
                  final SpecialPiece piece = SpecialPiece.values[index];
                  final bool isSelected = _selectedPieces.contains(piece);
                  final bool canSelect =
                      _selectedPieces.length < _requiredSelections;

                  return Card(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: ListTile(
                      enabled: isSelected || canSelect,
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        child: Text(
                          _getDisplayText(piece),
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: <Widget>[
                          Text(
                            _getDisplayText(piece),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            piece.englishName,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        piece.description,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedPieces.remove(piece);
                          } else if (canSelect) {
                            _selectedPieces.add(piece);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        // Same as Last Time button
        if (_hasLastSelection())
          TextButton(
            onPressed: () {
              _loadLastSelection();
            },
            child: const Text('Same as Last Time'),
          ),
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
          child: const Text('Auto Fill'),
        ),
        TextButton(
          onPressed: _selectedPieces.length == _requiredSelections
              ? () {
                  final List<SpecialPiece> selectedList =
                      _selectedPieces.toList();
                  _saveSelectionToDatabase(selectedList);
                  widget.onSelectionComplete(selectedList);
                  Navigator.of(context).pop();
                }
              : null,
          child: Text(S.of(context).ok),
        ),
      ],
    );
  }

  /// Check if there is a previous selection for this player
  bool _hasLastSelection() {
    final RuleSettings ruleSettings = DB().ruleSettings;
    final int lastSelection = widget.playerColor == PieceColor.white
        ? ruleSettings.lastWhiteSpecialPieceSelection
        : ruleSettings.lastBlackSpecialPieceSelection;
    return lastSelection != 0;
  }

  /// Load the last selection from database
  void _loadLastSelection() {
    final RuleSettings ruleSettings = DB().ruleSettings;
    final int lastSelectionMask = widget.playerColor == PieceColor.white
        ? ruleSettings.lastWhiteSpecialPieceSelection
        : ruleSettings.lastBlackSpecialPieceSelection;

    if (lastSelectionMask == 0) {
      return;
    }

    // Clear current selection
    _selectedPieces.clear();

    // Decode the bitmask to get the selected pieces
    // Each piece index is stored in 4 bits, up to 6 pieces
    for (int i = 0; i < 6; i++) {
      final int pieceIndex = (lastSelectionMask >> (i * 4)) & 0xF;
      if (pieceIndex < SpecialPiece.values.length) {
        _selectedPieces.add(SpecialPiece.values[pieceIndex]);
      }
    }

    setState(() {});
  }

  /// Save the current selection to database for future use
  void _saveSelectionToDatabase(List<SpecialPiece> selectedPieces) {
    // Encode the selection as a bitmask
    // Each piece index is stored in 4 bits, up to 6 pieces can be stored
    int selectionMask = 0;
    for (int i = 0; i < selectedPieces.length && i < 6; i++) {
      final int pieceIndex = selectedPieces[i].index;
      selectionMask |= pieceIndex << (i * 4);
    }

    // Save to database based on player color
    final RuleSettings currentSettings = DB().ruleSettings;
    final RuleSettings updatedSettings = widget.playerColor == PieceColor.white
        ? currentSettings.copyWith(
            lastWhiteSpecialPieceSelection: selectionMask)
        : currentSettings.copyWith(
            lastBlackSpecialPieceSelection: selectionMask);

    DB().ruleSettings = updatedSettings;
  }

  /// Get display text for special piece based on locale
  String _getDisplayText(SpecialPiece piece) {
    if (shouldUseChineseForCurrentSetting()) {
      return piece.localizedName(context);
    } else {
      return piece.emoji;
    }
  }
}

/// Show special piece selection dialog and return selected pieces
Future<List<SpecialPiece>?> showSpecialPieceSelectionDialog(
  BuildContext context,
  PieceColor playerColor,
) async {
  List<SpecialPiece>? selectedPieces;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => SpecialPieceSelectionDialog(
      playerColor: playerColor,
      onSelectionComplete: (List<SpecialPiece> pieces) {
        selectedPieces = pieces;
      },
    ),
  );

  return selectedPieces;
}
