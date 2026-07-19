// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/saved_games_page.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  late Directory savedGamesDirectory;
  late NativeMillGameSession session;

  setUp(() {
    savedGamesDirectory = Directory.systemTemp.createTempSync(
      'sanmill_saved_games_navigation_test_',
    );
    final MockDB db = MockDB();
    db.generalSettings = GeneralSettings(
      lastPgnSaveDirectory: savedGamesDirectory.path,
    );
    DB.instance = db;
    SoundManager.instance = MockAudios();

    session = NativeMillGameSession();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller
      ..bindActiveSession(session)
      ..gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    GameController().unbindActiveSession(session);
    session.dispose();
    DB.instance = null;
    savedGamesDirectory.deleteSync(recursive: true);
  });

  testWidgets(
    'loading a saved game returns exactly one navigation level',
    (WidgetTester tester) async {
      final File file = File('${savedGamesDirectory.path}/example.pgn');
      file.writeAsStringSync(_validPgn);
      int loadedCallbacks = 0;

      await tester.pumpWidget(
        _testApp(entry: _entry(file), onGameLoaded: () => loadedCallbacks++),
      );
      await tester.tap(find.byKey(const Key('open_saved_games')));
      await tester.pumpAndSettle();
      _openEntry(tester, file);
      await _waitForFileLoad(tester, () => loadedCallbacks == 1);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(GameController().loadedGameSourcePath, file.absolute.path);
      expect(loadedCallbacks, 1);
      expect(find.byKey(const Key('saved_games_parent')), findsOneWidget);
      expect(find.text('Saved games'), findsNothing);
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'a failed saved-game load keeps the library open',
    (WidgetTester tester) async {
      final File file = File('${savedGamesDirectory.path}/invalid.pgn');
      file.writeAsStringSync('1. z9');
      int loadedCallbacks = 0;

      await tester.pumpWidget(
        _testApp(entry: _entry(file), onGameLoaded: () => loadedCallbacks++),
      );
      await tester.tap(find.byKey(const Key('open_saved_games')));
      await tester.pumpAndSettle();
      _openEntry(tester, file);
      await _waitForFileLoad(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Saved games'), findsOneWidget);
      expect(find.byKey(Key('saved_game_${file.path}')), findsOneWidget);
      expect(loadedCallbacks, 0);
    },
    skip: nativeLibrarySkipReason() != null,
  );
}

void _openEntry(WidgetTester tester, File file) {
  final Finder inkWell = find.ancestor(
    of: find.text(file.uri.pathSegments.last),
    matching: find.byType(InkWell),
  );
  tester.widget<InkWell>(inkWell.first).onTap!();
}

Future<void> _waitForFileLoad(
  WidgetTester tester, [
  bool Function()? isDone,
]) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (isDone?.call() ?? false) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

SavedGameEntry _entry(File file) {
  return SavedGameEntry(
    path: file.path,
    filename: file.uri.pathSegments.last,
    modified: DateTime(2026),
    isLoading: false,
  );
}

Widget _testApp({
  required SavedGameEntry entry,
  required VoidCallback onGameLoaded,
}) {
  return MaterialApp(
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    localizationsDelegates: sanmillLocalizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      key: const Key('saved_games_parent'),
      body: Builder(
        builder: (BuildContext context) {
          return TextButton(
            key: const Key('open_saved_games'),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SavedGamesPage(
                    initialEntries: <SavedGameEntry>[entry],
                    onGameLoaded: onGameLoaded,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          );
        },
      ),
    ),
  );
}

const String _validPgn = '''
[Event "Sanmill-Game"]
[Site "Sanmill"]
[Date "2026.7.19"]
[Round "1"]
[White "Human"]
[Black "Computer"]
[Result "*"]
[Variant "Nine Men's Morris"]
[PlyCount "4"]

1. d2 f4
2. f2 d6
''';
