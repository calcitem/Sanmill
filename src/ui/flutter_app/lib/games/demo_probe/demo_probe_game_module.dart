// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import '../../game_platform/board_geometry.dart';
import '../../game_platform/game_feature_flags.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_module_metadata.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../game_platform/notation_port.dart';
import '../../game_platform/rules_port.dart';
import 'demo_probe_board_geometry.dart';
import 'demo_probe_notation_port.dart';
import 'demo_probe_page.dart';
import 'demo_probe_rules_port.dart';
import 'demo_probe_session.dart';

class DemoProbeGameModule extends GameModule {
  @override
  GameModuleMetadata get metadata => const GameModuleMetadata(
    id: GameId.demoProbe,
    shortLabel: 'Probe',
    showInGamePicker: false,
  );

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
  GameSessionHandle startSession() => DemoProbeSession();

  @override
  RulesPort? get rulesPort => DemoProbeRulesPort();

  @override
  NotationPort? get notationPort => const DemoProbeNotationPort();

  @override
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  }) {
    assert(
      session is DemoProbeSession,
      'Demo probe requires DemoProbeSession.',
    );
    return DemoProbePage(key: key, session: session! as DemoProbeSession);
  }
}
