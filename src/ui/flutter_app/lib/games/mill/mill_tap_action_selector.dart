// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ignore_for_file: avoid_classes_with_only_static_members

import '../../game_platform/game_session.dart';
import 'mill_action_codec.dart';

/// Result of translating one board tap into either a complete action or a
/// selected source square for a later Move action.
class MillTapActionSelection {
  const MillTapActionSelection._({this.action, this.selectedFrom});

  const MillTapActionSelection.action(GameAction action)
    : this._(action: action);

  const MillTapActionSelection.selected(String selectedFrom)
    : this._(selectedFrom: selectedFrom);

  const MillTapActionSelection.none() : this._();

  final GameAction? action;
  final String? selectedFrom;

  bool get hasAction => action != null;
}

/// Pure selector used by the native Mill session path.
///
/// The legacy tap handler receives C++ square ids and turns them into labels
/// with `ExtMove.sqToNotation`; this class deliberately works at the label
/// level (`"a7"`, `"d7-g7"`, `"xa1"`) so it can be tested without pulling in
/// `GameController` or `Position`.
abstract final class MillTapActionSelector {
  static MillTapActionSelection select({
    required Iterable<GameAction> legalActions,
    required String tappedLabel,
    String? selectedFrom,
  }) {
    final String tap = tappedLabel.toLowerCase();
    if (tap.isEmpty) {
      return const MillTapActionSelection.none();
    }

    final List<GameAction> actions = legalActions.toList(growable: false);

    final GameAction? remove = _firstMatchingMove(
      actions,
      type: MillActionTypes.remove,
      move: 'x$tap',
    );
    if (remove != null) {
      return MillTapActionSelection.action(remove);
    }

    if (selectedFrom != null && selectedFrom.isNotEmpty) {
      final GameAction? move = _firstMatchingMove(
        actions,
        type: MillActionTypes.move,
        move: '${selectedFrom.toLowerCase()}-$tap',
      );
      if (move != null) {
        return MillTapActionSelection.action(move);
      }
    }

    final GameAction? place = _firstMatchingMove(
      actions,
      type: MillActionTypes.place,
      move: tap,
    );
    if (place != null) {
      return MillTapActionSelection.action(place);
    }

    final bool canMoveFromTap = actions.any((GameAction action) {
      if (action.type != MillActionTypes.move) {
        return false;
      }
      final String? move = MillActionCodec.moveStringFrom(action);
      return move != null && move.toLowerCase().startsWith('$tap-');
    });
    if (canMoveFromTap) {
      return MillTapActionSelection.selected(tap);
    }

    return const MillTapActionSelection.none();
  }

  static GameAction? _firstMatchingMove(
    Iterable<GameAction> legalActions, {
    required String type,
    required String move,
  }) {
    for (final GameAction action in legalActions) {
      if (action.type != type) {
        continue;
      }
      final String? actionMove = MillActionCodec.moveStringFrom(action);
      if (actionMove?.toLowerCase() == move) {
        return action;
      }
    }
    return null;
  }
}
