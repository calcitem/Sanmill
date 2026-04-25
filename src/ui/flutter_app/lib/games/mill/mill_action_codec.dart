// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/mill.dart' show ExtMove, MoveType;
import '../../game_platform/game_session.dart';

/// Stable action type strings for Mill exports and future rules/service work.
abstract final class MillActionTypes {
  static const String place = 'mill.place';
  static const String move = 'mill.move';
  static const String remove = 'mill.remove';
}

/// Codec between Mill's legacy [ExtMove] and the cross-game [GameAction] shape.
abstract final class MillActionCodec {
  static GameAction fromExtMove(ExtMove move) {
    final String type = switch (move.type) {
      MoveType.place => MillActionTypes.place,
      MoveType.move => MillActionTypes.move,
      MoveType.remove => MillActionTypes.remove,
      _ => MillActionTypes.move,
    };
    return GameAction(type: type, payload: <String, Object?>{'move': move.move});
  }
}

