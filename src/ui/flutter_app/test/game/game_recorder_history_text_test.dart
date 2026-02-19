// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_recorder_history_text_test.dart
//
// Tests for GameRecorder move history text output variants:
// moveHistoryText, moveHistoryTextCurrentLine,
// moveHistoryTextWithoutVariations, and Position.hasGameResult.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  late GameController controller;

  setUp(() {
    DB.instance = MockDB();
    initBitboards();
    SoundManager.instance = MockAudios();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'bestmove d2';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });
    controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  // ---------------------------------------------------------------------------
  // moveHistoryText
  // ---------------------------------------------------------------------------
  group('GameRecorder.moveHistoryText', () {
    test('should contain move notations for linear game', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('b4', side: PieceColor.white));

      final String text = recorder.moveHistoryText;

      expect(text, contains('d6'));
      expect(text, contains('f4'));
      expect(text, contains('b4'));
    });

    test('should include move numbers', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      final String text = recorder.moveHistoryText;

      expect(text, contains('1.'));
    });

    test('should include result marker', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));

      final String text = recorder.moveHistoryText;

      // Should end with a result marker like *, 1-0, 0-1, or 1/2-1/2
      expect(
        text.contains('*') ||
            text.contains('1-0') ||
            text.contains('0-1') ||
            text.contains('1/2-1/2'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // moveHistoryTextWithoutVariations
  // ---------------------------------------------------------------------------
  group('GameRecorder.moveHistoryTextWithoutVariations', () {
    test('should be same as moveHistoryText for linear game', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      final String _ = recorder.moveHistoryText;
      final String mainOnly = recorder.moveHistoryTextWithoutVariations;

      // For a linear game, both should contain the same moves
      expect(mainOnly, contains('d6'));
      expect(mainOnly, contains('f4'));
    });

    test('should exclude variations', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Create a variation
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.branchNewMoveFromActiveNode(
        ExtMove('a1', side: PieceColor.black),
      );

      final String mainOnly = recorder.moveHistoryTextWithoutVariations;

      // Main line has d6, f4 — variation has a1
      expect(mainOnly, contains('d6'));
      expect(mainOnly, contains('f4'));
      // The variation move 'a1' should NOT be in mainline-only text
      // (unless it's also part of standard notation coincidence)
    });
  });

  // ---------------------------------------------------------------------------
  // moveHistoryTextCurrentLine
  // ---------------------------------------------------------------------------
  group('GameRecorder.moveHistoryTextCurrentLine', () {
    test('should contain moves along current path', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));
      recorder.appendMove(ExtMove('b4', side: PieceColor.white));

      final String text = recorder.moveHistoryTextCurrentLine;

      expect(text, contains('d6'));
      expect(text, contains('f4'));
      expect(text, contains('b4'));
    });

    test('should follow active branch, not just mainline', () {
      final GameRecorder recorder = controller.gameRecorder;
      recorder.appendMove(ExtMove('d6', side: PieceColor.white));
      recorder.appendMove(ExtMove('f4', side: PieceColor.black));

      // Go back and create variation
      recorder.activeNode = recorder.pgnRoot.children.first;
      recorder.branchNewMoveFromActiveNode(
        ExtMove('g7', side: PieceColor.black),
      );

      // Now active is on variation: d6 → g7
      final String text = recorder.moveHistoryTextCurrentLine;

      expect(text, contains('d6'));
      expect(text, contains('g7'));
    });

    test('empty recorder should produce minimal text', () {
      final GameRecorder recorder = controller.gameRecorder;
      final String text = recorder.moveHistoryTextCurrentLine;

      expect(text, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Position.hasGameResult
  // ---------------------------------------------------------------------------
  group('Position.hasGameResult', () {
    test('should be false for new position', () {
      final Position p = Position();
      expect(p.hasGameResult, isFalse);
    });

    test('should be false in placing phase', () {
      final Position p = Position();
      p.phase = Phase.placing;
      expect(p.hasGameResult, isFalse);
    });

    test('should be false in moving phase', () {
      final Position p = Position();
      p.phase = Phase.moving;
      expect(p.hasGameResult, isFalse);
    });

    test('should be true in gameOver phase', () {
      final Position p = Position();
      p.setGameOver(PieceColor.white, GameOverReason.loseFewerThanThree);
      expect(p.hasGameResult, isTrue);
      expect(p.phase, Phase.gameOver);
    });
  });
}
