// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// notation_parsing.dart

part of '../mill.dart';

const String _logTag = "[NotationParsing]";

String _wmdNotationToMoveString(String wmd) {
  // Handle capture moves starting with 'x' e.g., 'xd1'
  if (wmd.startsWith('x') && wmd.length == 3) {
    final String target = wmd.substring(1, 3);
    final String? mapped = wmdNotationToMove[target];
    if (mapped != null) {
      return "-$mapped";
    }
    logger.w("$_logTag Unknown capture target: $wmd");
    throw ImportFormatException(wmd);
  }

  // Handle from-to moves e.g., 'a1-a4'
  if (wmd.length == 5 && wmd[2] == '-') {
    final String from = wmd.substring(0, 2);
    final String to = wmd.substring(3, 5);
    final String? mappedFrom = wmdNotationToMove[from];
    final String? mappedTo = wmdNotationToMove[to];
    if (mappedFrom != null && mappedTo != null) {
      return "$mappedFrom->$mappedTo";
    }
    logger.w("$_logTag Unknown move from or to: $wmd");
    throw ImportFormatException(wmd);
  }

  // Handle simple moves without captures e.g., 'a1'
  if (wmd.length == 2) {
    final String? mapped = wmdNotationToMove[wmd];
    if (mapped != null) {
      return mapped;
    }
    logger.w("$_logTag Unknown move: $wmd");
    throw ImportFormatException(wmd);
  }

  // Handle unsupported formats
  if ((wmd.length == 8 && wmd[2] == '-' && wmd[5] == 'x') ||
      (wmd.length == 5 && wmd[2] == 'x')) {
    logger.w("$_logTag Not support parsing format oo-ooxo notation: $wmd");
    throw ImportFormatException(wmd);
  }

  // If none of the above conditions are met, throw an exception
  logger.w("$_logTag Not support parsing format: $wmd");
  throw ImportFormatException(wmd);
}

String _playOkNotationToMoveString(String playOk) {
  if (playOk.isEmpty) {
    throw ImportFormatException(playOk);
  }

  final int iDash = playOk.indexOf("-");
  final int iX = playOk.indexOf("x");

  if (iDash == -1 && iX == -1) {
    // 12
    final int val = int.parse(playOk);
    if (val >= 1 && val <= 24) {
      return playOkNotationToMove[playOk]!;
    } else {
      throw ImportFormatException(playOk);
    }
  }

  if (iX == 0) {
    // x12
    final String sub = playOk.substring(1);
    final int val = int.parse(sub);
    if (val >= 1 && val <= 24) {
      return "-${playOkNotationToMove[sub]!}";
    } else {
      throw ImportFormatException(playOk);
    }
  }
  if (iDash != -1 && iX == -1) {
    String? move;
    // 12-13
    final String sub1 = playOk.substring(0, iDash);
    final int val1 = int.parse(sub1);
    if (val1 >= 1 && val1 <= 24) {
      move = playOkNotationToMove[sub1];
    } else {
      throw ImportFormatException(playOk);
    }

    final String sub2 = playOk.substring(iDash + 1);
    final int val2 = int.parse(sub2);
    if (val2 >= 1 && val2 <= 24) {
      return "$move->${playOkNotationToMove[sub2]!}";
    } else {
      throw ImportFormatException(playOk);
    }
  }

  logger.w("$_logTag Not support parsing format oo-ooxo PlayOK notation.");
  throw ImportFormatException(playOk);
}
