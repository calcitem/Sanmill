// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import '../../game_page/services/mill.dart' as mill;
import '../../game_platform/game_session.dart';
import 'mill_constants.dart';

/// Bridges Mill session events into the legacy [mill.GameRecorder].
///
/// The native session path already emits [MillEventTypes.moveApplied] with a
/// stable move string and mover seat.  This adapter keeps recording outside of
/// tap/AI code, so future `GameController` shrink work can subscribe once at
/// session creation time instead of manually appending moves in each caller.
class MillSessionRecorderBridge {
  MillSessionRecorderBridge({
    required GameSession session,
    required mill.GameRecorder recorder,
  }) : _recorder = recorder {
    _subscription = session.events.listen(_onEvent);
  }

  MillSessionRecorderBridge.forGameController({required GameSession session})
    : this(session: session, recorder: mill.GameController().gameRecorder);

  final mill.GameRecorder _recorder;
  late final StreamSubscription<GameSessionEvent> _subscription;

  Future<void> dispose() => _subscription.cancel();

  void _onEvent(GameSessionEvent event) {
    if (event.type != MillEventTypes.moveApplied) {
      return;
    }
    final mill.ExtMove? move = extMoveFromEvent(event);
    if (move == null) {
      return;
    }
    _recorder.appendMoveIfDifferent(move);
  }

  static mill.ExtMove? extMoveFromEvent(GameSessionEvent event) {
    if (event.type != MillEventTypes.moveApplied) {
      return null;
    }
    final String? move = event.payload['move'] as String?;
    if (move == null || move.isEmpty) {
      return null;
    }
    final mill.PieceColor? side = _pieceColorFromMover(
      event.payload['mover'] as String?,
    );
    if (side == null) {
      return null;
    }
    return mill.ExtMove(move, side: side);
  }

  static mill.PieceColor? _pieceColorFromMover(String? mover) {
    return switch (mover) {
      'first' => mill.PieceColor.white,
      'second' => mill.PieceColor.black,
      _ => null,
    };
  }
}
