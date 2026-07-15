// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Regression: importing a move list must replay through the active native
// session when HistoryNavigator.takeBackAll / stepForwardAll run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

/// Replays [moves] through a throwaway port and returns the resulting FEN so
/// the test can assert the session reached the same position the importer did.
String _expectedFenAfter(List<String> moves) {
  final NativeMillRulesPort port = NativeMillRulesPort(
    ruleSettings: DB().ruleSettings,
    generalSettings: DB().generalSettings,
  );
  try {
    for (final String move in moves) {
      GameAction? action;
      for (final GameAction candidate in port.legalActions) {
        if (MillActionCodec.moveStringFrom(candidate) == move) {
          action = candidate;
          break;
        }
      }
      if (action == null) {
        throw StateError('Move $move is illegal while building expected FEN');
      }
      port.apply(action);
    }
    return port.exportFen();
  } finally {
    port.dispose();
  }
}

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

  // The Game -> Import game menu runs on a modal route whose BuildContext is
  // inserted above the GameSessionScope, so the scope lookup misses.  The
  // navigator must instead fall back to the controller-bound session.  This
  // test reproduces that exact shape: the context driving navigation is NOT
  // under any GameSessionScope, and the session is reachable only via
  // GameController.bindActiveSession.
  testWidgets(
    'import replays through the controller-bound session (modal context)',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));

      late BuildContext aboveScopeContext;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (BuildContext context) {
              // Captured above the scope on purpose (mirrors a modal route).
              aboveScopeContext = context;
              return GameSessionScope(
                session: session,
                child: const SizedBox.shrink(),
              );
            },
          ),
        ),
      );

      // Sanity check: this context cannot see the session through the scope.
      expect(GameSessionScope.sessionOf(aboveScopeContext), isNull);

      // Seed an unrelated on-board move so the session has history to discard.
      await session.apply(_findAction(session.legalActions, 'a1'));

      // The user's reported move list: a full placing + moving-phase game.
      const String pgn = '''
1. d6 f4
2. d2 b4
3. e4 d5
4. c4 d3
5. g4 d7
6. a4 d1
7. e5 e3
8. c3 c5
9. f6 b6
10. a4-a7 b4-a4
11. c4-b4 c5-c4
12. g4-g1 d7-g7
13. g1-g4 g7-d7
14. g4-g1 d7-g7
15. g1-g4 d1-g1
16. a7-d7 g1-d1''';

      ImportService.import(pgn);
      expect(GameController().newGameRecorder, isNotNull);

      final HistoryResponse? takeBackResp = await HistoryNavigator.takeBackAll(
        aboveScopeContext,
        pop: false,
      );
      expect(takeBackResp, const HistoryOK());
      // Adopting the staged recorder is the signal that the native replay path
      // (not the undo/redo fast path) handled the navigation.
      expect(GameController().newGameRecorder, isNull);

      final HistoryResponse? forwardResp =
          await HistoryNavigator.stepForwardAll(aboveScopeContext, pop: false);
      expect(forwardResp, const HistoryOK());

      final List<String> expectedMoves = GameController()
          .gameRecorder
          .mainlineMoves
          .map((ExtMove m) => m.move)
          .toList();
      expect(expectedMoves.first, 'd6');
      expect(expectedMoves.last, 'g1-d1');

      // The board (session) must now match the fully replayed move list.
      expect(session.getFen(), _expectedFenAfter(expectedMoves));

      await tester.pumpAndSettle();
    },
    skip: nativeLibrarySkipReason() != null,
  );

  // Regression: loading a short, freshly-started game (only a few placing
  // moves, full PGN tag pairs, tab/space-padded move text) reported "Load
  // failed" even though ImportService.import succeeded. Reproduces the
  // exact saved-game content from the bug report on a session with no prior
  // history, mirroring a fresh app launch.
  testWidgets(
    'import replays a short tag-paired PGN on a fresh session',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));

      late BuildContext aboveScopeContext;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (BuildContext context) {
              aboveScopeContext = context;
              return GameSessionScope(
                session: session,
                child: const SizedBox.shrink(),
              );
            },
          ),
        ),
      );

      const String pgn = '''
[Event "Sanmill-Game"]
[Site "Sanmill"]
[Date "2026.1.27"]
[Round "1"]
[White "Human"]
[Black "AI"]
[Result "*"]
[Variant "Nine Men's Morris"]
[PlyCount "4"]

 1.    d2    f4
 2.    f2    d6''';

      ImportService.import(pgn);
      expect(GameController().newGameRecorder, isNotNull);

      final HistoryResponse? takeBackResp = await HistoryNavigator.takeBackAll(
        aboveScopeContext,
        pop: false,
      );
      expect(takeBackResp, const HistoryOK());
      expect(GameController().newGameRecorder, isNull);

      final HistoryResponse? forwardResp =
          await HistoryNavigator.stepForwardAll(aboveScopeContext, pop: false);
      expect(forwardResp, const HistoryOK());

      final List<String> expectedMoves = GameController()
          .gameRecorder
          .mainlineMoves
          .map((ExtMove m) => m.move)
          .toList();
      expect(expectedMoves, <String>['d2', 'f4', 'f2', 'd6']);
      expect(session.getFen(), _expectedFenAfter(expectedMoves));

      await tester.pumpAndSettle();
    },
    skip: nativeLibrarySkipReason() != null,
  );

  testWidgets(
    'history replay can suppress the success snackbar for home launches',
    (WidgetTester tester) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      GameController().bindActiveSession(session);
      addTearDown(() => GameController().unbindActiveSession(session));

      late BuildContext launchContext;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          localizationsDelegates: sanmillLocalizationsDelegates,
          supportedLocales: S.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (BuildContext context) {
              launchContext = context;
              return GameSessionScope(
                session: session,
                child: const Scaffold(body: SizedBox.shrink()),
              );
            },
          ),
        ),
      );

      ImportService.import('1. d6 f4');
      await LoadService.handleHistoryNavigation(
        launchContext,
        showSuccessMessage: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Done'), findsNothing);
      expect(
        GameController().gameRecorder.mainlineMoves.map(
          (ExtMove move) => move.move,
        ),
        <String>['d6', 'f4'],
      );
    },
    skip: nativeLibrarySkipReason() != null,
  );
}

GameAction _findAction(List<GameAction> actions, String move) {
  for (final GameAction action in actions) {
    if (MillActionCodec.moveStringFrom(action) == move) {
      return action;
    }
  }
  throw StateError('No legal action matches $move');
}
