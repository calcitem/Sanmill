// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/import_game_page.dart';
import 'package:sanmill/game_page/widgets/moves_list_page.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/review/models/review_models.dart';
import 'package:sanmill/review/services/review_storage.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MemoryBox reviewBox;
  late ReviewStorage reviewStorage;

  setUpAll(() async {
    await initRustLibForTests();
    reviewBox = _MemoryBox();
    reviewStorage = ReviewStorage.forTesting(reviewBox);
  });
  tearDownAll(disposeRustLibForTests);

  late MockDB mockDB;

  setUp(() {
    reviewBox.reset();
    mockDB = MockDB();
    DB.instance = mockDB;
    SoundManager.instance = MockAudios();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.reset(force: true);
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets(
    'invalid PGN stays editable with inline feedback',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: const ImportGamePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        '[Site "PlayOK"]\n1. 1 4 2. x5',
      );
      await tester.pump();
      final Finder loadButton = find.byKey(
        const Key('import_game_load_button'),
      );
      expect(tester.widget<FilledButton>(loadButton).onPressed, isNotNull);
      await tester.tap(loadButton);
      await tester.pumpAndSettle();

      final Finder errorMessage = find.byKey(
        const Key('import_game_error_message'),
      );
      expect(errorMessage, findsOne);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('[Site "PlayOK"]\n1. 1 4 2. x5'), findsOne);

      final Rect errorRect = tester.getRect(errorMessage);
      final Rect loadButtonRect = tester.getRect(
        find.byKey(const Key('import_game_load_button')),
      );
      expect(errorRect.bottom, lessThanOrEqualTo(loadButtonRect.top));

      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        'corrected input',
      );
      await tester.pump();
      expect(errorMessage, findsNothing);
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'successful import opens one copy of the edited mainline',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      mockDB.displaySettings = const DisplaySettings(
        movesViewLayout: MovesViewLayout.medium,
        showBranchTree: false,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      int reviewRouteBuildCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: ImportGamePage(
            reviewStorage: reviewStorage,
            reviewPageBuilder:
                (
                  BuildContext context,
                  PrivateGameRecord record,
                  ReviewStorage storage,
                ) {
                  reviewRouteBuildCount++;
                  return Scaffold(
                    appBar: AppBar(title: const Text('Imported review')),
                    body: Text(record.id),
                  );
                },
          ),
        ),
      );

      const String pgnText = '''
[Event "Import test"]
[Variant "Nine Men's Morris"]
[White "Alice"]
[Black "Bob"]
[Result "*"]

1. d6 f4 2. d2 b4 *''';
      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        pgnText,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('import_game_load_button')));
      await _pumpUntilFound(tester, find.byType(MovesListPage));

      expect(find.byType(MovesListPage), findsOneWidget);
      expect(
        GameController().gameRecorder.mainlineMoves.map(
          (ExtMove move) => move.move,
        ),
        <String>['d6', 'f4', 'd2', 'b4'],
      );
      expect(find.byType(MoveListItem), findsNWidgets(4));
      expect(find.text('1. d6'), findsOneWidget);
      expect(find.text('1... f4'), findsOneWidget);
      expect(find.text('2. d2'), findsOneWidget);
      expect(find.text('2... b4'), findsOneWidget);
      expect(
        find.byKey(const Key('moves_list_imported_game_card')),
        findsOneWidget,
      );

      final List<PrivateGameRecord> records = reviewStorage.listGames();
      expect(records, hasLength(1));
      expect(records.single.white, 'Alice');
      expect(records.single.black, 'Bob');
      expect(records.single.result, '*');
      expect(records.single.isCompleted, isFalse);
      expect(records.single.moveCount, 4);

      await tester.tap(
        find.byKey(const Key('moves_list_review_imported_game_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Imported review'), findsOneWidget);
      expect(reviewRouteBuildCount, 1);

      Navigator.of(tester.element(find.text('Imported review'))).pop();
      await _pumpUntilGone(tester, find.text('Imported review'));
      expect(find.byType(MovesListPage), findsOneWidget);
      expect(
        find.byKey(const Key('moves_list_imported_game_card')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('moves_list_imported_game_card_dismiss')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('moves_list_imported_game_card')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('moves_list_more_menu_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('moves_list_menu_review_game')),
        findsOneWidget,
      );
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'completed PlayOK import is retained in private history',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      mockDB.displaySettings = const DisplaySettings(
        movesViewLayout: MovesViewLayout.medium,
        showBranchTree: false,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: ImportGamePage(reviewStorage: reviewStorage),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        _completedPlayOkGame,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('import_game_load_button')));
      await _pumpUntilFound(tester, find.byType(MovesListPage));

      final List<PrivateGameRecord> records = reviewStorage.listGames();
      expect(records, hasLength(1));
      expect(records.single.white, 'gyorgyusz');
      expect(records.single.black, 'nft7489g');
      expect(records.single.result, '1-0');
      expect(records.single.isCompleted, isTrue);
      expect(records.single.moveCount, 41);
      expect(reviewStorage.completedGamesOn(DateTime.now()), 1);
      expect(
        find.byKey(const Key('moves_list_imported_game_card')),
        findsOneWidget,
      );
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'archive failure keeps the imported game page visible with feedback',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: ImportGamePage(
            reviewStorage: ReviewStorage.forTesting(_FailingBox()),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        '1. d6 f4 *',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('import_game_load_button')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('import_game_error_message')),
      );

      expect(find.byType(ImportGamePage), findsOneWidget);
      expect(find.byType(MovesListPage), findsNothing);
      expect(
        find.text(
          'The game was imported, but could not be saved to private history. '
          'Try again.',
        ),
        findsOneWidget,
      );
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'imported variations disclose mainline-only review',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      mockDB.displaySettings = const DisplaySettings(
        movesViewLayout: MovesViewLayout.medium,
        showBranchTree: false,
      );

      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);
      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: ImportGamePage(reviewStorage: reviewStorage),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        '1. d6 f4 (1... b4) 2. d2 *',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('import_game_load_button')));
      await tester.pump();
      expect(find.text('All variations'), findsOneWidget);
      await tester.tap(find.text('All variations'));
      await _pumpUntilFound(tester, find.byType(MovesListPage));

      expect(
        find.byKey(const Key('moves_list_imported_game_variations_notice')),
        findsOneWidget,
      );
      expect(reviewStorage.listGames(), hasLength(1));
      expect(reviewStorage.listGames().single.sourcePgn, contains('('));
    },
    skip: nativeLibrarySkipReason() != null,
  );
}

const String _completedPlayOkGame = '''
[Event "?"]
[Site "PlayOK"]
[Date "2026.03.11"]
[Round "-"]
[White "gyorgyusz"]
[Black "nft7489g"]
[Result "1-0"]
[Time "19:16:16"]
[TimeControl "300"]
[GameType "70,0"]
[WhiteElo "1265"]
[BlackElo "1147"]

1. 5 13 2. 20 19 3. 14 21 4. 7 8 5.
23 17 6. 12 16 7. 18 11 8. 4 6 9.
10 22 10.
23-24 22-23 11. 24-15 23-22 12.
15-3 13-9 13. 18-13 22-23 14. 5-2
17-18 15.
10-1x23 8-5 16. 7-8 16-17 17.
12-16 11-10 18. 4-11 5-4 19. 2-5
10-22 20.
3-15x22 1-0''';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
}

class _MemoryBox extends Fake implements Box<dynamic> {
  final Map<dynamic, dynamic> _values = <dynamic, dynamic>{};

  void reset() => _values.clear();

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    return _values[key] ?? defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}

class _FailingBox extends _MemoryBox {
  @override
  Future<void> put(dynamic key, dynamic value) {
    throw StateError('Test archive failure');
  }
}
