// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ignore_for_file: avoid_classes_with_only_static_members

import '../../game_page/services/mill.dart' show ExtMove, MoveType;
import '../../game_platform/game_session.dart';

/// Stable action type strings for Mill exports and session interactions.
///
/// These strings are consumed by [MillGameSession], [MillNotationPort], and
/// [MillGameModule.buildExportData]. Using constants avoids scattered bare
/// string literals and reduces future migration cost when legalActions are
/// fully enumerated.
abstract final class MillActionTypes {
  /// The active player must place a new piece on the board.
  static const String place = 'mill.place';

  /// The active player must move (slide) an existing piece.
  static const String move = 'mill.move';

  /// The active player must remove an opponent's piece after forming a mill.
  static const String remove = 'mill.remove';

  /// The active player must select a piece to move (two-step move semantics).
  static const String select = 'mill.select';
}

/// Codec between Mill's legacy [ExtMove] and the cross-game [GameAction] shape.
///
/// Encoding convention:
/// - `type` → one of [MillActionTypes].*
/// - `payload['move']` → the raw ExtMove string (e.g. `"d6"`, `"d6-e5"`, `"d6xc3"`)
///
/// This encoding is stable: it is safe to persist and to round-trip through
/// [MillNotationPort].
abstract final class MillActionCodec {
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

  /// Extracts the raw ExtMove string from a [GameAction] produced by
  /// [fromExtMove], or `null` if the action carries no move payload.
  static String? moveStringFrom(GameAction action) {
    if (action.payload['move'] case final String m) {
      return m;
    }
    return null;
  }
}
