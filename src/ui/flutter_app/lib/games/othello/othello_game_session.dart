// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_id.dart';
import '../../game_platform/game_session.dart';
import '../../game_platform/game_session_handle.dart';

class OthelloGameSession extends StaticGameSession
    implements GameSessionHandle {
  OthelloGameSession()
    : super(
        const GameStateSnapshot(
          gameId: GameId.othello,
          activeSeat: PlayerSeat.first,
          outcome: GameOutcome.ongoing(),
          phase: 'opening',
          payload: <String, Object?>{'engine': 'tgf-othello'},
        ),
      );
}
