// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../shared/database/settings_repository.dart';
import '../game_persistence_scope.dart';
import 'game_persistence_naming.dart';

/// Thin facade over [SettingsRepository] to centralize access and to attach a
/// [GamePersistenceScope] for future namespaced storage.
class SettingsRepositoryPort {
  SettingsRepositoryPort(this.repository, {required this.persistenceScope});

  final SettingsRepository repository;
  final GamePersistenceScope? persistenceScope;

  /// Key prefix for new per-game box names (e.g. `game.mill.ruleSettings`).
  String? get boxPrefix => scopePrefixFor(persistenceScope?.gameId);
}
