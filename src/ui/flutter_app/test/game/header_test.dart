// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// header_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n_en.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  tearDown(() {
    DB.instance = null;
  });

  group("GameHeader", () {
    test('GameHeader ignores the legacy board-top preference', () {
      final MockDB db = MockDB();
      DB.instance = db;

      db.displaySettings = const DisplaySettings(boardTop: 0);
      final Size zeroSpacingSize = const GameHeader().preferredSize;

      db.displaySettings = const DisplaySettings(boardTop: 288);
      final Size legacySpacingSize = const GameHeader().preferredSize;

      expect(legacySpacingSize, zeroSpacingSize);
      expect(legacySpacingSize.height, kToolbarHeight + AppTheme.boardMargin);
    });

    testWidgets("GameHeader updates its contextual tip", (
      WidgetTester tester,
    ) async {
      const String testString = "Test";

      final MockDB db = MockDB();
      db.generalSettings = const GeneralSettings(showGameTips: true);
      DB.instance = db;
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;
      controller.headerTipNotifier.showTip('', snackBar: false);

      await tester.pumpWidget(
        makeTestableWidget(
          const Center(
            child: SizedBox(width: 360, height: 64, child: GameHeader()),
          ),
        ),
      );

      expect(find.text(SEn().welcome), findsOneWidget);

      controller.headerTipNotifier.showTip(testString, snackBar: false);
      await tester.pumpAndSettle();

      expect(find.text(testString), findsOneWidget);
      expect(find.byKey(const Key('game_header_contextual_tip')), findsOne);
    });

    testWidgets("GameTipBubble bounds a long tip on narrow widths", (
      WidgetTester tester,
    ) async {
      const String message =
          'Opening: Very long guidance that must remain inside the player row';

      await tester.pumpWidget(
        makeTestableWidget(
          const Center(
            child: SizedBox(width: 140, child: GameTipBubble(message: message)),
          ),
        ),
      );

      expect(find.byTooltip(message), findsOneWidget);
      expect(
        tester.getSize(find.byType(GameTipBubble)).width,
        lessThanOrEqualTo(140),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets("HeaderTipNotifier normalizes unsafe punctuation", (
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

    testWidgets("GameHeader hides when game tips are disabled", (
      WidgetTester tester,
    ) async {
      DB.instance = MockDB();
      final GameController controller = GameController();
      controller.gameInstance.gameMode = GameMode.humanVsHuman;

      await tester.pumpWidget(
        makeTestableWidget(
          const Center(
            child: SizedBox(width: 360, height: 64, child: GameHeader()),
          ),
        ),
      );

      expect(find.byKey(const Key('game_header_hidden')), findsOneWidget);
      expect(find.byKey(const Key('game_header_contextual_row')), findsNothing);
    });
  });
}
