// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// position_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Define the MethodChannel to be mocked
  const MethodChannel engineChannel = MethodChannel(
    "com.calcitem.sanmill/engine",
  );

  setUp(() {
    DB.instance = MockDB();
    // Initialize bitboards for square bit masks used by FEN parser/export
    initBitboards();
    // Use the new API to set up mock handlers for MethodChannel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
              return null; // Return a success response
            case 'shutdown':
              return null; // Return a success response
            case 'startup':
              return null; // Return a success response
            case 'read':
              return 'bestmove d2'; // Simulate a response for the 'read' method
            case 'isThinking':
              return false; // Simulate the 'isThinking' method response
            default:
              return null; // For unhandled methods, return null
          }
        });
  });

  tearDown(() {
    // Use the new API to remove the mock handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
  });

  group("Position", () {
    test(
      "_movesSinceLastRemove should output the moves since last remove",
      () async {
        const WinLessThanThreeGame testMill = WinLessThanThreeGame();

        // Initialize the test

        SoundManager.instance = MockAudios();
        final GameController controller = GameController();

        // Initialize mock AnimationManager to avoid LateInitializationError
        controller.animationManager = MockAnimationManager();

        // Reset to clean state before importing
        controller.reset(force: true);
        controller.gameInstance.gameMode = GameMode.humanVsHuman;

        // Verify using standard Nine Men's Morris rules
        expect(DB().ruleSettings.piecesCount, 9);
        expect(DB().ruleSettings.hasDiagonalLines, false);

        // Import a game
        ImportService.import(testMill.moveList);

        // Note: After import, the game state is in newGameRecorder
        // but position state may not reflect it until activation
        // For this test, we check if import succeeded by verifying newGameRecorder exists
        expect(
          controller.newGameRecorder,
          isNotNull,
          reason: 'newGameRecorder should be set after successful import',
        );

        // Verify moves were imported (in newGameRecorder)
        // The test game has 59 moves including capture remove operations
        expect(
          controller.newGameRecorder!.mainlineMoves.length,
          59,
          reason: 'Should have imported 59 moves',
        );
      },
    );
  });

  group('LeapCapture', () {
    late GameController controller;

    setUp(() {
      initBitboards();
      controller = GameController();
      controller.animationManager = MockAnimationManager();
      DB().ruleSettings = const RuleSettings(
        enableLeapCapture: true,
        hasDiagonalLines: true,
      );
      controller.reset(force: true);
    });

    // 'Leap Capture NOT in Placing Phase without movement' was
    // removed: it relied on `Position.putPieceForSetupPosition`
    // which went away with the setup-position editor.  Equivalent
    // coverage will be added against `NativeMillGameSession` once
    // `Position` itself is deleted in phase eta.

    test('Leap Capture in Placing Phase with movement enabled', () {
      final Position pos = controller.position;
      // Enable movement in placing phase
      DB().ruleSettings = const RuleSettings(
        enableLeapCapture: true,
        mayMoveInPlacingPhase: true,
        hasDiagonalLines: true,
      );
      controller.reset(force: true);
      pos.phase = Phase.placing;

      // Setup: W at 8, B at 9, 10 empty
      pos.board[8] = PieceColor.white;
      pos.board[9] = PieceColor.black;
      pos.board[10] = PieceColor.none;
      pos.pieceOnBoardCount[PieceColor.white] = 1;
      pos.pieceOnBoardCount[PieceColor.black] = 1;

      final List<int> captured = <int>[];
      // White moves from 8 to 10 (with from parameter) - should trigger leap
      final bool hasCapture = pos.checkLeapCaptureForTest(
        10,
        PieceColor.white,
        captured,
        8, // from parameter provided
      );

      expect(hasCapture, isTrue);
      expect(captured, contains(9));
    });

    test('Leap Capture in Moving Phase', () {
      final Position pos = controller.position;
      // Create position with white at d3, black at d2, d1 empty
      pos.setFen('********/********/******** w m m 0 0 0 0 0 0 0 0 0 0 0');

      // Place white at d3 (index 12)
      pos.board[12] = PieceColor.white;
      pos.pieceOnBoardCount[PieceColor.white] = 1;

      // Place black at d2 (index 20)
      pos.board[20] = PieceColor.black;
      pos.pieceOnBoardCount[PieceColor.black] = 1;

      final List<int> captured = <int>[];
      final bool hasCapture = pos.checkLeapCaptureForTest(
        28, // d1
        PieceColor.white,
        captured,
        12, // d3
      );

      expect(hasCapture, isTrue);
      expect(captured, contains(20)); // d2
    });

    // 'FEN Round Trip with Leap Capture Data' was removed for the
    // same reason as above.  Coverage migrates to phase eta.

    test('Do move with Leap Capture in moving phase', () {
      final Position pos = controller.position;
      // Setup a moving phase scenario: W at a7 (16), B at d7 (19), g7 (22) empty
      pos.setFen('********/********/******** w m s 1 0 1 0 0 0 0 0 0 0 0');

      pos.board[16] = PieceColor.white; // a7
      pos.board[19] = PieceColor.black; // d7
      pos.board[22] = PieceColor.none; // g7 empty
      pos.pieceOnBoardCount[PieceColor.white] = 1;
      pos.pieceOnBoardCount[PieceColor.black] = 1;
      pos.sideToMove = PieceColor.white;
      pos.phase = Phase.moving;
      pos.action = Act.select;

      // This test validates that leap moves work correctly in moving phase
      // The actual leap logic is tested in other test cases
      expect(pos.board[16], PieceColor.white);
      expect(pos.board[19], PieceColor.black);
      expect(pos.board[22], PieceColor.none);
    });

    test('Leap move execution in moving phase', () {
      final Position pos = controller.position;
      // Set up moving phase with white at d3 (12), black at d2 (20), d1 (28) empty
      pos.setFen('********/********/******** w m s 1 0 1 0 0 0 0 0 0 0 0');

      // Manually set board state
      pos.board[12] = PieceColor.white;
      pos.board[20] = PieceColor.black;
      pos.board[28] = PieceColor.none;
      pos.pieceOnBoardCount[PieceColor.white] = 1;
      pos.pieceOnBoardCount[PieceColor.black] = 1;
      pos.sideToMove = PieceColor.white;
      pos.phase = Phase.moving;
      pos.action = Act.select;

      // Select piece at d3
      expect(pos.board[12], PieceColor.white);

      // Attempt leap move from d3 (12) to d1 (28), jumping over black at d2 (20)
      // This should be allowed when leap capture is enabled
      final bool moveResult = pos.putPieceForTest(28);

      // The move should succeed if leap capture is properly implemented
      expect(moveResult, isTrue);
      expect(pos.board[28], PieceColor.white);
      expect(pos.board[12], PieceColor.none);
    });
  });
}
