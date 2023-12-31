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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/custom_drawer/custom_drawer.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/generated/intl/l10n_en.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  group("GameHeader", () {
    testWidgets("GameHeader updates tip", (WidgetTester tester) async {
      const String testString = "Test";

      DB.instance = MockDB();
      final GameController controller = GameController();
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
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      const Key iconKey = Key("DrawerIcon");

      final CustomDrawerIcon screen = CustomDrawerIcon(
        drawerIcon: IconButton(
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
