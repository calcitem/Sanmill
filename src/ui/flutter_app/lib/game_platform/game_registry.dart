// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import 'game_id.dart';
import 'game_module.dart';

/// Registers and selects [GameModule] implementations. Notifies on selection
/// change so the shell (e.g. [Home]) can rebuild.
class GameRegistry extends ChangeNotifier {
  GameRegistry._();

  /// App-wide registry.
  static final GameRegistry instance = GameRegistry._();

  final Map<GameId, GameModule> _modules = <GameId, GameModule>{};

  GameId _currentId = GameId.mill;

  void register(GameModule module) {
    _modules[module.metadata.id] = module;
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
}
