// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// notation_parsing.dart

part of '../mill.dart';

const String _logTag = "[NotationParsing]";

// TODO: Remove this function
String _wmdNotationToMoveString(String wmd) {
  // Validate standard notation format
  if (wmd.startsWith('x') && wmd.length == 3) {
    // Remove move format: "xa1", "xd5", etc.
    return wmd;
  }

  if (wmd.length == 5 && wmd[2] == '-') {
    // Move format: "a1-a4", "d5-e5", etc.
    return wmd;
  }

  if (wmd.length == 2 && RegExp(r'^[a-g][1-7]$').hasMatch(wmd)) {
    // Place move format: "a1", "d5", etc.
    return wmd;
  }

  // Unsupported format
  logger.w("$_logTag Unsupported move format: $wmd");
  throw ImportFormatException(wmd);
}

// Convert PlayOK notation to standard notation
String _playOkNotationToMoveString(String playOk) {
  if (playOk.isEmpty) {
    throw ImportFormatException(playOk);
  }

  final int iDash = playOk.indexOf("-");
  final int iX = playOk.indexOf("x");

  if (iDash == -1 && iX == -1) {
    // Simple place move: "12" -> "c4"
    final int val = int.parse(playOk);
    if (val >= 1 && val <= 24) {
      final String? standardNotation = playOkNotationToStandardNotation[playOk];
      if (standardNotation != null) {
        return standardNotation;
      } else {
        throw ImportFormatException(playOk);
      }
    } else {
      throw ImportFormatException(playOk);
    }
  }

  if (iX == 0) {
    // Remove move: "x12" -> "xc4"
    final String sub = playOk.substring(1);
    final int val = int.parse(sub);
    if (val >= 1 && val <= 24) {
      final String? standardNotation = playOkNotationToStandardNotation[sub];
      if (standardNotation != null) {
        return "x$standardNotation";
      } else {
        throw ImportFormatException(playOk);
      }
    } else {
      throw ImportFormatException(playOk);
    }
  }

  if (iDash != -1 && iX == -1) {
    // Move: "12-13" -> "c4-e4"
    final String sub1 = playOk.substring(0, iDash);
    final int val1 = int.parse(sub1);
    if (val1 < 1 || val1 > 24) {
      throw ImportFormatException(playOk);
    }

    final String sub2 = playOk.substring(iDash + 1);
    final int val2 = int.parse(sub2);
    if (val2 < 1 || val2 > 24) {
      throw ImportFormatException(playOk);
    }

    final String? fromSquare = playOkNotationToStandardNotation[sub1];
    final String? toSquare = playOkNotationToStandardNotation[sub2];

    if (fromSquare != null && toSquare != null) {
      return "$fromSquare-$toSquare";
    } else {
      throw ImportFormatException(playOk);
    }
  }

  logger.w("$_logTag Not support parsing format oo-ooxo PlayOK notation.");
  throw ImportFormatException(playOk);
}
