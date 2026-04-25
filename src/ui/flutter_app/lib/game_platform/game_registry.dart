// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'engine/engine_port.dart';
import 'engine/native_engine_router.dart';
import 'game_id.dart';
import 'game_module.dart';

/// Registers and selects [GameModule] implementations. Notifies on selection
/// change so the shell (e.g. [Home]) can rebuild.
class GameRegistry extends ChangeNotifier {
  GameRegistry._();

  /// App-wide registry.
  static final GameRegistry instance = GameRegistry._();

  final Map<GameId, GameModule> _modules = <GameId, GameModule>{};
  final NativeEngineRouter _engineRouter = NativeEngineRouter();

  GameId _currentId = GameId.mill;

  void register(GameModule module) {
    _assertPersistenceScopeDoesNotOverlap(module);
    _modules[module.metadata.id] = module;
    final EnginePort? enginePort = module.enginePort;
    if (enginePort != null) {
      _engineRouter.register(module.metadata.id, enginePort);
    }
  }

  GameModule? getModule(GameId id) => _modules[id];

  GameId get currentId => _currentId;

  GameModule get current {
    final GameModule? m = _modules[_currentId];
    assert(
      m != null,
      'No GameModule registered for $_currentId. Call register() at startup.',
    );
    return m!;
  }

  void select(GameId id) {
    if (!_modules.containsKey(id)) {
      throw StateError('Unknown game id: $id');
    }
    if (_currentId == id) {
      return;
    }
    _currentId = id;
    notifyListeners();
  }

  /// Games that should appear in a picker UI (e.g. debug or future menu).
  Iterable<GameModule> get registeredModules => _modules.values;

  /// Global strongly typed engine router. Modules register their [EnginePort]
  /// automatically when added via [register].
  NativeEngineRouter get engineRouter => _engineRouter;

  /// Test-only escape hatch: clears all modules and resets the active id back
  /// to [GameId.mill]. Listeners are not notified (use a fresh listener after
  /// reset).
  @visibleForTesting
  void resetForTesting() {
    _modules.clear();
    _currentId = GameId.mill;
    // ignore: invalid_use_of_visible_for_testing_member
    _engineRouter.resetForTesting();
  }

  void _assertPersistenceScopeDoesNotOverlap(GameModule module) {
    assert(() {
      final int? min = module.persistenceScope.hiveTypeIdMin;
      final int? max = module.persistenceScope.hiveTypeIdMax;
      if (min == null || max == null) {
        return true;
      }
      assert(
        min <= max,
        'Invalid Hive typeId range for ${module.metadata.id}.',
      );
      for (final GameModule registered in _modules.values) {
        if (registered.metadata.id == module.metadata.id) {
          // Re-registration of the same id is a replacement, not a conflict.
          continue;
        }
        final int? otherMin = registered.persistenceScope.hiveTypeIdMin;
        final int? otherMax = registered.persistenceScope.hiveTypeIdMax;
        if (otherMin == null || otherMax == null) {
          continue;
        }
        final bool overlaps = min <= otherMax && otherMin <= max;
        assert(
          !overlaps,
          'Hive typeId range $min-$max for ${module.metadata.id} overlaps '
          'with $otherMin-$otherMax for ${registered.metadata.id}.',
        );
      }
      return true;
    }());
  }
}
