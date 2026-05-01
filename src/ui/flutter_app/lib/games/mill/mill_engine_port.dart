// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_page/services/mill.dart' show GameController;
import '../../game_platform/engine/engine_port.dart';
import '../../game_platform/engine/native_engine_client.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../shared/database/database.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_constants.dart';
import 'mill_variant_options_mapper.dart';

/// Bridges the Mill native engine to [EnginePort]. Event streaming is not yet
/// exposed from the legacy [Engine] implementation; [eventLines] is a stub.
class MillEnginePortAdapter implements EnginePort {
  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();
  StreamSubscription<tgf.EngineEvent>? _nativeSearchSub;

  @override
  Future<void> dispose() async {
    await _nativeSearchSub?.cancel();
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
              'Mill legacy engine has not migrated ${request.command.name}.',
        );
    }
  }

  @override
  Future<void> updateGeneralOptions() async {
    GameController().engine.setGeneralOptions();
  }

  @override
  Future<void> updateRuleOptions() async {
    GameController().engine.setRuleOptions();

    // Phase 6 typed Rust path: validate the subset of rule settings that
    // Rust-native MillRules already supports.  The legacy C++ engine remains
    // authoritative for unsupported rule fields until those are implemented in
    // Rust, but this keeps the typed FRB option path exercised.
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
    await GameController().engine.stopSearching();
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

  GameAction? _actionFromNativeBestMove(tgf.EngineEvent event) {
    if (event.kind != 'bestMove' || event.toNode < 0) {
      return null;
    }
    final String move = _labelForNode(event.toNode);
    return GameAction(
      type: MillActionTypes.place,
      payload: <String, Object?>{'move': move, 'toNode': event.toNode},
    );
  }

  String _labelForNode(int node) {
    final tgf.TopologyBlob topology = tgf.kernelTopology();
    for (final tgf.TopologyPoint point in topology.points) {
      if (point.id == node) {
        return point.label;
      }
    }
    return '';
  }
}
