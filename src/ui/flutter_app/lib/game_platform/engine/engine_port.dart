// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

/// Minimal engine process boundary. Mill’s [Engine] is adapted here in
/// `games/mill/`; other games provide their own implementation.
abstract class EnginePort {
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  /// Low-level command string (UCI-like for Mill). Strong-typed commands are a
  /// later refactor.
  void sendRawCommand(String command);

  Stream<String> get eventLines;
}
