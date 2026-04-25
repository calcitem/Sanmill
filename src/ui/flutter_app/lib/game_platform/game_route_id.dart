// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Stable, type-safe identifier for a shell or game-module route.
///
/// This is a lightweight value object analogous to [GameId]. The underlying
/// string [value] is the canonical form used for serialization, navigation
/// state persistence, and integration tests. The value must never change once
/// published, so prefer named constants (e.g. [ShellRouteIds]) over ad-hoc
/// construction.
///
/// ## Migration strategy
///
/// Phase 1 (current): [GameModeEntry.id] and [GameMenuContribution.id] are
/// [GameRouteId]; the shared shell's internal state ([Home._routeId]) and
/// [GameModule] method parameters remain [String] for backward compatibility.
/// Call `.value` when a [String] is required.
///
/// Phase 2 (future): Migrate [GameModule.defaultShellRoute],
/// [GameModule.willNavigateToShellRoute], and [Home._routeId] to
/// [GameRouteId] and remove the need for `.value` at call sites.
@immutable
class GameRouteId {
  const GameRouteId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is GameRouteId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GameRouteId($value)';
}
