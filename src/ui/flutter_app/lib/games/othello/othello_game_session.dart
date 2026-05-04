// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Real `GameSession` for Othello backed by the Rust-native `tgf-othello`
// crate.  Exercises the typed FRB kernel surface end-to-end as a
// secondary game beside Mill.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_platform/engine/tgf_kernel.dart';
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';
import '../../src/rust/api/kernel.dart' as tgf;
import 'othello_action_codec.dart';

class OthelloGameSession implements GameSessionHandle {
  OthelloGameSession({TgfKernel? kernel})
    : _kernel = kernel ?? TgfKernel.create('othello'),
      _state = ValueNotifier<GameStateSnapshot>(_initialSnapshot());

  factory OthelloGameSession.fromKernel(TgfKernel kernel) =>
      OthelloGameSession(kernel: kernel);

  final TgfKernel _kernel;
  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();
  bool _disposed = false;

  static GameStateSnapshot _initialSnapshot() => const GameStateSnapshot(
    gameId: GameId.othello,
    activeSeat: PlayerSeat.first,
    outcome: GameOutcome.ongoing(),
    phase: 'opening',
    payload: <String, Object?>{'engine': 'tgf-othello'},
  );

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions {
    if (_disposed) {
      return const <GameAction>[];
    }
    return _kernel
        .rawLegalActions()
        .map(OthelloActionCodec.fromRust)
        .toList(growable: false);
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
    final tgf.TgfAction? rustAction = OthelloActionCodec.toRust(action);
    if (rustAction == null) {
      _events.add(
        GameSessionEvent(
          'actionIgnored',
          payload: <String, Object?>{'type': action.type},
        ),
      );
      return;
    }
    try {
      _state.value = _kernel.applyTypedAction(rustAction, lastAction: action);
      _events.add(
        GameSessionEvent(
          'moveApplied',
          payload: <String, Object?>{'type': action.type},
        ),
      );
    } on KernelException catch (e) {
      _events.add(
        GameSessionEvent(
          'moveRejected',
          payload: <String, Object?>{'reason': e.reason},
        ),
      );
    }
  }

  @override
  Future<void> undo() async {
    if (_disposed) {
      return;
    }
    try {
      _state.value = _kernel.undoTyped();
    } on KernelException {
      // Nothing to undo — silently ignore so callers can poll-then-undo
      // without wrapping each call in try/catch themselves.
    }
  }

  @override
  Future<void> redo() async {
    if (_disposed) {
      return;
    }
    try {
      _state.value = _kernel.redoTyped();
    } on KernelException {
      // Nothing to redo.
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _kernel.dispose();
    _state.dispose();
    _events.close();
  }
}
