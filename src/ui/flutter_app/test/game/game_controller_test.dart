/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/services/storage/storage.dart';

import '../helpers/mocks/storage_mock.dart';
import '../helpers/test_mills.dart';

@GenerateMocks([Clipboard])
void main() {
  group("MillController", () {
    test("new game should clear the history", () async {
      // initialize the test
      DB.instance = MockedDB();
      final controller = MillController();

      // import a game
      ImportService.import(testMill);

      // reset the game
      controller.gameInstance.newGame();

      expect(controller.recorder.moves, <ExtMove>[]);
    });
  });
}
