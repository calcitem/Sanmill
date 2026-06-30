// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../game_platform/notation_port.dart';

class DemoProbeNotationPort implements NotationPort {
  const DemoProbeNotationPort();

  @override
  List<GameAction> decodeMoveList(String notation) {
    if (notation.trim().isEmpty) {
      return const <GameAction>[];
    }
    return notation
        .split(RegExp(r'\s+'))
        .map((String token) {
          final int cell = int.parse(token);
          assert(cell >= 0 && cell < 9, 'Tic-tac-toe cell must be 0-8.');
          return GameAction(type: 'place', to: BoardCoordinate(cell));
        })
        .toList(growable: false);
  }

  @override
  String describeMove(GameAction action) {
    assert(action.to != null, 'Tic-tac-toe move requires a target cell.');
    return 'Place at ${action.to!.value}';
  }

  @override
  String encodeMoveList(Iterable<GameAction> actions) {
    return actions
        .map((GameAction action) {
          assert(action.to != null, 'Tic-tac-toe move requires a target cell.');
          return '${action.to!.value}';
        })
        .join(' ');
  }

  @override
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions) {
    return 'demo_probe:${encodeMoveList(actions)}';
  }
}
