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
import 'othello_board_geometry.dart';
import 'othello_game_session.dart';
import 'othello_page.dart';

class OthelloGameModule extends GameModule {
  @override
  GameModuleMetadata get metadata => const GameModuleMetadata(
    id: GameId.othello,
    shortLabel: 'Othello',
    showInGamePicker: false,
  );

  @override
  GameFeatureFlags get features => const GameFeatureFlags(supportsAi: true);

  @override
  BoardGeometry get boardGeometry => othelloBoardGeometry;

  @override
  GamePersistenceScope get persistenceScope => const GamePersistenceScope(
    gameId: GameId.othello,
    hiveTypeIdMin: 300,
    hiveTypeIdMax: 350,
  );

  @override
  GameSessionHandle startSession() => OthelloGameSession();

  @override
  Widget buildGameSurface(
    BuildContext context, {
    Key? key,
    GameSession? session,
  }) {
    return OthelloPage(key: key);
  }
}
