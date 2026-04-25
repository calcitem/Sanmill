// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Declares which cross-cutting features a [GameModule] supports.
@immutable
class GameFeatureFlags {
  const GameFeatureFlags({
    this.supportsAi = false,
    this.supportsLan = false,
    this.supportsPuzzles = false,
    this.supportsSetupPosition = false,
    this.supportsStatistics = false,
    this.supportsTimer = false,
  });

  final bool supportsAi;
  final bool supportsLan;
  final bool supportsPuzzles;
  final bool supportsSetupPosition;
  final bool supportsStatistics;
  final bool supportsTimer;
}
