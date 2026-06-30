// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';

void main() {
  group('LanSessionMeta', () {
    test('maps host and client seats from host color', () {
      expect(
        LanSessionMeta.fromHost(isHost: true, hostPlaysWhite: true),
        const LanSessionMeta(localSeat: PlayerSeat.first, hostPlaysWhite: true),
      );
      expect(
        LanSessionMeta.fromHost(isHost: false, hostPlaysWhite: true),
        const LanSessionMeta(
          localSeat: PlayerSeat.second,
          hostPlaysWhite: true,
        ),
      );
      expect(
        LanSessionMeta.fromHost(isHost: true, hostPlaysWhite: false),
        const LanSessionMeta(
          localSeat: PlayerSeat.second,
          hostPlaysWhite: false,
        ),
      );
      expect(
        LanSessionMeta.fromHost(isHost: false, hostPlaysWhite: false),
        const LanSessionMeta(
          localSeat: PlayerSeat.first,
          hostPlaysWhite: false,
        ),
      );
    });

    test('detects opponent turn from the active native seat', () {
      const LanSessionMeta meta = LanSessionMeta(
        localSeat: PlayerSeat.second,
        hostPlaysWhite: true,
      );

      expect(meta.localPieceColorName, 'black');
      expect(meta.isOpponentTurn(PlayerSeat.first), isTrue);
      expect(meta.isOpponentTurn(PlayerSeat.second), isFalse);
      expect(meta.isOpponentTurn(PlayerSeat.none), isFalse);
    });
  });
}
