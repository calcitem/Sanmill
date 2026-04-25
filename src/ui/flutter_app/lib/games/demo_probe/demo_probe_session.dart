// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';

class DemoProbeSession extends StaticGameSession implements GameSessionHandle {
  DemoProbeSession()
    : super(
        const GameStateSnapshot(
          gameId: GameId.demoProbe,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
          phase: 'probe',
          payload: <String, Object?>{
            'cells': <int>[0, 0, 0, 0, 0, 0, 0, 0, 0],
          },
        ),
      );

  final ValueNotifier<List<int>> cells = ValueNotifier<List<int>>(
    List<int>.filled(9, 0),
  );

  @override
  void dispose() {
    cells.dispose();
    super.dispose();
  }
}
