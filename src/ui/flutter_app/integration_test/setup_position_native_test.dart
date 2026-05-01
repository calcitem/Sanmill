// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// setup_position_native_test.dart
//
// Integration tests for the native session setup-position editing API.
// These complement the legacy FEN-based setup_position_fen_test.dart by
// exercising the Rust kernel setup path end-to-end through
// NativeMillGameSession.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  group('NativeMillGameSession setup-position API', () {
    testWidgets('setupClear resets board to empty placing state', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      // Initial placing phase has 24 legal placements.
      expect(session.legalActions, hasLength(24));

      session.setupClear();
      // After clear the session re-enters placing phase with empty board.
      expect(session.state.value.phase, 'placing');
      // Legal actions are restored to the full 24-node set.
      expect(session.legalActions, hasLength(24));
    });

    testWidgets('setupSetPiece places and clears single squares', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      session.setupClear();

      // Place White (owner=1) on node 0.
      session.setupSetPiece(0, 1);
      // The snapshot reflects the pending edit (phase stays 'placing').
      expect(session.state.value.phase, 'placing');

      // Clear node 0 (owner=0 means clear).
      session.setupSetPiece(0, 0);
      // Board is empty again, snapshot unchanged in phase.
      expect(session.state.value.phase, 'placing');
    });

    testWidgets('setupFinish transitions to moving phase when board is full', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      session.setupClear();

      // Place 9 White and 9 Black pieces (a full 18-piece moving-phase board).
      const List<int> whiteNodes = <int>[0, 1, 2, 8, 9, 10, 16, 17, 18];
      const List<int> blackNodes = <int>[3, 4, 5, 11, 12, 13, 19, 20, 21];
      for (final int n in whiteNodes) {
        session.setupSetPiece(n, 1);
      }
      for (final int n in blackNodes) {
        session.setupSetPiece(n, 2);
      }

      session.setupSetSide(0); // White to move.
      session.setupFinish();

      // All pieces on board → moving phase.
      expect(session.state.value.phase, 'moving');
      expect(session.state.value.activeSeat, PlayerSeat.first);
      // Legal actions are the valid moves for the loaded board.
      expect(session.legalActions, isNotEmpty);
    });

    testWidgets('setupSetSide chooses active seat after setupFinish', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      session.setupClear();
      session.setupSetPiece(0, 1);
      session.setupSetPiece(3, 2);
      session.setupSetSide(1); // Black to move.
      session.setupFinish();

      expect(session.state.value.activeSeat, PlayerSeat.second);
    });

    testWidgets('loadFen populates board from FEN and returns true', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      // Standard 9MM start FEN (all pieces in hand, placing phase).
      const String startFen =
          '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1';
      final bool loaded = session.loadFen(startFen);
      expect(loaded, isTrue);
      expect(session.state.value.phase, 'placing');
      expect(session.legalActions, hasLength(24));
    });

    testWidgets('loadFen returns false for invalid FEN', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      final bool loaded = session.loadFen('not-a-valid-fen');
      expect(loaded, isFalse);
      // State must not be corrupted by a failed load.
      expect(session.state.value.phase, 'placing');
    });

    testWidgets('setup round-trip: clear → set pieces → finish → undo', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      session.setupClear();
      session.setupSetPiece(0, 1); // White
      session.setupSetPiece(6, 2); // Black
      session.setupSetSide(0); // White to move
      session.setupFinish();

      // Placing phase: both players still have pieces in hand.
      expect(session.state.value.phase, 'placing');
      expect(session.state.value.activeSeat, PlayerSeat.first);
      expect(session.legalActions, isNotEmpty);

      // Applying and undoing one legal action must be symmetric.
      final GameAction first = session.legalActions.first;
      await session.apply(first);
      expect(session.state.value.activeSeat, PlayerSeat.second);

      await session.undo();
      expect(session.state.value.activeSeat, PlayerSeat.first);
    });
  });
}
