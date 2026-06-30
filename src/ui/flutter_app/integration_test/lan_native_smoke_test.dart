// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// lan_native_smoke_test.dart
//
// Smoke tests for the native LAN session path.
//
// Full over-the-wire LAN testing requires a device pair; this file
// focuses on the session-local behaviour:
//   - LanSessionMeta correctly tracks which seat belongs to this device.
//   - isOpponentTurn follows the session's activeSeat.
//   - NativeMillGameSession exposes the expected legal-action move labels
//     that sendLanMove would serialise for the peer.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/lan_session_meta.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';

import 'init_test_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initRustForIntegrationTest);

  group('LanSessionMeta seat tracking', () {
    test('host with white plays first seat', () {
      final LanSessionMeta meta = LanSessionMeta.fromHost(
        isHost: true,
        hostPlaysWhite: true,
      );
      expect(meta.localSeat, PlayerSeat.first);
      expect(meta.hostPlaysWhite, isTrue);
    });

    test('client with host-white plays second seat', () {
      final LanSessionMeta meta = LanSessionMeta.fromHost(
        isHost: false,
        hostPlaysWhite: true,
      );
      expect(meta.localSeat, PlayerSeat.second);
    });

    test('isOpponentTurn reflects the other seat', () {
      final LanSessionMeta meta = LanSessionMeta.fromHost(
        isHost: true,
        hostPlaysWhite: true,
      );
      // Local is first; opponent turn when active seat is second.
      expect(meta.isOpponentTurn(PlayerSeat.second), isTrue);
      expect(meta.isOpponentTurn(PlayerSeat.first), isFalse);
      expect(meta.isOpponentTurn(PlayerSeat.none), isFalse);
    });

    test('localPieceColorName returns stable string', () {
      final LanSessionMeta host = LanSessionMeta.fromHost(
        isHost: true,
        hostPlaysWhite: true,
      );
      expect(host.localPieceColorName, 'white');

      final LanSessionMeta client = LanSessionMeta.fromHost(
        isHost: false,
        hostPlaysWhite: true,
      );
      expect(client.localPieceColorName, 'black');
    });
  });

  group('NativeMillGameSession LAN move serialisation', () {
    testWidgets(
      'legal actions carry move strings suitable for LAN transmission',
      (WidgetTester tester) async {
        final NativeMillGameSession session = NativeMillGameSession(
          lanMeta: LanSessionMeta.fromHost(isHost: true, hostPlaysWhite: true),
        );
        addTearDown(session.dispose);

        expect(session.lanMeta, isNotNull);
        expect(session.legalActions, hasLength(24));

        // Every legal action must have a non-empty move string.
        for (final GameAction action in session.legalActions) {
          final String? move = MillActionCodec.moveStringFrom(action);
          expect(move, isNotNull);
          expect(move, isNotEmpty);
        }
      },
    );

    testWidgets(
      'applying a move changes activeSeat and isOpponentTurn accordingly',
      (WidgetTester tester) async {
        final LanSessionMeta meta = LanSessionMeta.fromHost(
          isHost: true,
          hostPlaysWhite: true,
        );
        final NativeMillGameSession session = NativeMillGameSession(
          lanMeta: meta,
        );
        addTearDown(session.dispose);

        // Before moving: White (first seat) is to move, not opponent.
        expect(meta.isOpponentTurn(session.state.value.activeSeat), isFalse);

        // Apply the first placing move.
        final GameAction first = session.legalActions.first;
        await session.apply(first);

        // After White's move, Black (second seat) is active → opponent turn.
        expect(meta.isOpponentTurn(session.state.value.activeSeat), isTrue);
      },
    );
  });
}
