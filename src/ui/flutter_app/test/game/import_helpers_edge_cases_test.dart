// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_helpers_edge_cases_test.dart
//
// Extended edge-case tests for import helper functions.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/import_helpers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // isPureFen - comprehensive edge cases
  // ---------------------------------------------------------------------------
  group('isPureFen edge cases', () {
    test('valid FEN with all empty board', () {
      const String fen =
          '********/********/******** w p p 9 0 9 0 0 0 0 0 0 0 0 0 1';
      expect(isPureFen(fen), isTrue);
    });

    test('valid FEN with pieces on board', () {
      const String fen =
          'O@O*****/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';
      expect(isPureFen(fen), isTrue);
    });

    test('valid FEN with all pieces placed', () {
      const String fen =
          'O@O@O@O@/O@O@O@O@/O@O@O@O@ w m s 0 0 0 0 0 0 0 0 0 0 0 0 1';
      expect(isPureFen(fen), isTrue);
    });

    test('FEN too short should be rejected', () {
      expect(isPureFen('short'), isFalse);
      expect(isPureFen(''), isFalse);
    });

    test('FEN without slashes should be rejected', () {
      // 50+ chars but no slashes in correct positions
      const String noSlash =
          'XXXXXXXXXXXXXXXXXXXXXXXXXX w p p 9 0 9 0 0 0 0 0 0 0 0 0 1';
      expect(isPureFen(noSlash), isFalse);
    });

    test('FEN with slashes in wrong positions should be rejected', () {
      const String wrongSlash =
          '***/*****/**/**** w p p 9 0 9 0 0 0 0 0 0 0 0 0 1 extra';
      // Position 8 and 17 must be '/'
      expect(isPureFen(wrongSlash), isFalse);
    });

    test('FEN without space at position 26 should be rejected', () {
      const String noSpace =
          '********/********/********Xw p p 9 0 9 0 0 0 0 0 0 0 0 0';
      expect(isPureFen(noSpace), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // hasTagPairs - more patterns
  // ---------------------------------------------------------------------------
  group('hasTagPairs edge cases', () {
    test('should detect [Event tag', () {
      expect(hasTagPairs('[Event "Sanmill Game"]'), isTrue);
    });

    test('should detect [White tag', () {
      expect(hasTagPairs('[White "Player"]'), isTrue);
    });

    test('should detect [FEN tag', () {
      expect(hasTagPairs('[FEN "some fen string"]'), isTrue);
    });

    test('should reject text shorter than 15 chars', () {
      expect(hasTagPairs('[Event "X"]'), isFalse);
    });

    test('should reject text without known tags', () {
      expect(hasTagPairs('[Unknown "value"] some long text here'), isFalse);
    });

    test('should reject plain move text', () {
      expect(hasTagPairs('1. d6 f4 2. b4 a1 *'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // isFenMoveList
  // ---------------------------------------------------------------------------
  group('isFenMoveList edge cases', () {
    test('should detect FEN in tag', () {
      expect(isFenMoveList('[FEN "********/********/********"]'), isTrue);
    });

    test('should reject without FEN tag', () {
      expect(isFenMoveList('[Event "Test"] 1. d6 f4'), isFalse);
    });

    test('should reject short text', () {
      expect(isFenMoveList('[FEN]'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // getTagPairs / removeTagPairs
  // ---------------------------------------------------------------------------
  group('getTagPairs edge cases', () {
    test('should return empty for text without brackets', () {
      expect(getTagPairs('no brackets here'), '');
    });

    test('should handle single tag pair', () {
      const String pgn = '[Event "Test"]';
      expect(getTagPairs(pgn), '[Event "Test"]');
    });

    test('should handle multiple tag pairs', () {
      const String pgn = '[Event "Test"]\n[White "Alice"]\n[Black "Bob"]';
      final String tags = getTagPairs(pgn);
      expect(tags, contains('[Event "Test"]'));
      expect(tags, contains('[Black "Bob"]'));
    });

    test('should handle tag pairs followed by moves', () {
      const String pgn = '[Event "Test"]\n\n1. d6 f4 *';
      final String tags = getTagPairs(pgn);
      expect(tags, contains('[Event "Test"]'));
      expect(tags, isNot(contains('1. d6')));
    });
  });

  group('removeTagPairs edge cases', () {
    test('should return original when no tags present', () {
      const String noTags = '1. d6 f4 *';
      expect(removeTagPairs(noTags), noTags);
    });

    test('should handle empty string', () {
      expect(removeTagPairs(''), '');
    });

    test('should handle text starting with [ but no closing ]', () {
      const String broken = '[Event "Test" no closing bracket';
      // No closing ']' found, returns as-is
      expect(removeTagPairs(broken), broken);
    });

    test('should trim leading whitespace from move text', () {
      const String pgn = '[Event "Test"]\n\n  1. d6 f4 *';
      final String moves = removeTagPairs(pgn);
      expect(moves.startsWith('1.'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // isPlayOkMoveList - more edge cases
  // ---------------------------------------------------------------------------
  group('isPlayOkMoveList edge cases', () {
    test('PlayOK site tag should be detected', () {
      expect(isPlayOkMoveList('[Site "PlayOK"] 1. 12 13'), isTrue);
    });

    test('numeric-only moves should be detected as PlayOK', () {
      expect(isPlayOkMoveList('1. 12 13 2. 14 15'), isTrue);
    });

    test('moves with letters a-g should NOT be PlayOK', () {
      expect(isPlayOkMoveList('1. a1 d5 2. g7 b4'), isFalse);
    });

    test('empty string should not be PlayOK', () {
      expect(isPlayOkMoveList(''), isFalse);
    });

    test('text without move numbers should not be PlayOK', () {
      expect(isPlayOkMoveList('12 13 14 15'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // isGoldTokenMoveList
  // ---------------------------------------------------------------------------
  group('isGoldTokenMoveList edge cases', () {
    test('should detect "GoldToken" keyword', () {
      expect(isGoldTokenMoveList('GoldToken game record 12345'), isTrue);
    });

    test('should detect "Place to" keyword', () {
      expect(isGoldTokenMoveList('Place to d6, take f4'), isTrue);
    });

    test('should detect ", take " keyword', () {
      expect(isGoldTokenMoveList('move d6-f6, take a7'), isTrue);
    });

    test('should detect " -> " keyword', () {
      expect(isGoldTokenMoveList('1. d6 -> f6'), isTrue);
    });

    test('should not detect standard PGN', () {
      expect(isGoldTokenMoveList('1. d6 f4 2. b4 a1 *'), isFalse);
    });

    test('should handle bracketed content removal', () {
      // GoldToken with brackets should still be detected after removal
      expect(isGoldTokenMoveList('(header) GoldToken game'), isTrue);
    });
  });
}
