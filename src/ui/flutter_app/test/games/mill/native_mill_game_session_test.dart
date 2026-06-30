// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_marked_pieces_codec.dart';
import 'package:sanmill/games/mill/mill_types.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

void main() {
  group('NativeMillGameSession', () {
    test('applies legal actions and emits state + move events', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      final GameAction action = rulesPort.placeA7;
      await session.apply(action);

      expect(rulesPort.isLegalCount, 1);
      expect(rulesPort.applyCount, 1);
      expect(session.state.value.lastAction, same(action));
      expect(session.state.value.activeSeat, PlayerSeat.second);
      expect(
        events.map((GameSessionEvent e) => e.type),
        containsAllInOrder(<String>[
          MillEventTypes.stateChanged,
          MillEventTypes.moveApplied,
        ]),
      );
      expect(events.last.payload['mover'], PlayerSeat.first.name);
      expect(events.last.payload['move'], 'a7');
      expect(events.last.payload['boardLayout'], 'O*******/********/********');
    });

    test('rejects illegal actions without mutating state', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      final GameStateSnapshot before = session.state.value;
      await session.apply(
        const GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'z9'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(rulesPort.isLegalCount, 1);
      expect(rulesPort.applyCount, 0);
      expect(session.state.value, same(before));
      expect(events.single.type, MillEventTypes.moveRejected);
    });

    test('undo and redo forward to the rules port', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);
      final List<GameSessionEvent> events = <GameSessionEvent>[];
      final StreamSubscription<GameSessionEvent> sub = session.events.listen(
        events.add,
      );
      addTearDown(sub.cancel);

      await session.apply(rulesPort.placeA7);
      await session.undo();
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.undoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.first);
      expect(
        events.map((GameSessionEvent e) => e.type),
        contains(MillEventTypes.undoApplied),
      );

      await session.redo();
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.redoCount, 1);
      expect(session.state.value.activeSeat, PlayerSeat.second);
      expect(
        events.map((GameSessionEvent e) => e.type),
        contains(MillEventTypes.redoApplied),
      );
    });

    test('terminal outcomes expose no legal actions', () {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        initial: const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.none,
          outcome: GameOutcome.draw(),
          phase: 'gameOver',
        ),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      expect(session.outcome.isTerminal, isTrue);
      expect(session.legalActions, isEmpty);
    });

    test('forceTerminal overlays a terminal result and blocks further '
        'moves until a real transition clears it', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      expect(session.outcome.isTerminal, isFalse);

      // Resignation / timeout: the rule machine cannot derive this, so it
      // is overlaid at the session layer.
      session.forceTerminal(
        const GameOutcome.win(PlayerSeat.first),
        reason: 'loseResign',
      );

      expect(session.outcome.kind, GameOutcomeKind.win);
      expect(session.outcome.winner, PlayerSeat.first);
      expect(
        session.state.value.payload[millOutcomeReasonPayloadKey],
        'loseResign',
      );
      expect(session.legalActions, isEmpty);

      // Further moves are rejected while the forced terminal stands.
      await session.apply(rulesPort.placeA7);
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.applyCount, 0);

      // A real kernel transition (New Game) clears the override so the
      // board accepts moves again.
      session.resetGame();
      expect(session.outcome.isTerminal, isFalse);
      await session.apply(rulesPort.placeA7);
      await Future<void>.delayed(Duration.zero);
      expect(rulesPort.applyCount, 1);
    });

    test(
      'searchBestAction returns null when no search bestMove is emitted',
      () async {
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);
        session.lastAiBestValue = 12;

        expect(await session.searchBestAction(), isNull);
        expect(session.lastAiBestValue, isNull);
        expect(await session.searchAndApplyBestAction(), isNull);
        expect(rulesPort.applyCount, 0);
      },
    );

    test(
      'searchBestAction stores the bestMove score for the advantage graph',
      () async {
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
          searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
            tgf.EngineEvent(
              kind: 'bestMove',
              depth: -1,
              score: -42,
              nodes: BigInt.from(256),
              toNode: 23,
              reason: 'a7 aimovetype=perfect rawScore=42',
            ),
          ]),
        );
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);

        final GameAction? best = await session.searchBestAction();

        expect(best, isNotNull);
        expect(best!.payload['move'], 'a7');
        expect(session.lastAiBestValue, -42);
        expect(session.lastAiMoveType, AiMoveType.perfect);
      },
    );

    test('searchPrincipalVariations parses and sorts MultiPV lines', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
          tgf.EngineEvent(
            kind: 'pv',
            depth: 4,
            score: -12,
            nodes: BigInt.from(128),
            toNode: 5,
            reason: 'f4 rank=2 rawScore=12 cutoff=false pv=f4,a1',
          ),
          tgf.EngineEvent(
            kind: 'pv',
            depth: 4,
            score: 30,
            nodes: BigInt.from(256),
            toNode: 3,
            reason: 'd6 rank=1 rawScore=-30 cutoff=false pv=d6,f4,a1',
          ),
        ]),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<NativeMillPrincipalVariation> variations = await session
          .searchPrincipalVariations(depth: 4, multiPv: 3);

      expect(
        variations.map((NativeMillPrincipalVariation pv) => pv.rank),
        <int>[1, 2],
      );
      expect(variations.first.move, 'd6');
      expect(variations.first.score, 30);
      expect(variations.first.nodes, 256);
      expect(variations.first.depth, 4);
      expect(variations.first.line, <String>['d6', 'f4', 'a1']);
    });

    test(
      'searchPrincipalVariations keeps the latest line for each rank',
      () async {
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
          searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
            tgf.EngineEvent(
              kind: 'pv',
              depth: 2,
              score: 10,
              nodes: BigInt.from(64),
              toNode: 3,
              reason: 'd6 rank=1 rawScore=-10 cutoff=false pv=d6,f4',
            ),
            tgf.EngineEvent(
              kind: 'pv',
              depth: 4,
              score: 28,
              nodes: BigInt.from(512),
              toNode: 3,
              reason: 'd6 rank=1 rawScore=-28 cutoff=false pv=d6,f4,a1',
            ),
            tgf.EngineEvent(
              kind: 'pv',
              depth: 4,
              score: -8,
              nodes: BigInt.from(256),
              toNode: 5,
              reason: 'f4 rank=2 rawScore=8 cutoff=false pv=f4,a1',
            ),
          ]),
        );
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);

        final List<NativeMillPrincipalVariation> variations = await session
            .searchPrincipalVariations(depth: 4, multiPv: 2);

        expect(variations, hasLength(2));
        expect(variations.first.rank, 1);
        expect(variations.first.depth, 4);
        expect(variations.first.score, 28);
        expect(variations.first.nodes, 512);
        expect(variations.first.line, <String>['d6', 'f4', 'a1']);
        expect(variations.last.rank, 2);
      },
    );

    test('searchPrincipalVariations parses a single bestMove line', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
          tgf.EngineEvent(
            kind: 'bestMove',
            depth: -1,
            score: 18,
            nodes: BigInt.from(64),
            toNode: 5,
            reason: 'f4 aimovetype=traditional rawScore=18',
          ),
        ]),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final List<NativeMillPrincipalVariation> variations = await session
          .searchPrincipalVariations(depth: 5, multiPv: 1);

      expect(variations, hasLength(1));
      expect(variations.single.rank, 1);
      expect(variations.single.move, 'f4');
      expect(variations.single.score, 18);
      expect(variations.single.nodes, 64);
      expect(variations.single.depth, 5);
      expect(variations.single.line, <String>['f4']);
    });

    test(
      'searchBestAction forces resignation when most-lost search is enabled',
      () async {
        final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
          searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
            tgf.EngineEvent(
              kind: 'bestMove',
              depth: 6,
              score: -80,
              nodes: BigInt.from(42),
              toNode: 0,
              reason: 'a7 rawScore=-80',
            ),
            tgf.EngineEvent(
              kind: 'stopped',
              depth: 6,
              score: -80,
              nodes: BigInt.from(42),
              toNode: -1,
              reason: '',
            ),
          ]),
        );
        final NativeMillGameSession session = NativeMillGameSession(
          rulesPort: rulesPort,
        );
        addTearDown(session.dispose);

        final GameAction? action = await session.searchBestAction(
          engineSettings: const GeneralSettings(resignIfMostLose: true),
        );

        expect(action, isNull);
        expect(session.outcome.kind, GameOutcomeKind.win);
        expect(session.outcome.winner, PlayerSeat.second);
        expect(
          session.state.value.payload[millOutcomeReasonPayloadKey],
          'loseResign',
        );
        expect(session.legalActions, isEmpty);
      },
    );

    test('searchBestAction picks the searched move when two moving-phase '
        'actions share the destination node', () async {
      // a7-a4 (node 23 -> 22) is listed BEFORE a1-a4 (node 21 -> 22); a
      // destination-only match would wrongly return a7-a4.
      const GameAction moveA7A4 = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{
          'move': 'a7-a4',
          'fromNode': 23,
          'toNode': 22,
        },
      );
      const GameAction moveA1A4 = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{
          'move': 'a1-a4',
          'fromNode': 21,
          'toNode': 22,
        },
      );
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        initial: const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
          phase: 'moving',
        ),
        legalActionsOverride: const <GameAction>[moveA7A4, moveA1A4],
        searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
          tgf.EngineEvent(
            kind: 'bestMove',
            depth: 6,
            score: 0,
            nodes: BigInt.zero,
            toNode: 22,
            reason: 'a1-a4 rawScore=0',
          ),
        ]),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final GameAction? applied = await session.searchAndApplyBestAction();
      expect(applied, isNotNull);
      expect(applied!.payload['move'], 'a1-a4');
      expect(rulesPort.lastApplied?.payload['move'], 'a1-a4');
      expect(
        rulesPort.isLegalCount,
        1,
        reason:
            'bestMove is checked once during mapping and not again on apply',
      );
    });

    test('searchBestAction keeps the action type when a place and a move '
        'share the destination node', () async {
      // mayMoveInPlacingPhase variants expose place + move actions with
      // the same destination at the same time.
      const GameAction moveA1A4 = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{
          'move': 'a1-a4',
          'fromNode': 21,
          'toNode': 22,
        },
      );
      const GameAction placeA4 = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'a4', 'fromNode': -1, 'toNode': 22},
      );
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        legalActionsOverride: const <GameAction>[moveA1A4, placeA4],
        searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
          tgf.EngineEvent(
            kind: 'bestMove',
            depth: -1,
            score: 0,
            nodes: BigInt.zero,
            toNode: 22,
            reason: 'a4 rawScore=0',
          ),
        ]),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final GameAction? best = await session.searchBestAction();
      expect(best, isNotNull);
      expect(best!.type, MillActionTypes.place);
      expect(best.payload['move'], 'a4');
    });

    test('searchBestAction returns null when the engine notation matches no '
        'legal action', () async {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        searchEvents: Stream<tgf.EngineEvent>.fromIterable(<tgf.EngineEvent>[
          tgf.EngineEvent(
            kind: 'bestMove',
            depth: -1,
            score: 0,
            nodes: BigInt.zero,
            toNode: 22,
            reason: 'a4 rawScore=0',
          ),
        ]),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      expect(await session.searchBestAction(), isNull);
      expect(rulesPort.applyCount, 0);
    });

    test('perfectDatabaseBestAction forwards the rules-port action', () {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        perfectDatabaseBestAction: const GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': 'a4'},
        ),
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      final GameAction? action = session.perfectDatabaseBestAction(
        engineSettings: const GeneralSettings(usePerfectDatabase: true),
      );

      expect(action, isNotNull);
      expect(action!.payload['move'], 'a4');
      expect(rulesPort.perfectDatabaseBestActionCount, 1);
    });

    test('rejects a concurrent search to serialize engine access', () async {
      // Two overlapping searchBestAction calls would read the same pre-move
      // snapshot; the first applies its move and the second's identical
      // bestMove is then rejected as illegal -- the spurious EngineNoBestMove
      // root cause.  The session asserts the single-search invariant so any
      // caller that bypasses the isEngineRunning serialization fails loudly.
      final StreamController<tgf.EngineEvent> controller =
          StreamController<tgf.EngineEvent>();
      addTearDown(controller.close);
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort(
        searchEvents: controller.stream,
      );
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      // The first search subscribes and latches the in-flight guard without
      // completing (the controller stays open).
      final Future<GameAction?> first = session.searchBestAction();
      await Future<void>.delayed(Duration.zero);

      // A second, overlapping search must trip the serialization assert.
      await expectLater(
        session.searchBestAction(),
        throwsA(isA<AssertionError>()),
      );

      // Let the first search finish cleanly so the in-flight guard releases.
      await controller.close();
      await first;
    });

    test('stores LAN metadata for native LAN turn checks', () {
      final _FakeNativeMillRulesPort rulesPort = _FakeNativeMillRulesPort();
      final NativeMillGameSession session = NativeMillGameSession(
        rulesPort: rulesPort,
      );
      addTearDown(session.dispose);

      const LanSessionMeta meta = LanSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: false,
      );
      session.lanMeta = meta;

      expect(session.lanMeta, meta);
    });
  });
}

class _FakeNativeMillRulesPort implements NativeMillRulesPort {
  _FakeNativeMillRulesPort({
    GameStateSnapshot? initial,
    List<GameAction>? legalActionsOverride,
    Stream<tgf.EngineEvent>? searchEvents,
    GameAction? perfectDatabaseBestAction,
  }) : _snapshot = initial ?? _initialSnapshot,
       _legalActionsOverride = legalActionsOverride,
       _searchEvents = searchEvents,
       _perfectDatabaseBestAction = perfectDatabaseBestAction;

  static const GameStateSnapshot _initialSnapshot = GameStateSnapshot(
    gameId: GameId.mill,
    activeSeat: PlayerSeat.first,
    outcome: GameOutcome.ongoing(),
    phase: 'placing',
  );

  final GameAction placeA7 = const GameAction(
    type: MillActionTypes.place,
    payload: <String, Object?>{'move': 'a7'},
  );

  GameStateSnapshot _snapshot;
  final List<GameAction>? _legalActionsOverride;
  final Stream<tgf.EngineEvent>? _searchEvents;
  final GameAction? _perfectDatabaseBestAction;
  int applyCount = 0;
  int isLegalCount = 0;
  int undoCount = 0;
  int redoCount = 0;
  int perfectDatabaseBestActionCount = 0;
  bool disposed = false;
  GameAction? lastApplied;

  @override
  int get undoDepth => applyCount - undoCount + redoCount;

  @override
  int get redoDepth => undoCount - redoCount;

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  List<GameAction> get legalActions => _snapshot.outcome.isTerminal
      ? const <GameAction>[]
      : _legalActionsOverride ?? <GameAction>[placeA7];

  @override
  bool isLegal(GameAction action) {
    isLegalCount++;
    return legalActions.any(
      (GameAction legal) =>
          legal.type == action.type &&
          legal.payload['move'] == action.payload['move'],
    );
  }

  @override
  GameStateSnapshot apply(GameAction action) {
    applyCount++;
    lastApplied = action;
    final Uint8List payload = Uint8List(280);
    payload[0] = 1;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
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
  GameStateSnapshot undo() {
    undoCount++;
    _snapshot = _initialSnapshot;
    return _snapshot;
  }

  @override
  GameStateSnapshot redo() {
    redoCount++;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.second,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      lastAction: placeA7,
    );
    return _snapshot;
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  Stream<tgf.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
    int multiPv = 1,
  }) {
    return _searchEvents ?? const Stream<tgf.EngineEvent>.empty();
  }

  @override
  GameAction? perfectDatabaseBestAction({GeneralSettings? engineSettings}) {
    perfectDatabaseBestActionCount++;
    return _perfectDatabaseBestAction;
  }

  @override
  GameStateSnapshot setupClear() => _snapshot;

  @override
  GameStateSnapshot setupSetPiece(int node, int owner) => _snapshot;

  @override
  GameStateSnapshot setupSetSide(int side) => _snapshot;

  @override
  GameStateSnapshot setupFinish() => _snapshot;

  @override
  GameStateSnapshot setFromFen(String fen) => _snapshot;

  @override
  String exportFen() =>
      'O*******/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';

  @override
  tgf.MillAnalysisReport analyzePerfectDb() => const tgf.MillAnalysisReport(
    moves: <tgf.MillMoveAnalysis>[],
    traps: <String>[],
  );
}
