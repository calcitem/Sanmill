// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/appearance_settings/models/display_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart' as platform;
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/services/environment_config.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GameController stores active session snapshots', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    const platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.first,
      outcome: platform.GameOutcome.ongoing(),
      phase: 'placing',
    );

    controller.activeSessionSnapshot = snapshot;

    expect(controller.activeSessionSnapshot, same(snapshot));
    expect(controller.activeSessionSnapshotNotifier.value, same(snapshot));
    expect(controller.activeSessionSideToMove, PieceColor.white);
    expect(controller.activeSessionPhase, Phase.placing);
    expect(controller.activeSessionWinner, isNull);
    expect(controller.activeSideToMoveIcon, isA<IconData>());
  });

  test('GameController side icon uses terminal session outcome', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    const platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.none,
      outcome: platform.GameOutcome.win(platform.PlayerSeat.second),
      phase: 'gameOver',
    );

    controller.activeSessionSnapshot = snapshot;

    expect(controller.activeSessionPhase, Phase.gameOver);
    expect(controller.activeSessionWinner, PieceColor.black);
    expect(controller.activeSideToMoveIcon, isA<IconData>());
  });

  test('GameController maps draw session outcome to legacy winner', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    const platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.none,
      outcome: platform.GameOutcome.draw(),
      phase: 'moving',
    );

    controller.activeSessionSnapshot = snapshot;

    expect(controller.activeSessionPhase, Phase.gameOver);
    expect(controller.activeSessionWinner, PieceColor.draw);
  });

  test('GameController exposes active native Mill board view', () {
    DB.instance = MockDB();
    addTearDown(() => DB.instance = null);
    final GameController controller = GameController.instance;
    addTearDown(() => controller.activeSessionSnapshot = null);

    final Uint8List payload = Uint8List(256)..[0] = 1;
    final platform.GameStateSnapshot snapshot = platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.first,
      outcome: const platform.GameOutcome.ongoing(),
      phase: 'placing',
      payload: <String, Object?>{'tgfPayload': payload},
    );

    controller.activeSessionSnapshot = snapshot;

    expect(
      controller.activeNativeMillBoardView?.pieceAtNode(0),
      platform.PlayerSeat.first,
    );
  });

  test('GameController syncs native AI score for the advantage graph', () {
    DB.instance = MockDB();
    final GameController controller = GameController.instance;
    final NativeMillGameSession session = NativeMillGameSession(
      rulesPort: _SnapshotOnlyNativeMillRulesPort(),
    );
    addTearDown(() {
      session.dispose();
      controller.value = null;
      controller.aiMoveType = null;
      controller.lastMoveFromAI = false;
      DB.instance = null;
    });

    session.lastAiMoveType = AiMoveType.traditional;
    session.lastAiBestValue = -13;
    controller.value = null;
    controller.aiMoveType = AiMoveType.unknown;
    controller.lastMoveFromAI = false;

    controller.syncAiMoveTypeFromSession(session);

    expect(controller.value, '-13');
    expect(controller.aiMoveType, AiMoveType.traditional);
    expect(controller.lastMoveFromAI, isTrue);

    session.lastAiMoveType = AiMoveType.openingBook;
    session.lastAiBestValue = null;

    controller.syncAiMoveTypeFromSession(session);

    expect(controller.value, isNull);
    expect(controller.aiMoveType, AiMoveType.openingBook);
    expect(controller.lastMoveFromAI, isFalse);
  });

  test(
    'GameController dev auto restart keeps the legacy no-draw score gate',
    () {
      final MockDB db = MockDB();
      db.generalSettings = const GeneralSettings(isAutoRestart: true);
      DB.instance = db;
      final bool originalDevMode = EnvironmentConfig.devMode;
      addTearDown(() {
        EnvironmentConfig.devMode = originalDevMode;
        resetMillScore();
        DB.instance = null;
      });

      final GameController controller = GameController.instance;
      EnvironmentConfig.devMode = true;
      resetMillScore();

      expect(controller.isAutoRestart(), isTrue);

      millScore[PieceColor.white] = 1;
      expect(controller.isAutoRestart(), isFalse);

      resetMillScore();
      millScore[PieceColor.black] = 1;
      expect(controller.isAutoRestart(), isFalse);

      EnvironmentConfig.devMode = false;
      expect(controller.isAutoRestart(), isTrue);
    },
  );

  test('shouldAutoRestartAfterGameOver mirrors master mode gating', () {
    final MockDB db = MockDB();
    db.generalSettings = const GeneralSettings(isAutoRestart: true);
    DB.instance = db;
    addTearDown(() => DB.instance = null);

    final GameController controller = GameController.instance;
    addTearDown(() {
      controller.activeSessionSnapshot = null;
      controller.gameInstance.gameMode = GameMode.humanVsAi;
    });

    controller.gameInstance.gameMode = GameMode.humanVsAi;
    controller.activeSessionSnapshot = const platform.GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: platform.PlayerSeat.none,
      outcome: platform.GameOutcome.win(platform.PlayerSeat.first),
      phase: 'gameOver',
    );

    expect(controller.shouldAutoRestartAfterGameOver(), isTrue);

    controller.gameInstance.gameMode = GameMode.humanVsLAN;
    expect(controller.shouldAutoRestartAfterGameOver(), isFalse);

    controller.gameInstance.gameMode = GameMode.aiVsAi;
    db.displaySettings = const DisplaySettings();
    expect(controller.shouldAutoRestartAfterGameOver(), isFalse);
  });

  test('GameController sends multi-step LAN takeback requests', () async {
    DB.instance = MockDB();
    final GameController controller = GameController.instance;
    final _RecordingNetworkService networkService = _RecordingNetworkService();
    addTearDown(() {
      controller.pendingTakeBackCompleter = null;
      controller.networkService = null;
      controller.isLanOpponentTurn = false;
      controller.gameInstance.gameMode = GameMode.humanVsAi;
      networkService.dispose();
      DB.instance = null;
    });

    controller.gameInstance.gameMode = GameMode.humanVsLAN;
    controller.networkService = networkService;
    controller.isLanOpponentTurn = false;

    final Future<bool> result = controller.requestLanTakeBack(3);

    expect(networkService.sentMessages, <String>['take back:3:request']);
    controller.pendingTakeBackCompleter?.complete(true);
    expect(await result, isTrue);
  });
}

class _RecordingNetworkService extends NetworkService {
  final List<String> sentMessages = <String>[];

  @override
  bool get isConnected => true;

  @override
  void sendMove(String move) {
    sentMessages.add(move);
  }
}

class _SnapshotOnlyNativeMillRulesPort implements NativeMillRulesPort {
  static const platform.GameStateSnapshot _snapshot =
      platform.GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: platform.PlayerSeat.first,
        outcome: platform.GameOutcome.ongoing(),
        phase: 'placing',
      );

  @override
  platform.GameStateSnapshot get snapshot => _snapshot;

  @override
  List<platform.GameAction> get legalActions => const <platform.GameAction>[];

  @override
  int get redoDepth => 0;

  @override
  int get undoDepth => 0;

  @override
  bool isLegal(platform.GameAction action) => false;

  @override
  platform.GameStateSnapshot apply(platform.GameAction action) => _snapshot;

  @override
  platform.GameStateSnapshot undo() => _snapshot;

  @override
  platform.GameStateSnapshot redo() => _snapshot;

  @override
  void dispose() {}

  @override
  platform.GameStateSnapshot setupClear() => _snapshot;

  @override
  platform.GameStateSnapshot setupSetPiece(int node, int owner) => _snapshot;

  @override
  platform.GameStateSnapshot setupSetSide(int side) => _snapshot;

  @override
  platform.GameStateSnapshot setupFinish() => _snapshot;

  @override
  platform.GameStateSnapshot setFromFen(String fen) => _snapshot;

  @override
  String exportFen() => '';

  @override
  Stream<tgf.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
  }) => const Stream<tgf.EngineEvent>.empty();

  @override
  platform.GameAction? perfectDatabaseBestAction({
    GeneralSettings? engineSettings,
  }) => null;

  @override
  tgf.MillAnalysisReport analyzePerfectDb() => const tgf.MillAnalysisReport(
    moves: <tgf.MillMoveAnalysis>[],
    traps: <String>[],
  );
}
