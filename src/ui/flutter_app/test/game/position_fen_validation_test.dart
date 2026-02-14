// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// position_fen_validation_test.dart
//
// Tests for Position FEN validation, state management, and score tracking.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
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
    initBitboards();
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
  // Position initial state
  // ---------------------------------------------------------------------------
  group('Position initial state', () {
    test('new Position should be empty', () {
      final Position p = Position();
      expect(p.isEmpty(), isTrue);
    });

    test('new Position should have correct piece counts', () {
      final Position p = Position();
      expect(
        p.pieceInHandCount[PieceColor.white],
        DB().ruleSettings.piecesCount,
      );
      expect(
        p.pieceInHandCount[PieceColor.black],
        DB().ruleSettings.piecesCount,
      );
      expect(p.pieceOnBoardCount[PieceColor.white], 0);
      expect(p.pieceOnBoardCount[PieceColor.black], 0);
    });

    test('new Position should be in ready phase', () {
      final Position p = Position();
      expect(p.phase, Phase.ready);
    });

    test('pieceCountDiff should be 0 initially', () {
      final Position p = Position();
      expect(p.pieceCountDiff(), 0);
    });

    test('initial pieceToRemoveCount should be 0 for both sides', () {
      final Position p = Position();
      expect(p.pieceToRemoveCount[PieceColor.white], 0);
      expect(p.pieceToRemoveCount[PieceColor.black], 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.validateFen
  // ---------------------------------------------------------------------------
  group('Position.validateFen', () {
    test('valid empty board FEN should pass', () {
      final Position p = Position();
      expect(
        p.validateFen(
          '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isTrue,
      );
    });

    test('valid FEN with pieces should pass', () {
      final Position p = Position();
      expect(
        p.validateFen(
          'O@O*****/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1',
        ),
        isTrue,
      );
    });

    test('valid FEN in moving phase should pass', () {
      final Position p = Position();
      expect(
        p.validateFen(
          'O@O@O@O@/O@*****/******** w m s 5 0 3 4 0 0 0 0 0 0 0 0 1',
        ),
        isTrue,
      );
    });

    test('FEN with too few parts should fail', () {
      final Position p = Position();
      expect(p.validateFen('********/********/********'), isFalse);
    });

    test('FEN with invalid board length should fail', () {
      final Position p = Position();
      expect(
        p.validateFen(
          '****/****/****  w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isFalse,
      );
    });

    test('FEN with invalid active color should fail', () {
      final Position p = Position();
      expect(
        p.validateFen(
          '********/********/******** x p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isFalse,
      );
    });

    test('FEN with invalid phase character should fail', () {
      final Position p = Position();
      expect(
        p.validateFen(
          '********/********/******** w x p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isFalse,
      );
    });

    test('FEN with invalid action character should fail', () {
      final Position p = Position();
      expect(
        p.validateFen(
          '********/********/******** w p x 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isFalse,
      );
    });

    test('FEN with invalid board characters should fail', () {
      final Position p = Position();
      expect(
        p.validateFen(
          'ZZZZZZZZ/ZZZZZZZZ/ZZZZZZZZ w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isFalse,
      );
    });

    test('empty string should fail', () {
      final Position p = Position();
      expect(p.validateFen(''), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.setFen and fen round-trip
  // ---------------------------------------------------------------------------
  group('Position FEN round-trip', () {
    test('setFen with valid FEN should succeed', () {
      final Position p = Position();
      expect(
        p.setFen(
          '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
        ),
        isTrue,
      );
    });

    test('FEN round-trip should preserve board state', () {
      const String originalFen =
          'O@O*****/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1';

      final Position p1 = Position();
      p1.setFen(originalFen);
      final String? exportedFen = p1.fen;

      expect(exportedFen, isNotNull);

      final Position p2 = Position();
      p2.setFen(exportedFen!);
      final String? reexportedFen = p2.fen;

      expect(reexportedFen, exportedFen);
    });

    test('setFen should update sideToMove', () {
      final Position p = Position();
      p.setFen(
        '********/********/******** b p p 0 9 0 9 0 0 0 0 0 0 0 0 1',
      );
      expect(p.sideToMove, PieceColor.black);
    });

    test('setFen should update phase', () {
      final Position p = Position();
      p.setFen(
        'O@O@O@O@/O@*****/******** w m s 5 0 3 4 0 0 0 0 0 0 0 0 1',
      );
      expect(p.phase, Phase.moving);
    });

    test('setFen should update board positions', () {
      final Position p = Position();
      p.setFen(
        'O*******/*O******/**O***** w p p 1 8 1 8 0 0 0 0 0 0 0 0 1',
      );

      // Inner ring position 0 (d5 = square 8) should be white
      expect(p.board[8], PieceColor.white);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.board access
  // ---------------------------------------------------------------------------
  group('Position board access', () {
    test('board should be indexable', () {
      final Position p = Position();
      // All squares should be PieceColor.none initially
      for (int i = sqBegin; i < sqEnd; i++) {
        expect(p.board[i], PieceColor.none);
      }
    });

    test('board assignment should work', () {
      final Position p = Position();
      p.board[8] = PieceColor.white;
      expect(p.board[8], PieceColor.white);

      p.board[9] = PieceColor.black;
      expect(p.board[9], PieceColor.black);
    });
  });

  // ---------------------------------------------------------------------------
  // Score tracking
  // ---------------------------------------------------------------------------
  group('Position score tracking', () {
    test('initial score should be all zeros', () {
      Position.resetScore();
      expect(Position.score[PieceColor.white], 0);
      expect(Position.score[PieceColor.black], 0);
      expect(Position.score[PieceColor.draw], 0);
    });

    test('scoreString should format correctly', () {
      Position.resetScore();
      final Position p = Position();
      expect(p.scoreString, '0 - 0 - 0');
    });

    test('score should be updatable', () {
      Position.resetScore();
      Position.score[PieceColor.white] = 5;
      Position.score[PieceColor.black] = 3;
      Position.score[PieceColor.draw] = 2;

      final Position p = Position();
      expect(p.scoreString, '5 - 2 - 3');
    });

    test('resetScore should clear all scores', () {
      Position.score[PieceColor.white] = 10;
      Position.score[PieceColor.black] = 7;
      Position.score[PieceColor.draw] = 3;

      Position.resetScore();

      expect(Position.score[PieceColor.white], 0);
      expect(Position.score[PieceColor.black], 0);
      expect(Position.score[PieceColor.draw], 0);
    });

    test('isNoDraw should return false when all scores are 0', () {
      Position.resetScore();
      final Position p = Position();
      expect(p.isNoDraw(), isFalse);
    });

    test('isNoDraw should return true when white has wins', () {
      Position.resetScore();
      Position.score[PieceColor.white] = 1;
      final Position p = Position();
      expect(p.isNoDraw(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.sideToMove
  // ---------------------------------------------------------------------------
  group('Position sideToMove', () {
    test('default should be white', () {
      final Position p = Position();
      expect(p.sideToMove, PieceColor.white);
    });

    test('should be settable', () {
      final Position p = Position();
      p.sideToMove = PieceColor.black;
      expect(p.sideToMove, PieceColor.black);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.winner
  // ---------------------------------------------------------------------------
  group('Position winner', () {
    test('initial winner should be nobody', () {
      final Position p = Position();
      expect(p.winner, PieceColor.nobody);
    });

    test('setGameOver should set winner', () {
      final Position p = Position();
      p.setGameOver(PieceColor.white, GameOverReason.loseFewerThanThree);
      expect(p.winner, PieceColor.white);
      expect(p.phase, Phase.gameOver);
    });

    test('setGameOver for draw should set draw winner', () {
      final Position p = Position();
      p.setGameOver(PieceColor.draw, GameOverReason.drawFiftyMove);
      expect(p.winner, PieceColor.draw);
      expect(p.phase, Phase.gameOver);
    });
  });
}
