// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../shared/database/database.dart';
import '../game_persistence_scope.dart';
import 'game_persistence_naming.dart';

/// Thin facade over [Database] to centralize access and to attach a
/// [GamePersistenceScope] for future namespaced storage.
class SettingsRepositoryPort {
  SettingsRepositoryPort(this._db, {required this.persistenceScope});

  final Database _db;
  final GamePersistenceScope? persistenceScope;

  Database get db => _db;

  /// Key prefix for new per-game box names (e.g. `game.mill.ruleSettings`).
  String? get boxPrefix => scopePrefixFor(persistenceScope?.gameId);
}
