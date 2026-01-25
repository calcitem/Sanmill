// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// export_service.dart

part of '../mill.dart';

class ExportService {
  const ExportService._();

  /// Exports the game to the device's clipboard.
  /// If the game contains variations, asks the user whether to include them.
  static Future<void> exportGame(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    final GameRecorder recorder = GameController().gameRecorder;
    String exportText = recorder.moveHistoryText;
    bool includedVariations = false;

    // Check if the game has variations
    if (recorder.hasVariations()) {
      // Ask user whether to include variations
      final bool includeVariations =
          await _showVariationsDialog(context) ?? false;

      if (!includeVariations) {
        // User chose mainline only
        exportText = recorder.moveHistoryTextWithoutVariations;
      } else {
        includedVariations = true;
      }
    }

    await Clipboard.setData(ClipboardData(text: exportText));

    if (!context.mounted) {
      return;
    }

    // Show success message with experimental warning if variations included
    final String message = includedVariations
        ? '${S.of(context).moveHistoryCopied} ${S.of(context).experimental}'
        : S.of(context).moveHistoryCopied;
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(message);

    if (shouldPop) {
      Navigator.pop(context);
    }
  }

  /// Shows a dialog asking the user whether to include variations.
  /// Returns true if user wants to include variations, false if mainline only.
  static Future<bool?> _showVariationsDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).variationsDetected),
          content: Text(
            '${S.of(context).moveListContainsVariations}\n\n'
            '${S.of(context).includeVariations}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.of(context).includeVariationsNo),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(S.of(context).includeVariationsYes),
            ),
          ],
        );
      },
    );
  }

  /// Export game with move quality symbols included
  static Future<void> exportGameWithQuality(
    BuildContext context, {
    bool shouldPop = true,
  }) async {
    final String exportText = _generatePgnWithQuality();

    await Clipboard.setData(ClipboardData(text: exportText));

    if (!context.mounted) {
      return;
    }

    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      S.of(context).moveHistoryCopied,
    );

    if (shouldPop) {
      Navigator.pop(context);
    }
  }

  /// Generate PGN text with move quality symbols
  static String _generatePgnWithQuality() {
    final GameRecorder recorder = GameController().gameRecorder;
    final List<PgnNode<ExtMove>> nodes = recorder.mainlineNodes;

    if (nodes.isEmpty) {
      return recorder.moveHistoryText;
    }

    final StringBuffer sb = StringBuffer();

    // Add headers if there are any
    if (recorder.setupPosition != null) {
      sb.writeln('[FEN "${recorder.setupPosition}"]');
      sb.writeln('[SetUp "1"]');
      sb.writeln();
    }

    int moveNumber = 1;
    int i = 0;

    // Process moves with quality symbols
    while (i < nodes.length) {
      sb.write("$moveNumber. ");

      // Process first move (usually White)
      final PgnNode<ExtMove> firstNode = nodes[i];
      sb.write(_formatMoveWithQuality(firstNode.data!));
      i++;

      // Handle subsequent remove moves
      while (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
        sb.write(' ');
        sb.write(_formatMoveWithQuality(nodes[i].data!));
        i++;
      }

      // Process second move (usually Black) if exists
      if (i < nodes.length) {
        sb.write(' ');
        sb.write(_formatMoveWithQuality(nodes[i].data!));
        i++;

        // Handle subsequent remove moves
        while (i < nodes.length && nodes[i].data!.type == MoveType.remove) {
          sb.write(' ');
          sb.write(_formatMoveWithQuality(nodes[i].data!));
          i++;
        }
      }

      sb.writeln();
      moveNumber++;
    }

    return sb.toString().trim();
  }

  /// Format a single move with quality symbols
  static String _formatMoveWithQuality(ExtMove move) {
    final StringBuffer sb = StringBuffer();

    // Add the basic move notation
    sb.write(move.notation);

    // Add quality symbols from NAGs and MoveQuality
    final List<int> allNags = move.getAllNags();
    if (allNags.isNotEmpty) {
      final List<String> qualitySymbols = <String>[];

      for (final int nag in allNags) {
        switch (nag) {
          case 1:
            qualitySymbols.add('!');
            break;
          case 2:
            qualitySymbols.add('?');
            break;
          case 3:
            qualitySymbols.add('!!');
            break;
          case 4:
            qualitySymbols.add('??');
            break;
          case 5:
            qualitySymbols.add('!?');
            break;
          case 6:
            qualitySymbols.add('?!');
            break;
          default:
            // For other NAGs, use standard notation
            qualitySymbols.add('\$$nag');
            break;
        }
      }

      if (qualitySymbols.isNotEmpty) {
        sb.write(qualitySymbols.join());
      }
    }

    // Add comments if present
    if (move.comments != null && move.comments!.isNotEmpty) {
      sb.write(' {${move.comments!.join(' ')}}');
    }

    return sb.toString();
  }
}
