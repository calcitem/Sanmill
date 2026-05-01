// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// experience_replay_native_test.dart
//
// Integration tests for native-session-based move replay.
//
// These tests exercise the NativeMillGameSession.replayMainline helper,
// which is the core of the history-navigation and experience-replay
// replay paths when useNativeMillSession is true.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanmill/game_page/services/mill.dart' show ExtMove, PieceColor;
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_action_codec.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  group('NativeMillGameSession replay', () {
    testWidgets('replayMainline reconstructs placing-phase position', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      expect(session.legalActions, hasLength(24));

      // Record two placing moves (first two legal actions).
      final List<GameAction> actions = <GameAction>[
        session.legalActions[0],
        session.legalActions[1], // after White places, it's Black's turn
      ];
      final List<String> moveStrings = actions
          .map((GameAction a) => MillActionCodec.moveStringFrom(a) ?? '')
          .toList();

      // Apply both moves.
      await session.apply(actions[0]);
      await session.apply(actions[1]);

      // Capture the snapshot after both moves.
      final GameStateSnapshot snapshotAfterPlay = session.state.value;

      // Now replay from scratch using ExtMove list.
      final List<ExtMove> extMoves = <ExtMove>[
        ExtMove(moveStrings[0], side: PieceColor.white),
        ExtMove(moveStrings[1], side: PieceColor.black),
      ];
      final bool success = await session.replayMainline(extMoves);
      expect(success, isTrue);

      final GameStateSnapshot snapshotAfterReplay = session.state.value;
      // After replay we should be at the same position.
      expect(
        snapshotAfterReplay.activeSeat,
        snapshotAfterPlay.activeSeat,
        reason: 'active seat must match after replay',
      );
      expect(
        snapshotAfterReplay.phase,
        snapshotAfterPlay.phase,
        reason: 'phase must match after replay',
      );
      // The Zobrist key distinguishes position uniquely.
      expect(
        snapshotAfterReplay.payload['tgfZobrist'],
        snapshotAfterPlay.payload['tgfZobrist'],
        reason: 'Zobrist key must match after replay',
      );
    });

    testWidgets('replayMainline from empty list undoes all moves', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      final GameStateSnapshot initial = session.state.value;
      expect(session.legalActions, hasLength(24));

      await session.apply(session.legalActions[0]);
      expect(session.undoDepth, 1);

      // Replay with zero moves — should return to initial state.
      final bool success = await session.replayMainline(<ExtMove>[]);
      expect(success, isTrue);
      expect(session.undoDepth, 0);
      expect(
        session.state.value.payload['tgfZobrist'],
        initial.payload['tgfZobrist'],
        reason: 'empty replay must restore initial Zobrist',
      );
    });

    testWidgets('setup then replay: FEN load followed by moves round-trips', (
      WidgetTester tester,
    ) async {
      final NativeMillGameSession session = NativeMillGameSession();
      addTearDown(session.dispose);

      // Load a known position via FEN.
      const String startFen =
          '********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1';
      expect(session.loadFen(startFen), isTrue);
      expect(session.state.value.phase, 'placing');

      // Apply one move.
      final GameAction first = session.legalActions.first;
      await session.apply(first);

      // Undo and verify we are back at the loaded state.
      await session.undo();
      expect(session.state.value.phase, 'placing');
      expect(session.legalActions, hasLength(24));

      // The FEN exported from the current state should be valid.
      final String exportedFen = session.getFen();
      expect(exportedFen, isNotEmpty);
      expect(exportedFen, contains(' w '));
    });
  });
}
