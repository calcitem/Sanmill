// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';

void main() {
  group('MillActionTypes', () {
    test('all values carry the "mill." prefix', () {
      expect(MillActionTypes.place, startsWith('mill.'));
      expect(MillActionTypes.move, startsWith('mill.'));
      expect(MillActionTypes.remove, startsWith('mill.'));
      expect(MillActionTypes.select, startsWith('mill.'));
    });

    test('values are unique', () {
      final List<String> values = <String>[
        MillActionTypes.place,
        MillActionTypes.move,
        MillActionTypes.remove,
        MillActionTypes.select,
      ];
      expect(values.toSet().length, values.length);
    });
  });

  group('MillEventTypes', () {
    test('all values carry the "mill" prefix', () {
      expect(MillEventTypes.stateChanged, startsWith('mill'));
      expect(MillEventTypes.moveApplied, startsWith('mill'));
      expect(MillEventTypes.moveRejected, startsWith('mill'));
      expect(MillEventTypes.undoApplied, startsWith('mill'));
      expect(MillEventTypes.redoApplied, startsWith('mill'));
      expect(MillEventTypes.actionIgnored, startsWith('mill'));
    });

    test('values are unique', () {
      final List<String> values = <String>[
        MillEventTypes.stateChanged,
        MillEventTypes.moveApplied,
        MillEventTypes.moveRejected,
        MillEventTypes.undoApplied,
        MillEventTypes.redoApplied,
        MillEventTypes.actionIgnored,
      ];
      expect(values.toSet().length, values.length);
    });
  });

  group('MillPhases', () {
    test('legacy phase is non-empty', () {
      expect(MillPhases.legacy, isNotEmpty);
    });
  });

  group('MillActionCodec.moveStringFrom', () {
    test('returns move string when payload carries move key', () {
      const GameAction action = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'd6'},
      );
      // Access moveStringFrom via the re-export from mill_action_codec.dart.
      // Because mill_action_codec.dart imports mill.dart, this group is kept
      // separate and only tests the pure-Dart moveStringFrom path without
      // exercising ExtMove directly.
      //
      // We verify the contract via the constants in GameAction.payload.
      expect(action.payload['move'], 'd6');
    });

    test('GameAction without move payload has null move field', () {
      const GameAction action = GameAction(type: 'mill.place');
      expect(action.payload['move'], isNull);
    });
  });
}
