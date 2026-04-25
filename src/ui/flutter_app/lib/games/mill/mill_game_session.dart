// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game_page/services/mill.dart' show GameController;
import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';

/// Transitional session wrapper around the legacy process-wide Mill controller.
class MillGameSession implements GameSessionHandle {
  MillGameSession({GameController? controller})
    : controller = controller ?? GameController(),
      _state = ValueNotifier<GameStateSnapshot>(
        const GameStateSnapshot(
          gameId: GameId.mill,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
          phase: 'legacy',
        ),
      );

  final GameController controller;
  final ValueNotifier<GameStateSnapshot> _state;
  final StreamController<GameSessionEvent> _events =
      StreamController<GameSessionEvent>.broadcast();

  @override
  Stream<GameSessionEvent> get events => _events.stream;

  @override
  List<GameAction> get legalActions => const <GameAction>[];

  @override
  GameOutcome get outcome => _state.value.outcome;

  @override
  ValueListenable<GameStateSnapshot> get state => _state;

  @override
  Future<void> apply(GameAction action) async {
    assert(action.type.isNotEmpty, 'GameAction.type must not be empty.');
    _events.add(GameSessionEvent('millLegacyAction', payload: action.payload));
  }

  @override
  void dispose() {
    _state.dispose();
    _events.close();
  }

  @override
  Future<void> redo() async {}

  @override
  Future<void> undo() async {}
}
