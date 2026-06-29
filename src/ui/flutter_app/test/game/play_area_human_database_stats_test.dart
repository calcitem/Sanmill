// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area_human_database_stats_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_bottom_bar.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustLibForTests);
  tearDownAll(disposeRustLibForTests);

  late MockDB db;

  setUp(() {
    db = MockDB();
    db.generalSettings = const GeneralSettings(showHumanDatabaseStats: true);
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    DB.instance = db;
    SoundManager.instance = MockAudios();
    final GameController controller = GameController();
    controller.animationManager = MockAnimationManager();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
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

  testWidgets('regular game toolbar stays pinned to the bottom', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

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

    expect(find.byKey(const Key('play_area_main_toolbar')), findsNothing);
    expect(
      find.byKey(const Key('play_area_main_toolbar_bottom')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_menu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_resign_result')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_previous')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_next')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('play_area_toolbar_item_info')), findsNothing);
    expect(
      tester
          .getBottomLeft(find.byKey(const Key('play_area_main_toolbar_bottom')))
          .dy,
      lessThanOrEqualTo(
        tester
            .getBottomLeft(
              find.byKey(const Key('play_area_sized_box_toolbar_bottom')),
            )
            .dy,
      ),
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
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_resign')),
        matching: find.byIcon(CupertinoIcons.flag),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_take_back')),
        matching: find.byIcon(CupertinoIcons.arrow_uturn_left),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_hint')),
        matching: find.byIcon(CupertinoIcons.lightbulb),
      ),
      findsOneWidget,
    );
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
    final Finder board = find.byKey(const Key('play_area_native_screenshot'));
    final Finder humanAiMoveList = find.byKey(
      const Key('play_area_human_ai_move_list'),
    );
    final Finder robotPanel = find.byKey(
      const Key('play_area_human_ai_robot_panel'),
    );
    final Finder playerPanel = find.byKey(
      const Key('play_area_human_ai_player_panel'),
    );
    expect(humanAiMoveList, findsOneWidget);
    expect(robotPanel, findsOneWidget);
    expect(playerPanel, findsOneWidget);
    expect(
      find.byKey(const Key('play_area_human_ai_robot_title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_human_ai_player_title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('play_area_piece_count_row')), findsNothing);
    expect(
      find.byKey(const Key('play_area_removed_piece_count_row')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(humanAiMoveList).dy,
      lessThan(tester.getTopLeft(robotPanel).dy),
    );
    expect(
      tester.getTopLeft(robotPanel).dy,
      lessThan(tester.getTopLeft(board).dy),
    );
    expect(
      tester.getTopLeft(playerPanel).dy,
      greaterThan(tester.getTopLeft(board).dy),
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_game_menu_sheet')), findsOne);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('play_area_game_menu_flip_board')), findsOne);
    expect(
      find.byKey(const Key('play_area_game_menu_board_orientation')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_game_menu_transform_swap_rotate_180')),
      findsNothing,
    );
    expect(find.byKey(const Key('play_area_game_menu_analysis')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_resign')), findsNothing);
    expect(find.byKey(const Key('play_area_game_menu_new_game')), findsOne);

    await tester.tap(
      find.byKey(const Key('play_area_game_menu_board_orientation')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_board_transform_sheet')), findsOne);
    expect(find.byKey(const Key('play_area_board_transform_rotate')), findsOne);
    expect(
      find.byKey(const Key('play_area_board_transform_horizontal_flip')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_board_transform_vertical_flip')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_board_transform_inner_outer_flip')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_board_transform_swap_rotate_180')),
      findsNothing,
    );

    Navigator.of(
      tester.element(find.byKey(const Key('play_area_board_transform_sheet'))),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_game_menu_new_game')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('human_ai_new_game_sheet')), findsOne);
    expect(
      find.byKey(const Key('human_ai_new_game_sheet_skill_slider')),
      findsOne,
    );
    expect(
      find.byKey(const Key('human_ai_new_game_sheet_move_time_slider')),
      findsOne,
    );
    expect(
      find.byKey(const Key('human_ai_new_game_sheet_side_picker')),
      findsOne,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('human_ai_new_game_sheet')), findsNothing);

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

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
    expect(find.byKey(const Key('play_area_human_ai_robot_panel')), findsOne);
    expect(find.byKey(const Key('play_area_human_ai_player_panel')), findsOne);
  });

  testWidgets('human vs ai route asks before leaving an active game', (
    WidgetTester tester,
  ) async {
    db = _GamePageDb(
      generalSettings: const GeneralSettings(),
      displaySettings: const DisplaySettings(
        isUnplacedAndRemovedPiecesShown: false,
        isHistoryNavigationToolbarShown: false,
      ),
    );
    DB.instance = db;

    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        GameSessionScope(
          session: session,
          child: Navigator(
            onGenerateRoute: (RouteSettings settings) {
              if (settings.name == '/game') {
                return MaterialPageRoute<void>(
                  builder: (_) => const GamePage(GameMode.humanVsAi),
                );
              }
              return MaterialPageRoute<void>(
                builder: (BuildContext context) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        key: const Key('open_human_ai_game_page'),
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/game'),
                        child: const Text('Open game'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open_human_ai_game_page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('game_page_scaffold')), findsOneWidget);
    expect(find.byKey(const Key('game_page_back_button')), findsOneWidget);
    expect(find.byKey(const Key('human_ai_new_game_sheet')), findsOneWidget);

    Navigator.of(
      tester.element(find.byKey(const Key('human_ai_new_game_sheet'))),
    ).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('human_ai_new_game_sheet')), findsNothing);

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
        ExtMove('f4', side: PieceColor.black),
      ]),
      isTrue,
    );
    await tester.pump();
    expect(_currentPathMoves(), <String>['d6', 'f4']);

    await tester.tap(find.byKey(const Key('game_page_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('game_page_leave_dialog')), findsOneWidget);
    expect(find.text('Leave current game?'), findsOneWidget);
    expect(find.text('No worries, your game will be kept.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('game_page_leave_cancel_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('game_page_leave_dialog')), findsNothing);
    expect(find.byKey(const Key('game_page_scaffold')), findsOneWidget);

    await tester.tap(find.byKey(const Key('game_page_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('game_page_leave_confirm_button')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('open_human_ai_game_page')), findsOneWidget);
    expect(find.byKey(const Key('game_page_scaffold')), findsNothing);
  });

  testWidgets('human vs ai hint is disabled while AI is to move', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings(aiMovesFirst: true);
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
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_hint')),
      0.4,
    );
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_menu')),
      1.0,
    );
  });

  testWidgets('human vs ai resign is disabled while game is abortable', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    await _pumpSessionPlayArea(tester, session);
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_resign')),
      0.4,
    );

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
      ]),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_resign')),
      0.4,
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play_area_game_menu_resign')), findsNothing);
  });

  testWidgets('human vs ai bottom resign is enabled after both sides moved', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
        ExtMove('f4', side: PieceColor.black),
      ]),
      isTrue,
    );
    await tester.pump();

    await _pumpSessionPlayArea(tester, session);
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_resign')),
      1.0,
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play_area_game_menu_resign')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_game_menu_resign')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_resign_cancel_button')), findsOne);
    expect(find.byKey(const Key('play_area_resign_confirm_button')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_resign_cancel_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_resign')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_resign_cancel_button')), findsOne);
    expect(find.byKey(const Key('play_area_resign_confirm_button')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_resign_cancel_button')));
    await tester.pumpAndSettle();
  });

  testWidgets('human vs ai takeback removes a full player turn', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
        ExtMove('f4', side: PieceColor.black),
      ]),
      isTrue,
    );
    await tester.pump();
    expect(_currentPathMoves(), <String>['d6', 'f4']);
    expect(GameController().gameInstance.isHumanToMove, isTrue);

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), isEmpty);
    expect(session.undoDepth, 0);
  });

  testWidgets('human vs ai takeback removes one move during AI turn', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
      ]),
      isTrue,
    );
    await tester.pump();
    expect(_currentPathMoves(), <String>['d6']);
    expect(GameController().gameInstance.isHumanToMove, isFalse);

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), isEmpty);
    expect(session.undoDepth, 0);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  scaffoldMessengerKey: rootScaffoldMessengerKey,
  localizationsDelegates: sanmillLocalizationsDelegates,
  supportedLocales: S.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

double _bottomBarButtonOpacity(WidgetTester tester, Key key) {
  final Opacity opacity = tester.widget<Opacity>(
    find.descendant(of: find.byKey(key), matching: find.byType(Opacity)),
  );
  return opacity.opacity;
}

Future<NativeMillGameSession> _bindNativeHumanAiGame() async {
  final GameController controller = GameController();
  controller.reset(force: true);
  controller.gameInstance.gameMode = GameMode.humanVsAi;
  final NativeMillGameSession session = NativeMillGameSession();
  controller.bindActiveSession(session);

  void listener() {
    controller.activeSessionSnapshot = session.state.value;
  }

  session.state.addListener(listener);
  controller.activeSessionSnapshot = session.state.value;
  addTearDown(() {
    session.state.removeListener(listener);
    controller.unbindActiveSession(session);
    session.dispose();
  });
  return session;
}

Future<void> _pumpSessionPlayArea(
  WidgetTester tester,
  NativeMillGameSession session,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    _localizedApp(
      GameSessionScope(
        session: session,
        child: const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('test_board_square'),
              dimension: 390,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _currentPathMoves() {
  return GameController().gameRecorder.currentPath
      .map((ExtMove move) => move.move)
      .toList();
}

class _GamePageDb extends MockDB {
  _GamePageDb({
    required GeneralSettings generalSettings,
    required DisplaySettings displaySettings,
  }) : _generalSettingsListenable = ValueNotifier<Box<GeneralSettings>>(
         _SettingsBox<GeneralSettings>(DB.generalSettingsKey, generalSettings),
       ),
       _displaySettingsListenable = ValueNotifier<Box<DisplaySettings>>(
         _SettingsBox<DisplaySettings>(DB.displaySettingsKey, displaySettings),
       ) {
    this.generalSettings = generalSettings;
    this.displaySettings = displaySettings;
  }

  final ValueNotifier<Box<GeneralSettings>> _generalSettingsListenable;
  final ValueNotifier<Box<DisplaySettings>> _displaySettingsListenable;

  @override
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings {
    return _generalSettingsListenable;
  }

  @override
  ValueListenable<Box<DisplaySettings>> get listenDisplaySettings {
    return _displaySettingsListenable;
  }
}

class _SettingsBox<T> extends Fake implements Box<T> {
  _SettingsBox(this.settingsKey, this.value);

  final String settingsKey;
  final T value;

  @override
  T? get(dynamic key, {T? defaultValue}) {
    return key == settingsKey ? value : defaultValue;
  }
}
