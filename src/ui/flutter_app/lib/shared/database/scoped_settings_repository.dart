// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_persistence_scope.dart';
import '../../game_platform/persistence/game_persistence_naming.dart';
import 'settings_repository.dart';

/// Settings facade with an explicit game scope.
///
/// The legacy repository still stores current settings in shared boxes. This
/// class centralizes the scope metadata so new per-game boxes can be introduced
/// without changing every caller again.
class ScopedSettingsRepository {
  const ScopedSettingsRepository({
    required this.repository,
    required this.scope,
  });

  final SettingsRepository repository;
  final GamePersistenceScope scope;

  GameId get gameId => scope.gameId;

  String get keyPrefix => scopePrefixFor(gameId) ?? '';

  /// Computes the box prefix for a category in this scope.
  ///
  /// `app`-category returns `'app.'` (cross-game), `game`-category returns
  /// `'game.<id>.'`.
  String? prefixFor(PersistenceScopeCategory category) {
    return scopePrefixFromCategory(category, gameId);
  }
}
