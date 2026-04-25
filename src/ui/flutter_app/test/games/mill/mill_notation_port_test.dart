// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_notation_port.dart';

void main() {
  const MillNotationPort port = MillNotationPort();

  group('MillNotationPort.describeMove', () {
    test('returns payload move string when present', () {
      const GameAction action = GameAction(
        type: 'mill.place',
        payload: <String, Object?>{'move': 'd6'},
      );
      expect(port.describeMove(action), 'd6');
    });

    test('returns payload notation string when move key is absent', () {
      const GameAction action = GameAction(
        type: 'millNotation',
        payload: <String, Object?>{'notation': 'd6 e5-d4'},
      );
      expect(port.describeMove(action), 'd6 e5-d4');
    });

    test('falls back to action.type when neither key is present', () {
      const GameAction action = GameAction(type: 'unknownType');
      expect(port.describeMove(action), 'unknownType');
    });
  });

  group('MillNotationPort.encodeMoveList', () {
    test('joins described moves with a space', () {
      const List<GameAction> actions = <GameAction>[
        GameAction(
          type: 'mill.place',
          payload: <String, Object?>{'move': 'd6'},
        ),
        GameAction(
          type: 'mill.move',
          payload: <String, Object?>{'move': 'd6-e5'},
        ),
      ];
      expect(port.encodeMoveList(actions), 'd6 d6-e5');
    });

    test('empty action list encodes to empty string', () {
      expect(port.encodeMoveList(const <GameAction>[]), isEmpty);
    });
  });

  group('MillNotationPort.decodeMoveList', () {
    test('wraps non-empty notation in a single millNotation action', () {
      final List<GameAction> actions = port.decodeMoveList('d6 e5-d4');
      expect(actions, hasLength(1));
      expect(actions.first.type, 'millNotation');
      expect(actions.first.payload['notation'], 'd6 e5-d4');
    });
  });

  group('MillNotationPort.exportGame', () {
    test('encodes move list for a Mill snapshot', () {
      const GameStateSnapshot snapshot = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: PlayerSeat.first,
        outcome: GameOutcome.ongoing(),
        phase: 'placing',
      );
      const List<GameAction> actions = <GameAction>[
        GameAction(
          type: 'mill.place',
          payload: <String, Object?>{'move': 'd6'},
        ),
      ];
      expect(port.exportGame(snapshot, actions), 'd6');
    });
  });

  group('MillNotationPort.round-trip', () {
    test('encode then decode preserves notation string', () {
      const List<GameAction> original = <GameAction>[
        GameAction(
          type: 'mill.place',
          payload: <String, Object?>{'move': 'd6'},
        ),
        GameAction(
          type: 'mill.move',
          payload: <String, Object?>{'move': 'd6-e5'},
        ),
      ];
      final String encoded = port.encodeMoveList(original);
      final List<GameAction> decoded = port.decodeMoveList(encoded);
      expect(decoded, hasLength(1));
      expect(decoded.first.payload['notation'], encoded);
    });
  });
}
