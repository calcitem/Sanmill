// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area_human_database_stats_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_bottom_bar.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDB db;

  setUp(() {
    db = MockDB();
    db.generalSettings = const GeneralSettings(showHumanDatabaseStats: true);
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    DB.instance = db;
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets('human database stats strip reserves space above the board', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('test_board_square'),
              dimension: 390,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder strip = find.byKey(
      const Key('play_area_human_database_stats_strip'),
    );
    final Finder header = find.byKey(const Key('play_area_game_header'));
    final Finder board = find.byKey(const Key('play_area_native_screenshot'));
    expect(strip, findsOneWidget);
    expect(header, findsOneWidget);
    expect(board, findsOneWidget);
    expect(tester.getSize(strip).height, greaterThan(0));
    final DecoratedBox statsBox = tester.widget<DecoratedBox>(
      find.byKey(const Key('play_area_human_database_stats')),
    );
    final BoxDecoration statsDecoration = statsBox.decoration as BoxDecoration;
    final ThemeData theme = Theme.of(tester.element(strip));
    expect(statsDecoration.color, isNot(Colors.white));
    expect(
      statsDecoration.color,
      isNot(theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82)),
    );
    expect(
      find.text('No human database stats for this position'),
      findsOneWidget,
    );
    expect(find.text('Human game database'), findsNothing);
    expect(
      find.byKey(const Key('play_area_human_database_stats_empty')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(strip).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(header).dy),
    );
    expect(
      tester.getBottomLeft(strip).dy,
      lessThanOrEqualTo(tester.getTopLeft(board).dy),
    );
    expect(
      find.byKey(const Key('play_area_human_database_stats_overlay')),
      findsNothing,
    );
  });

  testWidgets('human vs ai uses lichess-style bottom toolbar', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    GameController().gameInstance.gameMode = GameMode.humanVsAi;

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('test_board_square'),
              dimension: 390,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_lichess_bottom_bar')), findsOne);
    expect(find.byKey(const Key('play_area_bottom_bar_menu')), findsOne);
    expect(find.byKey(const Key('play_area_bottom_bar_resign')), findsOne);
    expect(find.byKey(const Key('play_area_bottom_bar_take_back')), findsOne);
    expect(find.byKey(const Key('play_area_bottom_bar_hint')), findsOne);
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_lichess_bottom_bar')))
          .height,
      kLichessBottomBarHeight,
    );

    final Opacity menuOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_menu')),
        matching: find.byType(Opacity),
      ),
    );
    expect(menuOpacity.opacity, 1);

    final Opacity resignOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_resign')),
        matching: find.byType(Opacity),
      ),
    );
    expect(resignOpacity.opacity, 0.4);

    expect(find.byKey(const Key('play_area_main_toolbar')), findsNothing);
    expect(
      find.byKey(const Key('play_area_main_toolbar_bottom')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_history_nav_toolbar')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_history_nav_toolbar_bottom')),
      findsNothing,
    );
    expect(find.byKey(const Key('play_area_toolbar_item_info')), findsNothing);
    expect(
      tester
          .getBottomLeft(find.byKey(const Key('play_area_lichess_bottom_bar')))
          .dy,
      tester
          .getBottomLeft(
            find.byKey(const Key('play_area_sized_box_toolbar_bottom')),
          )
          .dy,
    );

    RotatedBox boardOrientation = tester.widget<RotatedBox>(
      find.byKey(const Key('play_area_board_orientation')),
    );
    expect(boardOrientation.quarterTurns, 0);

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_game_menu_sheet')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_flip_board')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_analysis')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_new_game')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_game_menu_analysis')));
    await tester.pumpAndSettle();

    final Finder analysisPanel = find.byKey(
      const Key('analysis_panel_page_scaffold'),
    );
    expect(analysisPanel, findsOneWidget);
    final BuildContext analysisPanelContext = tester.element(analysisPanel);
    final Scaffold analysisPanelScaffold = tester.widget<Scaffold>(
      analysisPanel,
    );
    expect(
      analysisPanelScaffold.backgroundColor,
      Theme.of(analysisPanelContext).colorScheme.surface,
    );
    expect(find.text('Analysis'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_game_menu_flip_board')));
    await tester.pumpAndSettle();

    boardOrientation = tester.widget<RotatedBox>(
      find.byKey(const Key('play_area_board_orientation')),
    );
    expect(boardOrientation.quarterTurns, 2);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  localizationsDelegates: sanmillLocalizationsDelegates,
  supportedLocales: S.supportedLocales,
  locale: const Locale('en'),
  home: child,
);
