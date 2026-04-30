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

import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_constants.dart';
import 'native_mill_rules_port.dart';

class NativeMillGameSession implements GameSessionHandle {
  factory NativeMillGameSession({
    NativeMillRulesPort? rulesPort,
    RuleSettings? rules,
  }) {
    final NativeMillRulesPort port =
        rulesPort ??
        NativeMillRulesPort(ruleSettings: rules ?? const RuleSettings());
    return NativeMillGameSession._(port);
  }

  NativeMillGameSession._(this.rulesPort)
    : _state = ValueNotifier<GameStateSnapshot>(rulesPort.snapshot);

  final NativeMillRulesPort rulesPort;
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
