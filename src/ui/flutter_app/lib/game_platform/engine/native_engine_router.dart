// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game_id.dart';
import 'engine_port.dart';
import 'native_engine_client.dart';

/// Routes strongly typed engine requests to a game-specific [EnginePort].
class NativeEngineRouter {
  final Map<GameId, EnginePort> _ports = <GameId, EnginePort>{};

  void register(GameId gameId, EnginePort port) {
    assert(!_ports.containsKey(gameId), 'Engine already registered: $gameId');
    _ports[gameId] = port;
  }

  EnginePort portFor(GameId gameId) {
    final EnginePort? port = _ports[gameId];
    assert(port != null, 'No EnginePort registered for $gameId.');
    return port!;
  }

  Future<void> start(GameEngineConfig config) =>
      portFor(config.gameId).start(config);

  Future<void> stop(GameId gameId) => portFor(gameId).stop();

  Future<void> dispose(GameId gameId) async {
    final EnginePort? port = _ports.remove(gameId);
    assert(port != null, 'No EnginePort registered for $gameId.');
    await port!.dispose();
  }

  Stream<EngineEvent> eventsFor(GameId gameId) => portFor(gameId).events;

  Future<NativeEngineResponse> execute(NativeEngineRequest request) {
    return portFor(request.gameId).executeNativeRequest(request);
  }

  @visibleForTesting
  void resetForTesting() {
    _ports.clear();
  }
}
