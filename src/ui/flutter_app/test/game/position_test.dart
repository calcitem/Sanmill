// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  group("Position", () {
    test("_movesSinceLastRemove should output the moves since last remove",
        () async {
      const WinLessThanThreeGame testMill = WinLessThanThreeGame();

      // Initialize the test
      DB.instance = MockDB();
      SoundManager.instance = MockAudios();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Import a game
      ImportService.import(testMill.moveList);

      expect(
        controller.position.movesSinceLastRemove,
        testMill.movesSinceRemove,
      );
    });
  });
}
