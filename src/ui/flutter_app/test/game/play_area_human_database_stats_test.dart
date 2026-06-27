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
}

Widget _localizedApp(Widget child) => MaterialApp(
  localizationsDelegates: sanmillLocalizationsDelegates,
  supportedLocales: S.supportedLocales,
  locale: const Locale('en'),
  home: child,
);
