// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../game_id.dart';
import '../game_session.dart';

/// Game-neutral command shape used by Dart before a native multi-game bridge
/// exists.
///
/// The current native implementation is still Mill-only. New Dart code should
/// pass through this envelope so future native routing can be added without
/// changing game modules again.
enum NativeEngineCommandType {
  newGame,
  setPosition,
  legalActions,
  applyAction,
  undo,
  redo,
  search,
  analyze,
  stop,
  state,
  raw,
}

enum NativeEngineResponseStatus { ok, rejected, unsupported, notReady, error }

class NativeEngineRequest {
  const NativeEngineRequest({
    required this.requestId,
    required this.gameId,
    required this.command,
    this.snapshot,
    this.action,
    this.payload = const <String, Object?>{},
  });

  final String requestId;
  final GameId gameId;
  final NativeEngineCommandType command;
  final GameStateSnapshot? snapshot;
  final GameAction? action;
  final Map<String, Object?> payload;
}

class NativeEngineResponse {
  const NativeEngineResponse({
    required this.requestId,
    required this.gameId,
    required this.status,
    this.snapshot,
    this.legalActions = const <GameAction>[],
    this.bestMove,
    this.diagnostics = const <String>[],
    this.payload = const <String, Object?>{},
  });

  factory NativeEngineResponse.unsupported(
    NativeEngineRequest request, {
    String? reason,
  }) {
    return NativeEngineResponse(
      requestId: request.requestId,
      gameId: request.gameId,
      status: NativeEngineResponseStatus.unsupported,
      diagnostics: <String>[?reason],
    );
  }

  final String requestId;
  final GameId gameId;
  final NativeEngineResponseStatus status;
  final GameStateSnapshot? snapshot;
  final List<GameAction> legalActions;
  final GameAction? bestMove;
  final List<String> diagnostics;
  final Map<String, Object?> payload;

  bool get isOk => status == NativeEngineResponseStatus.ok;
}

abstract class NativeGameEngineClient {
  Future<NativeEngineResponse> send(NativeEngineRequest request);
}
