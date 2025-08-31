// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// available_pieces_selector.dart

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../services/mill.dart';

/// Widget to display and select from available pieces (6 special + 6 normal) for Zhuolu Chess
class AvailablePiecesSelector extends StatefulWidget {
  const AvailablePiecesSelector({
    super.key,
    required this.player,
    required this.onPieceSelected,
  });

  final PieceColor player;
  final Function(SpecialPiece?) onPieceSelected;

  @override
  State<AvailablePiecesSelector> createState() =>
      _AvailablePiecesSelectorState();
}

class _AvailablePiecesSelectorState extends State<AvailablePiecesSelector> {
  SpecialPiece? _selectedSpecialPiece;
  bool _selectedNormalPiece = false;
  SpecialPiece? _hoveredPiece; // For showing description

  @override
  Widget build(BuildContext context) {
    if (!DB().ruleSettings.zhuoluMode) {
      return const SizedBox.shrink();
    }

    final List<SpecialPiece> availableSpecialPieces =
        GameController().position.getAvailableSpecialPieces(widget.player);
    const int availableNormalPieces =
        6; // Always 6 normal pieces in Zhuolu Chess

    final String playerName = widget.player == PieceColor.white ? '白方' : '黑方';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$playerName 可用棋子',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // Special pieces section
            if (availableSpecialPieces.isNotEmpty) ...<Widget>[
              Text(
                '特殊棋子 (${availableSpecialPieces.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableSpecialPieces.map((SpecialPiece piece) {
                  final bool isSelected = _selectedSpecialPiece == piece;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSpecialPiece = isSelected ? null : piece;
                        _selectedNormalPiece = false;
                        _hoveredPiece = isSelected ? null : piece;
                      });
                      widget.onPieceSelected(isSelected ? null : piece);
                    },
                    child: Container(
                      width: 70,
                      height: 70,
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
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          _getDisplayText(piece),
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Normal pieces section
            Text(
              '普通棋子 ($availableNormalPieces)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedNormalPiece = !_selectedNormalPiece;
                  _selectedSpecialPiece = null;
                  _hoveredPiece = null; // Clear special piece description
                });
                // Pass null for normal piece selection
                widget.onPieceSelected(null);
              },
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selectedNormalPiece
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: _selectedNormalPiece
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.outline,
                    width: 3,
                  ),
                  boxShadow: _selectedNormalPiece
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '普',
                    style: TextStyle(
                      color: _selectedNormalPiece
                          ? Theme.of(context).colorScheme.onSecondary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Piece description area
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_hoveredPiece != null) ...<Widget>[
                    Text(
                      '${_getDisplayText(_hoveredPiece!)} (${_hoveredPiece!.englishName})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hoveredPiece!.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else if (_selectedNormalPiece) ...<Widget>[
                    Text(
                      '普通棋子',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text('普通棋子没有特殊能力，但可以正常成三提子'),
                  ] else ...<Widget>[
                    Text(
                      '选择要放置的棋子类型',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
