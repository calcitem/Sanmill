// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// types_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // abs()
  // ---------------------------------------------------------------------------
  group('abs()', () {
    test('should return the same value for positive numbers', () {
      expect(abs(5), 5);
      expect(abs(100), 100);
    });

    test('should return the negation for negative numbers', () {
      expect(abs(-5), 5);
      expect(abs(-100), 100);
    });

    test('should return 0 for 0', () {
      expect(abs(0), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // makeSquare / fileOf / rankOf
  // ---------------------------------------------------------------------------
  group('makeSquare / fileOf / rankOf', () {
    test('makeSquare(0,0) should return 0', () {
      expect(makeSquare(0, 0), 0);
    });

    test('makeSquare(-1,-1) should return -1', () {
      expect(makeSquare(-1, -1), -1);
    });

    test('should produce valid squares for file 1-3, rank 1-8', () {
      for (int file = 1; file <= 3; file++) {
        for (int rank = 1; rank <= 8; rank++) {
          final int sq = makeSquare(file, rank);
          expect(sq, greaterThan(0));
          expect(fileOf(sq), file);
          expect(rankOf(sq), rank);
        }
      }
    });

    test('fileOf should extract file from square', () {
      // Square 8 = file 1, rank 1
      expect(fileOf(8), 1);
      // Square 16 = file 2, rank 1
      expect(fileOf(16), 2);
      // Square 24 = file 3, rank 1
      expect(fileOf(24), 3);
    });

    test('rankOf should extract rank from square', () {
      expect(rankOf(8), 1);
      expect(rankOf(9), 2);
      expect(rankOf(15), 8);
    });
  });

  // ---------------------------------------------------------------------------
  // isOk()
  // ---------------------------------------------------------------------------
  group('isOk()', () {
    test('square 0 (SQ_NONE) should be OK', () {
      expect(isOk(0), isTrue);
    });

    test('squares 8-31 should be OK', () {
      for (int sq = 8; sq < 32; sq++) {
        expect(isOk(sq), isTrue, reason: 'Square $sq should be OK');
      }
    });

    test('squares outside valid range should not be OK', () {
      expect(isOk(1), isFalse);
      expect(isOk(7), isFalse);
      expect(isOk(32), isFalse);
      expect(isOk(-1), isFalse);
      expect(isOk(100), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // fromSq / toSq / makeMove
  // ---------------------------------------------------------------------------
  group('fromSq / toSq / makeMove', () {
    test('makeMove should encode from and to squares', () {
      final int move = makeMove(12, 20);
      expect(fromSq(move), 12);
      expect(toSq(move), 20);
    });

    test('should handle all valid square combinations', () {
      for (int from = 8; from < 32; from++) {
        for (int to = 8; to < 32; to++) {
          if (from == to) {
            continue;
          }
          final int move = makeMove(from, to);
          expect(fromSq(move), from, reason: 'fromSq($from->$to)');
          expect(toSq(move), to, reason: 'toSq($from->$to)');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // notationToSquare / squareToNotation
  // ---------------------------------------------------------------------------
  group('notationToSquare', () {
    const Map<String, int> allPositions = <String, int>{
      'd5': 8,
      'e5': 9,
      'e4': 10,
      'e3': 11,
      'd3': 12,
      'c3': 13,
      'c4': 14,
      'c5': 15,
      'd6': 16,
      'f6': 17,
      'f4': 18,
      'f2': 19,
      'd2': 20,
      'b2': 21,
      'b4': 22,
      'b6': 23,
      'd7': 24,
      'g7': 25,
      'g4': 26,
      'g1': 27,
      'd1': 28,
      'a1': 29,
      'a4': 30,
      'a7': 31,
    };

    test('should convert all 24 standard notation strings to squares', () {
      allPositions.forEach((String notation, int expectedSquare) {
        expect(
          notationToSquare(notation),
          expectedSquare,
          reason: 'notationToSquare("$notation")',
        );
      });
    });

    test('should return -1 for invalid notation', () {
      expect(notationToSquare('z9'), -1);
      expect(notationToSquare(''), -1);
      expect(notationToSquare('invalid'), -1);
    });

    test('should handle uppercase by trimming/lowering', () {
      // notationToSquare does .trim().toLowerCase()
      expect(notationToSquare('D5'), 8);
      expect(notationToSquare(' a1 '), 29);
    });
  });

  group('squareToNotation', () {
    test('should convert all 24 valid squares to notation strings', () {
      const Map<int, String> expected = <int, String>{
        8: 'd5',
        9: 'e5',
        10: 'e4',
        11: 'e3',
        12: 'd3',
        13: 'c3',
        14: 'c4',
        15: 'c5',
        16: 'd6',
        17: 'f6',
        18: 'f4',
        19: 'f2',
        20: 'd2',
        21: 'b2',
        22: 'b4',
        23: 'b6',
        24: 'd7',
        25: 'g7',
        26: 'g4',
        27: 'g1',
        28: 'd1',
        29: 'a1',
        30: 'a4',
        31: 'a7',
      };

      expected.forEach((int square, String expectedNotation) {
        expect(
          squareToNotation(square),
          expectedNotation,
          reason: 'squareToNotation($square)',
        );
      });
    });

    test('should return empty string for invalid square', () {
      expect(squareToNotation(0), '');
      expect(squareToNotation(7), '');
      expect(squareToNotation(32), '');
      expect(squareToNotation(-1), '');
    });
  });

  group('notationToSquare and squareToNotation round-trip', () {
    test('should be inverse functions for all valid squares', () {
      for (int sq = 8; sq < 32; sq++) {
        final String notation = squareToNotation(sq);
        expect(notation, isNotEmpty, reason: 'Square $sq has notation');
        expect(
          notationToSquare(notation),
          sq,
          reason: 'Round-trip for square $sq',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // squareToIndex / indexToSquare consistency
  // ---------------------------------------------------------------------------
  group('squareToIndex / indexToSquare', () {
    test('should be inverse mappings', () {
      squareToIndex.forEach((int square, int index) {
        expect(
          indexToSquare[index],
          square,
          reason: 'indexToSquare[$index] should be $square',
        );
      });
    });

    test('should cover all 24 board squares', () {
      expect(squareToIndex.length, 24);
      expect(indexToSquare.length, 24);
    });
  });

  // ---------------------------------------------------------------------------
  // PieceColor extensions
  // ---------------------------------------------------------------------------
  group('PieceColor.string', () {
    test('should return correct character for each color', () {
      expect(PieceColor.none.string, '*');
      expect(PieceColor.white.string, 'O');
      expect(PieceColor.black.string, '@');
      expect(PieceColor.marked.string, 'X');
      expect(PieceColor.nobody.string, '-');
      expect(PieceColor.draw.string, '=');
    });
  });

  group('PieceColor.opponent', () {
    test('white opponent is black', () {
      expect(PieceColor.white.opponent, PieceColor.black);
    });

    test('black opponent is white', () {
      expect(PieceColor.black.opponent, PieceColor.white);
    });

    test('non-player colors return themselves', () {
      expect(PieceColor.none.opponent, PieceColor.none);
      expect(PieceColor.draw.opponent, PieceColor.draw);
      expect(PieceColor.nobody.opponent, PieceColor.nobody);
      expect(PieceColor.marked.opponent, PieceColor.marked);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase.fen / Act.fen
  // ---------------------------------------------------------------------------
  group('Phase.fen', () {
    test('should return correct FEN character for each phase', () {
      expect(Phase.ready.fen, 'r');
      expect(Phase.placing.fen, 'p');
      expect(Phase.moving.fen, 'm');
      expect(Phase.gameOver.fen, 'o');
    });
  });

  group('Act.fen', () {
    test('should return correct FEN character for each action', () {
      expect(Act.place.fen, 'p');
      expect(Act.select.fen, 's');
      expect(Act.remove.fen, 'r');
    });
  });

  // ---------------------------------------------------------------------------
  // PlayOK notation mapping
  // ---------------------------------------------------------------------------
  group('playOkNotationToStandardNotation', () {
    test('should have 24 entries', () {
      expect(playOkNotationToStandardNotation.length, 24);
    });

    test('should map position 1 to a7', () {
      expect(playOkNotationToStandardNotation['1'], 'a7');
    });

    test('should map position 24 to g1', () {
      expect(playOkNotationToStandardNotation['24'], 'g1');
    });

    test('all values should be valid standard notation', () {
      for (final String notation
          in playOkNotationToStandardNotation.values) {
        expect(
          notationToSquare(notation),
          isNot(-1),
          reason: '"$notation" should be a valid notation',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  group('Board constants', () {
    test('sqBegin and sqEnd define valid range', () {
      expect(sqBegin, 8);
      expect(sqEnd, 32);
      expect(sqNumber, 40);
    });

    test('file and rank counts', () {
      expect(fileNumber, 3);
      expect(fileExNumber, 5);
      expect(rankNumber, 8);
    });
  });
}
