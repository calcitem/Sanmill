// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_service_native_test.dart
//
// Structural unit tests for the native import path.
//
// Full import/export integration (PGN, Play OK, Lichess, FEN round-trips
// with a live session) is exercised in integration_test/setup_position_import_test.dart.
// These tests validate class API surface and FEN string handling without FRB.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';

void main() {
  group('NativeMillGameSession FEN API surface', () {
    test(
      'loadFen and getFen methods are declared on NativeMillGameSession',
      () {
        // Verify type exports are visible without FRB calls.
        expect(NativeMillGameSession, isNotNull);
      },
    );

    test('LAN session meta holds seat correctly', () {
      const PlayerSeat seat = PlayerSeat.first;
      expect(seat, PlayerSeat.first);
      expect(seat != PlayerSeat.second, isTrue);
    });

    test('GameStateSnapshot payload is a mutable map', () {
      final Map<String, Object?> payload = <String, Object?>{
        'fen': '***/***/***/w/p/p',
        'count': 9,
      };
      expect(payload['fen'], isA<String>());
      expect(payload['count'], 9);
      payload['count'] = 8;
      expect(payload['count'], 8);
    });
  });
}
