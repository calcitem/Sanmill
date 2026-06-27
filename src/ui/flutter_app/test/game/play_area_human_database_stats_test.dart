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

  testWidgets('human database stats are overlaid inside the board', (
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

    final Finder overlay = find.byKey(
      const Key('play_area_human_database_stats_overlay'),
    );
    expect(overlay, findsOneWidget);
    expect(
      find.ancestor(
        of: overlay,
        matching: find.byKey(const Key('play_area_game_board_stack')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_human_database_stats_padding')),
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
