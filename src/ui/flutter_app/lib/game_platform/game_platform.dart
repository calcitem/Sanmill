// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

export 'board_display.dart';
// Barrel export for the minimal multi-game platform kernel.
export 'board_geometry.dart';
export 'board_hit_test.dart';
export 'engine/engine_port.dart';
export 'engine/native_engine_client.dart';
export 'engine/native_engine_router.dart';
export 'game_feature_flags.dart';
export 'game_id.dart';
export 'game_menu.dart';
export 'game_module.dart';
export 'game_module_metadata.dart';
export 'game_persistence_scope.dart';
export 'game_registry.dart';
export 'game_session.dart';
export 'game_session_handle.dart';
// `game_state_snapshot_mill_ext.dart` lives under `lib/games/mill/` now;
// import it from that path when consumers need Mill-specific accessors.
export 'notation_port.dart';
export 'painting/graph_board_painter.dart';
export 'persistence/game_persistence_naming.dart';
export 'persistence/settings_repository_port.dart';
export 'rules_port.dart';
