// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_id.dart';

/// Stable player slot used by generic game-shell UI.
enum PlayerSeat { none, first, second }

/// Coarse outcome independent from a specific board game.
enum GameOutcomeKind { ongoing, draw, win, abandoned }

/// A game-over result that can be rendered by shared UI.
@immutable
class GameOutcome {
  const GameOutcome._({required this.kind, this.winner});

  const GameOutcome.ongoing() : this._(kind: GameOutcomeKind.ongoing);

  const GameOutcome.draw() : this._(kind: GameOutcomeKind.draw);

  const GameOutcome.win(PlayerSeat winner)
    : this._(kind: GameOutcomeKind.win, winner: winner);

  const GameOutcome.abandoned() : this._(kind: GameOutcomeKind.abandoned);

  final GameOutcomeKind kind;
  final PlayerSeat? winner;

  bool get isTerminal => kind != GameOutcomeKind.ongoing;
}

/// Generic board/action coordinate. Game modules interpret [value].
@immutable
class BoardCoordinate {
  const BoardCoordinate(this.value);

  final Object value;
}

/// One user or engine action in a game session.
@immutable
class GameAction {
  const GameAction({
    required this.type,
    this.from,
    this.to,
    this.payload = const <String, Object?>{},
  });

  final String type;
  final BoardCoordinate? from;
  final BoardCoordinate? to;
  final Map<String, Object?> payload;
}

/// Immutable state summary for shell widgets, recorders, and engines.
@immutable
class GameStateSnapshot {
  const GameStateSnapshot({
    required this.gameId,
    required this.activeSeat,
    required this.outcome,
    this.phase,
    this.lastAction,
    this.payload = const <String, Object?>{},
  });

  final GameId gameId;
  final PlayerSeat activeSeat;
  final GameOutcome outcome;
  final String? phase;
  final GameAction? lastAction;
  final Map<String, Object?> payload;
}

/// Event emitted by a [GameSession].
@immutable
class GameSessionEvent {
  const GameSessionEvent(this.type, {this.payload = const <String, Object?>{}});

  final String type;
  final Map<String, Object?> payload;
}

/// Long-lived state holder for one playable board-game instance.
///
/// New game modules should make this the single source of truth for UI state:
/// [legalActions] comes from the module's rules implementation, [apply] is the
/// only path that mutates the position, and [events] reports state changes to
/// shell services such as recording, export, and future analysis widgets.
abstract class GameSession {
  ValueListenable<GameStateSnapshot> get state;
  List<GameAction> get legalActions;
  GameOutcome get outcome;
  Stream<GameSessionEvent> get events;

  Future<void> apply(GameAction action);
  Future<void> undo();
  Future<void> redo();
  void dispose();
}

/// Small reusable no-op session for modules that have not migrated yet.
class StaticGameSession implements GameSession {
  StaticGameSession(GameStateSnapshot initialState)
    : _state = ValueNotifier<GameStateSnapshot>(initialState);

  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    assert(action.type.isNotEmpty, 'GameAction.type must not be empty.');
    _events.add(GameSessionEvent('actionIgnored', payload: action.payload));
  }

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}
}
