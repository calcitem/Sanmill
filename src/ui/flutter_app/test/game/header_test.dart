// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n_en.dart';
import 'package:sanmill/screens/game_page/game_page.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/services/mill/mill.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  group("GameHeader", () {
    testWidgets("GameHeader updates tip", (WidgetTester tester) async {
      const String testString = "Test";

      DB.instance = MockDB();
      final MillController controller = MillController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
      const HeaderTip screen = HeaderTip();

      await tester.pumpWidget(makeTestableWidget(screen));

      expect(find.text(SEn().welcome), findsOneWidget);

      controller.headerTipNotifier.showTip(testString, snackBar: false);

      await tester.pump();

      expect(find.text(testString), findsOneWidget);
    });

    testWidgets("GameHeader position", (WidgetTester tester) async {
      DB.instance = MockDB();
      final MillController controller = MillController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      const Key iconKey = Key("DrawerIcon");

      final DrawerIcon screen = DrawerIcon(
        icon: IconButton(
          icon: const Icon(
            Icons.menu,
            key: iconKey,
          ),
          onPressed: () {},
        ),
        child: Scaffold(
          appBar: GameHeader(),
        ),
      );

      await tester.pumpWidget(makeTestableWidget(screen));

      final Offset icon = tester.getCenter(find.byKey(iconKey));
      final Offset header =
          tester.getCenter(find.byKey(const Key("HeaderIconRow")));

      // TODO: Why 44?
      expect(icon.dy + 44, header.dy);
    });
  });
}
