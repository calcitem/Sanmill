// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/engine/bitboard.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/puzzle/models/puzzle_models.dart';
import 'package:sanmill/puzzle/pages/puzzle_page.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/shared/widgets/snackbars/scaffold_messenger.dart';

import '../helpers/mocks/mock_animation_manager.dart';
import '../helpers/mocks/mock_audios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel engineChannel = MethodChannel(
    'com.calcitem.sanmill/engine',
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  // A valid, empty starting position in placing phase for standard 9mm.
  const String initialFen =
      '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1';

  late Directory appDocDir;

  setUpAll(() async {
    EnvironmentConfig.catcher = false;

    // Initialize bitboards for square bit masks used by move parsing and FEN.
    initBitboards();

    // Mock native engine channel so GameBoard.startup() won't hang in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'send':
            case 'shutdown':
            case 'startup':
              return null;
            case 'read':
              // Engine.startup() waits for "uciok".
              return 'uciok';
            case 'isThinking':
              return false;
            default:
              return null;
          }
        });

    // Provide a stable documents directory for Hive/path_provider callers.
    appDocDir = Directory.systemTemp.createTempSync('sanmill_test_');
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

    await DB.init();
    SoundManager.instance = MockAudios();

    // Keep animations deterministic and avoid lingering tickers.
    DB().displaySettings = const DisplaySettings(animationDuration: 0.0);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() {
    // Ensure controller state is clean between tests.
    final GameController controller = GameController();
    controller.reset(force: true);
    controller.puzzleHumanColor = null;
    controller.isPuzzleAutoMoveInProgress = false;
    controller.animationManager = MockAnimationManager();
  });

  PuzzleInfo buildPuzzle({
    required List<List<String>> solutions,
    String? initialPosition,
  }) {
    // Convert solution move lists to PuzzleSolution objects
    final Position tempPos = Position();
    tempPos.setFen(initialPosition ?? initialFen);
    final PieceColor startingSide = tempPos.sideToMove;

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

      return PuzzleSolution(moves: puzzleMoves, isOptimal: true);
    }).toList();

    return PuzzleInfo(
      id: 'test_puzzle',
      title: 'Test Puzzle',
      description: 'Test puzzle for auto-play behavior.',
      category: PuzzleCategory.formMill,
      difficulty: PuzzleDifficulty.easy,
      initialPosition: initialPosition ?? initialFen,
      solutions: puzzleSolutions,
      tags: const <String>['test'],
      isCustom: true,
      author: 'test',
    );
  }

  String buildPositionFenForOpponentMillThenRemove() {
    final GameController controller = GameController();
    controller.reset(force: true);

    final bool loaded = controller.position.setFen(initialFen);
    assert(loaded, 'Failed to load base test FEN.');

    // Prepare a placing-phase position where:
    // - White is to move (human in Puzzle mode).
    // - Black has two pieces on a potential mill line (a1 + a4),
    //   so Black can place a7 to form a mill and then remove.
    final List<String> setupMoves = <String>['d1', 'a1', 'd2', 'a4'];
    for (final String move in setupMoves) {
      final bool ok = controller.applyMove(
        ExtMove(move, side: controller.position.sideToMove),
      );
      assert(ok, 'Failed to apply setup move: $move');
    }

    final String? fen = controller.position.fen;
    assert(fen != null && fen.isNotEmpty, 'Generated FEN is empty.');
    return fen!;
  }

  Future<void> pumpPuzzlePage(WidgetTester tester, PuzzleInfo puzzle) async {
    // Set a larger screen size to avoid overflow errors in GameHeader
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: PuzzlePage(puzzle: puzzle),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxPumps = 200,
    Duration step = const Duration(milliseconds: 10),
  }) async {
    for (int i = 0; i < maxPumps && !condition(); i++) {
      await tester.pump(step);
    }
    expect(
      condition(),
      isTrue,
      reason: 'Condition not met after $maxPumps pumps',
    );
  }

  testWidgets('Puzzle auto-plays opponent response from solution line', (
    WidgetTester tester,
  ) async {
    final PuzzleInfo puzzle = buildPuzzle(
      solutions: const <List<String>>[
        <String>['a1', 'd7'],
      ],
    );
    await pumpPuzzlePage(tester, puzzle);

    final GameController controller = GameController();
    expect(controller.position.sideToMove, PieceColor.white);
    expect(controller.puzzleHumanColor, PieceColor.white);

    final bool ok = controller.applyMove(
      ExtMove('a1', side: controller.position.sideToMove),
    );
    expect(ok, isTrue);

    // Wait for auto-play to complete
    await pumpUntil(
      tester,
      () =>
          !controller.isPuzzleAutoMoveInProgress &&
          controller.gameRecorder.mainlineMoves.length == 2,
    );

    final List<String> moves = controller.gameRecorder.mainlineMoves
        .map((ExtMove m) => m.move)
        .toList(growable: false);
    expect(moves, <String>['a1', 'd7']);
    expect(controller.position.sideToMove, PieceColor.white);
  });

  testWidgets('Puzzle rolls back wrong human move when no solution matches', (
    WidgetTester tester,
  ) async {
    final PuzzleInfo puzzle = buildPuzzle(
      solutions: const <List<String>>[
        <String>['a1', 'd7'],
      ],
    );
    await pumpPuzzlePage(tester, puzzle);

    final GameController controller = GameController();
    final bool ok = controller.applyMove(
      ExtMove('a4', side: controller.position.sideToMove),
    );
    expect(ok, isTrue);

    // Wait for auto-play logic to complete (including undo)
    await pumpUntil(
      tester,
      () =>
          !controller.isPuzzleAutoMoveInProgress &&
          controller.gameRecorder.mainlineMoves.isEmpty,
    );

    expect(find.text('Wrong move. Try again.'), findsOneWidget);
    expect(controller.position.sideToMove, PieceColor.white);
  });

  testWidgets('Puzzle picks matching solution for current prefix', (
    WidgetTester tester,
  ) async {
    final PuzzleInfo puzzle = buildPuzzle(
      solutions: const <List<String>>[
        <String>['a1', 'd7'],
        <String>['a4', 'g7'],
      ],
    );
    await pumpPuzzlePage(tester, puzzle);

    final GameController controller = GameController();
    final bool ok = controller.applyMove(
      ExtMove('a4', side: controller.position.sideToMove),
    );
    expect(ok, isTrue);

    // Wait for auto-play to complete
    await pumpUntil(
      tester,
      () =>
          !controller.isPuzzleAutoMoveInProgress &&
          controller.gameRecorder.mainlineMoves.length == 2,
    );

    final List<String> moves = controller.gameRecorder.mainlineMoves
        .map((ExtMove m) => m.move)
        .toList(growable: false);
    expect(moves, <String>['a4', 'g7']);
  });

  testWidgets(
    'Puzzle auto-plays consecutive opponent moves (mill then remove)',
    (WidgetTester tester) async {
      final String startFen = buildPositionFenForOpponentMillThenRemove();
      final PuzzleInfo puzzle = buildPuzzle(
        initialPosition: startFen,
        solutions: const <List<String>>[
          <String>['g1', 'a7', 'xd1'],
        ],
      );
      await pumpPuzzlePage(tester, puzzle);

      final GameController controller = GameController();
      expect(controller.position.sideToMove, PieceColor.white);
      expect(controller.puzzleHumanColor, PieceColor.white);

      final bool ok = controller.applyMove(
        ExtMove('g1', side: controller.position.sideToMove),
      );
      expect(ok, isTrue);

      // Wait for consecutive auto-play to complete (mill + remove)
      await pumpUntil(
        tester,
        () =>
            !controller.isPuzzleAutoMoveInProgress &&
            controller.gameRecorder.mainlineMoves.length == 3,
      );

      final List<String> moves = controller.gameRecorder.mainlineMoves
          .map((ExtMove m) => m.move)
          .toList(growable: false);
      expect(moves, <String>['g1', 'a7', 'xd1']);
      expect(controller.position.sideToMove, PieceColor.white);
    },
  );
}
