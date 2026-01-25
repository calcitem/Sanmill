// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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

/// Expand shorthand capture-only alternatives in PGN variations.
///
/// Some move lists (often copied from analysis tools) abbreviate an alternative
/// remove target after a combined move by writing only the remove part in the
/// variation, for example:
///
/// - Mainline: `f4-g4xe4`
/// - Variation: `(xd1 ...)`  (meaning: `(f4-g4xd1 ...)`)
///
/// Sanmill encodes remove actions as standalone moves (e.g. `xd1`). When the
/// move list is parsed as PGN, a standalone `xd1` at the start of a variation
/// is treated as a full move and is usually illegal (because no removal is
/// pending). This helper expands the shorthand to a full combined token so the
/// importer can replay the variation correctly.
String expandShorthandCaptureVariations(String pgnText) {
  // Keep this tokenization in sync with `pgn.dart` so indices align.
  final RegExp tokenRegex = RegExp(
    r'(?:p|(?:[a-g][1-7](?:[-x][a-g][1-7])*)|(?:x[a-g][1-7](?:[-x][a-g][1-7])*))'
    r'|{|;|\$\d{1,4}|[?!]{1,2}|\(|\)|\*|1-0|0-1|1\/2-1\/2',
  );

  final Iterable<RegExpMatch> matches = tokenRegex.allMatches(pgnText);
  if (matches.isEmpty) {
    return pgnText;
  }

  bool isMoveToken(String token) {
    if (token == 'p') {
      return true;
    }
    if (token.startsWith('x')) {
      return true;
    }
    final int c = token.codeUnitAt(0);
    return c >= 97 && c <= 103; // 'a'..'g'
  }

  String? basePrefixFromMoveToken(String moveToken) {
    final int firstX = moveToken.indexOf('x');
    if (firstX > 0) {
      return moveToken.substring(0, firstX);
    }
    return null;
  }

  // Track the most recent move token in the current parentheses scope.
  String? lastMoveToken;
  // Restore lastMoveToken when leaving a variation.
  final List<String?> lastMoveTokenStack = <String?>[];
  // For each active '(' scope, store a pending base prefix that should only be
  // considered for the FIRST move token inside that scope.
  final List<String?> pendingPrefixStack = <String?>[];

  // Build a list of all tokens first so we can peek ahead.
  final List<RegExpMatch> matchList = matches.toList();
  final StringBuffer out = StringBuffer();
  int lastIndex = 0;

  for (int i = 0; i < matchList.length; i++) {
    final RegExpMatch match = matchList[i];
    final String token = match.group(0)!;

    // Preserve original spacing / text between tokens.
    out.write(pgnText.substring(lastIndex, match.start));

    if (token == '(') {
      // Enter a variation: save the current move-token context so we can restore
      // it on ')'. Determine the base prefix from the move token right before '('.
      lastMoveTokenStack.add(lastMoveToken);
      pendingPrefixStack.add(
        lastMoveToken == null ? null : basePrefixFromMoveToken(lastMoveToken),
      );
      out.write(token);
    } else if (token == ')') {
      // Exit a variation: restore the parent context.
      out.write(token);
      if (pendingPrefixStack.isNotEmpty) {
        pendingPrefixStack.removeLast();
      }
      if (lastMoveTokenStack.isNotEmpty) {
        lastMoveToken = lastMoveTokenStack.removeLast();
      }
    } else {
      // If we're at the start of the current variation scope, and the first move
      // token is capture-only (starts with 'x'), prefix it with the base segment
      // of the move that the variation is an alternative to.
      if (pendingPrefixStack.isNotEmpty) {
        final String? pendingBase = pendingPrefixStack.last;
        if (pendingBase != null && isMoveToken(token)) {
          if (token.startsWith('x')) {
            // Check if this variation contains nested variations (another '(' ahead).
            // If so, do NOT expand, because the splitSan logic in import_service
            // would split "f4-g4xd1" into two segments that each switch sides,
            // breaking nested variation structure.
            bool hasNestedVariation = false;
            for (int j = i + 1; j < matchList.length; j++) {
              final String futureToken = matchList[j].group(0)!;
              if (futureToken == '(') {
                hasNestedVariation = true;
                break;
              } else if (futureToken == ')') {
                // Reached end of current variation without finding nested '('
                break;
              }
            }

            if (!hasNestedVariation) {
              out.write(pendingBase);
            }
          }
          // Consume pending prefix once the first move token is seen (either used
          // or discarded if the variation starts with a normal move).
          pendingPrefixStack[pendingPrefixStack.length - 1] = null;
        }
      }

      out.write(token);

      if (isMoveToken(token)) {
        lastMoveToken = token;
      }
    }

    lastIndex = match.end;
  }

  // Append trailing text after the last token.
  out.write(pgnText.substring(lastIndex));
  return out.toString();
}
