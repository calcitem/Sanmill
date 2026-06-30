// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_tap_action_selector.dart';

void main() {
  group('MillTapActionSelector', () {
    test('selects a place action matching the tapped label', () {
      const GameAction placeA7 = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'a7'},
      );

      final MillTapActionSelection selection = MillTapActionSelector.select(
        legalActions: const <GameAction>[placeA7],
        tappedLabel: 'A7',
      );

      expect(selection.action, same(placeA7));
      expect(selection.selectedFrom, isNull);
    });

    test('first tap selects a movable source square', () {
      const GameAction move = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{'move': 'd7-g7'},
      );

      final MillTapActionSelection selection = MillTapActionSelector.select(
        legalActions: const <GameAction>[move],
        tappedLabel: 'd7',
      );

      expect(selection.action, isNull);
      expect(selection.selectedFrom, 'd7');
    });

    test('second tap completes a move from the selected source', () {
      const GameAction move = GameAction(
        type: MillActionTypes.move,
        payload: <String, Object?>{'move': 'd7-g7'},
      );

      final MillTapActionSelection selection = MillTapActionSelector.select(
        legalActions: const <GameAction>[move],
        selectedFrom: 'd7',
        tappedLabel: 'g7',
      );

      expect(selection.action, same(move));
      expect(selection.selectedFrom, isNull);
    });

    test('remove actions take precedence over place/move candidates', () {
      const GameAction remove = GameAction(
        type: MillActionTypes.remove,
        payload: <String, Object?>{'move': 'xa1'},
      );
      const GameAction place = GameAction(
        type: MillActionTypes.place,
        payload: <String, Object?>{'move': 'a1'},
      );

      final MillTapActionSelection selection = MillTapActionSelector.select(
        legalActions: const <GameAction>[place, remove],
        tappedLabel: 'a1',
      );

      expect(selection.action, same(remove));
    });

    test('returns none for unknown taps', () {
      final MillTapActionSelection selection = MillTapActionSelector.select(
        legalActions: const <GameAction>[],
        tappedLabel: 'z9',
      );

      expect(selection.hasAction, isFalse);
      expect(selection.selectedFrom, isNull);
    });
  });
}
