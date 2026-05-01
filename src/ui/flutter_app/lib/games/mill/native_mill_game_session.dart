// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Rust-native Mill GameSession.
//
// This is a parallel session implementation backed by `NativeMillRulesPort`
// and therefore by `crates/tgf-mill` through the typed FRB `TgfKernel`.
// `MillGameModule.startSession()` can select it behind the
// `GeneralSettings.useNativeMillSession` dogfood flag while the legacy
// `MillGameSession` remains the default rollback path.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_page/services/mill.dart' show ExtMove, PieceColor, Position;
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'lan_session_meta.dart';
import 'mill_action_codec.dart';
import 'mill_board_coordinate_maps.dart';
import 'native_mill_rules_port.dart';

class NativeMillGameSession implements GameSessionHandle {
  factory NativeMillGameSession({
    NativeMillRulesPort? rulesPort,
    RuleSettings? rules,
    GeneralSettings? generalSettings,
    LanSessionMeta? lanMeta,
  }) {
    final NativeMillRulesPort port =
        rulesPort ??
        NativeMillRulesPort(
          ruleSettings: rules ?? const RuleSettings(),
          generalSettings: generalSettings,
        );
    return NativeMillGameSession.fromPort(port, lanMeta: lanMeta);
  }

  // Named constructor for subclasses; callers outside this class should use
  // the factory constructor or this named form when subclassing.
  NativeMillGameSession.fromPort(this.rulesPort, {this.lanMeta})
    : _state = ValueNotifier<GameStateSnapshot>(rulesPort.snapshot);

  final NativeMillRulesPort rulesPort;
  LanSessionMeta? lanMeta;
  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions {
    if (_disposed || outcome.isTerminal) {
      return const <GameAction>[];
    }
    return rulesPort.legalActions;
  }

  @override
  GameOutcome get outcome => _state.value.outcome;

  int get undoDepth => rulesPort.undoDepth;

  int get redoDepth => rulesPort.redoDepth;

  // -------------------------------------------------------- setup-position API

  /// Clear the board for setup-position editing.
  void setupClear() {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupClear();
    _setState(next);
  }

  /// Place or clear one piece at [node] during setup editing.
  /// [owner]: 1 = first player, 2 = second player, other = clear.
  void setupSetPiece(int node, int owner) {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupSetPiece(node, owner);
    _setState(next);
  }

  /// Set the side to move during setup editing. [side]: 0 or 1.
  void setupSetSide(int side) {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupSetSide(side);
    _setState(next);
  }

  /// Finish setup editing and transition to a playable game state.
  void setupFinish() {
    if (_disposed) {
      return;
    }
    final GameStateSnapshot next = rulesPort.setupFinish();
    _setState(next);
  }

  /// Load a board position from a Mill FEN string via the native Rust kernel.
  ///
  /// Returns true if the FEN was valid and loaded; false otherwise.
  bool loadFen(String fen) {
    if (_disposed) {
      return false;
    }
    try {
      final GameStateSnapshot next = rulesPort.setFromFen(fen);
      _setState(next);
      return true;
    } on Object {
      return false;
    }
  }

  /// Reload using the legacy [Position] FEN parser as a fallback when the
  /// Rust parser rejects the FEN (e.g. extended custodian/intervention FENs
  /// not yet handled natively).
  bool loadFenLegacyFallback(String fen) {
    if (_disposed) {
      return false;
    }
    final Position parsed = Position();
    if (!parsed.setFen(fen)) {
      return false;
    }
    setupClear();
    for (final MapEntry<int, int> entry
        in MillBoardCoordinateMaps.nodeToLegacySquare.entries) {
      final PieceColor piece = parsed.pieceOnGrid(entry.value);
      final int owner = switch (piece) {
        PieceColor.white => 1,
        PieceColor.black => 2,
        _ => 0,
      };
      if (owner != 0) {
        setupSetPiece(entry.key, owner);
      }
    }
    setupSetSide(parsed.sideToMove == PieceColor.black ? 1 : 0);
    setupFinish();
    return true;
  }

  /// Export the current kernel state as a Mill FEN string.
  String getFen() {
    if (_disposed) {
      return '';
    }
    return rulesPort.exportFen();
  }

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    if (_disposed) {
      return;
    }
    if (!rulesPort.isLegal(action)) {
      _emit(MillEventTypes.moveRejected, <String, Object?>{
        'type': action.type,
        ...action.payload,
      });
      return;
    }
    final PlayerSeat mover = _state.value.activeSeat;
    final GameStateSnapshot next = rulesPort.apply(action);
    _setState(next);
    _emit(MillEventTypes.moveApplied, <String, Object?>{
      'type': action.type,
      'mover': mover.name,
      ...action.payload,
    });
  }

  @override
  Future<void> undo() async {
    if (_disposed) {
      return;
    }
    try {
      _setState(rulesPort.undo());
      _emit(MillEventTypes.undoApplied, const <String, Object?>{});
    } on Object catch (e) {
      _emit(MillEventTypes.actionIgnored, <String, Object?>{'reason': '$e'});
    }
  }

  @override
  Future<void> redo() async {
    if (_disposed) {
      return;
    }
    try {
      _setState(rulesPort.redo());
      _emit(MillEventTypes.redoApplied, const <String, Object?>{});
    } on Object catch (e) {
      _emit(MillEventTypes.actionIgnored, <String, Object?>{'reason': '$e'});
    }
  }

  /// Search from the current Rust kernel state backing this session.  Exposed
  /// as a concrete method (not on [GameSession]) while phase 6 moves
  /// `engine.dart` toward EngineEvent streams.
  Stream<tgf.EngineEvent> millSearchEvents({required int depth}) {
    return rulesPort.millSearchEvents(depth: depth);
  }

  /// Search the current kernel state and map the final bestMove event back to
  /// one of this session's current legal actions.  The current Rust event only
  /// exposes `toNode`, which is unambiguous for placing-phase dogfood; extend
  /// the event payload before using this for moving/removal searches.
  Future<GameAction?> searchBestAction({int depth = 1}) async {
    if (_disposed || outcome.isTerminal) {
      return null;
    }

    GameAction? bestAction;
    await for (final tgf.EngineEvent event in millSearchEvents(depth: depth)) {
      if (event.kind != 'bestMove' || event.toNode < 0) {
        continue;
      }
      bestAction = _legalActionForBestMoveToNode(event.toNode);
    }
    return bestAction;
  }

  /// Convenience dogfood hook used by the future engine.dart replacement: run
  /// Rust search from the current session, apply the best action if available,
  /// and return it to the caller for recording / UI feedback.
  Future<GameAction?> searchAndApplyBestAction({int depth = 1}) async {
    final GameAction? action = await searchBestAction(depth: depth);
    if (action == null) {
      return null;
    }
    await apply(action);
    return action;
  }

  /// Undo back to the root, then replay [moves] through this native session.
  ///
  /// Returns false if any replayed move is illegal in the Rust session.  The
  /// caller remains responsible for keeping any external PGN active-node
  /// pointer in sync with its chosen target node.
  Future<bool> replayMainline(Iterable<ExtMove> moves) async {
    while (undoDepth > 0) {
      await undo();
    }
    for (final ExtMove move in moves) {
      final String moveString = move.move;
      GameAction? action;
      for (final GameAction legal in legalActions) {
        if (MillActionCodec.moveStringFrom(legal) == moveString) {
          action = legal;
          break;
        }
      }
      if (action == null) {
        return false;
      }
      await apply(action);
    }
    return true;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    rulesPort.dispose();
    _state.dispose();
    _events.close();
  }

  void _setState(GameStateSnapshot next) {
    _state.value = next;
    _emit(MillEventTypes.stateChanged, <String, Object?>{
      'phase': next.phase,
      'activeSeat': next.activeSeat.name,
      'outcome': next.outcome.kind.name,
    });
  }

  void _emit(String type, Map<String, Object?> payload) {
    if (!_events.isClosed) {
      _events.add(GameSessionEvent(type, payload: payload));
    }
  }

  GameAction? _legalActionForBestMoveToNode(int toNode) {
    for (final GameAction action in legalActions) {
      if (action.payload['toNode'] == toNode) {
        return action;
      }
    }
    return null;
  }
}
