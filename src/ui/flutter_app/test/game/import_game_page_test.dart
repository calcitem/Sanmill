// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/import_game_page.dart';
import 'package:sanmill/game_page/widgets/moves_list_page.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
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

  late MockDB mockDB;

  setUp(() {
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

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: const ImportGamePage(),
        ),
      );

      const String pgnText = '''
[Event "Import test"]
[Variant "Nine Men's Morris"]
[Result "*"]

1. d6 f4 2. d2 b4 *''';
      await tester.enterText(
        find.byKey(const Key('import_game_paste_field')),
        pgnText,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('import_game_load_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

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
    },
    skip: nativeLibrarySkipReason() != null,
  );
}
