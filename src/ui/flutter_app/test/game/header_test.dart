// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// header_test.dart

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
  tearDown(() {
    DB.instance = null;
  });

  group("GameHeader", () {
    testWidgets("GameHeader updates tip", (WidgetTester tester) async {
      const String testString = "Test";

      DB.instance = MockDB();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
      const HeaderTip screen = HeaderTip();

      // Wrap the widget with necessary context (MaterialApp and Localizations)
      await tester.pumpWidget(makeTestableWidget(screen));

      // Verify initial text
      expect(find.text(SEn().welcome), findsOneWidget);

      // Trigger tip update
      controller.headerTipNotifier.showTip(testString, snackBar: false);

      // Ensure all updates are applied
      await tester.pumpAndSettle();

      // Verify updated text
      expect(find.text(testString), findsOneWidget);
    });

    testWidgets("HeaderTip scrolls overflowing tip", (
      WidgetTester tester,
    ) async {
      DB.instance = MockDB();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
      controller.headerTipNotifier.showTip('', snackBar: false);

      await tester.pumpWidget(
        makeTestableWidget(
          const Center(
            child: SizedBox(width: 140, height: 48, child: HeaderTip()),
          ),
        ),
      );

      controller.headerTipNotifier.showTip(
        'Opening: Very long header text that must scroll horizontally',
        snackBar: false,
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.byKey(const Key('header_tip_marquee')), findsOneWidget);
      final Finder textFinder = find.textContaining('Opening:').first;
      final double initialLeft = tester.getTopLeft(textFinder).dx;

      await tester.pump(const Duration(milliseconds: 800));

      final double movedLeft = tester.getTopLeft(textFinder).dx;
      expect(movedLeft, lessThan(initialLeft));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets("HeaderTip normalizes unsafe punctuation", (
      WidgetTester tester,
    ) async {
      DB.instance = MockDB();
      final GameController controller = GameController();

      controller.headerTipNotifier.showTip(
        'Opening: Alpha — Beta • Thinking…',
        snackBar: false,
      );
      await tester.pump(Duration.zero);

      expect(
        controller.headerTipNotifier.message,
        'Opening: Alpha - Beta - Thinking...',
      );
    });

    testWidgets("GameHeader position", (WidgetTester tester) async {
      DB.instance = MockDB();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      const Key iconKey = Key("DrawerIcon");

      final CustomDrawerIcon screen = CustomDrawerIcon(
        drawerIcon: IconButton(
          icon: const Icon(Icons.menu, key: iconKey),
          onPressed: () {},
        ),
        child: Scaffold(appBar: GameHeader()),
      );

      await tester.pumpWidget(makeTestableWidget(screen));

      await tester.pumpAndSettle();

      expect(find.byType(HeaderIcons), findsOneWidget);
      expect(find.byKey(const Key("header_icon_row")), findsOneWidget);
    });
  });
}
