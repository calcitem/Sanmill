// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ext_move_test.dart

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
  // MoveParser
  // ---------------------------------------------------------------------------
  group('MoveParser', () {
    final MoveParser parser = MoveParser();

    test('should parse place moves (e.g. "a1")', () {
      expect(parser.parseMoveType('a1'), MoveType.place);
      expect(parser.parseMoveType('d5'), MoveType.place);
      expect(parser.parseMoveType('g7'), MoveType.place);
    });

    test('should parse move moves (e.g. "a1-a4")', () {
      expect(parser.parseMoveType('a1-a4'), MoveType.move);
      expect(parser.parseMoveType('d5-e5'), MoveType.move);
    });

    test('should parse remove moves (e.g. "xa1")', () {
      expect(parser.parseMoveType('xa1'), MoveType.remove);
      expect(parser.parseMoveType('xd5'), MoveType.remove);
    });

    test('should parse draw', () {
      expect(parser.parseMoveType('draw'), MoveType.draw);
    });

    test('should parse none', () {
      expect(parser.parseMoveType('(none)'), MoveType.none);
      expect(parser.parseMoveType('none'), MoveType.none);
    });

    test('should throw FormatException for invalid move', () {
      expect(() => parser.parseMoveType('xyz'), throwsFormatException);
      expect(() => parser.parseMoveType(''), throwsFormatException);
    });
  });

  // ---------------------------------------------------------------------------
  // ExtMove construction and properties
  // ---------------------------------------------------------------------------
  group('ExtMove construction', () {
    test('should construct a place move correctly', () {
      final ExtMove move = ExtMove('a1', side: PieceColor.white);

      expect(move.type, MoveType.place);
      expect(move.move, 'a1');
      expect(move.side, PieceColor.white);
      expect(move.to, 29); // a1 = square 29
      expect(move.from, -1); // Place moves have no 'from'
    });

    test('should construct a move move correctly', () {
      final ExtMove move = ExtMove('a1-a4', side: PieceColor.white);

      expect(move.type, MoveType.move);
      expect(move.from, 29); // a1 = 29
      expect(move.to, 30); // a4 = 30
    });

    test('should construct a remove move correctly', () {
      final ExtMove move = ExtMove('xd5', side: PieceColor.black);

      expect(move.type, MoveType.remove);
      expect(move.to, 8); // d5 = square 8
      expect(move.from, -1); // Remove moves have no 'from'
    });

    test('should throw for invalid move format', () {
      expect(() => ExtMove('zzz', side: PieceColor.white), throwsA(anything));
    });

    test('should throw for same-square move', () {
      expect(() => ExtMove('a1-a1', side: PieceColor.white), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------------------
  // ExtMove.notation
  // ---------------------------------------------------------------------------
  group('ExtMove.notation', () {
    test('place move notation', () {
      final ExtMove move = ExtMove('d5', side: PieceColor.white);
      expect(move.notation, 'd5');
    });

    test('move notation', () {
      final ExtMove move = ExtMove('a1-a4', side: PieceColor.white);
      expect(move.notation, 'a1-a4');
    });

    test('remove notation', () {
      final ExtMove move = ExtMove('xa1', side: PieceColor.white);
      expect(move.notation, 'xa1');
    });
  });

  // ---------------------------------------------------------------------------
  // ExtMove.sqToNotation (static)
  // ---------------------------------------------------------------------------
  group('ExtMove.sqToNotation', () {
    test('should convert valid squares to notation', () {
      expect(ExtMove.sqToNotation(8), 'd5');
      expect(ExtMove.sqToNotation(29), 'a1');
      expect(ExtMove.sqToNotation(31), 'a7');
    });

    test('should return empty string for invalid square', () {
      expect(ExtMove.sqToNotation(99), '');
      expect(ExtMove.sqToNotation(7), '');
    });

    test('should return special strings for special values', () {
      expect(ExtMove.sqToNotation(-1), '(none)');
      expect(ExtMove.sqToNotation(0), 'draw');
    });
  });

  // ---------------------------------------------------------------------------
  // NAG (Numeric Annotation Glyph) conversion
  // ---------------------------------------------------------------------------
  group('NAG conversion', () {
    test('moveQualityToNag should map correctly', () {
      expect(ExtMove.moveQualityToNag(MoveQuality.minorGoodMove), 1);
      expect(ExtMove.moveQualityToNag(MoveQuality.minorBadMove), 2);
      expect(ExtMove.moveQualityToNag(MoveQuality.majorGoodMove), 3);
      expect(ExtMove.moveQualityToNag(MoveQuality.majorBadMove), 4);
      expect(ExtMove.moveQualityToNag(MoveQuality.normal), isNull);
      expect(ExtMove.moveQualityToNag(null), isNull);
    });

    test('nagToMoveQuality should map correctly', () {
      expect(ExtMove.nagToMoveQuality(1), MoveQuality.minorGoodMove);
      expect(ExtMove.nagToMoveQuality(2), MoveQuality.minorBadMove);
      expect(ExtMove.nagToMoveQuality(3), MoveQuality.majorGoodMove);
      expect(ExtMove.nagToMoveQuality(4), MoveQuality.majorBadMove);
      expect(ExtMove.nagToMoveQuality(5), isNull);
      expect(ExtMove.nagToMoveQuality(0), isNull);
    });

    test('round-trip: quality → NAG → quality', () {
      for (final MoveQuality q in MoveQuality.values) {
        final int? nag = ExtMove.moveQualityToNag(q);
        if (nag != null) {
          expect(ExtMove.nagToMoveQuality(nag), q, reason: 'Round-trip for $q');
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // getAllNags / updateQualityFromNags
  // ---------------------------------------------------------------------------
  group('getAllNags', () {
    test('should include quality-derived NAG', () {
      final ExtMove move = ExtMove('a1', side: PieceColor.white);
      move.quality = MoveQuality.majorGoodMove;

      final List<int> nags = move.getAllNags();
      expect(nags, contains(3)); // !!
    });

    test('should include existing NAGs', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[10, 20],
      );

      final List<int> nags = move.getAllNags();
      expect(nags, contains(10));
      expect(nags, contains(20));
    });

    test('should not duplicate quality NAG if already present', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[1], // Already has ! NAG
      );
      move.quality = MoveQuality.minorGoodMove; // Also maps to NAG 1

      final List<int> nags = move.getAllNags();
      // NAG 1 should appear exactly once
      expect(nags.where((int n) => n == 1).length, 1);
    });

    test('should not add quality NAG when conflicting NAG exists', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[2], // Has ? NAG
      );
      move.quality = MoveQuality.majorGoodMove; // Maps to NAG 3

      final List<int> nags = move.getAllNags();
      // Should not add NAG 3 because NAG 2 already exists as quality NAG
      expect(nags, contains(2));
      expect(nags, isNot(contains(3)));
    });
  });

  group('updateQualityFromNags', () {
    test('should set quality from NAG 1', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[1],
      );
      move.updateQualityFromNags();

      expect(move.quality, MoveQuality.minorGoodMove);
    });

    test('should set quality from NAG 4', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[4],
      );
      move.updateQualityFromNags();

      expect(move.quality, MoveQuality.majorBadMove);
    });

    test('should use first quality NAG when multiple exist', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[3, 2], // !! and ? — should take !!
      );
      move.updateQualityFromNags();

      expect(move.quality, MoveQuality.majorGoodMove);
    });

    test('should not change quality if no quality NAGs present', () {
      final ExtMove move = ExtMove(
        'a1',
        side: PieceColor.white,
        nags: <int>[10, 20], // Non-quality NAGs
      );
      move.quality = MoveQuality.normal;
      move.updateQualityFromNags();

      expect(move.quality, MoveQuality.normal);
    });

    test('should be a no-op when nags is null', () {
      final ExtMove move = ExtMove('a1', side: PieceColor.white);
      move.updateQualityFromNags();

      expect(move.quality, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // All standard notations for place, move, and remove
  // ---------------------------------------------------------------------------
  group('ExtMove all square constructions', () {
    // All valid standard notation squares
    const List<String> allSquares = <String>[
      'd5',
      'e5',
      'e4',
      'e3',
      'd3',
      'c3',
      'c4',
      'c5',
      'd6',
      'f6',
      'f4',
      'f2',
      'd2',
      'b2',
      'b4',
      'b6',
      'd7',
      'g7',
      'g4',
      'g1',
      'd1',
      'a1',
      'a4',
      'a7',
    ];

    test('should construct place moves for all squares', () {
      for (final String sq in allSquares) {
        final ExtMove move = ExtMove(sq, side: PieceColor.white);
        expect(move.type, MoveType.place, reason: 'Place $sq');
        expect(move.to, isNot(-1), reason: 'Square $sq should resolve');
      }
    });

    test('should construct remove moves for all squares', () {
      for (final String sq in allSquares) {
        final ExtMove move = ExtMove('x$sq', side: PieceColor.black);
        expect(move.type, MoveType.remove, reason: 'Remove x$sq');
        expect(move.to, isNot(-1), reason: 'Square x$sq should resolve');
      }
    });
  });
}
