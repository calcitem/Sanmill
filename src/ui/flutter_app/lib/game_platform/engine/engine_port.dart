// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../game_id.dart';
import '../game_session.dart';

class GameEngineConfig {
  const GameEngineConfig({
    required this.gameId,
    this.options = const <String, Object?>{},
  });

  final GameId gameId;
  final Map<String, Object?> options;
}

class EnginePosition {
  const EnginePosition({required this.snapshot, this.notation});

  final GameStateSnapshot snapshot;
  final String? notation;
}

class EngineSearchRequest {
  const EngineSearchRequest({
    required this.position,
    this.timeLimit,
    this.depth,
  });

  final EnginePosition position;
  final Duration? timeLimit;
  final int? depth;
}

enum EngineEventKind { ready, info, bestMove, error, stopped }

class EngineEvent {
  const EngineEvent({
    required this.kind,
    this.line,
    this.action,
    this.payload = const <String, Object?>{},
  });

  final EngineEventKind kind;
  final String? line;
  final GameAction? action;
  final Map<String, Object?> payload;
}

/// Minimal engine process boundary. Mill’s [Engine] is adapted here in
/// `games/mill/`; other games provide their own implementation.
abstract class EnginePort {
  Future<void> start([GameEngineConfig? config]);
  Future<void> stop();
  Future<void> dispose();

  /// Low-level command string (UCI-like for Mill). Strong-typed commands are a
  /// later refactor.
  void sendRawCommand(String command);

  @Deprecated('Use events instead.')
  Stream<String> get eventLines;

  Stream<EngineEvent> get events;

  Future<void> setPosition(EnginePosition position) async {}

  Future<void> search(EngineSearchRequest request) async {}

  Future<void> analyze(EngineSearchRequest request) async {}
}
