// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Widget integration tests for puzzle auto-play / move-validation flows on top
// of [NativeMillGameSession] + [MillSessionRecorderBridge].

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/animation/headless_animation_manager.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/game_page/services/player_timer.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/game_page/widgets/mini_board.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';
import 'package:sanmill/games/mill/mill_board_transform_actions.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/puzzle_page.dart';
import 'package:sanmill/puzzle/services/puzzle_auto_player.dart';
import 'package:sanmill/puzzle/services/puzzle_manager.dart';
import 'package:sanmill/puzzle/services/puzzle_rule_engine.dart';
import 'package:sanmill/puzzle/services/puzzle_transform_service.dart';
import 'package:sanmill/puzzle/widgets/puzzle_completion_confetti.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/themes/app_theme.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_audios.dart';
import '../helpers/test_native_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  const String initialFen =
      '********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';

  late Directory appDocDir;
  late NativeMillGameSession nativeSession;
  MillSessionRecorderBridge? recorderBridge;
  VoidCallback? sessionSnapshotListener;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              return 'uciok';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    appDocDir = Directory.systemTemp.createTempSync('sanmill_puzzle_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return appDocDir.path;
            default:
              return null;
          }
        });

    await initRustLibForTests();
    await DB.init();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    disposeRustLibForTests();
  });

  setUp(() {
    DB().displaySettings = const DisplaySettings(animationDuration: 0.0);
    DB().puzzleSettings = const PuzzleSettings(showHints: true);
    PuzzleManager().settingsNotifier.value = const PuzzleSettings(
      showHints: true,
    );
    SoundManager.instance = MockAudios();
    // Force a deterministic board orientation so move notations are stable.
    PuzzlePage.debugTransformationOverride = TransformationType.identity;

    final GameController controller = GameController();
    controller.reset(force: true);
    controller.puzzleHumanColor = null;
    controller.isPuzzleAutoMoveInProgress = false;
    controller.isControllerReady = true;
    controller.animationManager = HeadlessAnimationManager();

    nativeSession = NativeMillGameSession();
    controller.bindActiveSession(nativeSession);
    void listener() {
      controller.activeSessionSnapshot = nativeSession.state.value;
      controller.headerIconsNotifier.showIcons();
      controller.boardSemanticsNotifier.updateSemantics();
    }

    nativeSession.state.addListener(listener);
    sessionSnapshotListener = listener;
  });

  tearDown(() async {
    PuzzlePage.debugTransformationOverride = null;
    if (sessionSnapshotListener != null) {
      nativeSession.state.removeListener(sessionSnapshotListener!);
      sessionSnapshotListener = null;
    }
    await recorderBridge?.dispose();
    recorderBridge = null;
    nativeSession.dispose();
    GameController().reset(force: true);
  });

  PuzzleInfo buildPuzzle({
    required List<List<String>> solutions,
    String? initialPosition,
    bool markFirstSolutionOptimal = false,
    String id = 'test_puzzle',
    String title = 'Test Puzzle',
    PuzzleDifficulty difficulty = PuzzleDifficulty.easy,
  }) {
    final String fen = initialPosition ?? initialFen;
    final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(fen);
    assert(engine != null, 'Failed to load test FEN: $fen');
    final PieceColor startingSide = engine!.view.sideToMove;
    engine.dispose();

    final List<PuzzleSolution> puzzleSolutions = solutions.asMap().entries.map((
      MapEntry<int, List<String>> entry,
    ) {
      PieceColor currentSide = startingSide;
      final List<PuzzleMove> puzzleMoves = entry.value.map((String notation) {
        final PuzzleMove move = PuzzleMove(
          notation: notation,
          side: currentSide,
        );
        currentSide = currentSide.opponent;
        return move;
      }).toList();

      return PuzzleSolution(
        moves: puzzleMoves,
        isOptimal: markFirstSolutionOptimal && entry.key == 0,
      );
    }).toList();

    return PuzzleInfo(
      id: id,
      title: title,
      description: 'Test puzzle for native-session auto-play behavior.',
      category: PuzzleCategory.formMill,
      difficulty: difficulty,
      initialPosition: fen,
      solutions: puzzleSolutions,
      tags: const <String>['test'],
      isCustom: true,
      author: 'test',
    );
  }

  String buildPositionFenForOpponentMillThenRemove() {
    final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(initialFen);
    assert(engine != null, 'Failed to load base test FEN.');
    const List<String> setupMoves = <String>['d1', 'a1', 'd2', 'a4'];
    final int applied = engine!.applyMoves(setupMoves);
    assert(applied == setupMoves.length, 'Failed to apply setup moves.');
    final String? fen = engine.view.fen;
    engine.dispose();
    assert(fen != null && fen.isNotEmpty, 'Generated FEN is empty.');
    return fen!;
  }

  String buildPositionFenForHumanMillThenRemove() {
    final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(initialFen);
    assert(engine != null, 'Failed to load base test FEN.');
    const List<String> setupMoves = <String>['a1', 'd1', 'a4', 'd2'];
    final int applied = engine!.applyMoves(setupMoves);
    assert(applied == setupMoves.length, 'Failed to apply setup moves.');
    final String? fen = engine.view.fen;
    engine.dispose();
    assert(fen != null && fen.isNotEmpty, 'Generated FEN is empty.');
    return fen!;
  }

  TransformationType detectLoadedTransform({
    required String originalFen,
    required String loadedFen,
  }) {
    final String loadedBoard = loadedFen.split(' ').first;
    for (final TransformationType type in TransformationType.values) {
      final String candidateBoard = transformFEN(
        originalFen,
        type,
      ).split(' ').first;
      if (candidateBoard == loadedBoard) {
        return type;
      }
    }
    throw StateError(
      'Could not detect board transform for loaded FEN: $loadedFen',
    );
  }

  PuzzleInfo loadedTransformedPuzzle(PuzzleInfo base) {
    final GameController controller = GameController();
    final String? loadedFen =
        controller.activeNativeMillSession?.getFen() ?? controller.activeFen;
    assert(loadedFen != null && loadedFen.isNotEmpty);
    final TransformationType type = detectLoadedTransform(
      originalFen: base.initialPosition,
      loadedFen: loadedFen!,
    );
    return PuzzleTransformService.transformPuzzle(base, type);
  }

  Future<void> pumpPuzzlePage(
    WidgetTester tester,
    PuzzleInfo puzzle, {
    ThemeData? theme,
    Size viewSize = const Size(1024, 768),
    bool pushFromList = false,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Widget puzzlePage = GameSessionScope(
      session: nativeSession,
      child: PuzzlePage(puzzle: puzzle),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('en'),
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: pushFromList
            ? Builder(
                builder: (BuildContext context) {
                  return Scaffold(
                    key: const Key('puzzle_list_test_page'),
                    body: TextButton(
                      key: const Key('open_test_puzzle'),
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) => puzzlePage,
                          ),
                        );
                      },
                      child: const Text('Open puzzle'),
                    ),
                  );
                },
              )
            : puzzlePage,
      ),
    );
    if (pushFromList) {
      await tester.tap(find.byKey(const Key('open_test_puzzle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump();
    // PuzzlePage._initializePuzzle() resets GameController and replaces the
    // GameRecorder, so bind the bridge only after the page has initialized.
    await recorderBridge?.dispose();
    recorderBridge = MillSessionRecorderBridge.forGameController(
      session: nativeSession,
    );
    await tester.pump();
  }

  /// Flushes pending microtasks (stream delivery), post-frame callbacks
  /// (puzzle auto-play), and any chained opponent responses by pumping until
  /// the recorded move count stabilizes.
  ///
  /// NOTE: `tester.pump` advances the test's fake clock, so this never blocks
  /// on real time; the iteration cap guards against an unexpected live ticker.
  Future<void> drainUi(WidgetTester tester) async {
    final GameController controller = GameController();
    int previous = -1;
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final int current = controller.gameRecorder.currentPath.length;
      if (current == previous && i > 2) {
        break;
      }
      previous = current;
    }
  }

  /// Tears the puzzle page down inside the test body so the framework's
  /// pending-timer invariant check passes.
  ///
  /// Unmounting runs `PuzzlePage.dispose()`, which restores rule settings and
  /// schedules a one-shot 300ms engine-options debounce timer; pumping past it
  /// lets the timer fire and clear. The periodic [PlayerTimer] is cancelled
  /// explicitly because pumping never drains a periodic timer.
  Future<void> teardownPuzzlePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    PlayerTimer().reset();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> applyHumanMoveViaNativeSession(String notation) async {
    final bool ok = nativeSession.applyMoveString(notation);
    expect(ok, isTrue, reason: 'Failed to apply human move: $notation');
  }

  String pickWrongFirstMove(PuzzleInfo transformed) {
    final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(
      transformed.initialPosition,
    );
    assert(engine != null);
    for (final String move in engine!.legalMoveNotations()) {
      final String normalized = PuzzleAutoPlayer.normalizeMove(move);
      final bool matchesSolutionPrefix = transformed.solutions.any(
        (PuzzleSolution solution) =>
            solution.moves.isNotEmpty &&
            PuzzleAutoPlayer.normalizeMove(solution.moves.first.notation) ==
                normalized,
      );
      if (!matchesSolutionPrefix) {
        engine.dispose();
        return move;
      }
    }
    engine.dispose();
    throw StateError('No non-matching legal first move found.');
  }

  group('Puzzle native session widget flows', () {
    testWidgets(
      'shows Lichess-style puzzle bottom actions',
      (WidgetTester tester) async {
        DB().displaySettings = const DisplaySettings(
          animationDuration: 0.0,
          isAnnotationToolbarShown: true,
        );
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        expect(
          find.byKey(const Key('puzzle_page_lichess_bottom_bar')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('puzzle_page_reference')), findsOneWidget);
        expect(find.text('Puzzle #${puzzle.referenceCode}'), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_page_bottom_bar_menu')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_page_bottom_bar_give_up')),
          findsOneWidget,
        );
        expect(find.byTooltip('Give up'), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_page_app_bar_more')),
          findsOneWidget,
        );
        final Finder annotationButton = find.byKey(
          const Key('puzzle_page_app_bar_annotation_button'),
        );
        expect(annotationButton, findsOneWidget);
        final IconButton annotationIconButton = tester.widget<IconButton>(
          annotationButton,
        );
        expect(
          annotationIconButton.style?.backgroundColor?.resolve(<WidgetState>{}),
          Colors.transparent,
        );
        expect(
          find.byKey(const Key('annotation_toolbar_collapsed_position')),
          findsNothing,
        );
        await tester.tap(annotationButton);
        await tester.pump();
        expect(
          find.byKey(const Key('annotation_toolbar_surface')),
          findsOneWidget,
        );
        await tester.tap(annotationButton);
        await tester.pump();
        expect(
          find.byKey(const Key('annotation_toolbar_surface')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_page_app_bar_more')),
            matching: find.byIcon(Icons.more_vert),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('puzzle_page_app_bar_skip')), findsNothing);
        await tester.tap(find.byKey(const Key('puzzle_page_app_bar_more')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.byKey(const Key('puzzle_page_app_bar_skip')),
          findsOneWidget,
        );
        expect(find.text('Skip puzzle'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          find.byKey(const Key('puzzle_page_bottom_bar_skip')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('puzzle_page_bottom_bar_undo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_page_bottom_bar_hint')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('play_area_human_ai_landscape_side_panel')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('play_area_lichess_bottom_bar_builder')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('puzzle_page_bottom_bar_menu')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const Key('puzzle_page_action_sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_page_action_rotate')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_page_action_show_solution')),
          findsOneWidget,
        );
        expect(find.text('Show solution'), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_page_action_reset')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('puzzle_page_action_reset')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'keeps the puzzle screenshot tight while annotation tools are open',
      (WidgetTester tester) async {
        DB().displaySettings = const DisplaySettings(
          animationDuration: 0.0,
          isAnnotationToolbarShown: true,
          isScreenshotGameInfoShown: false,
        );
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle, viewSize: const Size(430, 800));

        await tester.tap(
          find.byKey(const Key('puzzle_page_app_bar_annotation_button')),
        );
        await tester.pump();

        final Rect screenshotRect = tester.getRect(
          find.byKey(const Key('play_area_native_screenshot')),
        );
        final Rect boardRect = tester.getRect(
          find.byKey(const Key('play_area_game_board_container')),
        );
        expect(screenshotRect, boardRect);
        expect(
          screenshotRect.bottom,
          lessThanOrEqualTo(
            tester
                .getRect(
                  find.byKey(const Key('annotation_toolbar_expanded_position')),
                )
                .top,
          ),
        );

        await tester.tap(find.byTooltip('Take screenshot'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'labels the exit confirmation as leaving the puzzle',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Exit puzzle?'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_exit_confirm')),
            matching: find.text('Exit puzzle'),
          ),
          findsOneWidget,
        );
        expect(find.text('Exit'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'hides ordinary game player panels in portrait puzzles',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        final PuzzleSettings settings = PuzzleSettings(
          showHints: true,
          progressMap: <String, PuzzleProgress>{
            puzzle.id: PuzzleProgress(puzzleId: puzzle.id, attempts: 2),
          },
        );
        DB().puzzleSettings = settings;
        PuzzleManager().settingsNotifier.value = settings;
        await pumpPuzzlePage(tester, puzzle, viewSize: const Size(390, 844));

        expect(
          find.byKey(const Key('play_area_human_ai_robot_panel')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('play_area_human_ai_player_panel')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('play_area_human_ai_move_list_hidden')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_page_lichess_bottom_bar')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_page_stats_row')),
            matching: find.byKey(const Key('puzzle_attempts_stat_chip')),
          ),
          findsOneWidget,
        );
        expect(find.text('Attempts'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_attempts_stat_chip')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_attempts_stat_chip')),
            matching: find.byIcon(Icons.numbers),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_attempts_stat_chip')),
            matching: find.byIcon(Icons.replay),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_first_move_stat_chip')),
            matching: find.text('White'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(find.byKey(const Key('puzzle_first_move_stat_chip')))
              .dx,
          greaterThan(
            tester
                .getTopRight(
                  find.byKey(const Key('puzzle_difficulty_stat_chip')),
                )
                .dx,
          ),
        );
        expect(tester.takeException(), isNull);

        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'shows when Black makes the first puzzle move',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition:
              '********/********/******** b p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes',
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_first_move_stat_chip')),
            matching: find.text('First move'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_first_move_stat_chip')),
            matching: find.text('Black'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('puzzle_first_move_stat_chip')),
            matching: find.byIcon(Icons.play_arrow),
          ),
          findsOneWidget,
        );

        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'offers all transforms and keeps puzzle moves and solution in sync',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7', 'a4', 'g7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        await applyHumanMoveViaNativeSession('a1');
        await drainUi(tester);

        final String fenBeforeTransform = nativeSession.getFen();
        final List<String> movesBeforeTransform = controller
            .gameRecorder
            .currentPath
            .map((ExtMove move) => move.move)
            .toList(growable: false);
        expect(movesBeforeTransform, <String>['a1', 'd7']);

        await tester.tap(find.byKey(const Key('puzzle_page_bottom_bar_menu')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const Key('puzzle_page_action_rotate')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const Key('puzzle_page_board_transform_sheet')),
          findsOneWidget,
        );
        final GridView grid = tester.widget<GridView>(
          find.byKey(const Key('puzzle_page_board_transform_grid')),
        );
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          4,
        );
        for (final MillBoardTransformAction action
            in allMillBoardTransformActions) {
          expect(
            find.byKey(Key('puzzle_page_board_transform_${action.id}')),
            findsOneWidget,
            reason: 'Missing puzzle transformation ${action.id}',
          );
        }

        await tester.tap(
          find.byKey(const Key('puzzle_page_board_transform_rotate')),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final List<String> expectedMoves = movesBeforeTransform
            .map(
              (String move) =>
                  transformMoveNotation(move, TransformationType.rotate90),
            )
            .toList(growable: false);
        expect(
          nativeSession.getFen(),
          transformFEN(fenBeforeTransform, TransformationType.rotate90),
        );
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          expectedMoves,
        );

        await tester.tap(find.byKey(const Key('puzzle_page_bottom_bar_undo')));
        await drainUi(tester);
        expect(controller.gameRecorder.currentPath, isEmpty);
        expect(
          nativeSession.getFen(),
          transformFEN(initialFen, TransformationType.rotate90),
        );

        await applyHumanMoveViaNativeSession(
          transformMoveNotation('a1', TransformationType.rotate90),
        );
        await drainUi(tester);
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          expectedMoves,
        );

        final String nextHumanMove = transformMoveNotation(
          'a4',
          TransformationType.rotate90,
        );
        await applyHumanMoveViaNativeSession(nextHumanMove);
        await drainUi(tester);

        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          <String>[
            ...expectedMoves,
            nextHumanMove,
            transformMoveNotation('g7', TransformationType.rotate90),
          ],
        );
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'labels solution entries as atomic actions',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(tester, puzzle);

        await tester.tap(
          find.byKey(const Key('puzzle_page_bottom_bar_give_up')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('⭐ Optimal · 2 actions:'), findsOneWidget);
        expect(find.byType(PuzzleCompletionConfetti), findsNothing);
        expect(find.byType(MiniBoard), findsNWidgets(2));
        expect(
          find.byKey(const Key('puzzle_solution_1_miniboard_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('puzzle_solution_1_miniboard_1')),
          findsOneWidget,
        );
        final MiniBoard firstBoard = tester.widget<MiniBoard>(
          find.byKey(const Key('puzzle_solution_1_miniboard_0')),
        );
        final MiniBoard secondBoard = tester.widget<MiniBoard>(
          find.byKey(const Key('puzzle_solution_1_miniboard_1')),
        );
        expect(firstBoard.boardLayout, isNot(secondBoard.boardLayout));
        expect(firstBoard.extMove?.move, 'a1');
        expect(secondBoard.extMove?.move, 'd7');
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'returns to the puzzle list after viewing the solution',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
            <String>['d1', 'g7'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(
          tester,
          puzzle,
          viewSize: const Size(390, 844),
          pushFromList: true,
        );

        await tester.tap(
          find.byKey(const Key('puzzle_page_bottom_bar_give_up')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const Key('puzzle_solution_dialog')), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_solution_next_puzzle')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('puzzle_solution_back_to_list')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byKey(const Key('puzzle_list_test_page')), findsOneWidget);
        expect(find.byKey(const Key('puzzle_page_scaffold')), findsNothing);
        expect(tester.takeException(), isNull);

        PlayerTimer().reset();
        await tester.pump(const Duration(milliseconds: 350));
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'offers the next puzzle after solving',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
          markFirstSolutionOptimal: true,
        );
        final PuzzleInfo nextPuzzle = buildPuzzle(
          id: 'next_test_puzzle',
          title: 'Next Test Puzzle',
          solutions: const <List<String>>[
            <String>['d1', 'g7'],
          ],
          markFirstSolutionOptimal: true,
        );
        final PuzzleSettings settings = PuzzleSettings(
          showHints: true,
          allPuzzles: <PuzzleInfo>[puzzle, nextPuzzle],
        );
        DB().puzzleSettings = settings;
        PuzzleManager().settingsNotifier.value = settings;
        await pumpPuzzlePage(tester, puzzle);

        await applyHumanMoveViaNativeSession('a1');
        await drainUi(tester);

        expect(find.text('Puzzle solved!'), findsOneWidget);
        expect(find.byType(PuzzleCompletionConfetti), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_completion_next_puzzle')),
          findsOneWidget,
        );
        expect(find.text('Next puzzle'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('puzzle_completion_next_puzzle')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(nextPuzzle.title), findsOneWidget);
        expect(GameController().gameInstance.gameMode, GameMode.puzzle);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'returns to the puzzle list after solving',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(
          tester,
          puzzle,
          viewSize: const Size(390, 844),
          pushFromList: true,
        );

        await applyHumanMoveViaNativeSession('a1');
        await drainUi(tester);

        expect(find.text('Puzzle solved!'), findsOneWidget);
        expect(
          find.byKey(const Key('puzzle_completion_back_to_list')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const Key('puzzle_completion_back_to_list')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byKey(const Key('puzzle_list_test_page')), findsOneWidget);
        expect(find.byKey(const Key('puzzle_page_scaffold')), findsNothing);
        expect(tester.takeException(), isNull);

        PlayerTimer().reset();
        await tester.pump(const Duration(milliseconds: 350));
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'continues from the app bar after dismissing the completion dialog',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
          markFirstSolutionOptimal: true,
        );
        final PuzzleInfo nextPuzzle = buildPuzzle(
          id: 'next_test_puzzle',
          title: 'Next Test Puzzle',
          solutions: const <List<String>>[
            <String>['d1', 'g7'],
          ],
          markFirstSolutionOptimal: true,
        );
        final PuzzleSettings settings = PuzzleSettings(
          showHints: true,
          allPuzzles: <PuzzleInfo>[puzzle, nextPuzzle],
        );
        DB().puzzleSettings = settings;
        PuzzleManager().settingsNotifier.value = settings;
        await pumpPuzzlePage(tester, puzzle);

        await applyHumanMoveViaNativeSession('a1');
        await drainUi(tester);

        final GameController controller = GameController();
        final String solvedFen = nativeSession.getFen();
        final List<String> solvedMoves = controller.gameRecorder.currentPath
            .map((ExtMove move) => move.move)
            .toList(growable: false);
        expect(find.text('Puzzle solved!'), findsOneWidget);

        await tester.tapAt(const Offset(8, 8));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Puzzle solved!'), findsNothing);
        expect(find.byKey(const Key('puzzle_page_scaffold')), findsOneWidget);
        expect(nativeSession.getFen(), solvedFen);
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          solvedMoves,
        );

        await tester.tap(find.byKey(const Key('puzzle_page_app_bar_more')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const Key('puzzle_page_app_bar_next')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('puzzle_page_app_bar_skip')), findsNothing);
        expect(find.text('Next puzzle'), findsOneWidget);

        await tester.tap(find.byKey(const Key('puzzle_page_app_bar_next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(nextPuzzle.title), findsOneWidget);
        expect(GameController().gameInstance.gameMode, GameMode.puzzle);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'skips the current puzzle and records an attempt',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        final PuzzleInfo nextPuzzle = buildPuzzle(
          id: 'next_test_puzzle',
          title: 'Next Test Puzzle',
          solutions: const <List<String>>[
            <String>['d1', 'g7'],
          ],
        );
        final PuzzleSettings settings = PuzzleSettings(
          showHints: true,
          allPuzzles: <PuzzleInfo>[puzzle, nextPuzzle],
        );
        DB().puzzleSettings = settings;
        PuzzleManager().settingsNotifier.value = settings;
        await pumpPuzzlePage(tester, puzzle);

        await tester.tap(find.byKey(const Key('puzzle_page_app_bar_more')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const Key('puzzle_page_app_bar_skip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(nextPuzzle.title), findsOneWidget);
        expect(GameController().gameInstance.gameMode, GameMode.puzzle);
        expect(PuzzleManager().getProgress(puzzle.id)?.attempts, 1);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'solution metadata uses readable light-theme colors',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
            <String>['a4', 'g7'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(tester, puzzle, theme: AppTheme.lightThemeData);

        await tester.tap(
          find.byKey(const Key('puzzle_page_bottom_bar_give_up')),
        );
        await tester.pump();

        final ColorScheme colors = AppTheme.lightThemeData.colorScheme;
        final Text optimal = tester.widget<Text>(find.text('⭐ Optimal'));
        final Text alternative = tester.widget<Text>(find.text('Alternative'));
        final Iterable<Text> moveCounts = tester.widgetList<Text>(
          find.text('(2 actions)'),
        );
        expect(optimal.style?.color, colors.tertiary);
        expect(alternative.style?.color, colors.onSurfaceVariant);
        expect(moveCounts, hasLength(2));
        expect(
          moveCounts.every(
            (Text text) => text.style?.color == colors.onSurfaceVariant,
          ),
          isTrue,
        );

        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'auto-plays opponent response from solution line',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        expect(controller.activeBoardView.sideToMove, PieceColor.white);
        expect(controller.puzzleHumanColor, PieceColor.white);

        final String humanMove = transformed.solutions.first.moves[0].notation;
        final String opponentMove =
            transformed.solutions.first.moves[1].notation;

        await applyHumanMoveViaNativeSession(humanMove);
        await drainUi(tester);

        final List<String> moves = controller.gameRecorder.mainlineMoves
            .map((ExtMove m) => m.move)
            .toList(growable: false);
        expect(moves, <String>[humanMove, opponentMove]);
        expect(controller.activeBoardView.sideToMove, PieceColor.white);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'rolls back wrong human move when no solution matches',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        final String wrongMove = pickWrongFirstMove(transformed);

        await applyHumanMoveViaNativeSession(wrongMove);
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        // The wrong move is undone on the live session: it is the human's turn
        // again and the board is back to the puzzle's initial position.  The PGN
        // tree keeps the move as a dangling branch (history navigation), so we
        // assert on the active path rather than the full mainline.
        expect(controller.activeBoardView.sideToMove, PieceColor.white);
        expect(controller.gameRecorder.currentPath, isEmpty);
        expect(
          controller.activeNativeMillSession?.getFen(),
          transformed.initialPosition,
        );
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'rejects a wrong human removal and keeps the mill-forming move',
      (WidgetTester tester) async {
        final String startFen = buildPositionFenForHumanMillThenRemove();
        final PuzzleRuleEngine? probe = PuzzleRuleEngine.tryLoad(startFen);
        assert(probe != null, 'Failed to load generated start FEN.');
        expect(probe!.applyMoves(<String>['a7']), 1);
        expect(probe.legalMoveNotations(), containsAll(<String>['xd1', 'xd2']));
        probe.dispose();

        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition: startFen,
          solutions: const <List<String>>[
            <String>['a7', 'xd1', 'g1'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        await applyHumanMoveViaNativeSession('a7');
        await drainUi(tester);
        expect(controller.gameRecorder.currentPath, hasLength(1));

        await applyHumanMoveViaNativeSession('xd2');
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          <String>['a7'],
        );
        expect(controller.activeBoardView.action, Act.remove);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'rejects a wrong mill-forming move before asking for removal',
      (WidgetTester tester) async {
        // Built-in puzzle #7302EEAD: e4-e3 is the only shortest move.
        // d2-b2 instead forms a mill, but that primary action is already
        // outside every accepted solution and must be rejected immediately.
        const String startFen =
            'O*O*@@@@/****O*OO/******** w m p 5 0 4 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
        final PuzzleRuleEngine? probe = PuzzleRuleEngine.tryLoad(startFen);
        assert(probe != null, 'Failed to load puzzle #7302EEAD.');
        expect(probe!.applyMoves(<String>['d2-b2']), 1);
        expect(probe.view.action, Act.remove);
        probe.dispose();

        final PuzzleInfo puzzle = buildPuzzle(
          id: 'malom_movement_white_1_7302eead',
          title: 'White · Win in 1: block before attacking',
          initialPosition: startFen,
          solutions: const <List<String>>[
            <String>['e4-e3'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        await applyHumanMoveViaNativeSession('d2-b2');
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(controller.gameRecorder.currentPath, isEmpty);
        expect(controller.activeBoardView.action, isNot(Act.remove));
        expect(
          controller.activeNativeMillSession?.getFen(),
          transformed.initialPosition,
        );
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'rejects a non-optimal removal when an optimal line is explicit',
      (WidgetTester tester) async {
        const String startFen =
            'O*****@*/@****@*O/OO@***@O b m p 5 0 5 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition: startFen,
          solutions: const <List<String>>[
            <String>['b2-b4', 'xd5'],
            <String>['b2-b4', 'xb6', 'd5-e5'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        await applyHumanMoveViaNativeSession('b2-b4');
        await drainUi(tester);
        expect(controller.gameRecorder.currentPath, hasLength(1));

        await applyHumanMoveViaNativeSession('xb6');
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          <String>['b2-b4'],
        );
        expect(controller.activeBoardView.action, Act.remove);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'highlights the real capture targets in the first transformed puzzle',
      (WidgetTester tester) async {
        const String startFen =
            'O*****@*/@****@*O/OO@***@O b m p 5 0 5 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition: startFen,
          solutions: const <List<String>>[
            <String>['b2-b4', 'xd5'],
            <String>['b2-b4', 'xb6', 'd5-e5'],
          ],
          markFirstSolutionOptimal: true,
        );
        PuzzlePage.debugTransformationOverride =
            TransformationType.mirrorHorizontal;
        await pumpPuzzlePage(tester, puzzle);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        final BuildContext boardContext = tester.element(
          find.byKey(const Key('puzzle_game')),
        );
        final TapHandler tapHandler = TapHandler(context: boardContext);
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        final String movement =
            transformed.solutions.first.moves.first.notation;
        final List<String> movementSquares = movement.split('-');
        expect(movementSquares, <String>['f2', 'f4']);

        await tapHandler.onBoardTap(
          MillBoardCoordinateMaps.notationToLegacySquare(movementSquares[0]),
        );
        await tapHandler.onBoardTap(
          MillBoardCoordinateMaps.notationToLegacySquare(movementSquares[1]),
        );
        await drainUi(tester);

        final GameController controller = GameController();
        expect(controller.activeBoardView.action, Act.remove);
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          <String>['f2-f4'],
        );

        final PiecePainter piecePainter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('custom_paint_piece_painter')),
                    )
                    .painter!
                as PiecePainter;
        expect(piecePainter.forceCapturableHighlights, isTrue);
        expect(piecePainter.capturableGridIndices, <int>{
          MillBoardCoordinateMaps.squareToGridIndex[8]!,
          MillBoardCoordinateMaps.squareToGridIndex[17]!,
        });

        final TurnHighlightPainter turnPainter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('custom_paint_turn_highlight')),
                    )
                    .painter!
                as TurnHighlightPainter;
        expect(turnPainter.highlight, isNull);

        await tapHandler.onBoardTap(
          MillBoardCoordinateMaps.notationToLegacySquare('f6'),
        );
        await drainUi(tester);
        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(controller.activeBoardView.action, Act.remove);
        expect(
          controller.gameRecorder.currentPath
              .map((ExtMove move) => move.move)
              .toList(growable: false),
          <String>['f2-f4'],
        );

        await tapHandler.onBoardTap(
          MillBoardCoordinateMaps.notationToLegacySquare('d5'),
        );
        await drainUi(tester);
        expect(find.text('Puzzle solved!'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'allows correct retry after a rolled-back wrong move',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        final String correctMove =
            transformed.solutions.first.moves[0].notation;
        final String opponentMove =
            transformed.solutions.first.moves[1].notation;
        final String wrongMove = pickWrongFirstMove(transformed);

        await applyHumanMoveViaNativeSession(wrongMove);
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(controller.gameRecorder.currentPath, isEmpty);
        await tester.pump(const Duration(seconds: 3));

        await applyHumanMoveViaNativeSession(correctMove);
        await drainUi(tester);

        final List<String> moves = controller.gameRecorder.currentPath
            .map((ExtMove m) => m.move)
            .toList(growable: false);
        expect(moves, <String>[correctMove, opponentMove]);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'picks matching solution for current prefix',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1', 'd7'],
            <String>['a4', 'g7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        final PuzzleSolution secondLine = transformed.solutions[1];
        final String humanMove = secondLine.moves[0].notation;
        final String opponentMove = secondLine.moves[1].notation;

        await applyHumanMoveViaNativeSession(humanMove);
        await drainUi(tester);

        final List<String> moves = controller.gameRecorder.mainlineMoves
            .map((ExtMove m) => m.move)
            .toList(growable: false);
        expect(moves, <String>[humanMove, opponentMove]);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'rejects a known slower line when an optimal line is explicit',
      (WidgetTester tester) async {
        final PuzzleInfo puzzle = buildPuzzle(
          solutions: const <List<String>>[
            <String>['a1'],
            <String>['a4'],
          ],
          markFirstSolutionOptimal: true,
        );
        await pumpPuzzlePage(tester, puzzle);

        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        final String slowerMove = transformed.solutions[1].moves.first.notation;
        await applyHumanMoveViaNativeSession(slowerMove);
        await drainUi(tester);

        expect(
          find.text("That move isn't part of the solution. Try again."),
          findsOneWidget,
        );
        expect(GameController().gameRecorder.currentPath, isEmpty);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'auto-plays consecutive opponent moves (mill then remove)',
      (WidgetTester tester) async {
        final String startFen = buildPositionFenForOpponentMillThenRemove();
        final PuzzleRuleEngine? probe = PuzzleRuleEngine.tryLoad(startFen);
        assert(probe != null, 'Failed to load generated start FEN.');
        expect(probe!.applyMoves(<String>['g1', 'a7']), 2);
        expect(probe.legalMoveNotations(), contains('xd1'));
        probe.dispose();

        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition: startFen,
          solutions: const <List<String>>[
            <String>['g1', 'a7', 'xd1'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        final PuzzleInfo transformed = loadedTransformedPuzzle(puzzle);
        expect(controller.activeBoardView.sideToMove, PieceColor.white);
        expect(controller.puzzleHumanColor, PieceColor.white);

        final List<String> expectedMoves = transformed.solutions.first.moves
            .map((PuzzleMove m) => m.notation)
            .toList(growable: false);

        await applyHumanMoveViaNativeSession(expectedMoves.first);
        await drainUi(tester);

        final List<String> moves = controller.gameRecorder.mainlineMoves
            .map((ExtMove m) => m.move)
            .toList(growable: false);
        expect(moves, expectedMoves);
        expect(controller.activeBoardView.sideToMove, PieceColor.white);
        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );

    testWidgets(
      'assigns human to black when puzzle starts with black to move',
      (WidgetTester tester) async {
        const String blackToMoveFen =
            '@O****O*/*****O*@/*@****@@ b m p 3 0 5 0 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
        final PuzzleInfo puzzle = buildPuzzle(
          initialPosition: blackToMoveFen,
          solutions: const <List<String>>[
            <String>['c4', 'g7'],
          ],
        );
        await pumpPuzzlePage(tester, puzzle);

        final GameController controller = GameController();
        expect(controller.puzzleHumanColor, PieceColor.black);
        expect(controller.activeBoardView.sideToMove, PieceColor.black);
        expect(
          controller.gameInstance.gameMode.whoIsAI[PieceColor.black],
          isFalse,
        );
        expect(
          controller.gameInstance.gameMode.whoIsAI[PieceColor.white],
          isTrue,
        );

        await teardownPuzzlePage(tester);
      },
      skip: nativeLibrarySkipReason() != null,
    );
  });
}
