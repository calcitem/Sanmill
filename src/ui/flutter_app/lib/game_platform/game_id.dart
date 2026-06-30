// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Stable identifier for a game module. Use value equality (not [Object] identity).
@immutable
class GameId {
  const GameId(this.value);

  /// Sanmill (Nine / Twelve / Morabaraba-style Mill family).
  static const GameId mill = GameId('mill');

  /// Bundled sample game (Tic-Tac-Toe) used to validate the multi-game
  /// architecture end-to-end. Self-contained: own session, rules, notation
  /// and persistence scope, does not depend on Mill internals.
  static const GameId demoProbe = GameId('demo_probe');

  /// Othello/Reversi pressure-test module backed by the Rust tgf-othello crate.
  static const GameId othello = GameId('othello');

  final String value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is GameId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GameId($value)';
}
