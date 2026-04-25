// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../game_platform/notation_port.dart';

/// Transitional notation adapter for Mill.
class MillNotationPort implements NotationPort {
  const MillNotationPort();

  @override
  List<GameAction> decodeMoveList(String notation) {
    assert(notation.isNotEmpty, 'Mill notation must not be empty.');
    return <GameAction>[
      GameAction(
        type: 'millNotation',
        payload: <String, Object?>{'notation': notation},
      ),
    ];
  }

  @override
  String describeMove(GameAction action) {
    assert(action.type.isNotEmpty, 'GameAction.type must not be empty.');
    if (action.payload['move'] case final String move) {
      return move;
    }
    return action.payload['notation']?.toString() ?? action.type;
  }

  @override
  String encodeMoveList(Iterable<GameAction> actions) {
    return actions.map(describeMove).join(' ');
  }

  @override
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions) {
    assert(
      snapshot.gameId.value == 'mill',
      'MillNotationPort needs Mill state.',
    );
    return encodeMoveList(actions);
  }
}
