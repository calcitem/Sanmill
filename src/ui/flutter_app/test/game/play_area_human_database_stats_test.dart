// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area_human_database_stats_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/player_timer.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart' as platform;
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
    controller.gameRecorder.reset();
    controller.isEngineRunning = false;
    controller.isEngineInDelay = false;
    PlayerTimer().reset();
  });

  tearDown(() {
    PlayerTimer().reset();
    DB.instance = null;
  });

  testWidgets('human database stats strip sits near the bottom bar', (
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
    final Finder board = find.byKey(const Key('play_area_native_screenshot'));
    final Finder bottomBar = find.byKey(
      const Key('play_area_main_toolbar_bottom'),
    );
    expect(strip, findsOneWidget);
    expect(board, findsOneWidget);
    expect(bottomBar, findsOneWidget);
    expect(tester.getSize(strip).height, greaterThan(0));
    final DecoratedBox statsBox = tester.widget<DecoratedBox>(
      find.byKey(const Key('play_area_human_database_stats')),
    );
    final BoxDecoration statsDecoration = statsBox.decoration as BoxDecoration;
    expect(statsDecoration.color, Colors.transparent);
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
      greaterThanOrEqualTo(tester.getBottomLeft(board).dy),
    );
    expect(
      tester.getBottomLeft(strip).dy,
      lessThanOrEqualTo(tester.getTopLeft(bottomBar).dy),
    );
    expect(
      find.byKey(const Key('play_area_human_database_stats_overlay')),
      findsNothing,
    );
  });

  testWidgets('human database stats strip uses compact sample text', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.humanVsHuman,
    );
    session.lastHumanDatabaseMoveStats = const HumanDatabaseMoveStats(
      notation: 'd6',
      wins: 50,
      draws: 30,
      losses: 20,
      total: 100,
      scoreDelta: 0,
    );

    await _pumpSessionPlayArea(tester, session);

    expect(find.textContaining('Human Database'), findsNothing);
    expect(find.textContaining('Human game database'), findsNothing);
    expect(find.textContaining('n=100'), findsOneWidget);
    expect(find.textContaining('d6'), findsOneWidget);
  });

  testWidgets('regular game uses a Lichess-style inline move list', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white),
    );
    GameController().gameRecorder.appendMove(
      ExtMove('f4', side: PieceColor.black),
    );

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

    expect(
      find.byKey(const Key('play_area_regular_move_list_wrap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_inline_move_list_scroll_view')),
      findsOneWidget,
    );
    final SingleChildScrollView moveListScrollView = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('play_area_inline_move_list_scroll_view')),
        );
    expect(moveListScrollView.scrollDirection, Axis.horizontal);
    expect(find.byKey(const Key('play_area_regular_round_1')), findsOneWidget);
    expect(find.byKey(const Key('play_area_regular_move_1')), findsOneWidget);
    expect(find.byKey(const Key('play_area_regular_move_2')), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('d6'), findsOneWidget);
    expect(find.text('f4'), findsOneWidget);
    expect(find.text('2. f4'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_regular_move_2')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_human_ai_move_list_wrap')),
      findsNothing,
    );
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
      find.byKey(const Key('play_area_regular_bottom_bar_take_back')),
      findsOneWidget,
    );
    final double headerToBoardGap =
        tester.getTopLeft(find.byKey(const Key('test_board_square'))).dy -
        tester.getBottomLeft(find.byKey(const Key('play_area_game_header'))).dy;
    expect(headerToBoardGap, greaterThanOrEqualTo(0));
    expect(headerToBoardGap, lessThan(120));

    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_regular_bottom_bar_take_back')),
          )
          .label,
      'Take back',
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_previous')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_next')),
      findsNothing,
    );
    expect(find.byKey(const Key('play_area_toolbar_item_info')), findsNothing);

    await tester.tap(
      find.byKey(const Key('play_area_regular_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_regular_game_menu_sheet')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_flip_board')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_board_orientation')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_analysis')),
      findsNothing,
    );
    expect(find.byKey(const Key('play_area_toolbar_item_game')), findsOne);
    expect(find.text('New game'), findsOne);
    expect(find.byKey(const Key('play_area_toolbar_item_move')), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_toolbar_item_move')),
        matching: find.text('Move list'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_move_now')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_previous')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_next')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_take_back')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_resign')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_result')),
      findsNothing,
    );

    expect(
      find.byKey(const Key('play_area_regular_game_menu_board_orientation')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_flip_board')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_regular_board_transform_sheet')),
      findsOne,
    );
    final BuildContext regularRotateActionContext = tester.element(
      find.byKey(const Key('play_area_regular_board_transform_rotate')),
    );
    expect(
      IconTheme.of(regularRotateActionContext).color,
      Theme.of(regularRotateActionContext).colorScheme.onSurfaceVariant,
    );
    expect(
      find.byKey(const Key('play_area_regular_board_transform_rotate')),
      findsOne,
    );
    expect(
      find.byKey(
        const Key('play_area_regular_board_transform_horizontal_flip'),
      ),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_board_transform_vertical_flip')),
      findsOne,
    );
    expect(
      find.byKey(
        const Key('play_area_regular_board_transform_inner_outer_flip'),
      ),
      findsOne,
    );
    expect(
      find.byKey(
        const Key('play_area_regular_board_transform_swap_rotate_180'),
      ),
      findsNothing,
    );

    Navigator.of(
      tester.element(
        find.byKey(const Key('play_area_regular_board_transform_sheet')),
      ),
    ).pop();
    await tester.pumpAndSettle();

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

  testWidgets('regular finite clock shows Lichess-style pause control', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings(humanMoveTime: 30);
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    controller.gameRecorder.reset();
    controller.gameRecorder.appendMove(ExtMove('d6', side: PieceColor.white));
    PlayerTimer().start();

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

    final Finder clockButton = find.byKey(
      const Key('play_area_regular_bottom_bar_clock'),
    );
    expect(clockButton, findsOneWidget);
    expect(tester.widget<LichessBottomBarButton>(clockButton).label, 'Pause');

    await tester.tap(clockButton);
    await tester.pumpAndSettle();
    expect(PlayerTimer().status, PlayerTimerStatus.paused);
    expect(tester.widget<LichessBottomBarButton>(clockButton).label, 'Resume');

    await tester.tap(clockButton);
    await tester.pumpAndSettle();
    expect(PlayerTimer().status, PlayerTimerStatus.running);
    expect(tester.widget<LichessBottomBarButton>(clockButton).label, 'Pause');
    PlayerTimer().reset();
  });

  testWidgets('regular move chip long press opens mini board preview', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        boardLayout: '********/********/O*******',
      ),
    );

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

    await tester.longPress(find.byKey(const Key('play_area_regular_move_1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('play_area_move_preview_dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_move_preview_board')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_move_preview_go_button')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_move_preview_dialog')),
        matching: find.text('1. d6'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_move_preview_close_button')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('human vs ai uses lichess-style bottom toolbar', (
    WidgetTester tester,
  ) async {
    const Color messageTextColor = Color(0xFFE6F4EA);
    db.generalSettings = const GeneralSettings();
    db.colorSettings = const ColorSettings(
      darkBackgroundColor: Color(0xFF006B3F),
      messageColor: messageTextColor,
    );
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
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_bottom_bar_take_back')),
          )
          .label,
      'Take back',
    );
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
    final BottomAppBar bottomAppBar = tester.widget<BottomAppBar>(
      find.descendant(
        of: find.byKey(const Key('play_area_lichess_bottom_bar')),
        matching: find.byType(BottomAppBar),
      ),
    );
    expect(bottomAppBar.color, Colors.transparent);
    expect(bottomAppBar.elevation, 0);
    final BuildContext menuIconContext = tester.element(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_menu')),
        matching: find.byIcon(Icons.menu),
      ),
    );
    expect(IconTheme.of(menuIconContext).color, messageTextColor);
    expect(
      tester.getTopLeft(find.byKey(const Key('play_area_bottom_bar_menu'))).dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('play_area_bottom_bar_resign')))
            .dx,
      ),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('play_area_bottom_bar_resign')))
          .dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('play_area_bottom_bar_take_back')))
            .dx,
      ),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('play_area_bottom_bar_take_back')))
          .dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('play_area_bottom_bar_hint')))
            .dx,
      ),
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

    final RotatedBox boardOrientation = tester.widget<RotatedBox>(
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
    expect(
      tester
          .widget<Text>(find.byKey(const Key('play_area_human_ai_robot_title')))
          .style
          ?.color,
      messageTextColor,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('play_area_human_ai_player_elo')))
          .style
          ?.color,
      messageTextColor.withValues(alpha: 0.72),
    );
    final Finder pieceCountRow = find.byKey(
      const Key('play_area_piece_count_row'),
    );
    final Finder removedPieceCountRow = find.byKey(
      const Key('play_area_removed_piece_count_row'),
    );
    expect(pieceCountRow, findsOneWidget);
    expect(removedPieceCountRow, findsOneWidget);
    expect(
      find.byKey(const Key('play_area_advantage_indicator')),
      findsOneWidget,
    );
    final double robotToBoardTableGap =
        tester.getTopLeft(pieceCountRow).dy -
        tester.getBottomLeft(robotPanel).dy;
    final double boardTableToPlayerGap =
        tester.getTopLeft(playerPanel).dy -
        tester.getBottomLeft(removedPieceCountRow).dy;
    expect(robotToBoardTableGap, greaterThanOrEqualTo(0));
    expect(robotToBoardTableGap, lessThanOrEqualTo(16));
    expect(boardTableToPlayerGap, greaterThanOrEqualTo(0));
    expect(boardTableToPlayerGap, lessThanOrEqualTo(16));
    expect(
      tester.getTopLeft(humanAiMoveList).dy,
      lessThan(tester.getTopLeft(robotPanel).dy),
    );
    expect(
      tester.getTopLeft(robotPanel).dy,
      lessThan(tester.getTopLeft(pieceCountRow).dy),
    );
    expect(
      tester.getTopLeft(pieceCountRow).dy,
      lessThan(tester.getTopLeft(board).dy),
    );
    final Finder shell = find.byKey(
      const Key('play_area_sized_box_toolbar_bottom'),
    );
    final Finder bottomBar = find.byKey(
      const Key('play_area_lichess_bottom_bar'),
    );
    final double playableCenterY =
        tester.getTopLeft(shell).dy +
        (tester.getTopLeft(bottomBar).dy - tester.getTopLeft(shell).dy) / 2;
    expect(tester.getCenter(board).dy, greaterThan(playableCenterY - 16));
    expect(
      tester.getTopLeft(board).dy,
      lessThan(tester.getTopLeft(removedPieceCountRow).dy),
    );
    expect(
      tester.getTopLeft(playerPanel).dy,
      greaterThan(tester.getTopLeft(removedPieceCountRow).dy),
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_game_menu_sheet')), findsOne);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('play_area_game_menu_flip_board')), findsOne);
    expect(
      find.byKey(const Key('play_area_game_menu_board_orientation')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_game_menu_transform_swap_rotate_180')),
      findsNothing,
    );
    expect(find.byKey(const Key('play_area_game_menu_analysis')), findsNothing);
    expect(find.byKey(const Key('play_area_game_menu_move_list')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_move_now')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_resign')), findsNothing);
    expect(find.byKey(const Key('play_area_game_menu_new_game')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_game_menu_flip_board')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_board_transform_sheet')), findsOne);
    final BuildContext rotateActionContext = tester.element(
      find.byKey(const Key('play_area_board_transform_rotate')),
    );
    expect(
      IconTheme.of(rotateActionContext).color,
      Theme.of(rotateActionContext).colorScheme.onSurfaceVariant,
    );
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

    await tester.tap(find.byKey(const Key('play_area_game_menu_flip_board')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_board_transform_sheet')), findsOne);
    expect(find.byKey(const Key('play_area_board_transform_rotate')), findsOne);
    expect(find.byKey(const Key('play_area_human_ai_robot_panel')), findsOne);
    expect(find.byKey(const Key('play_area_human_ai_player_panel')), findsOne);
  });

  testWidgets('human vs ai hides piece rows when the display switch is off', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
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

    expect(find.byKey(const Key('play_area_piece_count_row')), findsNothing);
    expect(
      find.byKey(const Key('play_area_removed_piece_count_row')),
      findsNothing,
    );
  });

  testWidgets('human vs ai move list uses a horizontal lichess layout', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    for (int i = 0; i < 20; i++) {
      controller.gameRecorder.appendMove(
        ExtMove(
          i.isEven ? 'd6' : 'f4',
          side: i.isEven ? PieceColor.white : PieceColor.black,
        ),
      );
    }

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

    expect(
      find.byKey(const Key('play_area_human_ai_move_list_wrap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_inline_move_list_scroll_view')),
      findsOneWidget,
    );
    final SingleChildScrollView moveListScrollView = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('play_area_inline_move_list_scroll_view')),
        );
    expect(moveListScrollView.scrollDirection, Axis.horizontal);
    expect(find.byKey(const Key('play_area_human_ai_move_1')), findsOneWidget);
    expect(find.byKey(const Key('play_area_human_ai_move_20')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_human_ai_move_20')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );

    final Finder scrollable = find.descendant(
      of: find.byKey(const Key('play_area_inline_move_list_scroll_view')),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final ScrollableState scrollableState = tester.state<ScrollableState>(
      scrollable,
    );
    expect(scrollableState.position.pixels, greaterThan(0));
  });

  testWidgets('human vs ai menu keeps QR move list import reachable', (
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

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_game_menu_move_list')), findsOne);
    expect(find.byKey(const Key('play_area_game_menu_move_now')), findsOne);

    await tester.tap(find.byKey(const Key('play_area_game_menu_move_list')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('moves_list_page_scaffold')), findsOneWidget);

    await tester.tap(find.byKey(const Key('moves_list_more_menu_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('moves_list_menu_scan_qr')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('moves_list_menu_scan_qr')),
        matching: find.text('Scan QR Code'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('human vs ai uses landscape side panel layout', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    <ExtMove>[
      ExtMove('a1', side: PieceColor.white, roundIndex: 1),
      ExtMove('d1', side: PieceColor.black, roundIndex: 1),
      ExtMove('a4', side: PieceColor.white, roundIndex: 2),
    ].forEach(controller.gameRecorder.appendMove);

    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('test_board_square'),
              dimension: 388,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder landscapeContent = find.byKey(
      const Key('play_area_human_ai_landscape_content'),
    );
    final Finder boardPane = find.byKey(
      const Key('play_area_human_ai_landscape_board_pane'),
    );
    final Finder sidePanel = find.byKey(
      const Key('play_area_human_ai_landscape_side_panel'),
    );

    expect(landscapeContent, findsOneWidget);
    expect(boardPane, findsOneWidget);
    expect(sidePanel, findsOneWidget);
    expect(find.byKey(const Key('play_area_lichess_bottom_bar')), findsOne);
    expect(
      find.byKey(const Key('play_area_human_ai_landscape_move_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_human_ai_landscape_move_3')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(boardPane).dx,
      lessThan(tester.getTopLeft(sidePanel).dx),
    );
    expect(
      find.byKey(const Key('play_area_sized_box_toolbar_bottom')),
      findsNothing,
    );
  });

  testWidgets('regular games use landscape side panel layout', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    <ExtMove>[
      ExtMove('a1', side: PieceColor.white, roundIndex: 1),
      ExtMove('d1', side: PieceColor.black, roundIndex: 1),
      ExtMove('a4', side: PieceColor.white, roundIndex: 2),
    ].forEach(controller.gameRecorder.appendMove);

    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        const Scaffold(
          body: PlayArea(
            boardImage: null,
            child: SizedBox.square(
              key: Key('test_board_square'),
              dimension: 388,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder landscapeContent = find.byKey(
      const Key('play_area_regular_landscape_content'),
    );
    final Finder boardPane = find.byKey(
      const Key('play_area_regular_landscape_board_pane'),
    );
    final Finder sidePanel = find.byKey(
      const Key('play_area_regular_landscape_side_panel'),
    );

    expect(landscapeContent, findsOneWidget);
    expect(boardPane, findsOneWidget);
    expect(sidePanel, findsOneWidget);
    expect(find.byKey(const Key('play_area_main_toolbar_bottom')), findsOne);
    expect(
      find.byKey(const Key('play_area_regular_landscape_move_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_landscape_move_3')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(boardPane).dx,
      lessThan(tester.getTopLeft(sidePanel).dx),
    );
    expect(
      find.byKey(const Key('play_area_sized_box_toolbar_bottom')),
      findsNothing,
    );
  });

  testWidgets('human vs ai move list groups capture with the mill move', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    <ExtMove>[
      ExtMove('a1', side: PieceColor.white, roundIndex: 1),
      ExtMove('d1', side: PieceColor.black, roundIndex: 1),
      ExtMove('a4', side: PieceColor.white, roundIndex: 2),
      ExtMove('d2', side: PieceColor.black, roundIndex: 2),
      ExtMove('a7', side: PieceColor.white, roundIndex: 3),
      ExtMove('xd1', side: PieceColor.white, roundIndex: 3),
      ExtMove('g7', side: PieceColor.black, roundIndex: 3),
    ].forEach(controller.gameRecorder.appendMove);

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

    expect(find.byKey(const Key('play_area_human_ai_round_3')), findsOneWidget);
    expect(find.byKey(const Key('play_area_human_ai_move_5')), findsNothing);
    expect(find.byKey(const Key('play_area_human_ai_move_6')), findsOneWidget);
    expect(find.text('a7 xd1'), findsOneWidget);
    expect(find.byKey(const Key('play_area_human_ai_move_7')), findsOneWidget);
    expect(find.text('g7'), findsOneWidget);
  });

  testWidgets('human vs ai robot panel follows engine activity', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    controller.isEngineRunning = false;
    controller.isEngineInDelay = false;

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

    expect(
      find.byKey(const Key('play_area_human_ai_robot_thinking_icon')),
      findsNothing,
    );

    controller.isEngineRunning = true;
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_human_ai_robot_thinking_icon')),
      findsOneWidget,
    );

    controller.isEngineRunning = false;
    controller.isEngineInDelay = true;
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_human_ai_robot_thinking_icon')),
      findsOneWidget,
    );

    controller.isEngineInDelay = false;
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_human_ai_robot_thinking_icon')),
      findsNothing,
    );
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

    await _pumpGamePageRoute(
      tester,
      session: session,
      gameMode: GameMode.humanVsAi,
      openButtonKey: const Key('open_human_ai_game_page'),
    );

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
      find.byKey(const Key('play_area_move_list_route_top_inset')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('play_area_human_ai_move_list')))
          .dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('game_page_back_button'))).dy,
      ),
    );

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

  testWidgets('human vs human route asks before leaving an active game', (
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

    await _pumpGamePageRoute(
      tester,
      session: session,
      gameMode: GameMode.humanVsHuman,
      openButtonKey: const Key('open_human_game_page'),
    );

    await tester.tap(find.byKey(const Key('open_human_game_page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('game_page_scaffold')), findsOneWidget);
    expect(find.byKey(const Key('game_page_back_button')), findsOneWidget);
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

  testWidgets('human vs ai finished game shows result action', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeHumanAiGame();
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    GameController().activeSessionSnapshot = const platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.none,
      outcome: platform.GameOutcome.win(platform.PlayerSeat.first),
      phase: 'gameOver',
    );

    await _pumpSessionPlayArea(tester, session);

    final LichessBottomBarButton resultButton = tester
        .widget<LichessBottomBarButton>(
          find.byKey(const Key('play_area_bottom_bar_resign')),
        );
    expect(resultButton.label, 'Results');
    expect(resultButton.highlighted, isTrue);
    expect(resultButton.onTap, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_bottom_bar_resign')),
        matching: find.byIcon(Icons.info_outline),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('play_area_bottom_bar_hint')), findsOneWidget);
    expect(
      _bottomBarButtonOpacity(tester, const Key('play_area_bottom_bar_hint')),
      0.4,
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play_area_game_menu_result')), findsOneWidget);
    expect(find.byKey(const Key('play_area_game_menu_resign')), findsNothing);
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

  testWidgets(
    'human vs ai white takeback removes black reply and own capture',
    (WidgetTester tester) async {
      final NativeMillGameSession session = await _bindNativeHumanAiGame();
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      expect(
        await session.replayMainline(<ExtMove>[
          ExtMove('a1', side: PieceColor.white),
          ExtMove('d1', side: PieceColor.black),
          ExtMove('a4', side: PieceColor.white),
          ExtMove('d2', side: PieceColor.black),
          ExtMove('a7', side: PieceColor.white),
          ExtMove('xd1', side: PieceColor.white),
          ExtMove('g7', side: PieceColor.black),
        ]),
        isTrue,
      );
      await tester.pump();
      expect(_currentPathMoves(), <String>[
        'a1',
        'd1',
        'a4',
        'd2',
        'a7',
        'xd1',
        'g7',
      ]);
      expect(GameController().gameInstance.isHumanToMove, isTrue);

      await _pumpSessionPlayArea(tester, session);
      await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
      await tester.pumpAndSettle();

      expect(_currentPathMoves(), <String>['a1', 'd1', 'a4', 'd2', 'a7']);
      expect(GameController().gameInstance.isHumanToMove, isTrue);
    },
  );

  testWidgets(
    'human vs ai black takeback removes only black reply after capture',
    (WidgetTester tester) async {
      db.generalSettings = const GeneralSettings(aiMovesFirst: true);
      final NativeMillGameSession session = await _bindNativeHumanAiGame();
      final MillSessionRecorderBridge recorderBridge =
          MillSessionRecorderBridge.forGameController(session: session);
      addTearDown(recorderBridge.dispose);

      expect(
        await session.replayMainline(<ExtMove>[
          ExtMove('a1', side: PieceColor.white),
          ExtMove('d1', side: PieceColor.black),
          ExtMove('a4', side: PieceColor.white),
          ExtMove('d2', side: PieceColor.black),
          ExtMove('a7', side: PieceColor.white),
          ExtMove('xd1', side: PieceColor.white),
          ExtMove('g7', side: PieceColor.black),
        ]),
        isTrue,
      );
      await tester.pump();
      expect(_currentPathMoves(), <String>[
        'a1',
        'd1',
        'a4',
        'd2',
        'a7',
        'xd1',
        'g7',
      ]);
      expect(GameController().gameInstance.isHumanToMove, isFalse);

      await _pumpSessionPlayArea(tester, session);
      await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
      await tester.pumpAndSettle();

      expect(_currentPathMoves(), <String>[
        'a1',
        'd1',
        'a4',
        'd2',
        'a7',
        'xd1',
      ]);
      expect(GameController().gameInstance.isHumanToMove, isTrue);
    },
  );

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

  testWidgets('human vs human black requester removes only black reply', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.humanVsHuman,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(await session.replayMainline(_takeBackCaptureFixture()), isTrue);
    await tester.pump();

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(
      find.byKey(const Key('play_area_regular_bottom_bar_take_back')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_take_back_requester_sheet')),
      findsOneWidget,
    );
    expect(find.text('Who is taking back?'), findsOneWidget);
    expect(find.text('White takes back'), findsOneWidget);
    expect(find.text('Black takes back'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('play_area_take_back_requester_black')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['a1', 'd1', 'a4', 'd2', 'a7', 'xd1']);
  });

  testWidgets('human vs human white requester removes reply and own capture', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.humanVsHuman,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(await session.replayMainline(_takeBackCaptureFixture()), isTrue);
    await tester.pump();

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(
      find.byKey(const Key('play_area_regular_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_take_back')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_take_back_requester_sheet')),
      findsOneWidget,
    );
    expect(find.text('Who is taking back?'), findsOneWidget);
    expect(find.text('White takes back'), findsOneWidget);
    expect(find.text('Black takes back'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('play_area_take_back_requester_white')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['a1', 'd1', 'a4', 'd2', 'a7']);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  scaffoldMessengerKey: rootScaffoldMessengerKey,
  localizationsDelegates: sanmillLocalizationsDelegates,
  supportedLocales: S.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

Future<void> _pumpGamePageRoute(
  WidgetTester tester, {
  required NativeMillGameSession session,
  required GameMode gameMode,
  required Key openButtonKey,
}) async {
  await tester.pumpWidget(
    _localizedApp(
      GameSessionScope(
        session: session,
        child: Navigator(
          onGenerateRoute: (RouteSettings settings) {
            if (settings.name == '/game') {
              return MaterialPageRoute<void>(
                builder: (_) => GamePage(gameMode),
              );
            }
            return MaterialPageRoute<void>(
              builder: (BuildContext context) {
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      key: openButtonKey,
                      onPressed: () => Navigator.of(context).pushNamed('/game'),
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
}

double _bottomBarButtonOpacity(WidgetTester tester, Key key) {
  final Opacity opacity = tester.widget<Opacity>(
    find.descendant(of: find.byKey(key), matching: find.byType(Opacity)),
  );
  return opacity.opacity;
}

Future<NativeMillGameSession> _bindNativeHumanAiGame() {
  return _bindNativeGame(GameMode.humanVsAi);
}

Future<NativeMillGameSession> _bindNativeGame(GameMode gameMode) async {
  final GameController controller = GameController();
  controller.reset(force: true);
  controller.gameInstance.gameMode = gameMode;
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

List<ExtMove> _takeBackCaptureFixture() {
  return <ExtMove>[
    ExtMove('a1', side: PieceColor.white),
    ExtMove('d1', side: PieceColor.black),
    ExtMove('a4', side: PieceColor.white),
    ExtMove('d2', side: PieceColor.black),
    ExtMove('a7', side: PieceColor.white),
    ExtMove('xd1', side: PieceColor.white),
    ExtMove('g7', side: PieceColor.black),
  ];
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
