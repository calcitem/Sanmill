// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/mill.dart' show ExtMove, MoveType;
import '../../game_platform/game_session.dart';
import '../../src/rust/api/kernel.dart' as tgf_kernel;
import 'mill_board_coordinate_maps.dart';
import 'mill_constants.dart';

export 'mill_constants.dart';

/// Codec between Mill's legacy [ExtMove] and the cross-game [GameAction] shape.
///
/// Encoding convention:
/// - `type` → one of [MillActionTypes].*
/// - `payload['move']` → the raw ExtMove string (e.g. `"d6"`, `"d6-e5"`, `"d6xc3"`)
///
/// This encoding is stable: it is safe to persist and to round-trip through
/// [MillNotationPort].
abstract final class MillActionCodec {
  static const int _kindPlace = 0;
  static const int _kindMove = 1;
  static const int _kindRemove = 2;

  static GameAction fromExtMove(ExtMove move) {
    final String type = switch (move.type) {
      MoveType.place => MillActionTypes.place,
      MoveType.move => MillActionTypes.move,
      MoveType.remove => MillActionTypes.remove,
      _ => MillActionTypes.move,
    };
    return GameAction(
      type: type,
      payload: <String, Object?>{'move': move.move},
    );
  }

  /// Converts a Rust-native TGF action to the stable Mill `GameAction`
  /// representation used by the existing session/export/notation code.
  ///
  /// The payload keeps both the raw typed action and the UCI-like move
  /// string so callers that still expect `"d7"` / `"d7-g7"` / `"xa1"`
  /// can work unchanged while newer code can round-trip without reparsing.
  static GameAction fromTgfAction(tgf_kernel.TgfAction action) {
    final String move = moveStringFromTgfAction(action);
    final String type = switch (action.kindTag) {
      _kindPlace => MillActionTypes.place,
      _kindMove => MillActionTypes.move,
      _kindRemove => MillActionTypes.remove,
      _ => MillActionTypes.move,
    };
    return GameAction(
      type: type,
      payload: <String, Object?>{
        'move': move,
        'tgfAction': action,
        'kindTag': action.kindTag,
        'fromNode': action.fromNode,
        'toNode': action.toNode,
        'aux': action.aux,
        'payloadBits': action.payloadBits,
      },
    );
  }

  /// Converts a `GameAction` produced by [fromTgfAction] or by legacy
  /// UCI notation back into the FRB action DTO.
  static tgf_kernel.TgfAction? toTgfAction(GameAction action) {
    final Object? raw = action.payload['tgfAction'];
    if (raw is tgf_kernel.TgfAction) {
      return raw;
    }

    final String? move = moveStringFrom(action);
    if (move == null || move.isEmpty) {
      return null;
    }
    return tgfActionFromMoveString(move);
  }

  /// Extracts the raw ExtMove string from a [GameAction] produced by
  /// [fromExtMove], or `null` if the action carries no move payload.
  static String? moveStringFrom(GameAction action) {
    if (action.payload['move'] case final String m) {
      return m;
    }
    return null;
  }

  static String moveStringFromTgfAction(tgf_kernel.TgfAction action) {
    return switch (action.kindTag) {
      _kindPlace => MillBoardCoordinateMaps.nodeToNotation(action.toNode),
      _kindMove =>
        '${MillBoardCoordinateMaps.nodeToNotation(action.fromNode)}-'
            '${MillBoardCoordinateMaps.nodeToNotation(action.toNode)}',
      _kindRemove =>
        'x${MillBoardCoordinateMaps.nodeToNotation(action.toNode)}',
      _ => '',
    };
  }

  static tgf_kernel.TgfAction? tgfActionFromMoveString(String move) {
    if (move.startsWith('x')) {
      final int to = MillBoardCoordinateMaps.notationToNode(move.substring(1));
      if (to < 0) {
        return null;
      }
      return _action(kindTag: _kindRemove, fromNode: -1, toNode: to);
    }
    if (move.contains('-')) {
      final List<String> parts = move.split('-');
      if (parts.length != 2) {
        return null;
      }
      final int from = MillBoardCoordinateMaps.notationToNode(parts[0]);
      final int to = MillBoardCoordinateMaps.notationToNode(parts[1]);
      if (from < 0 || to < 0) {
        return null;
      }
      return _action(kindTag: _kindMove, fromNode: from, toNode: to);
    }
    final int to = MillBoardCoordinateMaps.notationToNode(move);
    if (to < 0) {
      return null;
    }
    return _action(kindTag: _kindPlace, fromNode: -1, toNode: to);
  }

  static tgf_kernel.TgfAction _action({
    required int kindTag,
    required int fromNode,
    required int toNode,
  }) {
    return tgf_kernel.TgfAction(
      kindTag: kindTag,
      fromNode: fromNode,
      toNode: toNode,
      aux: -1,
      payloadBits: BigInt.zero,
    );
  }
}
