// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// import_export_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  group("Import Export Service", () {
    setUp(() {
      // Mock DB and SoundManager to isolate the test environment
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();

      // Initialize the singleton GameController
      final GameController controller = GameController.instance;
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
    });

    test(
      "Import standard notation should populate the recorder with the imported moves",
      () async {
        const WinLessThanThreeGame testMill = WinLessThanThreeGame();

        // Access the singleton GameController instance
        final GameController controller = GameController.instance;

        // Import a game using ImportService
        ImportService.import(testMill.moveList);

        // Verify that the recorder contains the expected moves
        expect(
          controller.gameRecorder.toString(),
          testMill.recorderToString,
          reason: 'GameRecorder should contain the imported moves',
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
      expect(
        controller.gameRecorder.moveHistoryText.trim(),
        testMill.moveList.trim(),
        reason: 'Exported move list should match the original imported list',
      );
    });
  });
}
