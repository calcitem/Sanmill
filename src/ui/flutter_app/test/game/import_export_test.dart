// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_export_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
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

  group("Import Export Service", () {
    setUp(() {
      // Mock DB and SoundManager to isolate the test environment
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();

      // Initialize the singleton GameController
      final GameController controller = GameController.instance;

      // Initialize mock AnimationManager to avoid LateInitializationError
      controller.animationManager = MockAnimationManager();

      // Reset the game controller to a clean state
      controller.reset(force: true);
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
    });

    test(
      "Import standard notation should populate the recorder with the imported moves",
      () async {
        const WinLessThanThreeGame testMill = WinLessThanThreeGame();

        // Access the singleton GameController instance
        final GameController controller = GameController.instance;

        // Verify MockDB is using standard Nine Men's Morris rules
        expect(DB().ruleSettings.piecesCount, 9);
        expect(DB().ruleSettings.hasDiagonalLines, false);

        // Import a game using ImportService
        ImportService.import(testMill.moveList);

        // After import, the moves are stored in newGameRecorder
        // (not yet activated in gameRecorder until takeBackAll/stepForwardAll)

        // Verify that the newGameRecorder contains the expected number of moves
        // The test game has 25 pairs of moves, but captures split into separate moves
        // Actual count is 59 (25 pairs + capture remove operations)
        expect(
          controller.newGameRecorder?.mainlineMoves.length,
          59,
          reason: 'newGameRecorder should contain 59 moves after import',
        );

        // Verify the exported move list matches the imported one
        expect(
          controller.newGameRecorder?.moveHistoryText.trim(),
          testMill.moveList.trim(),
          reason: 'Exported moves should match imported moves',
        );
      },
    );

    test("Export standard notation", () async {
      const WinLessThanThreeGame testMill = WinLessThanThreeGame();

      // Access the singleton GameController instance
      final GameController controller = GameController.instance;

      // Import a game
      ImportService.import(testMill.moveList);

      // Verify the exported moves match the original imported moves
      // After import, moves are in newGameRecorder (not yet activated)
      expect(
        controller.newGameRecorder?.moveHistoryText.trim(),
        testMill.moveList.trim(),
        reason: 'Exported move list should match the original imported list',
      );
    });
  });
}
