// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/engine/engine_port.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_engine_port.dart';

void main() {
  group('MillEnginePortAdapter', () {
    test('search requires a live kernel handle or FEN root', () async {
      final MillEnginePortAdapter port = MillEnginePortAdapter();
      addTearDown(port.dispose);

      await expectLater(
        port.search(
          const EngineSearchRequest(
            position: EnginePosition(
              snapshot: GameStateSnapshot(
                gameId: GameId.mill,
                activeSeat: PlayerSeat.first,
                outcome: GameOutcome.ongoing(),
              ),
            ),
            depth: 1,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
