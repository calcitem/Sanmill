// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// enums_comprehensive_test.dart
//
// Comprehensive tests for all game-related enums ensuring complete
// value coverage and consistent behavior.

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
  // MoveType
  // ---------------------------------------------------------------------------
  group('MoveType enum', () {
    test('should have five values', () {
      expect(MoveType.values.length, 5);
    });

    test('should include all expected values', () {
      expect(
        MoveType.values,
        containsAll(<MoveType>[
          MoveType.place,
          MoveType.move,
          MoveType.remove,
          MoveType.draw,
          MoveType.none,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ExportVariationOption
  // ---------------------------------------------------------------------------
  group('ExportVariationOption enum', () {
    test('should have three values', () {
      expect(ExportVariationOption.values.length, 3);
    });

    test('should include all expected values', () {
      expect(
        ExportVariationOption.values,
        containsAll(<ExportVariationOption>[
          ExportVariationOption.all,
          ExportVariationOption.currentLine,
          ExportVariationOption.mainline,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // PieceColor comprehensive
  // ---------------------------------------------------------------------------
  group('PieceColor enum comprehensive', () {
    test('should have six values', () {
      expect(PieceColor.values.length, 6);
    });

    test('string representation should be unique', () {
      final Set<String> strings = PieceColor.values
          .map((PieceColor c) => c.string)
          .toSet();
      expect(strings.length, PieceColor.values.length);
    });

    test('opponent should be involutory for player colors', () {
      expect(PieceColor.white.opponent.opponent, PieceColor.white);
      expect(PieceColor.black.opponent.opponent, PieceColor.black);
    });

    test('opponent of non-player colors should be self', () {
      expect(PieceColor.none.opponent, PieceColor.none);
      expect(PieceColor.draw.opponent, PieceColor.draw);
      expect(PieceColor.marked.opponent, PieceColor.marked);
      expect(PieceColor.nobody.opponent, PieceColor.nobody);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase comprehensive
  // ---------------------------------------------------------------------------
  group('Phase enum comprehensive', () {
    test('should have four phases', () {
      expect(Phase.values.length, 4);
    });

    test('FEN character should be unique per phase', () {
      final Set<String> fens = Phase.values.map((Phase p) => p.fen).toSet();
      expect(fens.length, Phase.values.length);
    });

    test('all FEN characters should be single lowercase letter', () {
      for (final Phase p in Phase.values) {
        expect(p.fen.length, 1, reason: 'FEN for $p');
        expect(
          RegExp(r'^[a-z]$').hasMatch(p.fen),
          isTrue,
          reason: 'FEN "${p.fen}" for $p should be lowercase letter',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Act comprehensive
  // ---------------------------------------------------------------------------
  group('Act enum comprehensive', () {
    test('should have three actions', () {
      expect(Act.values.length, 3);
    });

    test('FEN character should be unique per action', () {
      final Set<String> fens = Act.values.map((Act a) => a.fen).toSet();
      expect(fens.length, Act.values.length);
    });

    test('all FEN characters should be single lowercase letter', () {
      for (final Act a in Act.values) {
        expect(a.fen.length, 1, reason: 'FEN for $a');
        expect(
          RegExp(r'^[a-z]$').hasMatch(a.fen),
          isTrue,
          reason: 'FEN "${a.fen}" for $a should be lowercase letter',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // GameOverReason comprehensive
  // ---------------------------------------------------------------------------
  group('GameOverReason comprehensive', () {
    test('should have ten reasons', () {
      expect(GameOverReason.values.length, 10);
    });

    test('lose reasons should start with "lose"', () {
      final List<GameOverReason> loseReasons = GameOverReason.values
          .where((GameOverReason r) => r.name.startsWith('lose'))
          .toList();
      expect(loseReasons.length, 5);
    });

    test('draw reasons should start with "draw"', () {
      final List<GameOverReason> drawReasons = GameOverReason.values
          .where((GameOverReason r) => r.name.startsWith('draw'))
          .toList();
      expect(drawReasons.length, 5);
    });
  });

  // ---------------------------------------------------------------------------
  // GameResult comprehensive
  // ---------------------------------------------------------------------------
  group('GameResult comprehensive', () {
    test('should have three results', () {
      expect(GameResult.values.length, 3);
    });

    test('toNagString should return valid PGN termination markers', () {
      const Set<String> validTerminations = <String>{'1-0', '0-1', '1/2-1/2'};
      for (final GameResult r in GameResult.values) {
        expect(
          validTerminations.contains(r.toNagString()),
          isTrue,
          reason: '$r.toNagString() = "${r.toNagString()}"',
        );
      }
    });

    test('all results should map to unique NAG strings', () {
      final Set<String> nags = GameResult.values
          .map((GameResult r) => r.toNagString())
          .toSet();
      expect(nags.length, GameResult.values.length);
    });
  });

  // ---------------------------------------------------------------------------
  // MoveQuality comprehensive
  // ---------------------------------------------------------------------------
  group('MoveQuality comprehensive', () {
    test('should have five qualities', () {
      expect(MoveQuality.values.length, 5);
    });

    test('NAG mapping should cover good and bad moves only', () {
      int mappedCount = 0;
      for (final MoveQuality q in MoveQuality.values) {
        if (ExtMove.moveQualityToNag(q) != null) {
          mappedCount++;
        }
      }
      // normal → null, so 4 out of 5 should map
      expect(mappedCount, 4);
    });

    test('normal quality should not have a NAG', () {
      expect(ExtMove.moveQualityToNag(MoveQuality.normal), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Board constants consistency
  // ---------------------------------------------------------------------------
  group('Board constants consistency', () {
    test('sqEnd - sqBegin should equal 24 (board squares)', () {
      expect(sqEnd - sqBegin, 24);
    });

    test('valueUnique and valueEachPiece should be positive', () {
      expect(valueUnique, greaterThan(0));
      expect(valueEachPiece, greaterThan(0));
    });

    test('move direction constants', () {
      expect(moveDirectionBegin, 0);
      expect(moveDirectionNumber, 4);
    });

    test('line direction number', () {
      expect(lineDirectionNumber, 3);
    });
  });
}
