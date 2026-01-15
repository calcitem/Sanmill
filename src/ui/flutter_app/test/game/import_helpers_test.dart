// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/import_helpers.dart';

void main() {
  group('Import helpers', () {
    test('Detects pure FEN text', () {
      const String fen =
          '********/********/******** w p p 9 0 9 0 0 0 0 0 0 0 0 0';
      expect(isPureFen(fen), isTrue);
    });

    test('Detects tag pairs and FEN tag', () {
      const String pgn = '[Event "Sanmill"]\n[White "Human"]\n[Result "*"]';
      const String pgnWithFen = '[FEN "dummy"]\n[SetUp "1"]\n';
      expect(hasTagPairs(pgn), isTrue);
      expect(isFenMoveList(pgnWithFen), isTrue);
    });

    test('Detects PlayOK move list', () {
      const String playOk = '[Site "PlayOK"]\n1. 12 34 56';
      const String noLetters = '1. 12 34 56';
      expect(isPlayOkMoveList(playOk), isTrue);
      expect(isPlayOkMoveList(noLetters), isTrue);
    });

    test('Detects GoldToken move list', () {
      const String goldToken = 'GoldToken Place to d6, take f4';
      const String goldTokenAlt = '1. d6 -> f4';
      expect(isGoldTokenMoveList(goldToken), isTrue);
      expect(isGoldTokenMoveList(goldTokenAlt), isTrue);
    });

    test('Rejects non-PlayOK move list with letters', () {
      const String withLetters = '1. a1 b2 c3'; // Has letters a-g
      expect(isPlayOkMoveList(withLetters), isFalse);
    });

    test('Extracts tag pairs correctly', () {
      const String pgn = '''
[Event "Test"]
[White "Alice"]

1. d6 f4 *
''';

      final String tagPairs = getTagPairs(pgn);
      expect(tagPairs, contains('[Event "Test"]'));
      expect(tagPairs, contains('[White "Alice"]'));
      expect(tagPairs, isNot(contains('1. d6')));
    });

    test('Removes tag pairs correctly', () {
      const String pgn = '[Event "Test"]\n[White "Alice"]\n\n1. d6 f4 *';

      final String withoutTags = removeTagPairs(pgn);
      expect(withoutTags, isNot(contains('[Event')));
      expect(withoutTags, contains('1. d6'));
    });

    test('Returns empty string when no tag pairs exist', () {
      const String noTags = '1. d6 f4 *';

      final String tagPairs = getTagPairs(noTags);
      expect(tagPairs, isEmpty);

      final String withoutTags = removeTagPairs(noTags);
      expect(withoutTags, equals(noTags));
    });

    test('isPureFen rejects invalid FEN strings', () {
      const String tooShort = '****/****/****';
      const String noSlashes = '********************************';
      const String wrongFormat = 'abcdefgh/ijklmnop/qrstuvwx w p p 9 0 9 0';

      expect(isPureFen(tooShort), isFalse);
      expect(isPureFen(noSlashes), isFalse);
      expect(isPureFen(wrongFormat), isFalse);
    });

    test('hasTagPairs detects various tag patterns', () {
      const String withEvent = '[Event "Test"] 1. d6';
      const String withWhite = '[White "Alice"] 1. f4';
      const String withFen = '[FEN "****/****/****"] 1. g7';
      const String noTags = '1. d6 f4 *';

      expect(hasTagPairs(withEvent), isTrue);
      expect(hasTagPairs(withWhite), isTrue);
      expect(hasTagPairs(withFen), isTrue);
      expect(hasTagPairs(noTags), isFalse);
    });

    test('Handles tag pairs with complex values', () {
      const String complexPgn =
          '[Event "Test [Bracket] Event"]\n[White "Name, Surname"]\n1. d6 *';

      final String tagPairs = getTagPairs(complexPgn);
      expect(tagPairs, contains('[Event'));
      expect(tagPairs, contains('[White'));

      final String withoutTags = removeTagPairs(complexPgn);
      expect(withoutTags, contains('1. d6'));
    });
  });
}
