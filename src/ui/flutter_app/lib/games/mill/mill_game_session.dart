// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_page/services/mill.dart' as mill;
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import 'mill_action_codec.dart';
import 'mill_rules_port.dart';

/// Transitional session wrapper around the legacy process-wide Mill controller.
class MillGameSession implements GameSessionHandle {
  MillGameSession({mill.GameController? controller, MillRulesPort? rulesPort})
    : controller = controller ?? mill.GameController(),
      rulesPort = rulesPort ?? MillRulesPort(),
      _state = ValueNotifier<GameStateSnapshot>(_initialSnapshot()) {
    _syncFromController(emitEvent: false);
    this.controller.boardSemanticsNotifier.addListener(_onControllerChanged);
    this.controller.gameResultNotifier.addListener(_onControllerChanged);
    this.controller.headerTipNotifier.addListener(_onControllerChanged);
    this.controller.headerIconsNotifier.addListener(_onControllerChanged);
    this.controller.setupPositionNotifier.addListener(_onControllerChanged);
  }

  final mill.GameController controller;
  final MillRulesPort rulesPort;
  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();

  static GameStateSnapshot _initialSnapshot() {
    return const GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.first,
      outcome: GameOutcome.ongoing(),
      phase: MillPhases.legacy,
    );
  }

  static String _pieceColorName(mill.PieceColor c) =>
      c.toString().split('.').last;

  void _onControllerChanged() => _syncFromController(emitEvent: true);

  void _syncFromController({required bool emitEvent}) {
    if (_events.isClosed) {
      return;
    }

    final String controllerFen = controller.position.fen ?? '';
    if (controllerFen.isNotEmpty && controllerFen != rulesPort.fen) {
      rulesPort.setFen(controllerFen);
    }

    final GameStateSnapshot next = _snapshotFromController();
    final GameStateSnapshot prev = _state.value;
    if (prev == next) {
      return;
    }
    _state.value = next;
    if (emitEvent) {
      _events.add(
        GameSessionEvent(
          MillEventTypes.stateChanged,
          payload: <String, Object?>{
            'phase': next.phase,
            'activeSeat': next.activeSeat.name,
            'outcome': next.outcome.kind.name,
          },
        ),
      );
    }
  }

  GameStateSnapshot _snapshotFromController() {
    final mill.PieceColor sideToMove = controller.position.sideToMove;
    final PlayerSeat activeSeat = switch (sideToMove) {
      mill.PieceColor.white => PlayerSeat.first,
      mill.PieceColor.black => PlayerSeat.second,
      _ => PlayerSeat.none,
    };

    final mill.PieceColor winner = controller.position.winner;
    final GameOutcome outcome = switch (winner) {
      mill.PieceColor.nobody ||
      mill.PieceColor.none => const GameOutcome.ongoing(),
      mill.PieceColor.draw => const GameOutcome.draw(),
      mill.PieceColor.white => const GameOutcome.win(PlayerSeat.first),
      mill.PieceColor.black => const GameOutcome.win(PlayerSeat.second),
      _ => const GameOutcome.ongoing(),
    };

    final mill.Phase phase = controller.position.phase;
    final mill.Act action = controller.position.action;

    return GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: activeSeat,
      outcome: outcome,
      phase: phase.name,
      lastAction: _state.value.lastAction,
      payload: <String, Object?>{
        'fen': controller.position.fen,
        'action': action.name,
        'winner': _pieceColorName(winner),
        'isLan': controller.gameInstance.gameMode == mill.GameMode.humanVsLAN,
        'disableStats': controller.disableStats,
      },
    );
  }

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions {
    if (outcome.isTerminal) {
      return const <GameAction>[];
    }
    return rulesPort.legalActions;
  }

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    assert(action.type.isNotEmpty, 'GameAction.type must not be empty.');
    final String? moveStr = MillActionCodec.moveStringFrom(action);
    if (moveStr != null) {
      final bool ok = controller.applyMove(
        mill.ExtMove(moveStr, side: controller.position.sideToMove),
      );
      if (ok && rulesPort.isLegal(action)) {
        rulesPort.apply(action);
      }
      _events.add(
        GameSessionEvent(
          ok ? MillEventTypes.moveApplied : MillEventTypes.moveRejected,
          payload: <String, Object?>{'move': moveStr, 'type': action.type},
        ),
      );
      _syncFromController(emitEvent: true);
      return;
    }
    _events.add(
      GameSessionEvent(
        MillEventTypes.actionIgnored,
        payload: <String, Object?>{'type': action.type, ...action.payload},
      ),
    );
  }

  @override
  void dispose() {
    controller.boardSemanticsNotifier.removeListener(_onControllerChanged);
    controller.gameResultNotifier.removeListener(_onControllerChanged);
    controller.headerTipNotifier.removeListener(_onControllerChanged);
    controller.headerIconsNotifier.removeListener(_onControllerChanged);
    controller.setupPositionNotifier.removeListener(_onControllerChanged);
    _state.dispose();
    _events.close();
  }

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}
}
