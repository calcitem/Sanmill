// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

/// Cross-cutting feature a game module may expose to the shell.
enum GameCapability {
  ai,
  lan,
  puzzles,
  setupPosition,
  statistics,
  timer,
  analysis,
  importExport,
  recording,
}

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
    this.capabilities = const <GameCapability>{},
  });

  const GameFeatureFlags.fromCapabilities(this.capabilities)
    : supportsAi = false,
      supportsLan = false,
      supportsPuzzles = false,
      supportsSetupPosition = false,
      supportsStatistics = false,
      supportsTimer = false;

  final bool supportsAi;
  final bool supportsLan;
  final bool supportsPuzzles;
  final bool supportsSetupPosition;
  final bool supportsStatistics;
  final bool supportsTimer;
  final Set<GameCapability> capabilities;

  bool supports(GameCapability capability) {
    switch (capability) {
      case GameCapability.ai:
        return supportsAi || capabilities.contains(capability);
      case GameCapability.lan:
        return supportsLan || capabilities.contains(capability);
      case GameCapability.puzzles:
        return supportsPuzzles || capabilities.contains(capability);
      case GameCapability.setupPosition:
        return supportsSetupPosition || capabilities.contains(capability);
      case GameCapability.statistics:
        return supportsStatistics || capabilities.contains(capability);
      case GameCapability.timer:
        return supportsTimer || capabilities.contains(capability);
      case GameCapability.analysis:
      case GameCapability.importExport:
      case GameCapability.recording:
        return capabilities.contains(capability);
    }
  }
}
