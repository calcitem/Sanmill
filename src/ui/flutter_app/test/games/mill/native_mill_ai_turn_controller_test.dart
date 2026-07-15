// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/game_platform/opening_book_provider.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_human_database_provider.dart';
import 'package:sanmill/games/mill/mill_marked_pieces_codec.dart';
import 'package:sanmill/games/mill/mill_types.dart';
import 'package:sanmill/games/mill/native_mill_ai_turn_controller.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/rule_settings/models/rule_settings.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

void main() {
  group('NativeMillAiTurnController', () {
    test('maps aiMovesFirst to first-player AI seat', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: GeneralSettings(aiMovesFirst: true),
      );

      expect(controller.aiSeat, PlayerSeat.first);
    });

    test('maps default AI side to second player', () {
      const NativeMillAiTurnController controller =
          NativeMillAiTurnController();

      expect(controller.aiSeat, PlayerSeat.second);
    });

    test('uses fixed depth override when provided', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        depth: 4,
        generalSettings: GeneralSettings(skillLevel: 30),
      );

      expect(controller.searchDepthForSnapshot(_placingSnapshot()), 4);
    });

    test('uses human-experience placing depth table when enabled', () {
      const NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: GeneralSettings(skillLevel: 30),
      );

      // 9MM placing index 4 maps to depth 3 in master Mills::get_search_depth.
      expect(
        controller.searchDepthForSnapshot(
          _placingSnapshot(
            whiteInHand: 7,
            blackInHand: 7,
            whiteOnBoard: 2,
            blackOnBoard: 2,
          ),
        ),
        3,
      );
    });

    test(
      'falls back to skill level outside human-experience placing table',
      () {
        const NativeMillAiTurnController controller =
            NativeMillAiTurnController(
              generalSettings: GeneralSettings(
                skillLevel: 6,
                drawOnHumanExperience: false,
              ),
            );

        expect(controller.searchDepthForSnapshot(_placingSnapshot()), 6);
        expect(controller.searchDepthForSnapshot(_movingSnapshot()), 6);
      },
    );

    test(
      'corrects human database candidates with perfect database actions',
      () async {
        const GameAction humanAction = GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'd6'},
        );
        const GameAction perfectAction = GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'a7'},
        );
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
          legalActions: const <GameAction>[humanAction, perfectAction],
          perfectDatabaseBestAction: perfectAction,
          analysisReport: const tgf.MillAnalysisReport(
            moves: <tgf.MillMoveAnalysis>[
              tgf.MillMoveAnalysis(
                mv: 'a7',
                outcome: 'win',
                value: 1,
                steps: 3,
              ),
            ],
            traps: <String>[],
          ),
        );
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);
        final _FakeHumanDatabaseProvider humanDatabase =
            _FakeHumanDatabaseProvider(humanAction);
        final NativeMillAiTurnController controller =
            NativeMillAiTurnController(
              generalSettings: const GeneralSettings(
                aiMovesFirst: true,
                usePerfectDatabase: true,
              ),
              humanDatabase: humanDatabase,
            );

        final GameAction? applied = await controller.playIfAiTurn(session);

        expect(applied, perfectAction);
        expect(rulesPort.lastApplied, perfectAction);
        expect(session.lastAiMoveType, AiMoveType.perfect);
        expect(session.lastAiBestValue, 100);
        expect(session.lastHumanDatabaseMoveStats, isNull);
        expect(humanDatabase.discarded, isTrue);
      },
    );

    test('maps human database score delta to white graph score', () async {
      const GameAction humanAction = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'd6'},
      );
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        legalActions: const <GameAction>[humanAction],
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);
      final _FakeHumanDatabaseProvider humanDatabase =
          _FakeHumanDatabaseProvider(humanAction);
      final NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: const GeneralSettings(aiMovesFirst: true),
        humanDatabase: humanDatabase,
      );

      final GameAction? applied = await controller.playIfAiTurn(session);

      expect(applied, humanAction);
      expect(session.lastAiMoveType, AiMoveType.humanDatabase);
      expect(session.lastAiBestValue, 50);
      expect(session.lastHumanDatabaseMoveStats, isNotNull);
    });

    test(
      'maps black human database score delta to black graph score',
      () async {
        const GameAction humanAction = GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'd6'},
        );
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
          legalActions: const <GameAction>[humanAction],
          initial: _placingSnapshot(activeSeat: PlayerSeat.second),
        );
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);
        final _FakeHumanDatabaseProvider humanDatabase =
            _FakeHumanDatabaseProvider(humanAction);
        final NativeMillAiTurnController controller =
            NativeMillAiTurnController(humanDatabase: humanDatabase);

        final GameAction? applied = await controller.playIfAiTurn(session);

        expect(applied, humanAction);
        expect(session.lastAiMoveType, AiMoveType.humanDatabase);
        expect(session.lastAiBestValue, -50);
      },
    );

    test('uses opening book before human database and engine search', () async {
      const GameAction bookAction = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'd2'},
      );
      const GameAction humanAction = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'd6'},
      );
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        legalActions: const <GameAction>[bookAction, humanAction],
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);
      final _FakeOpeningBookProvider openingBook = _FakeOpeningBookProvider(
        bookAction,
      );
      final _FakeHumanDatabaseProvider humanDatabase =
          _FakeHumanDatabaseProvider(humanAction);
      final NativeMillAiTurnController controller = NativeMillAiTurnController(
        generalSettings: const GeneralSettings(aiMovesFirst: true),
        openingBook: openingBook,
        humanDatabase: humanDatabase,
      );

      final GameAction? applied = await controller.playIfAiTurn(session);

      expect(applied, bookAction);
      expect(rulesPort.lastApplied, bookAction);
      expect(session.lastAiMoveType, AiMoveType.openingBook);
      expect(session.lastAiBestValue, 0);
      expect(session.lastHumanDatabaseMoveStats, isNull);
      expect(openingBook.lookupCount, 1);
      expect(humanDatabase.lookupCount, 0);
    });
  });
}

class _FakeOpeningBookProvider implements OpeningBookProvider {
  _FakeOpeningBookProvider(this.action);

  final GameAction action;
  int lookupCount = 0;

  @override
  GameAction? lookup(GameSession session) {
    lookupCount++;
    return action;
  }
}

class _FakeHumanDatabaseProvider extends MillHumanDatabaseProvider {
  _FakeHumanDatabaseProvider(this.action)
    : super(
        ruleSettings: const RuleSettings(),
        generalSettings: const GeneralSettings(humanDatabaseEnabled: true),
      );

  final GameAction action;
  bool discarded = false;
  int lookupCount = 0;

  @override
  GameAction? lookup(GameSession session) {
    lookupCount++;
    lastStats = const HumanDatabaseMoveStats(
      notation: 'd6',
      wins: 7,
      draws: 1,
      losses: 2,
      total: 10,
      scoreDelta: 0.25,
    );
    return action;
  }

  @override
  void discardPendingMove() {
    discarded = true;
    super.discardPendingMove();
  }
}

class _FakeNativeMillRulesPort implements NativeMillRulesPort {
  _FakeNativeMillRulesPort({
    required this.legalActions,
    GameAction? perfectDatabaseBestAction,
    GameStateSnapshot? initial,
    tgf.MillAnalysisReport analysisReport = const tgf.MillAnalysisReport(
      moves: <tgf.MillMoveAnalysis>[],
      traps: <String>[],
    ),
  }) : perfectDatabaseBestActionResult = perfectDatabaseBestAction,
       analysisReportResult = analysisReport,
       _snapshot = initial ?? _initialSnapshot;

  static final GameStateSnapshot _initialSnapshot = GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: const GameOutcome.ongoing(),
    phase: 'placing',
    payload: <String, Object?>{
      'tgfPayload': _emptyBoardPayload,
      millMarkedNodesPayloadKey: const <int>{},
    },
  );
  static final Uint8List _emptyBoardPayload = Uint8List(280);

  @override
  final List<GameAction> legalActions;

  @override
  RuleSettings get ruleSettings => const RuleSettings();

  final GameAction? perfectDatabaseBestActionResult;
  final tgf.MillAnalysisReport analysisReportResult;
  GameStateSnapshot _snapshot;
  GameAction? lastApplied;

  @override
  int get redoDepth => 0;

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  int get undoDepth => 0;

  @override
  bool isLegal(GameAction action) {
    return legalActions.contains(action);
  }

  @override
  GameStateSnapshot apply(GameAction action) {
    lastApplied = action;
    final PlayerSeat nextSeat = switch (_snapshot.activeSeat) {
      PlayerSeat.first => PlayerSeat.second,
      PlayerSeat.second => PlayerSeat.first,
      PlayerSeat.none => PlayerSeat.none,
    };
    final Uint8List payload = Uint8List(280);
    payload[0] = 1;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: nextSeat,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      lastAction: action,
      payload: <String, Object?>{
        'tgfPayload': payload,
        millMarkedNodesPayloadKey: const <int>{},
      },
    );
    return _snapshot;
  }

  @override
  tgf.MillAnalysisReport analyzePerfectDb() => analysisReportResult;

  @override
  void dispose() {}

  @override
  String exportFen() => '';

  @override
  Stream<tgf.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
    int multiPv = 1,
  }) => const Stream<tgf.EngineEvent>.empty();

  @override
  GameAction? perfectDatabaseBestAction({GeneralSettings? engineSettings}) {
    return perfectDatabaseBestActionResult;
  }

  @override
  GameAction? patchCorrectAction(
    GameAction chosen, {
    GeneralSettings? engineSettings,
  }) => null;

  @override
  int? patchTrapScoreAfter(
    GameAction action, {
    GeneralSettings? engineSettings,
  }) => null;

  @override
  GameAction? patchMakeTrapsAction(
    GameAction chosen, {
    GeneralSettings? engineSettings,
  }) => null;

  @override
  GameStateSnapshot redo() => _snapshot;

  @override
  GameStateSnapshot setFromFen(String fen) => _snapshot;

  @override
  GameStateSnapshot setupClear() => _snapshot;

  @override
  GameStateSnapshot setupFinish() => _snapshot;

  @override
  GameStateSnapshot setupSetPiece(int node, int owner) => _snapshot;

  @override
  GameStateSnapshot setupSetSide(int side) => _snapshot;

  @override
  GameStateSnapshot undo() => _snapshot;
}

GameStateSnapshot _placingSnapshot({
  int whiteInHand = 9,
  int blackInHand = 9,
  int whiteOnBoard = 0,
  int blackOnBoard = 0,
  PlayerSeat activeSeat = PlayerSeat.first,
}) {
  final Uint8List payload = Uint8List(256);
  payload[24] = whiteInHand;
  payload[25] = blackInHand;
  payload[26] = whiteOnBoard;
  payload[27] = blackOnBoard;
  return GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: activeSeat,
    outcome: const GameOutcome.ongoing(),
    phase: 'placing',
    payload: <String, Object?>{'tgfPayload': payload},
  );
}

GameStateSnapshot _movingSnapshot() {
  final Uint8List payload = Uint8List(256);
  payload[24] = 0;
  payload[25] = 0;
  payload[26] = 9;
  payload[27] = 9;
  return GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: const GameOutcome.ongoing(),
    phase: 'moving',
    payload: <String, Object?>{'tgfPayload': payload},
  );
}
