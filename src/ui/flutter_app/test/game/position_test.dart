// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
