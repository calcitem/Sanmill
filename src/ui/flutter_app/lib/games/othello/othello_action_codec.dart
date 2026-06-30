// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Translate between the framework-level `GameAction` value object (used by
// `tap_handler` and `GameSession.apply`) and the FRB-typed `TgfAction`
// shipped by `crates/tgf-othello`.
//
// Othello has a single action kind ("place"); the destination square is
// stored as `to_node` (0..63 index into the 8x8 grid).

import '../../game_platform/game_session.dart';
import '../../src/rust/api/kernel.dart' as tgf;

/// Stable string tags used by the framework `GameAction.type` field.
abstract class OthelloActionTypes {
  static const String place = 'place';
}

class OthelloActionCodec {
  OthelloActionCodec._();

  /// Convert a Rust-side `TgfAction` to the framework-level Dart action.
  static GameAction fromRust(tgf.TgfAction action) {
    return GameAction(
      type: OthelloActionTypes.place,
      to: BoardCoordinate(action.toNode),
      payload: <String, Object?>{
        'kindTag': action.kindTag,
        'fromNode': action.fromNode,
        'toNode': action.toNode,
        'aux': action.aux,
        'payloadBits': action.payloadBits,
      },
    );
  }

  /// Inverse direction: convert a Dart `GameAction` (e.g. produced by a
  /// gesture handler) back into the Rust action shape.  Returns `null` if
  /// the action does not encode a recognisable Othello placement.
  static tgf.TgfAction? toRust(GameAction action) {
    if (action.type != OthelloActionTypes.place) {
      return null;
    }
    final Object? toRaw = action.payload['toNode'] ?? action.to?.value;
    if (toRaw is! int) {
      return null;
    }
    return tgf.TgfAction(
      kindTag: 0,
      fromNode: -1,
      toNode: toRaw,
      aux: -1,
      payloadBits: BigInt.zero,
    );
  }
}
