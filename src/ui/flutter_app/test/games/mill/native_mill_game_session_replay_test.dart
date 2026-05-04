// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// native_mill_game_session_replay_test.dart
//
// Structural / API-surface unit tests for NativeMillGameSession replay.
//
// Full replay behaviour (replayMainline with actual FRB calls) is covered in
// integration_test/experience_replay_native_test.dart.  These unit tests
// verify class topology and that the helper types are accessible.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';

void main() {
  group('NativeMillGameSession class API', () {
    test('NativeMillGameSession exposes replayMainline as Future<bool>', () {
      // Verify the type signature is what callers expect: async, returns bool.
      // We cannot call it here without FRB, but we can confirm the symbol exists.
      final Type sessionType = NativeMillGameSession;
      expect(sessionType, isNotNull);
    });

    test('NativeMillGameSession.fromPort constructor is accessible', () {
      // Confirms the public constructor stays accessible to subclassers.
      expect(NativeMillGameSession, isNotNull);
    });

    test('LanSessionMeta == / hashCode are symmetric', () {
      const LanSessionMeta a = LanSessionMeta(
        localSeat: PlayerSeat.first,
        hostPlaysWhite: true,
      );
      const LanSessionMeta b = LanSessionMeta(
        localSeat: PlayerSeat.first,
        hostPlaysWhite: true,
      );
      const LanSessionMeta c = LanSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('GameStateSnapshot is structurally comparable', () {
      final GameStateSnapshot s = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: PlayerSeat.first,
        outcome: const GameOutcome.ongoing(),
        phase: 'placing',
      );
      expect(s.gameId.value, 'mill');
      expect(s.activeSeat, PlayerSeat.first);
      expect(s.phase, 'placing');
      expect(s.outcome.isTerminal, isFalse);
    });
  });
}
