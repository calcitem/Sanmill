// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../../game_platform/board_geometry.dart';
import '../../game_platform/game_feature_flags.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_module_metadata.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/game_session_handle.dart';
import 'demo_probe_board_geometry.dart';
import 'demo_probe_page.dart';

class DemoProbeSessionHandle implements GameSessionHandle {
  @override
  void dispose() {}
}

class DemoProbeGameModule extends GameModule {
  @override
  GameModuleMetadata get metadata =>
      const GameModuleMetadata(id: GameId.demoProbe, shortLabel: 'Probe');

  @override
  GameFeatureFlags get features => const GameFeatureFlags();

  @override
  BoardGeometry get boardGeometry => demoProbeBoardGeometry;

  /// Placeholder high range for future [Hive] types; no probe models yet.
  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId.demoProbe,
    hiveTypeIdMin: 200,
    hiveTypeIdMax: 250,
  );

  @override
  GameSessionHandle startSession() => DemoProbeSessionHandle();

  @override
  Widget buildGameSurface(BuildContext context, {Key? key}) {
    return DemoProbePage(key: key);
  }
}
