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
import 'package:sanmill/game_page/services/analysis/analysis_service.dart';
import 'package:sanmill/game_page/services/analysis_mode.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/advantage_graph_painter.dart';
import 'package:sanmill/game_page/services/player_timer.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/game_page/widgets/moves_list_page.dart';
import 'package:sanmill/game_page/widgets/play_area.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart' as platform;
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/config/constants.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/lichess_bottom_bar.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../games/mill/opening_book/opening_book_test_assets.dart';
import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';
import '../helpers/mocks/mock_database.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initRustLibForTests();
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
    await OpeningBookRepository.instance.ensureLoaded();
  });

  tearDownAll(() {
    OpeningBookRepository.instance.resetForTest();
    disposeRustLibForTests();
  });

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
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setShowMoveAnnotations(true);
    AnalysisMode.setShowMoveComments(true);
    AnalysisMode.setShowBestMoveArrow(true);
    AnalysisMode.setShowEvaluationGauge(true);
    AnalysisMode.setInlineNotation(false);
    AnalysisMode.setSmallBoard(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
    PlayerTimer().reset();
  });

  tearDown(() {
    AnalysisMode.disable();
    AnalysisMode.setShowEngineLines(true);
    AnalysisMode.setShowMoveAnnotations(true);
    AnalysisMode.setShowMoveComments(true);
    AnalysisMode.setShowBestMoveArrow(true);
    AnalysisMode.setShowEvaluationGauge(true);
    AnalysisMode.setInlineNotation(false);
    AnalysisMode.setSmallBoard(false);
    AnalysisMode.setEngineLineCount(AnalysisMode.defaultEngineLineCount);
    AnalysisMode.setEngineSearchTimeMs(AnalysisMode.defaultEngineSearchTimeMs);
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

  testWidgets('screen reader board uses a stable semantics grid', (
    WidgetTester tester,
  ) async {
    db = _GamePageDb(
      generalSettings: const GeneralSettings(screenReaderSupport: true),
      displaySettings: const DisplaySettings(
        isUnplacedAndRemovedPiecesShown: false,
        isHistoryNavigationToolbarShown: false,
      ),
    );
    DB.instance = db;
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.humanVsHuman,
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        GameSessionScope(
          session: session,
          child: const Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 390,
                child: GameBoard(boardImage: null),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byKey(const Key('board_semantics_grid')), findsOneWidget);
    expect(find.byKey(const Key('board_grid_view')), findsNothing);
    expect(find.byType(GridView), findsNothing);
    expect(_boardSquareSemanticsFinder(), findsNWidgets(49));

    GameController().boardSemanticsNotifier.updateSemantics();
    await tester.pump();

    expect(find.byKey(const Key('board_semantics_grid')), findsOneWidget);
    expect(_boardSquareSemanticsFinder(), findsNWidgets(49));
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
    expect(moveListScrollView.scrollDirection, Axis.vertical);
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
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_next')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_regular_bottom_bar_previous')),
          )
          .label,
      'Previous',
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_regular_bottom_bar_previous')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_regular_bottom_bar_next')),
          )
          .label,
      'Next',
    );
    expect(
      tester
          .widget<LichessBottomBarButton>(
            find.byKey(const Key('play_area_regular_bottom_bar_next')),
          )
          .enabled,
      isFalse,
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
      findsNothing,
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
      Theme.of(regularRotateActionContext).colorScheme.onSurface,
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
      tester
          .getTopLeft(
            find.byKey(
              const Key('play_area_regular_board_transform_vertical_flip'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const Key('play_area_regular_board_transform_horizontal_flip'),
              ),
            )
            .dy,
      ),
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

  testWidgets('regular game move list wraps when the line is full', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
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

    final Finder firstMove = find.byKey(const Key('play_area_regular_move_1'));
    final Finder lastMove = find.byKey(const Key('play_area_regular_move_20'));
    expect(firstMove, findsOneWidget);
    expect(lastMove, findsOneWidget);
    expect(
      tester.getTopLeft(lastMove).dy,
      greaterThan(tester.getTopLeft(firstMove).dy),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_regular_move_list_wrap')))
          .height,
      104,
    );
    expect(
      tester.getBottomLeft(lastMove).dy,
      lessThanOrEqualTo(
        tester
            .getBottomLeft(
              find.byKey(const Key('play_area_regular_move_list_wrap')),
            )
            .dy,
      ),
    );
  });

  testWidgets('regular game move list wraps consecutive same-side actions', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsHuman;
    for (final String notation in <String>[
      'd6',
      'xa1',
      'xd1',
      'xg1',
      'xb2',
      'xd2',
      'xf2',
      'xc3',
      'xd3',
      'xe3',
      'a4',
      'b4',
    ]) {
      controller.gameRecorder.appendMove(
        ExtMove(notation, side: PieceColor.white),
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

    final Finder groupedMove = find.byKey(
      const Key('play_area_regular_move_12'),
    );
    final Finder moveList = find.byKey(
      const Key('play_area_regular_move_list_wrap'),
    );
    expect(find.byKey(const Key('play_area_regular_move_1')), findsNothing);
    expect(find.byKey(const Key('play_area_regular_move_2')), findsNothing);
    expect(groupedMove, findsOneWidget);
    expect(
      find.text('d6 xa1 xd1 xg1 xb2 xd2 xf2 xc3 xd3 xe3 a4 b4'),
      findsOneWidget,
    );
    expect(
      tester.getSize(groupedMove).height,
      greaterThan(tester.getSize(find.text('1.')).height),
    );
    expect(
      tester.getTopRight(groupedMove).dx,
      lessThanOrEqualTo(tester.getTopRight(moveList).dx),
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
      Theme.of(rotateActionContext).colorScheme.onSurface,
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
      tester
          .getTopLeft(
            find.byKey(const Key('play_area_board_transform_vertical_flip')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const Key('play_area_board_transform_horizontal_flip'),
              ),
            )
            .dy,
      ),
    );
    expect(
      find.byKey(const Key('play_area_board_transform_inner_outer_flip')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_board_transform_swap_rotate_180')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('play_area_board_transform_rotate')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_board_transform_sheet')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 4));
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

  testWidgets('human vs ai move now menu action keeps a live context', (
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

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play_area_game_menu_move_now')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('human vs ai move now plays from a human turn', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _MoveNowFakeSearchSession session = _MoveNowFakeSearchSession();
    _bindExistingNativeGame(GameMode.humanVsAi, session);
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    expect(GameController().gameInstance.isHumanToMove, isTrue);
    expect(_currentPathMoves(), isEmpty);

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(find.byKey(const Key('play_area_bottom_bar_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play_area_game_menu_move_now')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(session.searchCalls, 1);
    expect(_currentPathMoves(), hasLength(1));
    expect(GameController().gameInstance.isHumanToMove, isFalse);
  });

  testWidgets('move now skips the AI vs AI animation delay', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings(
      animationDuration: 20,
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _MoveNowFakeSearchSession session = _MoveNowFakeSearchSession(
      actionLimit: 1,
    );
    _bindExistingNativeGame(GameMode.aiVsAi, session);
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    await _pumpSessionPlayArea(tester, session);
    final BuildContext context = tester.element(find.byType(PlayArea));
    final Future<EngineResponse> engineLoop = GameController().engineToGo(
      context,
      isMoveNow: false,
      session: session,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(session.searchCalls, 1);
    expect(GameController().isEngineInDelay, isTrue);

    await GameController().moveNow(
      context,
      session: session,
      messages: const MoveNowMessages(
        aiIsDelaying: 'AI delay',
        analyzing: 'Analyzing',
        notAIsTurn: 'Not AI turn',
        timeout: 'Timeout',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('AI delay'), findsNothing);
    expect(session.searchCalls, 2);
    expect(GameController().isEngineInDelay, isFalse);
    expect(await engineLoop, const EngineResponseOK());
  });

  testWidgets('human vs ai balanced layout fits with advantage graph', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(isAdvantageGraphShown: true);
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

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play_area_advantage_graph')), findsOneWidget);
  });

  testWidgets('regular board page avoids overflow when dense', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(isAdvantageGraphShown: true);
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;

    await tester.binding.setSurfaceSize(const Size(390, 788));
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

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play_area_advantage_graph')), findsOneWidget);
    expect(
      find.byKey(const Key('play_area_human_database_stats_strip')),
      findsOneWidget,
    );
  });

  testWidgets('human vs ai dense portrait layout handles insets', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings(showHumanDatabaseStats: true);
    db.displaySettings = const DisplaySettings(
      isAdvantageGraphShown: true,
      isHistoryNavigationToolbarShown: false,
    );
    GameController().gameInstance.gameMode = GameMode.humanVsAi;

    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 720),
            padding: EdgeInsets.only(top: 36, bottom: 24),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
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

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play_area_lichess_bottom_bar')), findsOne);
    expect(find.byKey(const Key('play_area_human_ai_scroll_view')), findsOne);
  });

  testWidgets('analysis dense portrait layout handles engine lines', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.draw),
      const MoveAnalysisResult(move: 'g7', outcome: AnalysisOutcome.loss),
    ]);

    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        GameSessionScope(
          session: session,
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 700),
              padding: EdgeInsets.only(top: 36, bottom: 24),
              textScaler: TextScaler.linear(1.2),
            ),
            child: Scaffold(
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
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('play_area_analysis_board')), findsOne);
    expect(find.byKey(const Key('play_area_analysis_engine_lines')), findsOne);
    expect(find.byKey(const Key('play_area_analysis_panel')), findsOne);
  });

  testWidgets('analysis keeps empty engine line slots visible', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);

    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_2')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_empty')),
      findsNothing,
    );

    AnalysisMode.setShowEngineLines(false, persist: true);
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_hidden')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsNothing,
    );
    expect(db.displaySettings.analysisShowEngineLines, isFalse);
  });

  testWidgets('setup position game page reserves toolbar height', (
    WidgetTester tester,
  ) async {
    db = _GamePageDb(
      generalSettings: const GeneralSettings(showHumanDatabaseStats: true),
      displaySettings: const DisplaySettings(
        isHistoryNavigationToolbarShown: false,
      ),
    );
    DB.instance = db;
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.setupPosition,
    );

    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        GameSessionScope(
          session: session,
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 700),
              padding: EdgeInsets.only(top: 36, bottom: 24),
              textScaler: TextScaler.linear(1.2),
            ),
            child: GamePage(GameMode.setupPosition),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('play_area_setup_position_toolbar_bottom')),
      findsOne,
    );
    expect(find.byKey(const Key('setup_position_three_row_toolbar')), findsOne);
  });

  testWidgets('setup position dispose cleanup waits until the tree unlocks', (
    WidgetTester tester,
  ) async {
    db = _GamePageDb(
      generalSettings: const GeneralSettings(),
      displaySettings: const DisplaySettings(
        isHistoryNavigationToolbarShown: false,
      ),
    );
    DB.instance = db;
    final GameController controller = GameController();
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.setupPosition,
    );

    await tester.pumpWidget(
      _localizedApp(
        GameSessionScope(
          session: session,
          child: const GamePage(GameMode.setupPosition),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.setupPositionController, isNotNull);

    await tester.pumpWidget(_localizedApp(const SizedBox.shrink()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.setupPositionController, isNull);
  });

  testWidgets('setup position hides the positional advantage indicator', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings();
    GameController().gameInstance.gameMode = GameMode.setupPosition;

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
      find.byKey(const Key('play_area_advantage_indicator')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_advantage_indicator_positioned')),
      findsNothing,
    );
  });

  testWidgets('analysis mode uses lichess-style navigation bottom bar', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        roundIndex: 1,
        nags: <int>[1],
        comments: <String>['Good opening'],
        boardLayout: '********/********/O*******',
      ),
    );
    GameController().gameRecorder.appendMove(
      ExtMove(
        'f4',
        side: PieceColor.black,
        roundIndex: 1,
        nags: <int>[2],
        comments: <String>['Check this'],
      ),
    );
    await _pumpSessionPlayArea(tester, session);

    expect(find.byKey(const Key('play_area_analysis_board')), findsOne);
    expect(find.byKey(const Key('play_area_analysis_panel')), findsOne);
    expect(find.byKey(const Key('play_area_analysis_tabs')), findsOne);
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_analysis_tab_explorer')))
          .height,
      26,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_analysis_tab_moves')))
          .height,
      26,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_analysis_tab_summary')))
          .height,
      26,
    );
    final Icon explorerTabIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_tab_explorer')),
        matching: find.byIcon(Icons.explore_outlined),
      ),
    );
    final Icon movesTabIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_tab_moves')),
        matching: find.byIcon(Icons.account_tree_outlined),
      ),
    );
    final Icon summaryTabIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_tab_summary')),
        matching: find.byIcon(Icons.area_chart_outlined),
      ),
    );
    expect(explorerTabIcon.size, 18);
    expect(movesTabIcon.size, 18);
    expect(summaryTabIcon.size, 18);
    expect(find.byKey(const Key('play_area_analysis_moves')), findsOne);
    expect(find.text('d6! {Good opening}'), findsOne);
    expect(find.text('f4? {Check this}'), findsOne);
    expect(find.byKey(const Key('opening_explorer_embedded')), findsNothing);

    await tester.longPress(find.byKey(const Key('play_area_analysis_move_1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_move_actions_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_move_action_preview_board')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_move_action_preview_board')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_move_preview_dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_move_preview_board')),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    AnalysisMode.enable(<MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.withValue(AnalysisOutcome.advantage, '+42'),
        depth: 1,
        nodes: 12345,
        nodesPerSecond: 32000,
        line: const <String>['d6', 'f4'],
      ),
      const MoveAnalysisResult(
        move: 'a1',
        outcome: AnalysisOutcome.draw,
        depth: 8,
        nodes: 67890,
        nodesPerSecond: 64000,
        line: <String>['a1'],
      ),
    ], source: AnalysisSource.engine);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_analysis_summary')), findsOne);
    expect(
      find.byKey(const Key('play_area_analysis_summary_source')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_engine')),
      findsOne,
    );
    expect(find.byKey(const Key('play_area_analysis_summary_moves')), findsOne);
    expect(
      find.byKey(const Key('play_area_analysis_summary_variations')),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.textContaining('d8'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.textContaining('64k n/s'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.textContaining('d6 f4'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_source')),
        matching: find.text('Engine'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_best_move')),
        matching: find.text('Best Move'),
      ),
      findsOne,
    );

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.withValue(AnalysisOutcome.advantage, '+42'),
          depth: 6,
          nodes: 12345,
          line: const <String>['d6', 'f4'],
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_source')),
        matching: find.text('Threat · Engine'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.text('Threat'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_best_move')),
        matching: find.text('Threat'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_best_move')),
        matching: find.text('Best Move'),
      ),
      findsNothing,
    );

    expect(find.byKey(const Key('play_area_main_toolbar_bottom')), findsOne);
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_previous')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_next')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_menu')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_resign_result')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_take_back')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_bottom_bar_clock')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play_area_toolbar_item_move')), findsNothing);
    expect(
      find.byKey(const Key('play_area_analysis_game_menu_move_list')),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_game_menu_move_list')),
        matching: find.text('Move list'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_opening_explorer')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_board_editor')),
      findsOne,
    );
    expect(
      find.byKey(
        const Key('play_area_regular_game_menu_play_against_computer'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_over_the_board')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_analysis')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_toggle_engine_lines')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_analysis_settings')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_show_threat')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_continue_from_here')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_share_export')),
      findsOne,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_game_menu_move_list')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byType(MovesListPage), findsOneWidget);
    expect(
      find.byKey(const Key('play_area_regular_game_menu_sheet')),
      findsNothing,
    );

    Navigator.of(tester.element(find.byType(MovesListPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_analysis_settings')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsOne,
    );

    Navigator.of(
      tester.element(
        find.byKey(const Key('play_area_analysis_settings_sheet')),
      ),
    ).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_toggle_engine_lines')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(AnalysisMode.showEngineLines, isFalse);
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_hidden')),
      findsOneWidget,
    );
    expect(db.displaySettings.analysisShowEngineLines, isFalse);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    final Finder shareExportTile = find.byKey(
      const Key('play_area_regular_game_menu_share_export'),
    );
    await tester.ensureVisible(shareExportTile);
    await tester.tap(shareExportTile);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_share_export_sheet')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_copy_fen')),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_share_fen')),
      findsOne,
    );

    Navigator.of(
      tester.element(
        find.byKey(const Key('play_area_analysis_share_export_sheet')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_continue_from_here')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_continue_from_here_sheet')),
      findsOne,
    );
    expect(
      find.byKey(
        const Key('play_area_analysis_continue_play_against_computer'),
      ),
      findsOne,
    );
    expect(
      find.byKey(const Key('play_area_analysis_continue_over_the_board')),
      findsOne,
    );
  });

  testWidgets('analysis share export offers system PGN and FEN sharing', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white, roundIndex: 1),
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_share_export')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_share_export_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_share_pgn')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_share_fen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_copy_pgn')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_share_export_copy_fen')),
      findsOneWidget,
    );
  });

  testWidgets('analysis menu toggles game sounds', (WidgetTester tester) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    db.generalSettings = db.generalSettings.copyWith(toneEnabled: true);
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_regular_game_menu_toggle_sound')),
      findsOneWidget,
    );
    expect(db.generalSettings.toneEnabled, isTrue);

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_toggle_sound')),
    );
    await tester.pumpAndSettle();

    expect(db.generalSettings.toneEnabled, isFalse);
  });

  testWidgets('analysis move list toggles annotations and comments', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.rootComments.add('Imported study note');
    GameController().gameRecorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        roundIndex: 1,
        nags: <int>[1],
        comments: <String>['Good opening'],
      ),
    );
    GameController().gameRecorder.appendMove(
      ExtMove('f4', side: PieceColor.black, roundIndex: 1, nags: <int>[16]),
    );

    await _pumpSessionPlayArea(tester, session);

    final Finder movesPanel = find.byKey(const Key('play_area_analysis_moves'));
    expect(
      find.descendant(
        of: movesPanel,
        matching: find.text('d6! {Good opening}'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: movesPanel,
        matching: find.text('{Imported study note}'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: movesPanel, matching: find.text('f4±')),
      findsOne,
    );

    AnalysisMode.setShowMoveAnnotations(false);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: movesPanel, matching: find.text('d6 {Good opening}')),
      findsOne,
    );
    expect(
      find.descendant(
        of: movesPanel,
        matching: find.text('d6! {Good opening}'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: movesPanel, matching: find.text('f4')),
      findsOne,
    );
    expect(
      find.descendant(of: movesPanel, matching: find.text('f4±')),
      findsNothing,
    );

    AnalysisMode.setShowMoveComments(false);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: movesPanel, matching: find.text('d6')),
      findsOne,
    );
    expect(
      find.descendant(of: movesPanel, matching: find.text('d6 {Good opening}')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: movesPanel,
        matching: find.text('{Imported study note}'),
      ),
      findsNothing,
    );
  });

  testWidgets('analysis move list toggles inline notation layout', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white, roundIndex: 1),
    );
    GameController().gameRecorder.appendMove(
      ExtMove('f4', side: PieceColor.black, roundIndex: 1),
    );

    await _pumpSessionPlayArea(tester, session);

    expect(AnalysisMode.inlineNotation, isFalse);
    expect(
      find.byKey(const Key('play_area_inline_move_list_two_column')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_inline_move_list_inline_notation')),
      findsNothing,
    );

    AnalysisMode.setInlineNotation(true);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_inline_move_list_two_column')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_inline_move_list_inline_notation')),
      findsOneWidget,
    );
  });

  testWidgets('analysis previous and next repeat while long pressed', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
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

    await _pumpSessionPlayArea(tester, session);

    await _holdBottomBarButton(
      tester,
      const Key('play_area_analysis_bottom_bar_previous'),
    );
    expect(_currentPathMoves(), isEmpty);
    final Finder movesPanel = find.byKey(const Key('play_area_analysis_moves'));
    expect(
      find.descendant(of: movesPanel, matching: find.text('d6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: movesPanel, matching: find.text('f4')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_moves')),
        matching: find.textContaining('2 · d6 f4'),
      ),
      findsOneWidget,
    );

    await _holdBottomBarButton(
      tester,
      const Key('play_area_analysis_bottom_bar_next'),
    );
    expect(_currentPathMoves(), <String>['d6', 'f4']);
  });

  testWidgets('analysis summary shows combined source details', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
        const MoveAnalysisResult(move: 'd1', outcome: AnalysisOutcome.draw),
        const MoveAnalysisResult(move: 'a4', outcome: AnalysisOutcome.loss),
        const MoveAnalysisResult(
          move: 'd2',
          outcome: AnalysisOutcome.advantage,
        ),
        const MoveAnalysisResult(
          move: 'a7',
          outcome: AnalysisOutcome.disadvantage,
        ),
        const MoveAnalysisResult(move: 'd3', outcome: AnalysisOutcome.unknown),
      ],
      lineResults: <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'g7',
          outcome: AnalysisOutcome.withValue(AnalysisOutcome.advantage, '+32'),
          depth: 12,
          nodes: 45678,
          nodesPerSecond: 91000,
          line: const <String>['g7', 'b2'],
        ),
      ],
      trapMoves: const <String>['a1', 'd6'],
      source: AnalysisSource.perfectDatabaseAndEngine,
    );

    await _pumpSessionPlayArea(tester, session);

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
        matching: find.text('DB · Engine'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_source')),
        matching: find.text('Perfect database · Engine'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.textContaining('d12'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.textContaining('g7 b2'),
      ),
      findsOneWidget,
    );
    final Finder bestMove = find.byKey(
      const Key('play_area_analysis_summary_best_move'),
    );
    expect(bestMove, findsOneWidget);
    expect(
      find.descendant(of: bestMove, matching: find.text('Best Move')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bestMove,
        matching: find.byKey(
          const Key('play_area_analysis_summary_best_move_eval'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestMove, matching: find.textContaining('+32')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestMove, matching: find.textContaining('d12')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestMove, matching: find.textContaining('g7 b2')),
      findsOneWidget,
    );

    final Finder results = find.byKey(
      const Key('play_area_analysis_summary_results'),
    );
    expect(results, findsOneWidget);
    expect(
      find.descendant(
        of: results,
        matching: find.byKey(
          const Key('play_area_analysis_summary_outcome_distribution'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: results,
        matching: find.byKey(
          const Key('play_area_analysis_summary_outcome_meter'),
        ),
      ),
      findsOneWidget,
    );
    for (final String label in <String>[
      'Wins 1',
      'Draws 1',
      'Losses 1',
      '+ 1',
      '- 1',
      'Unknown 1',
    ]) {
      expect(
        find.descendant(of: results, matching: find.textContaining(label)),
        findsWidgets,
      );
      expect(find.byTooltip(label), findsWidgets);
    }
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Results · Wins 1 · Draws 1 · Losses 1 · + 1 · - 1 · Unknown 1',
      ),
      findsOneWidget,
    );
    for (final String outcome in <String>[
      'win',
      'draw',
      'loss',
      'advantage',
      'disadvantage',
      'unknown',
    ]) {
      expect(
        find.descendant(
          of: results,
          matching: find.byKey(
            Key('play_area_analysis_summary_outcome_segment_$outcome'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: results,
          matching: find.byKey(
            Key('play_area_analysis_summary_outcome_legend_$outcome'),
          ),
        ),
        findsOneWidget,
      );
    }
    final Finder candidateChips = find.descendant(
      of: results,
      matching: find.byKey(
        const Key('play_area_analysis_summary_result_candidates'),
      ),
    );
    expect(candidateChips, findsOneWidget);
    expect(
      find.descendant(
        of: results,
        matching: find.byKey(
          const Key('play_area_analysis_summary_result_candidate_0'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: results, matching: find.text('a1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: results, matching: find.text('d1')),
      findsOneWidget,
    );
    final Finder drawLegend = find.descendant(
      of: results,
      matching: find.byKey(
        const Key('play_area_analysis_summary_outcome_legend_draw'),
      ),
    );
    await tester.ensureVisible(drawLegend);
    await tester.pumpAndSettle();
    await tester.tap(drawLegend);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: candidateChips, matching: find.text('d1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidateChips, matching: find.text('a1')),
      findsNothing,
    );
    expect(
      find.descendant(of: candidateChips, matching: find.text('a4')),
      findsNothing,
    );

    await tester.ensureVisible(drawLegend);
    await tester.pumpAndSettle();
    await tester.tap(drawLegend);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: candidateChips, matching: find.text('a1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidateChips, matching: find.text('d1')),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_traps')),
        matching: find.text('Trap exists. Trap moves: a1 d6'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('analysis summary best move applies the candidate', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.advantage,
        ),
      ],
      lineResults: <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 8,
          nodes: 128000,
          line: <String>['d6', 'f4'],
        ),
      ],
      source: AnalysisSource.engine,
    );

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    final Finder bestMove = find.byKey(
      const Key('play_area_analysis_summary_best_move'),
    );
    expect(bestMove, findsOneWidget);
    expect(
      find.descendant(of: bestMove, matching: find.textContaining('d8')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestMove, matching: find.textContaining('d6 f4')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Apply this result to board · + 1. d6 f4'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Apply this result to board · + 1. d6 f4',
      ),
      findsOneWidget,
    );

    await tester.tap(bestMove);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_currentPathMoves(), <String>['d6']);
  });

  testWidgets('analysis summary expands hidden result candidates', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'd1', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'a4', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'd2', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'a7', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'd3', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'g7', outcome: AnalysisOutcome.win),
      const MoveAnalysisResult(move: 'b2', outcome: AnalysisOutcome.win),
    ], source: AnalysisSource.perfectDatabase);

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    final Finder candidateList = find.byKey(
      const Key('play_area_analysis_summary_result_candidates'),
    );
    expect(candidateList, findsOneWidget);
    expect(
      find.descendant(of: candidateList, matching: find.text('d3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidateList, matching: find.text('g7')),
      findsNothing,
    );
    expect(
      find.descendant(of: candidateList, matching: find.text('b2')),
      findsNothing,
    );

    final Finder moreCandidates = find.byKey(
      const Key('play_area_analysis_summary_result_candidates_more'),
    );
    expect(moreCandidates, findsOneWidget);
    expect(
      find.descendant(of: moreCandidates, matching: find.text('+2 More')),
      findsOneWidget,
    );
    expect(find.byTooltip('+2 More'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == '+2 More',
      ),
      findsOneWidget,
    );

    final Finder summaryScrollable = find.descendant(
      of: find.byKey(const Key('play_area_analysis_summary')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      moreCandidates,
      120,
      scrollable: summaryScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(moreCandidates);
    await tester.pumpAndSettle();

    expect(moreCandidates, findsNothing);
    expect(
      find.descendant(of: candidateList, matching: find.text('g7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidateList, matching: find.text('b2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_result_candidate_7')),
      findsOneWidget,
    );
  });

  testWidgets('analysis summary result candidate applies the move', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
        const MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.draw),
      ],
      lineResults: <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.win,
          rank: 1,
          depth: 8,
          line: <String>['d6', 'f4'],
        ),
      ],
      source: AnalysisSource.engine,
    );

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    final Finder candidate = find.byKey(
      const Key('play_area_analysis_summary_result_candidate_0'),
    );
    expect(candidate, findsOneWidget);
    expect(
      find.descendant(of: candidate, matching: find.text('d6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: candidate, matching: find.text('W')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Apply this result to board · W 1. d6'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Apply this result to board · W 1. d6',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(candidate);
    await tester.pumpAndSettle();
    await tester.tap(candidate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_currentPathMoves(), <String>['d6']);
  });

  testWidgets('analysis summary offers request and waiting states', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_summary_analyze')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_engine_progress')),
      findsNothing,
    );

    AnalysisMode.setAnalyzing(true);
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_summary_analyze')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_engine_progress')),
      findsOneWidget,
    );
    final CircularProgressIndicator summaryProgress = tester
        .widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byKey(
              const Key('play_area_analysis_summary_engine_progress'),
            ),
            matching: find.byType(CircularProgressIndicator),
          ),
        );
    expect(summaryProgress.semanticsLabel, 'Analyzing…');
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_engine')),
        matching: find.text('Analyzing…'),
      ),
      findsOneWidget,
    );

    AnalysisMode.setAnalyzing(false);
  });

  testWidgets('analysis summary shows the advantage graph', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      isAdvantageGraphShown: true,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);
    final PlayAreaState playAreaState = tester.state<PlayAreaState>(
      find.byType(PlayArea),
    );
    playAreaState.advantageData
      ..clear()
      ..addAll(<int>[0, 24, -12, 36]);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_summary_advantage_graph')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_advantage_paint')),
      findsOneWidget,
    );
  });

  testWidgets('analysis summary keeps key moments when graph is hidden', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      isAdvantageGraphShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.appendMove(ExtMove('f4', side: PieceColor.black));
    recorder.appendMove(ExtMove('a1', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);
    final PlayAreaState playAreaState = tester.state<PlayAreaState>(
      find.byType(PlayArea),
    );
    playAreaState.advantageData
      ..clear()
      ..addAll(<int>[0, 24, -12, 36]);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_summary_advantage_graph')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_summary_graph_header')),
      findsNothing,
    );

    final Finder topKeyMoment = find.byKey(
      const Key('play_area_analysis_summary_key_moment'),
    );
    final Finder secondKeyMoment = find.byKey(
      const Key('play_area_analysis_summary_key_moment_2'),
    );
    expect(topKeyMoment, findsOneWidget);
    expect(secondKeyMoment, findsOneWidget);
    expect(
      find.descendant(of: topKeyMoment, matching: find.text('Move 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topKeyMoment, matching: find.textContaining('+48')),
      findsOneWidget,
    );

    await tester.tap(secondKeyMoment);
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'f4']);
  });

  testWidgets('analysis summary advantage graph jumps to tapped move', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      isAdvantageGraphShown: true,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.appendMove(ExtMove('f4', side: PieceColor.black));
    recorder.appendMove(ExtMove('a1', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);
    final PlayAreaState playAreaState = tester.state<PlayAreaState>(
      find.byType(PlayArea),
    );
    playAreaState.advantageData
      ..clear()
      ..addAll(<int>[0, 24, -12, 36]);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(_summaryAdvantagePainter(tester).currentIndex, 3);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Show advantage graph · Move 3 · +36',
      ),
      findsOneWidget,
    );
    final Finder topKeyMoment = find.byKey(
      const Key('play_area_analysis_summary_key_moment'),
    );
    final Finder secondKeyMoment = find.byKey(
      const Key('play_area_analysis_summary_key_moment_2'),
    );
    final Finder thirdKeyMoment = find.byKey(
      const Key('play_area_analysis_summary_key_moment_1'),
    );
    expect(topKeyMoment, findsOneWidget);
    expect(secondKeyMoment, findsOneWidget);
    expect(thirdKeyMoment, findsOneWidget);
    expect(
      find.descendant(of: topKeyMoment, matching: find.text('Move 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topKeyMoment, matching: find.textContaining('+48')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topKeyMoment, matching: find.textContaining('a1')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Continue from here · Move 3 · +48 · a1'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Continue from here · Move 3 · +48 · a1',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondKeyMoment, matching: find.text('Move 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: secondKeyMoment,
        matching: find.textContaining('-36'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: secondKeyMoment, matching: find.textContaining('f4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: thirdKeyMoment, matching: find.text('Move 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: thirdKeyMoment, matching: find.textContaining('+24')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: thirdKeyMoment, matching: find.textContaining('d6')),
      findsOneWidget,
    );

    final Finder graph = find.byKey(
      const Key('play_area_analysis_summary_advantage_graph'),
    );
    final Size graphSize = tester.getSize(graph);
    final Offset graphTopLeft = tester.getTopLeft(graph);
    const double chartMargin = 10;
    final double stepWidth = (graphSize.width - chartMargin * 2) / 49;
    await tester.tapAt(
      graphTopLeft + Offset(chartMargin + stepWidth * 2, graphSize.height / 2),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'f4']);
    expect(_summaryAdvantagePainter(tester).currentIndex, 2);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Show advantage graph · Move 2 · -12',
      ),
      findsOneWidget,
    );

    await tester.tap(topKeyMoment);
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'f4', 'a1']);
    expect(_summaryAdvantagePainter(tester).currentIndex, 3);

    await tester.tap(secondKeyMoment);
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'f4']);
    expect(_summaryAdvantagePainter(tester).currentIndex, 2);
  });

  testWidgets('analysis summary advantage graph scrubs while dragging', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      isAdvantageGraphShown: true,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.appendMove(ExtMove('f4', side: PieceColor.black));
    recorder.appendMove(ExtMove('a1', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);
    final PlayAreaState playAreaState = tester.state<PlayAreaState>(
      find.byType(PlayArea),
    );
    playAreaState.advantageData
      ..clear()
      ..addAll(<int>[0, 24, -12, 36]);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    final Finder graph = find.byKey(
      const Key('play_area_analysis_summary_advantage_graph'),
    );
    final Size graphSize = tester.getSize(graph);
    final Offset graphTopLeft = tester.getTopLeft(graph);
    const double chartMargin = 10;
    final double stepWidth = (graphSize.width - chartMargin * 2) / 49;
    final Offset firstMovePoint =
        graphTopLeft + Offset(chartMargin + stepWidth, graphSize.height / 2);
    final Offset thirdMovePoint =
        graphTopLeft +
        Offset(chartMargin + stepWidth * 3, graphSize.height / 2);

    final TestGesture gesture = await tester.startGesture(firstMovePoint);
    await tester.pump();
    await gesture.moveTo(thirdMovePoint);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'f4', 'a1']);
    expect(_summaryAdvantagePainter(tester).currentIndex, 3);
  });

  testWidgets(
    'deep analysis marks max search time in summary and engine sheet',
    (WidgetTester tester) async {
      db.displaySettings = const DisplaySettings(
        isUnplacedAndRemovedPiecesShown: false,
        isHistoryNavigationToolbarShown: false,
      );
      final NativeMillGameSession session = await _bindNativeGame(
        GameMode.analysis,
      );

      AnalysisMode.enable(
        <MoveAnalysisResult>[
          const MoveAnalysisResult(
            move: 'd6',
            outcome: AnalysisOutcome.advantage,
            rank: 1,
            depth: 12,
            nodes: 256000,
            nodesPerSecond: 64000,
            line: <String>['d6', 'f4', 'a1'],
          ),
        ],
        source: AnalysisSource.engine,
        isEngineAnalysisDeep: true,
      );

      await _pumpSessionPlayArea(tester, session);

      await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('play_area_analysis_summary_engine')),
          matching: find.textContaining('∞'),
        ),
        findsOneWidget,
      );

      await tester.longPress(
        find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('play_area_analysis_engine_status')),
          matching: find.textContaining('∞'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('play_area_analysis_engine_go_deeper')),
        findsNothing,
      );
    },
  );

  testWidgets('analysis summary opens the full move list page', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        boardLayout: '********/********/O*******',
      ),
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();
    final Finder summaryMoves = find.byKey(
      const Key('play_area_analysis_summary_moves'),
    );
    await tester.ensureVisible(summaryMoves);
    await tester.tapAt(tester.getTopLeft(summaryMoves) + const Offset(48, 12));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byKey(const Key('moves_list_page_scaffold')), findsOneWidget);
  });

  testWidgets('analysis summary counts the whole variation tree', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.appendMove(ExtMove('a1', side: PieceColor.black));
    final a1Node = recorder.activeNode!;
    recorder.appendMove(ExtMove('d1', side: PieceColor.white));
    recorder.activeNode = recorder.pgnRoot;
    recorder.appendMove(ExtMove('f4', side: PieceColor.white));
    recorder.activeNode = a1Node;
    recorder.appendMove(ExtMove('g7', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(find.byKey(const Key('play_area_analysis_tab_summary')));
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6', 'a1', 'g7']);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_moves')),
        matching: find.textContaining('3 · d6 a1 g7'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Move list · 3 · d6 a1 g7'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Move list · 3 · d6 a1 g7',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_summary_variations')),
        matching: find.textContaining('2 · Branch moves: f4, g7'),
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Variations · 2 · Branch moves: f4, g7'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics &&
            widget.properties.label == 'Variations · 2 · Branch moves: f4, g7',
      ),
      findsOneWidget,
    );
  });

  testWidgets('analysis menu clears saved moves back to the start position', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);
    final String initialFen = session.getFen();

    expect(
      await session.replayMainline(<ExtMove>[
        ExtMove('d6', side: PieceColor.white),
        ExtMove('f4', side: PieceColor.black),
      ]),
      isTrue,
    );
    await tester.pump();
    expect(_currentPathMoves(), <String>['d6', 'f4']);
    expect(session.getFen(), isNot(initialFen));

    await _pumpSessionPlayArea(tester, session);
    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_regular_game_menu_clear_saved_moves')),
      findsOne,
    );
    expect(find.text('Clear saved moves'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('play_area_regular_game_menu_clear_saved_moves')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), isEmpty);
    expect(session.getFen(), initialFen);
    expect(find.text('Analysis moves cleared.'), findsOneWidget);
  });

  testWidgets('analysis engine button shows source and opens settings', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
    ]);

    await _pumpSessionPlayArea(tester, session);
    Text sourceLabel = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_label')),
    );
    expect(sourceLabel.data, 'DB');
    expect(find.byTooltip('Engine · DB · 1'), findsOneWidget);

    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.advantage),
    ], source: AnalysisSource.engine);
    await tester.pump();
    sourceLabel = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_label')),
    );
    expect(sourceLabel.data, 'Engine');
    Text engineValue = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_value')),
    );
    expect(engineValue.data, '1');
    expect(find.byTooltip('Engine · 1'), findsOneWidget);

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.advantage,
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );
    await tester.pump();
    sourceLabel = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_label')),
    );
    expect(sourceLabel.data, 'Threat');
    expect(find.byTooltip('Engine · Threat · 1'), findsOneWidget);

    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 1,
        nodes: 12000,
        line: <String>['d6', 'f4', 'a1'],
      ),
      const MoveAnalysisResult(
        move: 'a1',
        outcome: AnalysisOutcome.draw,
        rank: 2,
        depth: 8,
        nodes: 128000,
        line: <String>['a1'],
      ),
    ], source: AnalysisSource.engine);
    await tester.pump();
    engineValue = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_value')),
    );
    expect(engineValue.data, '8');
    expect(find.byTooltip('Engine · d8'), findsOneWidget);
    expect(find.text('1. d6 f4 a1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_0')),
        matching: find.text('PV 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_1')),
        matching: find.text('PV 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_0')),
        matching: find.text('d1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_1')),
        matching: find.text('d8'),
      ),
      findsOneWidget,
    );
    final Text engineLineText = tester.widget<Text>(find.text('1. d6 f4 a1'));
    expect(engineLineText.style?.fontSize, 11);

    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(move: 'a1', outcome: AnalysisOutcome.loss),
        const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
      ],
      lineResults: <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'f4',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 7,
          nodes: 64000,
          line: <String>['f4', 'a1'],
        ),
      ],
      source: AnalysisSource.perfectDatabaseAndEngine,
    );
    await tester.pump();
    sourceLabel = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_label')),
    );
    expect(sourceLabel.data, 'DB · Engine');
    engineValue = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_value')),
    );
    expect(engineValue.data, '7');
    expect(find.byTooltip('DB · Engine · d7'), findsOneWidget);
    expect(find.text('1. f4 a1'), findsOneWidget);

    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white, roundIndex: 1),
    );
    GameController().activeSessionSnapshot = const platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.second,
      outcome: platform.GameOutcome.ongoing(),
      phase: 'placing',
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'f4',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 8,
        nodes: 128000,
        nodesPerSecond: 32000,
        line: <String>['f4', 'a1'],
      ),
    ], source: AnalysisSource.engine);
    await tester.pump();
    expect(find.text('1... f4 a1'), findsOneWidget);

    expect(
      tester.widgetList<Text>(find.byType(Text)).where((Text text) {
        return text.data?.contains('#1') ?? false;
      }),
      isEmpty,
    );
    await tester.longPress(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('play_area_analysis_engine_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_status_depth')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_go_deeper')),
      findsOneWidget,
    );
    final IconButton goDeeperButton = tester.widget<IconButton>(
      find.byKey(const Key('play_area_analysis_engine_go_deeper')),
    );
    expect(goDeeperButton.tooltip, 'Continue from here · ∞');
    expect(
      find.byKey(const Key('play_area_analysis_engine_toggle_engine_lines')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_show_threat')),
      findsOneWidget,
    );
    expect(find.text('Show threat'), findsOneWidget);
    expect(
      find.byKey(const Key('play_area_analysis_engine_settings')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_status')),
        matching: find.textContaining('d8'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_status')),
        matching: find.textContaining('128k'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_status')),
        matching: find.textContaining('32k n/s'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_status')),
        matching: find.textContaining('Continue from here · ∞'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const Key('play_area_analysis_engine_settings')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_engine_sheet')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsOneWidget,
    );
    Navigator.of(
      tester.element(
        find.byKey(const Key('play_area_analysis_settings_sheet')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsOneWidget,
    );
  });

  testWidgets('analysis engine sheet toggles engine lines', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 8,
        nodes: 128000,
        line: <String>['d6', 'f4', 'a1'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);
    expect(AnalysisMode.showEngineLines, isTrue);
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsOneWidget,
    );

    await tester.longPress(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('play_area_analysis_engine_toggle_engine_lines')),
    );
    await tester.pumpAndSettle();

    expect(AnalysisMode.showEngineLines, isFalse);
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_hidden')),
      findsOneWidget,
    );
    expect(db.displaySettings.analysisShowEngineLines, isFalse);
  });

  testWidgets('analysis engine sheet labels threat mode', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 8,
          nodes: 128000,
          line: <String>['d6', 'f4', 'a1'],
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );

    await _pumpSessionPlayArea(tester, session);
    await tester.longPress(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_status')),
        matching: find.text('Threat'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_show_threat')),
      findsOneWidget,
    );
    expect(find.text('Stop showing threat'), findsOneWidget);
  });

  testWidgets('analysis engine button shows progress while analyzing', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        rank: 1,
        depth: 8,
        nodes: 128000,
        line: <String>['d6', 'f4', 'a1'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);
    AnalysisMode.setAnalyzing(true);
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_progress')),
      findsOneWidget,
    );
    final CircularProgressIndicator bottomBarProgress = tester
        .widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byKey(
              const Key('play_area_analysis_bottom_bar_engine_progress'),
            ),
            matching: find.byType(CircularProgressIndicator),
          ),
        );
    expect(bottomBarProgress.semanticsLabel, 'Analyzing…');
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_value')),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! Tooltip) {
          return false;
        }
        return widget.message?.startsWith('Engine · Analyzing') ?? false;
      }),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pump();

    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(AnalysisMode.isAnalyzing, isTrue);
    expect(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_progress')),
      findsOneWidget,
    );

    AnalysisMode.setAnalyzing(false);
    await tester.pump();

    final Text engineValue = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine_value')),
    );
    expect(engineValue.data, '8');
  });

  testWidgets('analysis engine popup hides go deeper while analyzing', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.advantage,
        depth: 8,
        nodes: 128000,
        line: <String>['d6', 'f4'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);
    AnalysisMode.setAnalyzing(true);
    await tester.pump();

    await tester.longPress(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_engine_go_deeper')),
      findsNothing,
    );

    AnalysisMode.setAnalyzing(false);
  });

  testWidgets('analysis engine popup hides go deeper after deep search', (
    WidgetTester tester,
  ) async {
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(
      <MoveAnalysisResult>[
        const MoveAnalysisResult(
          move: 'd6',
          outcome: AnalysisOutcome.advantage,
          depth: 12,
          nodes: 256000,
          line: <String>['d6', 'f4'],
        ),
      ],
      source: AnalysisSource.engine,
      isEngineAnalysisDeep: true,
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.longPress(
      find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('play_area_analysis_engine_go_deeper')),
      findsNothing,
    );
  });

  testWidgets('analysis settings sheet toggles engine lines', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      isPositionalAdvantageIndicatorShown: false,
      analysisShowEvaluationGauge: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);
    AnalysisMode.setShowEvaluationGauge(false);
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);

    expect(
      find.byKey(const Key('play_area_analysis_evaluation_gauge')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_advantage_indicator_positioned')),
      findsNothing,
    );

    await _openAnalysisSettingsFromEnginePopup(tester);

    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_engine_lines')),
      findsOneWidget,
    );

    final Finder engineLinesTile = find.byKey(
      const Key('play_area_analysis_settings_engine_lines'),
    );
    await tester.ensureVisible(engineLinesTile);
    await tester.tap(engineLinesTile);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_hidden')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsNothing,
    );
    expect(session.requestedMultiPvValues, isEmpty);
  });

  testWidgets('analysis settings sheet changes engine line count', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);

    expect(AnalysisMode.engineLineCount, AnalysisMode.defaultEngineLineCount);
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_1')),
      findsOneWidget,
    );

    AnalysisMode.setEngineLineCount(3);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_2')),
      findsOneWidget,
    );

    await _openAnalysisSettingsFromEnginePopup(tester);

    expect(
      find.byKey(
        const Key('play_area_analysis_settings_engine_line_count_control'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('play_area_analysis_settings_engine_search_time_control'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('play_area_analysis_settings_engine_threads_control'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_perfect_database')),
      findsOneWidget,
    );
    expect(find.text('Search time'), findsOneWidget);
    expect(find.text('6s'), findsOneWidget);
    expect(find.text('Use perfect database'), findsOneWidget);
    expect(find.text('Search threads'), findsOneWidget);
    expect(find.text('Multiple lines'), findsOneWidget);

    final Finder perfectDatabaseSwitchFinder = find.byKey(
      const Key('play_area_analysis_settings_perfect_database'),
    );
    SwitchListTile perfectDatabaseSwitch = tester.widget<SwitchListTile>(
      perfectDatabaseSwitchFinder,
    );
    expect(perfectDatabaseSwitch.value, isFalse);

    await tester.tap(perfectDatabaseSwitchFinder);
    await tester.pumpAndSettle();

    expect(db.generalSettings.usePerfectDatabase, isTrue);
    perfectDatabaseSwitch = tester.widget<SwitchListTile>(
      perfectDatabaseSwitchFinder,
    );
    expect(perfectDatabaseSwitch.value, isTrue);

    final Finder threadSliderFinder = find.byKey(
      const Key('play_area_analysis_settings_engine_threads_control'),
    );
    Slider threadSlider = tester.widget<Slider>(threadSliderFinder);
    expect(threadSlider.onChanged, isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_settings_engine_threads')),
        matching: find.text('Only available with one engine line'),
      ),
      findsOneWidget,
    );

    final Finder searchTimeSliderFinder = find.byKey(
      const Key('play_area_analysis_settings_engine_search_time_control'),
    );
    final Slider searchTimeSlider = tester.widget<Slider>(
      searchTimeSliderFinder,
    );
    final double maxSearchTimeIndex =
        (AnalysisMode.engineSearchTimeOptionsMs.length - 1).toDouble();
    searchTimeSlider.onChanged!(maxSearchTimeIndex);
    searchTimeSlider.onChangeEnd!(maxSearchTimeIndex);
    await tester.pumpAndSettle();

    expect(AnalysisMode.engineSearchTimeMs, AnalysisMode.maxEngineSearchTimeMs);
    expect(
      db.displaySettings.analysisEngineSearchTimeMs,
      AnalysisMode.maxEngineSearchTimeMs,
    );
    expect(find.text('∞'), findsOneWidget);

    final Finder lineCountSliderFinder = find.byKey(
      const Key('play_area_analysis_settings_engine_line_count_control'),
    );
    Slider lineCountSlider = tester.widget<Slider>(lineCountSliderFinder);
    lineCountSlider.onChanged!(1);
    lineCountSlider.onChangeEnd!(1);
    await tester.pumpAndSettle();

    expect(AnalysisMode.engineLineCount, 1);
    expect(db.displaySettings.analysisEngineLineCount, 1);
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_empty_1')),
      findsNothing,
    );

    threadSlider = tester.widget<Slider>(threadSliderFinder);
    expect(threadSlider.onChanged, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_settings_engine_threads')),
        matching: find.text('Only available with one engine line'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_settings_engine_threads')),
        matching: find.text(db.generalSettings.engineThreads.toString()),
      ),
      findsOneWidget,
    );
    threadSlider.onChanged!(4);
    threadSlider.onChangeEnd!(4);
    await tester.pumpAndSettle();

    expect(db.generalSettings.engineThreads, 8);
    threadSlider = tester.widget<Slider>(threadSliderFinder);
    expect(threadSlider.value, 4);

    lineCountSlider = tester.widget<Slider>(lineCountSliderFinder);
    lineCountSlider.onChanged!(0);
    lineCountSlider.onChangeEnd!(0);
    await tester.pumpAndSettle();

    expect(AnalysisMode.engineLineCount, 0);
    expect(db.displaySettings.analysisEngineLineCount, 0);
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_disabled')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines')),
      findsNothing,
    );
  });

  testWidgets('perfect database analysis lines use display candidates', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    final MoveAnalysisResult weak = MoveAnalysisResult(
      move: 'a1',
      outcome: AnalysisOutcome.withValueAndSteps(AnalysisOutcome.loss, '-1', 6),
    );
    final MoveAnalysisResult best = MoveAnalysisResult(
      move: 'd6',
      outcome: AnalysisOutcome.withValueAndSteps(AnalysisOutcome.win, '1', 2),
    );
    final MoveAnalysisResult draw = MoveAnalysisResult(
      move: 'f4',
      outcome: AnalysisOutcome.withValueAndSteps(AnalysisOutcome.draw, '0', 0),
    );

    AnalysisMode.setEngineLineCount(2);
    AnalysisMode.enable(
      <MoveAnalysisResult>[weak, best, draw],
      lineResults: <MoveAnalysisResult>[best, draw, weak],
      source: AnalysisSource.perfectDatabase,
    );

    await _pumpSessionPlayArea(tester, session);

    expect(AnalysisMode.analysisResults, hasLength(3));
    expect(AnalysisMode.analysisLineResults, hasLength(3));
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_engine_line_2')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_0')),
        matching: find.textContaining('d6'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_line_1')),
        matching: find.textContaining('f4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_engine_lines')),
        matching: find.textContaining('a1'),
      ),
      findsNothing,
    );
  });

  testWidgets('analysis settings line count refreshes engine MultiPV', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.draw,
        rank: 1,
        depth: 1,
        nodes: 1,
        line: <String>['d6'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);
    await _openAnalysisSettingsFromEnginePopup(tester);

    final Slider slider = tester.widget<Slider>(
      find.byKey(
        const Key('play_area_analysis_settings_engine_line_count_control'),
      ),
    );
    slider.onChanged!(3);
    slider.onChangeEnd!(3);
    await tester.pumpAndSettle();

    expect(AnalysisMode.engineLineCount, 3);
    expect(session.requestedMultiPvValues.last, 3);
  });

  testWidgets('hidden analysis engine lines keep configured MultiPV', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);
    AnalysisMode.setEngineLineCount(3);
    AnalysisMode.setShowEngineLines(false);

    await _pumpSessionPlayArea(tester, session);
    await AnalysisService.refresh(tester.element(find.byType(PlayArea)));
    await tester.pumpAndSettle();

    expect(AnalysisMode.showEngineLines, isFalse);
    expect(
      find.byKey(const Key('play_area_analysis_engine_lines_hidden')),
      findsOneWidget,
    );
    expect(session.requestedMultiPvValues.last, 3);
  });

  testWidgets('analysis position refresh is debounced during fast navigation', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);
    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white, roundIndex: 1),
    );

    await _pumpSessionPlayArea(tester, session);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'd6',
        outcome: AnalysisOutcome.draw,
        rank: 1,
        depth: 1,
        nodes: 1,
        line: <String>['d6'],
      ),
    ], source: AnalysisSource.engine);

    GameController().gameRecorder.appendMove(
      ExtMove('f4', side: PieceColor.black, roundIndex: 1),
    );
    GameController().gameRecorder.appendMove(
      ExtMove('a1', side: PieceColor.white, roundIndex: 2),
    );

    await tester.pump(const Duration(milliseconds: 249));
    expect(session.requestedMultiPvValues, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(session.requestedMultiPvValues, hasLength(1));
  });

  testWidgets('analysis engine line tap keeps analysis active', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'a7',
        outcome: AnalysisOutcome.draw,
        rank: 1,
        depth: 1,
        nodes: 1,
        line: <String>['a7'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);

    expect(find.byTooltip('Engine · = · d1 · 1. a7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play_area_analysis_engine_line_0')));
    await tester.pumpAndSettle();

    expect(AnalysisMode.isFullAnalysis, isTrue);
    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.defaultEngineLineCount,
    ]);
    expect(AnalysisMode.analysisResults.single.move, 'd6');

    AnalysisMode.enable(
      const <MoveAnalysisResult>[
        MoveAnalysisResult(
          move: 'f4',
          outcome: AnalysisOutcome.advantage,
          rank: 1,
          depth: 2,
          nodes: 2,
          line: <String>['f4'],
        ),
      ],
      source: AnalysisSource.engine,
      isThreatMode: true,
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! Tooltip) {
          return false;
        }
        final String? message = widget.message;
        return message != null &&
            message.startsWith('Threat · + · d2 · ') &&
            message.contains('f4');
      }),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('play_area_analysis_engine_line_0')));
    await tester.pumpAndSettle();

    expect(AnalysisMode.isThreatMode, isTrue);
    expect(session.requestedMultiPvValues, <int>[
      AnalysisMode.defaultEngineLineCount,
    ]);
    expect(AnalysisMode.analysisResults.single.move, 'f4');
  });

  testWidgets('analysis engine line tap is disabled while analyzing', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final _RecordingAnalysisSession session = _RecordingAnalysisSession();
    _bindExistingNativeGame(GameMode.analysis, session);

    AnalysisMode.enable(const <MoveAnalysisResult>[
      MoveAnalysisResult(
        move: 'a7',
        outcome: AnalysisOutcome.draw,
        rank: 1,
        depth: 1,
        nodes: 1,
        line: <String>['a7'],
      ),
    ], source: AnalysisSource.engine);

    await _pumpSessionPlayArea(tester, session);
    AnalysisMode.setAnalyzing(true);
    await tester.pump();

    await tester.tap(find.byKey(const Key('play_area_analysis_engine_line_0')));
    await tester.pump();

    expect(session.requestedMultiPvValues, isEmpty);
    expect(AnalysisMode.analysisResults.single.move, 'a7');
    expect(AnalysisMode.isAnalyzing, isTrue);

    AnalysisMode.setAnalyzing(false);
    await tester.pump();
  });

  testWidgets('analysis settings sheet toggles evaluation displays', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isPositionalAdvantageIndicatorShown: false,
      analysisShowEvaluationGauge: false,
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    AnalysisMode.setShowEvaluationGauge(false);
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    AnalysisMode.enable(<MoveAnalysisResult>[
      const MoveAnalysisResult(move: 'd6', outcome: AnalysisOutcome.win),
    ]);

    await _pumpSessionPlayArea(tester, session);

    await _openAnalysisSettingsFromEnginePopup(tester);

    expect(
      find.byKey(const Key('play_area_analysis_settings_evaluation_gauge')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_settings_advantage_graph')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_evaluation_gauge')),
      findsNothing,
    );

    final Finder evaluationGaugeTile = find.byKey(
      const Key('play_area_analysis_settings_evaluation_gauge'),
    );
    await tester.ensureVisible(evaluationGaugeTile);
    await tester.tap(evaluationGaugeTile);
    await tester.pumpAndSettle();

    expect(db.displaySettings.analysisShowEvaluationGauge, isTrue);
    expect(db.displaySettings.isPositionalAdvantageIndicatorShown, isFalse);
    expect(
      find.byKey(const Key('play_area_analysis_evaluation_gauge')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_advantage_indicator_positioned')),
      findsNothing,
    );

    final Finder advantageGraphTile = find.byKey(
      const Key('play_area_analysis_settings_advantage_graph'),
    );
    await tester.ensureVisible(advantageGraphTile);
    await tester.tap(advantageGraphTile);
    await tester.pumpAndSettle();

    expect(db.displaySettings.isAdvantageGraphShown, isTrue);
  });

  testWidgets('analysis settings sheet toggles small board', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);
    final Size regularBoardSize = tester.getSize(
      find.byKey(const Key('play_area_analysis_board')),
    );

    await _openAnalysisSettingsFromEnginePopup(tester);

    expect(
      find.byKey(const Key('play_area_analysis_settings_small_board')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_settings_small_board')),
    );
    await tester.pumpAndSettle();

    final Size smallBoardSize = tester.getSize(
      find.byKey(const Key('play_area_analysis_board')),
    );
    expect(smallBoardSize.width, lessThan(regularBoardSize.width));
    expect(smallBoardSize.height, lessThan(regularBoardSize.height));
    expect(db.displaySettings.analysisSmallBoard, isTrue);
  });

  testWidgets('analysis settings sheet opens explorer source settings', (
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
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);
    await _openAnalysisSettingsFromEnginePopup(tester);

    final Finder explorerSourcesTile = find.byKey(
      const Key('play_area_analysis_settings_opening_explorer_sources'),
    );
    expect(explorerSourcesTile, findsOneWidget);
    await tester.ensureVisible(explorerSourcesTile);
    await tester.tap(explorerSourcesTile);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_settings_sheet')),
      findsNothing,
    );
    expect(find.byKey(const Key('ai_knowledge_sources_page')), findsOneWidget);
    expect(
      find.byKey(const Key('ai_knowledge_sources_page_opening_book_card')),
      findsOneWidget,
    );
  });

  testWidgets('analysis settings sheet toggles move display preferences', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await _pumpSessionPlayArea(tester, session);
    await _openAnalysisSettingsFromEnginePopup(tester);

    final Finder annotationsTile = find.byKey(
      const Key('play_area_analysis_settings_move_annotations'),
    );
    final Finder inlineNotationTile = find.byKey(
      const Key('play_area_analysis_settings_inline_notation'),
    );
    final Finder commentsTile = find.byKey(
      const Key('play_area_analysis_settings_move_comments'),
    );
    final Finder bestMoveArrowTile = find.byKey(
      const Key('play_area_analysis_settings_best_move_arrow'),
    );

    await tester.tap(inlineNotationTile);
    await tester.pumpAndSettle();
    await tester.tap(annotationsTile);
    await tester.pumpAndSettle();
    await tester.tap(commentsTile);
    await tester.pumpAndSettle();
    await tester.ensureVisible(bestMoveArrowTile);
    await tester.tap(bestMoveArrowTile);
    await tester.pumpAndSettle();

    expect(AnalysisMode.inlineNotation, isTrue);
    expect(AnalysisMode.showMoveAnnotations, isFalse);
    expect(AnalysisMode.showMoveComments, isFalse);
    expect(AnalysisMode.showBestMoveArrow, isFalse);
    expect(db.displaySettings.analysisInlineNotation, isTrue);
    expect(db.displaySettings.analysisShowMoveAnnotations, isFalse);
    expect(db.displaySettings.analysisShowMoveComments, isFalse);
    expect(db.displaySettings.analysisShowBestMoveArrow, isFalse);
  });

  test(
    'controller starts a playable game from the current analysis FEN',
    () async {
      final NativeMillGameSession session = await _bindNativeGame(
        GameMode.analysis,
      );
      final String fen = session.getFen();

      final bool started = GameController().startGameFromFen(
        mode: GameMode.humanVsHuman,
        fen: fen,
      );

      expect(started, isTrue);
      expect(GameController().gameInstance.gameMode, GameMode.humanVsHuman);
      expect(GameController().gameRecorder.setupPosition, fen);
      expect(GameController().activeNativeMillSession?.getFen(), fen);
    },
  );

  testWidgets('human vs ai move list wraps when the line is full', (
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
    expect(moveListScrollView.scrollDirection, Axis.vertical);
    expect(find.byKey(const Key('play_area_human_ai_move_1')), findsOneWidget);
    expect(find.byKey(const Key('play_area_human_ai_move_20')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('play_area_human_ai_move_20'))).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const Key('play_area_human_ai_move_1')))
            .dy,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_human_ai_move_20')),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_inline_move_list_scroll_view')),
        matching: find.byType(Wrap),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('play_area_human_ai_move_list_wrap')))
          .height,
      104,
    );
    expect(
      tester
          .getBottomLeft(find.byKey(const Key('play_area_human_ai_move_20')))
          .dy,
      lessThanOrEqualTo(
        tester
            .getBottomLeft(
              find.byKey(const Key('play_area_human_ai_move_list_wrap')),
            )
            .dy,
      ),
    );
  });

  testWidgets('human vs ai move list constrains long capture groups', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings();
    db.displaySettings = const DisplaySettings();
    final GameController controller = GameController();
    controller.gameInstance.gameMode = GameMode.humanVsAi;
    for (final String notation in <String>[
      'd6',
      'xa1',
      'xd1',
      'xg1',
      'xb2',
      'xd2',
      'xf2',
      'xc3',
      'xd3',
      'xe3',
      'a4',
      'b4',
    ]) {
      controller.gameRecorder.appendMove(
        ExtMove(notation, side: PieceColor.white),
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

    final Finder groupedMove = find.byKey(
      const Key('play_area_human_ai_move_12'),
    );
    final Finder moveList = find.byKey(
      const Key('play_area_human_ai_move_list_wrap'),
    );
    expect(find.byKey(const Key('play_area_human_ai_move_1')), findsNothing);
    expect(find.byKey(const Key('play_area_human_ai_move_2')), findsNothing);
    expect(groupedMove, findsOneWidget);
    expect(
      find.text('d6 xa1 xd1 xg1 xb2 xd2 xf2 xc3 xd3 xe3 a4 b4'),
      findsOneWidget,
    );
    expect(
      tester.getSize(groupedMove).height,
      greaterThan(tester.getSize(find.text('1.')).height),
    );
    expect(
      tester.getTopRight(groupedMove).dx,
      lessThanOrEqualTo(tester.getTopRight(moveList).dx),
    );
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

  testWidgets('analysis panel opens moves first and keeps explorer as a tab', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove('d6', side: PieceColor.white),
    );

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_menu')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_regular_game_menu_opening_explorer')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('play_area_regular_game_menu_continue_from_here')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('play_area_analysis_moves')), findsOneWidget);

    Navigator.of(
      tester.element(
        find.byKey(const Key('play_area_regular_game_menu_sheet')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('opening_explorer_embedded')), findsOneWidget);
  });

  testWidgets('analysis explorer moves are applied to the analysis tree', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);

    await _pumpSessionPlayArea(tester, session);
    expect(_currentPathMoves(), isEmpty);

    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opening_explorer_embedded')), findsOneWidget);

    for (
      int i = 0;
      i < 20 &&
          find
              .byKey(const Key('opening_explorer_loading_row_0'))
              .evaluate()
              .isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final Finder moveRows = find.byWidgetPredicate((Widget widget) {
      final Key? key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('opening_explorer_move_');
    }, description: 'rendered opening explorer move row');
    expect(moveRows, findsWidgets);
    final Finder firstMoveFinder = moveRows.first;
    expect(firstMoveFinder, findsOneWidget);

    final Widget firstMoveWidget = tester.widget<Widget>(firstMoveFinder);
    final String selectedMove = (firstMoveWidget.key! as ValueKey<String>).value
        .substring('opening_explorer_move_'.length);

    await tester.tap(firstMoveFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_currentPathMoves(), <String>[selectedMove]);
    expect(
      find.byKey(Key('opening_explorer_move_$selectedMove')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_previous')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_currentPathMoves(), isEmpty);
    expect(
      find.byKey(Key('opening_explorer_move_$selectedMove')),
      findsOneWidget,
    );
  });

  testWidgets('analysis moves tab opens the full move list page', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      movesViewLayout: MovesViewLayout.list,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    GameController().gameRecorder.reset();
    GameController().gameRecorder.appendMove(
      ExtMove(
        'd6',
        side: PieceColor.white,
        boardLayout: '********/********/O*******',
      ),
    );

    await _pumpSessionPlayArea(tester, session);

    expect(
      find.byKey(const Key('play_area_analysis_open_full_move_list')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Move list · Small board · Current line only · 1'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_open_full_move_list')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byKey(const Key('moves_list_page_scaffold')), findsOneWidget);
    expect(find.byType(MiniBoard), findsOneWidget);
    expect(find.byTooltip('Board: Move d6'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.label == 'Board: Move d6',
      ),
      findsOneWidget,
    );
    expect(db.displaySettings.movesViewLayout, MovesViewLayout.list);
  });

  testWidgets('analysis full move list opens near the active node', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
      movesViewLayout: MovesViewLayout.medium,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    <ExtMove>[
      ExtMove('a1', side: PieceColor.white),
      ExtMove('d1', side: PieceColor.black),
      ExtMove('a4', side: PieceColor.white),
      ExtMove('d2', side: PieceColor.black),
      ExtMove('a7', side: PieceColor.white),
      ExtMove('d3', side: PieceColor.black),
      ExtMove('d6', side: PieceColor.white),
      ExtMove('f4', side: PieceColor.black),
      ExtMove('g1', side: PieceColor.white),
      ExtMove('g4', side: PieceColor.black),
      ExtMove('g7', side: PieceColor.white),
      ExtMove('b2', side: PieceColor.black),
      ExtMove('d5', side: PieceColor.white),
      ExtMove('f6', side: PieceColor.black),
    ].forEach(recorder.appendMove);

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(
      find.byKey(const Key('play_area_analysis_open_full_move_list')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byKey(const Key('moves_list_page_scaffold')), findsOneWidget);
    expect(
      find.byKey(const Key('moves_list_active_node_item')),
      findsOneWidget,
    );
    expect(find.text('7... f6'), findsOneWidget);
  });

  testWidgets('analysis moves tab shows a variations bar', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white, nags: <int>[1]));
    recorder.activeNode = recorder.pgnRoot;
    recorder.appendMove(ExtMove('f4', side: PieceColor.white, nags: <int>[2]));
    recorder.activeNode = recorder.pgnRoot;
    recorder.moveCountNotifier.value = 0;

    await _pumpSessionPlayArea(tester, session);

    final Text movesHeaderTitle = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_moves_header_title')),
    );
    expect(movesHeaderTitle.data, 'Move list');
    final Text movesHeaderSubtitle = tester.widget<Text>(
      find.byKey(const Key('play_area_analysis_moves_header_subtitle')),
    );
    expect(
      movesHeaderSubtitle.data,
      contains('Current line only · 1 · Variations 1'),
    );
    expect(
      find.byKey(const Key('play_area_analysis_variations_bar_content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_variation_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_variation_2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_1')),
        matching: find.text('d6!'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_2')),
        matching: find.text('f4?'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Variation: d6!'), findsOneWidget);
    expect(find.byTooltip('Variation: f4?'), findsOneWidget);

    AnalysisMode.setShowMoveAnnotations(false);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_1')),
        matching: find.text('d6'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_2')),
        matching: find.text('f4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_1')),
        matching: find.text('d6!'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_variation_2')),
        matching: find.text('f4?'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Variation: d6'), findsOneWidget);
    expect(find.byTooltip('Variation: f4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play_area_analysis_variation_2')));
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['f4']);
    expect(
      find.byKey(const Key('play_area_analysis_variations_bar_content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_path_variation_1_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_path_variation_1_2')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_previous')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), isEmpty);
    expect(
      find.byKey(const Key('play_area_analysis_variations_bar_content')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_bottom_bar_next')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6']);
  });

  testWidgets('analysis variations bar keeps ancestor branches visible', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.activeNode = recorder.pgnRoot;
    recorder.appendMove(ExtMove('f4', side: PieceColor.white));
    recorder.appendMove(ExtMove('a1', side: PieceColor.black));
    final a1Node = recorder.activeNode!;
    recorder.appendMove(ExtMove('d1', side: PieceColor.white));
    recorder.activeNode = a1Node;
    recorder.appendMove(ExtMove('g7', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);

    expect(_currentPathMoves(), <String>['f4', 'a1', 'g7']);
    expect(
      find.byKey(const Key('play_area_analysis_path_variation_group_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_path_variation_group_3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_path_variation_1_1')),
        matching: find.text('d6'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_path_variation_1_2')),
        matching: find.text('f4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_path_variation_3_1')),
        matching: find.text('d1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('play_area_analysis_path_variation_3_2')),
        matching: find.text('g7'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_path_variation_1_1')),
    );
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6']);
  });

  testWidgets('analysis move actions promote a sideline to mainline', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.activeNode = recorder.pgnRoot;
    recorder.appendMove(ExtMove('f4', side: PieceColor.white));
    recorder.activeNode = recorder.pgnRoot;
    recorder.moveCountNotifier.value = 0;

    await _pumpSessionPlayArea(tester, session);

    await tester.tap(find.byKey(const Key('play_area_analysis_variation_2')));
    await tester.pumpAndSettle();
    expect(_currentPathMoves(), <String>['f4']);

    await tester.longPress(find.byKey(const Key('play_area_analysis_move_1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_move_actions_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_move_action_set_main_line')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_move_action_set_main_line')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(recorder.pgnRoot.children.first.data?.move, 'f4');
    expect(_currentPathMoves(), <String>['f4']);
  });

  testWidgets('analysis move actions promote the nearest variation only', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.activeNode = recorder.pgnRoot;
    recorder.appendMove(ExtMove('f4', side: PieceColor.white));
    recorder.appendMove(ExtMove('a1', side: PieceColor.black));
    final a1Node = recorder.activeNode!;
    recorder.appendMove(ExtMove('d1', side: PieceColor.white));
    recorder.activeNode = a1Node;
    recorder.appendMove(ExtMove('g7', side: PieceColor.white));

    await _pumpSessionPlayArea(tester, session);
    expect(_currentPathMoves(), <String>['f4', 'a1', 'g7']);
    expect(recorder.pgnRoot.children.first.data?.move, 'd6');
    expect(a1Node.children.first.data?.move, 'd1');

    await tester.longPress(find.byKey(const Key('play_area_analysis_move_3')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('play_area_analysis_move_action_make_primary_variation'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const Key('play_area_analysis_move_action_make_primary_variation'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(recorder.pgnRoot.children.first.data?.move, 'd6');
    expect(a1Node.children.first.data?.move, 'g7');
    expect(_currentPathMoves(), <String>['f4', 'a1', 'g7']);
  });

  testWidgets('analysis move actions delete from the selected move', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );
    final GameRecorder recorder = GameController().gameRecorder;
    recorder.reset();
    recorder.appendMove(ExtMove('d6', side: PieceColor.white));
    recorder.appendMove(ExtMove('f4', side: PieceColor.black));

    await _pumpSessionPlayArea(tester, session);
    expect(_currentPathMoves(), <String>['d6', 'f4']);

    await tester.longPress(find.byKey(const Key('play_area_analysis_move_2')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('play_area_analysis_move_actions_sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('play_area_analysis_move_action_delete_from_here')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('play_area_analysis_move_action_delete_from_here')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_currentPathMoves(), <String>['d6']);
    expect(recorder.pgnRoot.children.single.children, isEmpty);
    expect(find.byKey(const Key('play_area_analysis_move_2')), findsNothing);
  });

  testWidgets('analysis uses a framed side panel in landscape', (
    WidgetTester tester,
  ) async {
    db.displaySettings = const DisplaySettings(
      isUnplacedAndRemovedPiecesShown: false,
      isHistoryNavigationToolbarShown: false,
    );
    final NativeMillGameSession session = await _bindNativeGame(
      GameMode.analysis,
    );

    await tester.binding.setSurfaceSize(const Size(900, 420));
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
                dimension: 388,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder landscapeContent = find.byKey(
      const Key('play_area_analysis_landscape_content'),
    );
    final Finder boardPane = find.byKey(
      const Key('play_area_analysis_landscape_board_pane'),
    );
    final Finder sidePanel = find.byKey(
      const Key('play_area_analysis_landscape_side_panel'),
    );
    final Finder panelCard = find.byKey(
      const Key('play_area_analysis_panel_card'),
    );

    expect(landscapeContent, findsOneWidget);
    expect(boardPane, findsOneWidget);
    expect(sidePanel, findsOneWidget);
    expect(panelCard, findsOneWidget);
    expect(find.descendant(of: sidePanel, matching: panelCard), findsOneWidget);
    expect(
      tester.getTopLeft(boardPane).dx,
      lessThan(tester.getTopLeft(sidePanel).dx),
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
    final Finder bottomBar = find.byKey(
      const Key('play_area_lichess_bottom_bar'),
    );
    expect(bottomBar, findsOne);
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
      tester.getTopLeft(bottomBar).dy,
      greaterThan(tester.getBottomLeft(sidePanel).dy),
    );
    expect(
      tester.getBottomLeft(bottomBar).dy,
      tester.getBottomLeft(landscapeContent).dy,
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
    final Finder bottomBar = find.byKey(
      const Key('play_area_main_toolbar_bottom'),
    );
    expect(bottomBar, findsOne);
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
      tester.getTopLeft(bottomBar).dy,
      greaterThan(tester.getBottomLeft(sidePanel).dy),
    );
    expect(
      tester.getBottomLeft(bottomBar).dy,
      tester.getBottomLeft(landscapeContent).dy,
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
        tester
                .getBottomLeft(find.byKey(const Key('game_page_back_button')))
                .dy +
            8,
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

  testWidgets('human vs ai takeback stays safe after reaching start', (
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
    await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
    await tester.pumpAndSettle();
    expect(_currentPathMoves(), isEmpty);

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_currentPathMoves(), isEmpty);
  });

  testWidgets('human vs ai disables takeback when requester has no turn', (
    WidgetTester tester,
  ) async {
    db.generalSettings = const GeneralSettings(aiMovesFirst: true);
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

    await _pumpSessionPlayArea(tester, session);
    expect(
      _bottomBarButtonOpacity(
        tester,
        const Key('play_area_bottom_bar_take_back'),
      ),
      0.4,
    );

    await tester.tap(find.byKey(const Key('play_area_bottom_bar_take_back')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_currentPathMoves(), <String>['d6']);
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
  navigatorKey: currentNavigatorKey,
  scaffoldMessengerKey: rootScaffoldMessengerKey,
  theme: AppTheme.lightThemeData,
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

Future<void> _holdBottomBarButton(WidgetTester tester, Key key) async {
  final Finder button = find.byKey(key);
  expect(button, findsOneWidget);
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(button),
  );
  await tester.pump(const Duration(milliseconds: 900));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _openAnalysisSettingsFromEnginePopup(WidgetTester tester) async {
  await tester.longPress(
    find.byKey(const Key('play_area_analysis_bottom_bar_engine')),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(const Key('play_area_analysis_engine_settings')),
    findsOneWidget,
  );
  await tester.tap(find.byKey(const Key('play_area_analysis_engine_settings')));
  await tester.pumpAndSettle();
}

Future<NativeMillGameSession> _bindNativeHumanAiGame() {
  return _bindNativeGame(GameMode.humanVsAi);
}

class _MoveNowFakeSearchSession extends NativeMillGameSession {
  _MoveNowFakeSearchSession({this.actionLimit})
    : super.fromPort(NativeMillRulesPort());

  final int? actionLimit;

  int searchCalls = 0;

  @override
  Future<platform.GameAction?> searchBestAction({
    int depth = 1,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
  }) async {
    searchCalls++;
    if (actionLimit != null && searchCalls > actionLimit!) {
      return null;
    }
    return legalActions.isEmpty ? null : legalActions.first;
  }
}

Future<NativeMillGameSession> _bindNativeGame(GameMode gameMode) async {
  final NativeMillGameSession session = NativeMillGameSession();
  _bindExistingNativeGame(gameMode, session);
  return session;
}

void _bindExistingNativeGame(GameMode gameMode, NativeMillGameSession session) {
  final GameController controller = GameController();
  controller.reset(force: true);
  controller.gameInstance.gameMode = gameMode;
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

Finder _boardSquareSemanticsFinder() {
  return find.byWidgetPredicate((Widget widget) {
    final Key? key = widget.key;
    return widget is Semantics &&
        key is ValueKey<String> &&
        key.value.startsWith('board_square_');
  });
}

List<String> _currentPathMoves() {
  return GameController().gameRecorder.currentPath
      .map((ExtMove move) => move.move)
      .toList();
}

AdvantageGraphPainter _summaryAdvantagePainter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byKey(const Key('play_area_analysis_summary_advantage_paint')),
  );
  final CustomPainter? painter = paint.painter;
  assert(
    painter is AdvantageGraphPainter,
    'Analysis summary graph must use AdvantageGraphPainter.',
  );
  return painter! as AdvantageGraphPainter;
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

class _RecordingAnalysisSession extends NativeMillGameSession {
  _RecordingAnalysisSession() : super.fromPort(NativeMillRulesPort());

  final List<int> requestedMultiPvValues = <int>[];

  @override
  Future<List<NativeMillPrincipalVariation>> searchPrincipalVariations({
    int depth = 1,
    int moveLimitMs = 0,
    required int multiPv,
    GeneralSettings? engineSettings,
    void Function(List<NativeMillPrincipalVariation> variations)? onUpdate,
  }) async {
    requestedMultiPvValues.add(multiPv);
    const List<NativeMillPrincipalVariation> variations =
        <NativeMillPrincipalVariation>[
          NativeMillPrincipalVariation(
            rank: 1,
            move: 'd6',
            score: 0,
            nodes: 1,
            depth: 1,
            line: <String>['d6'],
          ),
        ];
    onUpdate?.call(variations);
    return variations;
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
