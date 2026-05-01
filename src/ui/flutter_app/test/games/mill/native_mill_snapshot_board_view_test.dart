// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';

void main() {
  group('NativeMillSnapshotBoardView', () {
    test('returns null when snapshot has no native payload', () {
      const GameStateSnapshot snapshot = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: PlayerSeat.first,
        outcome: GameOutcome.ongoing(),
      );

      expect(NativeMillSnapshotBoardView.fromSnapshot(snapshot), isNull);
    });

    test('decodes first and second player occupancy from opaque payload', () {
      final Uint8List payload = Uint8List(256);
      payload[0] = 1;
      payload[23] = 2;
      final NativeMillSnapshotBoardView view =
          NativeMillSnapshotBoardView.fromSnapshot(
            GameStateSnapshot(
              gameId: GameId.mill,
              activeSeat: PlayerSeat.first,
              outcome: const GameOutcome.ongoing(),
              payload: <String, Object?>{'tgfPayload': payload},
            ),
          )!;

      expect(view.pieceAtNode(0), PlayerSeat.first);
      expect(view.pieceAtNode(23), PlayerSeat.second);
      expect(view.pieceAtLegacySquare(31), PlayerSeat.first);
      expect(view.pieceAtLegacySquare(14), PlayerSeat.second);
      expect(view.pieceAtLegacyGridIndex(0), PlayerSeat.first);
      expect(view.pieceAtLegacyGridIndex(23), PlayerSeat.second);
      expect(view.pieceAtLegacyGridIndex(24), isNull);
      expect(view.pieceAtLegacySquare(0), isNull);
      expect(view.pieceAtNode(8), isNull);
      expect(view.pieceAtNode(-1), isNull);
      expect(view.pieceAtNode(24), isNull);
      expect(view.occupiedNodes(), <int, PlayerSeat>{
        0: PlayerSeat.first,
        23: PlayerSeat.second,
      });
    });

    test('decodes delayed marked nodes from opaque payload', () {
      final Uint8List payload = Uint8List(256);
      // MillState::encode stores delayed_marked_pieces at 39..43.
      payload[39] = (1 << 2) | (1 << 7);

      final NativeMillSnapshotBoardView view =
          NativeMillSnapshotBoardView.fromSnapshot(
            GameStateSnapshot(
              gameId: GameId.mill,
              activeSeat: PlayerSeat.first,
              outcome: const GameOutcome.ongoing(),
              payload: <String, Object?>{'tgfPayload': payload},
            ),
          )!;

      expect(view.markedNodes, <int>{2, 7});
      expect(view.isMarkedLegacySquare(25), isTrue);
      expect(view.isMarkedLegacySquare(30), isTrue);
      expect(view.isMarkedLegacySquare(31), isFalse);
      expect(view.isMarkedLegacyGridIndex(6), isTrue);
      expect(view.isMarkedLegacyGridIndex(21), isTrue);
      expect(view.isMarkedLegacyGridIndex(0), isFalse);
    });
  });
}
