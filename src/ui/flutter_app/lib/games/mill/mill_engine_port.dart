// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_platform/engine/engine_port.dart';
import '../../game_platform/engine/native_engine_client.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../shared/database/database.dart';
import '../../src/rust/api/kernel.dart' as tgf_kernel;
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_action_codec.dart';
import 'mill_variant_options_mapper.dart';

/// Bridges the Rust/FRB Mill native search to the game-neutral
/// [EnginePort] surface used by `GameRegistry`.  Streaming events come
/// from `tgf.nativeMillSearchEvents`; the legacy method-channel UCI
/// path is gone, so [eventLines] is intentionally an empty stream.
class MillEnginePortAdapter implements EnginePort {
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();
  StreamSubscription<tgf.EngineEvent>? _nativeSearchSub;

  @override
  Future<void> dispose() async {
    await _nativeSearchSub?.cancel();
    _nativeSearchSub = null;
    await _events.close();
  }

  @override
  Stream<String> get eventLines => const Stream<String>.empty();

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  Future<void> start([GameEngineConfig? config]) async {
    assert(
      config == null || config.gameId == GameId.mill,
      'MillEnginePortAdapter only supports GameId.mill.',
    );
    // The Rust kernel is created lazily by `NativeMillRulesPort`; no
    // explicit startup is required.
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
    await _startNativeSearch(depth: request.depth ?? 1);
  }

  @override
  Future<void> analyze(EngineSearchRequest request) async {
    assert(
      request.position.snapshot.gameId == GameId.mill,
      'Expected Mill analyze request.',
    );
    await _startNativeSearch(depth: request.depth ?? 1);
  }

  @override
  Future<NativeEngineResponse> executeNativeRequest(
    NativeEngineRequest request,
  ) async {
    assert(request.gameId == GameId.mill, 'Expected Mill native request.');
    switch (request.command) {
      case NativeEngineCommandType.raw:
        final Object? command = request.payload['command'];
        assert(command is String, 'Mill raw native request needs command.');
        sendRawCommand(command! as String);
        return NativeEngineResponse(
          requestId: request.requestId,
          gameId: request.gameId,
          status: NativeEngineResponseStatus.ok,
        );
      case NativeEngineCommandType.stop:
        await stop();
        return NativeEngineResponse(
          requestId: request.requestId,
          gameId: request.gameId,
          status: NativeEngineResponseStatus.ok,
        );
      case NativeEngineCommandType.setPosition:
        final GameStateSnapshot? snapshot = request.snapshot;
        assert(snapshot != null, 'Mill setPosition request needs a snapshot.');
        await setPosition(
          EnginePosition(
            snapshot: snapshot!,
            notation: request.payload['notation'] as String?,
          ),
        );
        return NativeEngineResponse(
          requestId: request.requestId,
          gameId: request.gameId,
          status: NativeEngineResponseStatus.ok,
        );
      case NativeEngineCommandType.search:
        await search(
          EngineSearchRequest(
            position: EnginePosition(
              snapshot:
                  request.snapshot ??
                  GameStateSnapshot(
                    gameId: request.gameId,
                    activeSeat: PlayerSeat.first,
                    outcome: const GameOutcome.ongoing(),
                  ),
            ),
            depth: request.payload['depth'] as int?,
          ),
        );
        return NativeEngineResponse(
          requestId: request.requestId,
          gameId: request.gameId,
          status: NativeEngineResponseStatus.ok,
        );
      case NativeEngineCommandType.analyze:
        await analyze(
          EngineSearchRequest(
            position: EnginePosition(
              snapshot:
                  request.snapshot ??
                  GameStateSnapshot(
                    gameId: request.gameId,
                    activeSeat: PlayerSeat.first,
                    outcome: const GameOutcome.ongoing(),
                  ),
            ),
            depth: request.payload['depth'] as int?,
          ),
        );
        return NativeEngineResponse(
          requestId: request.requestId,
          gameId: request.gameId,
          status: NativeEngineResponseStatus.ok,
        );
      case NativeEngineCommandType.newGame:
      case NativeEngineCommandType.legalActions:
      case NativeEngineCommandType.applyAction:
      case NativeEngineCommandType.undo:
      case NativeEngineCommandType.redo:
      case NativeEngineCommandType.state:
        return NativeEngineResponse.unsupported(
          request,
          reason:
              'Mill EnginePort does not implement '
              '${request.command.name}; consumers should use '
              'NativeMillGameSession directly.',
        );
    }
  }

  @override
  Future<void> updateGeneralOptions() async {
    // General settings (skill level, move time, search algorithm,
    // shuffling, …) are read directly from `DB().generalSettings` by
    // `NativeMillAiTurnController` / `MillVariantOptionsMapper` on the
    // next AI turn, so this hook is a no-op now that the legacy UCI
    // engine has been deleted.
  }

  @override
  Future<void> updateRuleOptions() async {
    // Rule changes propagate through
    // `RuleSettings.toTgfMillVariantOptions()` whenever a fresh
    // `NativeMillGameSession` is created, so no broadcast is needed.
    // We still validate that the typed FRB option path produces a
    // non-empty opening to catch encoder regressions early.
    final tgf.MillVariantOptions variant = DB().ruleSettings
        .toTgfMillVariantOptions(generalSettings: DB().generalSettings);
    final int openingCount = tgf.nativeMillInitialLegalCountForVariant(
      variant: variant,
    );
    assert(openingCount > 0, 'Rust Mill variant produced no opening actions.');
  }

  @override
  void sendRawCommand(String command) {
    // Mill uses specialized methods; raw UCI string routing can be added here.
    assert(command.isNotEmpty, 'sendRawCommand: empty command');
  }

  @override
  Future<void> stop() async {
    tgf.nativeMillSearchStop();
    await _nativeSearchSub?.cancel();
    _nativeSearchSub = null;
  }

  Future<void> _startNativeSearch({required int depth}) async {
    await _nativeSearchSub?.cancel();
    _nativeSearchSub = tgf
        .nativeMillSearchEvents(depth: depth)
        .listen(
          (tgf.EngineEvent event) {
            if (_events.isClosed) {
              return;
            }
            _events.add(_mapNativeEvent(event));
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_events.isClosed) {
              _events.add(
                EngineEvent(
                  kind: EngineEventKind.error,
                  line: error.toString(),
                  payload: <String, Object?>{'error': error.toString()},
                ),
              );
            }
          },
          onDone: () => _nativeSearchSub = null,
        );
  }

  EngineEvent _mapNativeEvent(tgf.EngineEvent event) {
    final EngineEventKind kind = switch (event.kind) {
      'ready' => EngineEventKind.ready,
      'info' => EngineEventKind.info,
      'bestMove' => EngineEventKind.bestMove,
      'stopped' => EngineEventKind.stopped,
      _ => EngineEventKind.error,
    };
    return EngineEvent(
      kind: kind,
      line: event.kind,
      action: _actionFromNativeBestMove(event),
      payload: <String, Object?>{
        'depth': event.depth,
        'score': event.score,
        'nodes': event.nodes,
        'toNode': event.toNode,
        'reason': event.reason,
      },
    );
  }

  /// Decode the engine's bestMove event into a typed [GameAction].
  ///
  /// The `reason` field starts with the full UCI notation ("a4", "a1-a4",
  /// "xa4"), so moves and removals keep their real type and origin node
  /// instead of being collapsed into a place at the destination node.
  GameAction? _actionFromNativeBestMove(tgf.EngineEvent event) {
    if (event.kind != 'bestMove' || event.toNode < 0) {
      return null;
    }
    final String notation = event.reason.split(' ').first;
    final tgf_kernel.TgfAction? tgfAction =
        MillActionCodec.tgfActionFromMoveString(notation);
    assert(
      tgfAction != null && tgfAction.toNode == event.toNode,
      'bestMove notation "$notation" (reason="${event.reason}") decodes to '
      'toNode=${tgfAction?.toNode} but the engine reported '
      'toNode=${event.toNode}.',
    );
    if (tgfAction == null) {
      return null;
    }
    return MillActionCodec.fromTgfAction(tgfAction);
  }
}
