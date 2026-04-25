// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_page/services/mill.dart' show GameController;
import '../../game_platform/engine/engine_port.dart';

/// Bridges the Mill native engine to [EnginePort]. Event streaming is not yet
/// exposed from the legacy [Engine] implementation; [eventLines] is a stub.
class MillEnginePortAdapter implements EnginePort {
  @override
  Future<void> dispose() => GameController().engine.shutdown();

  @override
  Stream<String> get eventLines => const Stream<String>.empty();

  @override
  Future<void> start() => GameController().engine.ensureReady();

  @override
  void sendRawCommand(String command) {
    // Mill uses specialized methods; raw UCI string routing can be added here.
    assert(command.isNotEmpty, 'sendRawCommand: empty command');
  }

  @override
  Future<void> stop() => GameController().engine.stopSearching();
}
