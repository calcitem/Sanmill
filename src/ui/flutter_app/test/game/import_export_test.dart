// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
import 'package:sanmill/models/display_settings.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/mill/mill.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_mills.dart';

void main() {
  group("Import Export Service", () {
    test(
        "Import standard notation should populate the recorder with the imported moves",
        () async {
      const testMill = WinLessThanThreeGame();

      // Initialize the test
      DB.instance = MockDB();
      Audios.instance = MockAudios();
      final controller = MillController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Import a game
      ImportService.import(testMill.export);

      expect(MillController().recorder.toString(), testMill.recorder);
    });

    test("export standard notation", () async {
      const testMill = WinLessThanThreeGame();

      // Initialize the test
      DB.instance = MockDB();
      Audios.instance = MockAudios();
      final controller = MillController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      // Import a game
      ImportService.import(testMill.export);

      expect(controller.recorder.moveHistoryText, testMill.export);
    });

    test(
      "export not standard notation",
      () async {
        const testMill = WinLessThanThreeGame();

        // Initialize the test
        final mockDB = MockDB();
        // ignore: deprecated_member_use_from_same_package
        mockDB.displaySettings =
            const DisplaySettings(standardNotationEnabled: false);
        DB.instance = mockDB;
        Audios.instance = MockAudios();
        final controller = MillController();
        controller.gameInstance.gameMode = GameMode.humanVsHuman;

        // Import a game
        ImportService.import(testMill.export);

        expect(controller.recorder.moveHistoryText, testMill.exportNotStandard);
      },
      skip: "Deprecated test. See [DisplaySettings.standardNotationEnabled].",
    );
  });
}
