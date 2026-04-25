// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_module.dart';
import '../../game_platform/game_registry.dart';
import '../../game_platform/persistence/settings_repository_port.dart';
import 'database.dart';
import 'scoped_settings_repository.dart';
import 'settings_repository.dart';

/// App-wide access point for settings repositories.
///
/// [current] resolves the active [GameRegistry] scope on each call so game
/// switches cannot leave callers with a stale persistence prefix.
class SettingsRepositories {
  SettingsRepositories._();

  static final SettingsRepositories instance = SettingsRepositories._();

  SettingsRepository? _repository;
  final Map<GameId, SettingsRepositoryPort> _ports =
      <GameId, SettingsRepositoryPort>{};

  void init({SettingsRepository? repository}) {
    _repository = repository ?? DatabaseSettingsRepository(DB());
    _ports.clear();
  }

  SettingsRepository get repository {
    return _repository ??= DatabaseSettingsRepository(DB());
  }

  SettingsRepositoryPort get current {
    final GameId currentId = GameRegistry.instance.currentId;
    final GameModule? module = GameRegistry.instance.getModule(currentId);
    if (module == null) {
      return SettingsRepositoryPort(repository, persistenceScope: null);
    }

    return _ports.putIfAbsent(
      currentId,
      () => SettingsRepositoryPort(
        repository,
        persistenceScope: module.persistenceScope,
      ),
    );
  }

  ScopedSettingsRepository scoped(GameModule module) {
    return ScopedSettingsRepository(
      repository: repository,
      scope: module.persistenceScope,
    );
  }

  void resetForTesting() {
    _repository = null;
    _ports.clear();
  }
}
