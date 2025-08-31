// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// zhuolu_hand_pieces_display.dart

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../../shared/services/language_locale_mapping.dart';
import '../services/mill.dart';

/// Widget to display pieces in hand for Zhuolu Chess
/// Shows 6 special pieces and 6 normal pieces in a row
class ZhuoluHandPiecesDisplay extends StatefulWidget {
  const ZhuoluHandPiecesDisplay({
    super.key,
    required this.player,
    required this.isOpponent,
  });

  final PieceColor player;
  final bool isOpponent; // true for opponent (top), false for player (bottom)

  @override
  State<ZhuoluHandPiecesDisplay> createState() =>
      _ZhuoluHandPiecesDisplayState();
}

class _ZhuoluHandPiecesDisplayState extends State<ZhuoluHandPiecesDisplay> {
  // No local preview state needed anymore - info is shown in Info dialog

  @override
  Widget build(BuildContext context) {
    if (!DB().ruleSettings.zhuoluMode) {
      return const SizedBox.shrink();
    }

    // Get player's selected special pieces (all 6) and available ones (remaining)
    final List<SpecialPiece> availableSpecialPieces =
        GameController().position.getAvailableSpecialPieces(widget.player);

    // Get the player's original 6 selected special pieces
    final SpecialPieceSelection? selection =
        GameController().position.specialPieceSelection;
    final List<SpecialPiece> selectedSpecialPieces =
        widget.player == PieceColor.white
            ? (selection?.whiteSelection ?? <SpecialPiece>[])
            : (selection?.blackSelection ?? <SpecialPiece>[]);

    // For Zhuolu Chess: each player has 6 special pieces + 6 normal pieces = 12 total
    // Get total pieces remaining in hand
    final int totalPiecesInHand =
        GameController().position.pieceInHandCount[widget.player] ?? 0;

    // Calculate normal pieces in hand
    // Normal pieces = total in hand - available special pieces
    final int normalPiecesCount =
        totalPiecesInHand - availableSpecialPieces.length;

    // Calculate piece size based on screen width
    final double screenWidth = MediaQuery.of(context).size.width;
    final double pieceSize =
        (screenWidth - 32) / 7; // 7 pieces per row with margins
    const double maxPieceSize = 50.0; // Maximum size limit
    final double actualPieceSize =
        pieceSize > maxPieceSize ? maxPieceSize : pieceSize;

    // Determine if current display is interactive
    // Only the local player's row (isOpponent == false), during placing phase,
    // when it is this player's turn, and not AI side to move.
    final bool canInteract = !widget.isOpponent &&
        GameController().position.phase == Phase.placing &&
        GameController().position.sideToMove == widget.player &&
        !GameController().gameInstance.isAiSideToMove;

    // Current selected special piece for placement (null means normal piece)
    final SpecialPiece? selectedPiece =
        GameController().position.selectedPieceForPlacement;

    void selectPiece(SpecialPiece? piece) {
      // Update selected piece for placement and request UI refresh
      GameController().position.selectedPieceForPlacement = piece;
      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: <Widget>[
          // Row of 7 pieces (6 special + 1 normal)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              // Show all 6 selected special pieces, marking used ones
              ...List<Widget>.generate(6, (int index) {
                if (index < selectedSpecialPieces.length) {
                  final SpecialPiece piece = selectedSpecialPieces[index];
                  final bool isAvailable =
                      availableSpecialPieces.contains(piece);
                  final bool isSelected = canInteract &&
                      selectedPiece != null &&
                      selectedPiece == piece;

                  if (isAvailable) {
                    // Show available special piece
                    return _buildPieceCircle(
                      context,
                      actualPieceSize,
                      _getDisplayText(piece),
                      true, // is special piece
                      enabled: canInteract,
                      isSelected: isSelected,
                      onTap: canInteract ? () => selectPiece(piece) : null,
                    );
                  } else {
                    // Show used special piece (grayed out)
                    return _buildUsedPieceCircle(
                      context,
                      actualPieceSize,
                      _getDisplayText(piece),
                    );
                  }
                } else {
                  // Show empty slot if less than 6 pieces selected
                  return _buildEmptyPieceCircle(context, actualPieceSize);
                }
              }),

              // 1 normal piece slot showing count
              _buildPieceCircle(
                context,
                actualPieceSize,
                '普',
                false, // not special piece
                count: normalPiecesCount > 0 ? normalPiecesCount : 0,
                enabled: canInteract && normalPiecesCount > 0,
                isSelected: canInteract && selectedPiece == null,
                onTap: canInteract && normalPiecesCount > 0
                    ? () => selectPiece(null)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build a circle representing a piece in hand
  Widget _buildPieceCircle(
    BuildContext context,
    double size,
    String text,
    bool isSpecialPiece, {
    int? count,
    bool enabled = false,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    final Color baseFillColor = widget.player == PieceColor.white
        ? DB().colorSettings.whitePieceColor
        : DB().colorSettings.blackPieceColor;
    final Color baseTextColor = widget.player == PieceColor.white
        ? DB().colorSettings.blackPieceColor
        : DB().colorSettings.whitePieceColor;

    final Color fillColor =
        enabled ? baseFillColor : baseFillColor.withValues(alpha: 0.6);
    final Color textColor =
        enabled ? baseTextColor : baseTextColor.withAlpha(150);

    final Color borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : (widget.player == PieceColor.white
            ? DB().colorSettings.blackPieceColor
            : DB().colorSettings.whitePieceColor);
    final double borderWidth = isSelected ? 3.0 : 2.0;

    final List<BoxShadow> boxShadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
      if (isSelected)
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
          blurRadius: 8,
          spreadRadius: 1,
        ),
    ];

    final Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: boxShadows,
      ),
      child: Stack(
        children: <Widget>[
          // Main piece text
          Center(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: isSpecialPiece ? size * 0.3 : size * 0.4,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Count indicator for normal pieces
          if (count != null && count > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                  border: Border.all(color: Colors.white),
                ),
                child: Center(
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: content,
    );
  }

  /// Build an empty circle for unused special piece slots
  Widget _buildEmptyPieceCircle(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade300,
        border: Border.all(
          color: Colors.grey.shade500,
          width: 2.0,
        ),
      ),
      child: const Icon(
        Icons.close,
        color: Colors.grey,
      ),
    );
  }

  /// Build a circle for used special pieces (grayed out)
  Widget _buildUsedPieceCircle(BuildContext context, double size, String text) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade400,
        border: Border.all(
          color: Colors.grey.shade600,
          width: 2.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: size * 0.3,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
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
