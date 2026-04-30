// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Rust-native Mill GameSession.
//
// This is a parallel session implementation backed by `NativeMillRulesPort`
// and therefore by `crates/tgf-mill` through the typed FRB `TgfKernel`.
// It is intentionally NOT wired into `MillGameModule.startSession()` yet:
// the legacy `MillGameSession` remains the production path until UI
// widgets stop depending on `GameController` / `Position` internals.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../rule_settings/models/rule_settings.dart';
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
    final GameStateSnapshot next = rulesPort.apply(action);
    _setState(next);
    _emit(MillEventTypes.moveApplied, <String, Object?>{
      'type': action.type,
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
}
