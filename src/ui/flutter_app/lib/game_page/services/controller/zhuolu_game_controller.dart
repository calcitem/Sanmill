// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// zhuolu_game_controller.dart

part of '../mill.dart';

// Import widgets that are not part of the mill library
// Note: These imports would normally be in mill.dart, but for organization
// we're referencing them here. In a production app, these should be properly
// imported in the mill.dart file.

/// Controller for managing Zhuolu Chess specific game flow
/// Start the special piece selection process for Zhuolu Chess
Future<void> startSpecialPieceSelection(BuildContext context) async {
  if (!DB().ruleSettings.zhuoluMode) {
    return; // Not a Zhuolu Chess game
  }

  // Show information dialog about Zhuolu Chess special pieces
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(S.of(context).zhuolu),
      content: Text("${S.of(context).welcome} ${S.of(context).zhuolu}!"),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).ok),
        ),
      ],
    ),
  );

  if (!context.mounted) {
    return;
  }

  // Show selection dialog for White player first
  final List<SpecialPiece>? whiteSelection =
      await showSpecialPieceSelectionDialog(
    context,
    PieceColor.white,
  );

  if (whiteSelection == null || whiteSelection.length != 6) {
    // If cancelled, use random selection for white and AI selection strategy for black
    final List<SpecialPiece> randomSelection =
        SpecialPieceSelection.generateRandomSelection();
    GameController().position.setSpecialPieceSelections(
          whiteSelection: randomSelection,
          blackSelection: getAiSpecialPieceSelection(PieceColor.black),
        );

    if (context.mounted) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Selection cancelled - using random special pieces'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return;
  }

  if (!context.mounted) {
    return;
  }

  // Show selection dialog for Black player
  final List<SpecialPiece>? blackSelection =
      await showSpecialPieceSelectionDialog(
    context,
    PieceColor.black,
  );

  if (blackSelection == null || blackSelection.length != 6) {
    // If cancelled, use AI selection strategy for black
    GameController().position.setSpecialPieceSelections(
          whiteSelection: whiteSelection,
          blackSelection: getAiSpecialPieceSelection(PieceColor.black),
        );

    if (context.mounted) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content:
              Text('Black player selection cancelled - using random pieces'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  } else {
    // Set both selections
    GameController().position.setSpecialPieceSelections(
          whiteSelection: whiteSelection,
          blackSelection: blackSelection,
        );
  }

  // Reveal selections immediately
  GameController().position.revealSpecialPieceSelections();

  // Show reveal dialog
  if (GameController().position.specialPieceSelection != null &&
      context.mounted) {
    showSpecialPieceRevealDialog(
      context,
      GameController().position.specialPieceSelection!,
    );
  }

  // Show confirmation message
  if (context.mounted) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('${S.of(context).zhuolu} game ready to start!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Get the current special piece to be placed for a player
SpecialPiece? getCurrentSpecialPiece(PieceColor player) {
  final List<SpecialPiece> available =
      GameController().position.getAvailableSpecialPieces(player);
  return available.isNotEmpty ? available.first : null;
}

/// Get the display name for a special piece on the board
String getSpecialPieceDisplayName(SpecialPiece piece) {
  return piece.chineseName; // Show Chinese name on the board
}

/// Check if the game should start special piece selection
bool shouldStartSpecialPieceSelection() {
  return DB().ruleSettings.zhuoluMode &&
      !GameController().position.hasCompleteSpecialPieceSelections;
}

/// Get AI special piece selection based on Move Randomly setting
List<SpecialPiece> getAiSpecialPieceSelection(PieceColor aiColor) {
  final bool moveRandomly = DB().generalSettings.shufflingEnabled;

  if (!moveRandomly) {
    // If Move Randomly is false, try to use last selection
    final List<SpecialPiece>? lastSelection = _getLastSelection(aiColor);
    if (lastSelection != null && lastSelection.length == 6) {
      return lastSelection;
    }
  }

  // If Move Randomly is true, or no valid last selection exists, generate random
  return SpecialPieceSelection.generateRandomSelection();
}

/// Get the last selection for a player from database
List<SpecialPiece>? _getLastSelection(PieceColor playerColor) {
  final RuleSettings ruleSettings = DB().ruleSettings;
  final int lastSelectionMask = playerColor == PieceColor.white
      ? ruleSettings.lastWhiteSpecialPieceSelection
      : ruleSettings.lastBlackSpecialPieceSelection;

  if (lastSelectionMask == 0) {
    return null;
  }

  final List<SpecialPiece> selection = <SpecialPiece>[];

  // Decode the bitmask to get the selected pieces
  // Each piece index is stored in 4 bits, up to 6 pieces
  for (int i = 0; i < 6; i++) {
    final int pieceIndex = (lastSelectionMask >> (i * 4)) & 0xF;
    if (pieceIndex < SpecialPiece.values.length) {
      selection.add(SpecialPiece.values[pieceIndex]);
    }
  }

  return selection.length == 6 ? selection : null;
}
