// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../game_page/services/mill.dart' show GameMode;
import '../../game_page/widgets/game_page.dart' show GamePage;
import '../../game_platform/board_geometry.dart';
import '../../game_platform/game_feature_flags.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_module_metadata.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/game_session_handle.dart';
import 'mill_board_geometry.dart';
import 'mill_game_session.dart';

class MillGameModule extends GameModule {
  MillGameModule();

  @override
  GameModuleMetadata get metadata =>
      const GameModuleMetadata(id: GameId.mill, shortLabel: 'Mill');

  @override
  GameFeatureFlags get features => const GameFeatureFlags(
    supportsAi: true,
    supportsLan: true,
    supportsPuzzles: true,
    supportsSetupPosition: true,
    supportsStatistics: true,
    supportsTimer: true,
    capabilities: <GameCapability>{
      GameCapability.analysis,
      GameCapability.importExport,
      GameCapability.recording,
    },
  );

  @override
  BoardGeometry get boardGeometry => millDefaultBoardGeometry;

  /// Mill legacy [Hive] models use scattered low typeId values (0–~38) — frozen.
  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId.mill,
    hiveTypeIdMin: 0,
    hiveTypeIdMax: 50,
  );

  @override
  GameSessionHandle startSession() => MillGameSession();

  @override
  Widget buildGameSurface(BuildContext context, {Key? key}) {
    return GamePage(
      kIsWeb ? GameMode.humanVsHuman : GameMode.humanVsAi,
      key: key,
    );
  }
}
