// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/rules_port.dart';

class DemoProbeRulesPort implements RulesPort {
  DemoProbeRulesPort([
    List<int>? cells,
    PlayerSeat activeSeat = PlayerSeat.first,
  ]) : _cells = List<int>.of(cells ?? List<int>.filled(9, _empty)),
       _activeSeat = activeSeat {
    assert(_cells.length == 9, 'Tic-tac-toe board must have 9 cells.');
  }

  static const int _empty = 0;
  static const int _first = 1;
  static const int _second = 2;

  final List<int> _cells;
  PlayerSeat _activeSeat;
  GameAction? _lastAction;

  @override
  List<GameAction> get legalActions {
    if (snapshot.outcome.isTerminal) {
      return const <GameAction>[];
    }
    return <GameAction>[
      for (int i = 0; i < _cells.length; i++)
        if (_cells[i] == _empty)
          GameAction(type: 'place', to: BoardCoordinate(i)),
    ];
  }

  @override
  GameStateSnapshot get snapshot => GameStateSnapshot(
    gameId: GameId.demoProbe,
    activeSeat: _activeSeat,
    outcome: _outcome(),
    phase: 'play',
    lastAction: _lastAction,
    payload: <String, Object?>{'cells': List<int>.unmodifiable(_cells)},
  );

  @override
  GameStateSnapshot apply(GameAction action) {
    assert(isLegal(action), 'Illegal tic-tac-toe action: ${action.type}.');
    final int index = action.to!.value as int;
    _cells[index] = _activeSeat == PlayerSeat.first ? _first : _second;
    _lastAction = action;
    if (!_outcome().isTerminal) {
      _activeSeat = _activeSeat == PlayerSeat.first
          ? PlayerSeat.second
          : PlayerSeat.first;
    }
    return snapshot;
  }

  @override
  bool isLegal(GameAction action) {
    if (action.type != 'place' || action.to == null) {
      return false;
    }
    final Object value = action.to!.value;
    if (value is! int || value < 0 || value >= _cells.length) {
      return false;
    }
    return !snapshot.outcome.isTerminal && _cells[value] == _empty;
  }

  GameOutcome _outcome() {
    const List<List<int>> lines = <List<int>>[
      <int>[0, 1, 2],
      <int>[3, 4, 5],
      <int>[6, 7, 8],
      <int>[0, 3, 6],
      <int>[1, 4, 7],
      <int>[2, 5, 8],
      <int>[0, 4, 8],
      <int>[2, 4, 6],
    ];
    for (final List<int> line in lines) {
      final int value = _cells[line[0]];
      if (value != _empty &&
          value == _cells[line[1]] &&
          value == _cells[line[2]]) {
        return GameOutcome.win(
          value == _first ? PlayerSeat.first : PlayerSeat.second,
        );
      }
    }
    return _cells.contains(_empty)
        ? const GameOutcome.ongoing()
        : const GameOutcome.draw();
  }
}
