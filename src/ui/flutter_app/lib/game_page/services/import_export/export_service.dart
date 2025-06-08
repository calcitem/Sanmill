// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// export_service.dart

part of '../mill.dart';

class ExportService {
  const ExportService._();

  /// Exports the game to the device's clipboard.
  static Future<void> exportGame(BuildContext context,
      {bool shouldPop = true}) async {
    await Clipboard.setData(
      ClipboardData(text: GameController().gameRecorder.moveHistoryText),
    );

    if (!context.mounted) {
      return;
    }

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).moveHistoryCopied);

    if (shouldPop) {
      Navigator.pop(context);
    }
  }

  /// Export game with move quality symbols included
  static Future<void> exportGameWithQuality(BuildContext context,
      {bool shouldPop = true}) async {
    final String exportText = _generatePgnWithQuality();

    await Clipboard.setData(ClipboardData(text: exportText));

    if (!context.mounted) {
      return;
    }

    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).moveHistoryCopied);

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
