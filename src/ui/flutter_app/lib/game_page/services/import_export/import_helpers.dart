// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_helpers.dart

import '../../../shared/utils/helpers/string_helpers/string_helper.dart';

bool isPureFen(String text) {
  if (text.length >=
          "********/********/******** w p p 9 0 9 0 0 0 0 0 0 0 0 0".length &&
      (text.contains("/") &&
          text[8] == "/" &&
          text[17] == "/" &&
          text[26] == " ")) {
    return true;
  }

  return false;
}

bool hasTagPairs(String text) {
  if (text.length >= 15 &&
      (text.contains("[Event") ||
          text.contains("[White") ||
          text.contains("[FEN"))) {
    return true;
  }

  return false;
}

bool isFenMoveList(String text) {
  if (text.length >= 15 && (text.contains("[FEN"))) {
    return true;
  }

  return false;
}

bool isPlayOkMoveList(String text) {
  // See https://www.playok.com/en/mill/#t/f

  // Check for PlayOK identifier
  if (text.contains('[Site "PlayOK"]')) {
    return true;
  }

  text = removeBracketedContent(text);
  final String noTag = removeTagPairs(text);

  // Must contain "1."
  if (!noTag.contains("1.")) {
    return false;
  }

  // Must not be empty and must not contain any letters a-g or A-G
  if (noTag.isEmpty || RegExp(r'[a-gA-G]').hasMatch(noTag)) {
    return false;
  }

  return true;
}

bool isGoldTokenMoveList(String text) {
  // Example: https://www.goldtoken.com/games/play?g=13097650;print=yes

  text = removeBracketedContent(text);

  return text.contains("GoldToken") ||
      text.contains("Place to") ||
      text.contains(", take ") ||
      text.contains(" -> ");
}

String getTagPairs(String pgn) {
  // Find the index of the first '['
  final int firstBracket = pgn.indexOf('[');

  // Find the index of the last ']'
  final int lastBracket = pgn.lastIndexOf(']');

  // Check if both brackets are found and properly ordered
  if (firstBracket != -1 && lastBracket != -1 && lastBracket > firstBracket) {
    // Extract and return the substring from the first '[' to the last ']'
    return pgn.substring(firstBracket, lastBracket + 1);
  }

  // Return an empty string or handle the error as needed
  return '';
}

String removeTagPairs(String pgn) {
  // Check if the PGN starts with '[' indicating the presence of tag pairs
  if (!pgn.startsWith("[")) {
    return pgn;
  }

  // Find the position of the last ']'
  final int lastBracketPos = pgn.lastIndexOf("]");
  if (lastBracketPos == -1) {
    return pgn; // No closing ']', return as is
  }

  // Extract the substring after the last ']' and trim leading whitespace
  return pgn.substring(lastBracketPos + 1).trimLeft();
}
