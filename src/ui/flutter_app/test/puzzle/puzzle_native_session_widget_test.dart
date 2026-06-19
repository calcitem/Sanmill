// SPDX-License-Identifier: GPL-3.0-or-later
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
import 'package:sanmill/game_page/services/player_timer.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';
import 'package:sanmill/game_shell/game_session_scope.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/puzzle_page.dart';
import 'package:sanmill/puzzle/services/puzzle_auto_player.dart';
import 'package:sanmill/puzzle/services/puzzle_rule_engine.dart';
import 'package:sanmill/puzzle/services/puzzle_transform_service.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
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
  }) {
    final String fen = initialPosition ?? initialFen;
    final PuzzleRuleEngine? engine = PuzzleRuleEngine.tryLoad(fen);
    assert(engine != null, 'Failed to load test FEN: $fen');
    final PieceColor startingSide = engine!.view.sideToMove;
    engine.dispose();

    final List<PuzzleSolution> puzzleSolutions = solutions.map((
      List<String> moves,
    ) {
      PieceColor currentSide = startingSide;
      final List<PuzzleMove> puzzleMoves = moves.map((String notation) {
        final PuzzleMove move = PuzzleMove(
          notation: notation,
          side: currentSide,
        );
        currentSide = currentSide.opponent;
        return move;
      }).toList();

      return PuzzleSolution(moves: puzzleMoves);
    }).toList();

    return PuzzleInfo(
      id: 'test_puzzle',
      title: 'Test Puzzle',
      description: 'Test puzzle for native-session auto-play behavior.',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.easy,
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

  Future<void> pumpPuzzlePage(WidgetTester tester, PuzzleInfo puzzle) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: sanmillLocalizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: GameSessionScope(
          session: nativeSession,
          child: PuzzlePage(puzzle: puzzle),
        ),
      ),
    );
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
      final int current = controller.gameRecorder.mainlineMoves.length;
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

        expect(find.text('Wrong move. Try again.'), findsOneWidget);
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
  });
}
