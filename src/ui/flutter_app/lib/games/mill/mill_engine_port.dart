// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_page/services/mill.dart' show GameController;
import '../../game_platform/engine/engine_port.dart';
import '../../game_platform/game_id.dart';

/// Bridges the Mill native engine to [EnginePort]. Event streaming is not yet
/// exposed from the legacy [Engine] implementation; [eventLines] is a stub.
class MillEnginePortAdapter implements EnginePort {
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();

  @override
  Future<void> dispose() async {
    await GameController().engine.shutdown();
    await _events.close();
  }

  @override
  Stream<String> get eventLines => const Stream<String>.empty();

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> start([GameEngineConfig? config]) {
    assert(
      config == null || config.gameId == GameId.mill,
      'MillEnginePortAdapter only supports GameId.mill.',
    );
    return GameController().engine.ensureReady();
  }

  @override
  Future<void> setPosition(EnginePosition position) async {
    assert(position.snapshot.gameId == GameId.mill, 'Expected Mill position.');
  }

  @override
  Future<void> search(EngineSearchRequest request) async {
    assert(
      request.position.snapshot.gameId == GameId.mill,
      'Expected Mill search request.',
    );
  }

  @override
  Future<void> analyze(EngineSearchRequest request) async {
    assert(
      request.position.snapshot.gameId == GameId.mill,
      'Expected Mill analyze request.',
    );
  }

  @override
  Future<void> updateGeneralOptions() async {
    GameController().engine.setGeneralOptions();
  }

  @override
  Future<void> updateRuleOptions() async {
    GameController().engine.setRuleOptions();
  }

  @override
  void sendRawCommand(String command) {
    // Mill uses specialized methods; raw UCI string routing can be added here.
    assert(command.isNotEmpty, 'sendRawCommand: empty command');
  }

  @override
  Future<void> stop() => GameController().engine.stopSearching();
}
