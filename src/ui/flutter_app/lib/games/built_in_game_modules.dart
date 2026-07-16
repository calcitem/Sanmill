// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_platform/game_registry.dart';
import '../game_platform/play_mode_contribution.dart';
import 'mill/mill_game_module.dart';

void registerBuiltInGameModules(
  GameRegistry registry, {
  Iterable<PlayModeContribution> playModeContributions =
      const <PlayModeContribution>[],
}) {
  registry.register(
    MillGameModule(
      playModeContributions: playModeContributions
          .where((PlayModeContribution item) => item.gameId.value == 'mill')
          .toList(growable: false),
    ),
  );
}
