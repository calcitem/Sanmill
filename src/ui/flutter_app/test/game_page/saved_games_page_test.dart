// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/widgets/saved_games_page.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/locale_helper.dart';
import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory savedGamesDirectory;

  setUp(() {
    savedGamesDirectory = Directory.systemTemp.createTempSync(
      'sanmill_saved_games_test_',
    );
    final MockDB db = MockDB();
    db.generalSettings = GeneralSettings(
      lastPgnSaveDirectory: savedGamesDirectory.path,
    );
    DB.instance = db;
  });

  tearDown(() {
    savedGamesDirectory.deleteSync(recursive: true);
  });

  testWidgets('labels the saved-game library and its empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(makeTestableWidget(const SavedGamesPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Saved games'), findsOneWidget);
    expect(find.text('No saved games yet.'), findsOneWidget);
    expect(find.text('Load game'), findsNothing);
  });
}
