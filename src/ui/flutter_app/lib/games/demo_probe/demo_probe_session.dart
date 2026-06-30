// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import 'demo_probe_rules_port.dart';

class DemoProbeSession implements GameSessionHandle {
  DemoProbeSession() : _rules = DemoProbeRulesPort() {
    _state = ValueNotifier<GameStateSnapshot>(_rules.snapshot);
  }

  DemoProbeRulesPort _rules;
  final List<GameAction> _history = <GameAction>[];
  final List<GameAction> _redoStack = <GameAction>[];
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();
  late final ValueNotifier<GameStateSnapshot> _state;

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions => _rules.legalActions;

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    _rules.apply(action);
    _history.add(action);
    _redoStack.clear();
    _state.value = _rules.snapshot;
    _events.add(GameSessionEvent('actionApplied', payload: action.payload));
  }

  void reset() {
    _rules = DemoProbeRulesPort();
    _history.clear();
    _redoStack.clear();
    _state.value = _rules.snapshot;
    _events.add(const GameSessionEvent('reset'));
  }

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }

  @override
  Future<void> redo() async {
    if (_redoStack.isEmpty) {
      return;
    }
    final GameAction action = _redoStack.removeLast();
    _rules.apply(action);
    _history.add(action);
    _state.value = _rules.snapshot;
    _events.add(GameSessionEvent('actionRedone', payload: action.payload));
  }

  @override
  Future<void> undo() async {
    if (_history.isEmpty) {
      return;
    }
    _redoStack.add(_history.removeLast());

    final List<GameAction> replay = List<GameAction>.of(_history);
    _history.clear();
    _rules = DemoProbeRulesPort();
    for (final GameAction action in replay) {
      _rules.apply(action);
      _history.add(action);
    }
    _state.value = _rules.snapshot;
    _events.add(const GameSessionEvent('actionUndone'));
  }
}
