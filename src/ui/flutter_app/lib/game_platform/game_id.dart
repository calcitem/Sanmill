// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Stable identifier for a game module. Use value equality (not [Object] identity).
@immutable
class GameId {
  const GameId(this.value);

  /// Sanmill (Nine / Twelve / Morabaraba-style Mill family).
  static const GameId mill = GameId('mill');

  /// Minimal second game used to validate platform abstractions.
  static const GameId demoProbe = GameId('demo_probe');

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
