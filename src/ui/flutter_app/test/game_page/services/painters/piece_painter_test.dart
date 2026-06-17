// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/painters/animations/piece_effect_animation.dart';
import 'package:sanmill/game_page/services/painters/painters.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/native_mill_snapshot_board_view.dart';

void main() {
  group('PiecePainter', () {
    test('repaints when native board occupancy changes', () {
      final NativeMillSnapshotBoardView before = _viewWithBlackAtNode(23);
      final NativeMillSnapshotBoardView after = _viewWithBlackAtNode(22);

      final PiecePainter oldPainter = _painterFor(before);
      final PiecePainter newPainter = _painterFor(after);

      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });
  });
}

NativeMillSnapshotBoardView _viewWithBlackAtNode(int node) {
  final Uint8List payload = Uint8List(256);
  payload[node] = 2;
  return NativeMillSnapshotBoardView.fromSnapshot(
    GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: PlayerSeat.first,
      outcome: const GameOutcome.ongoing(),
      payload: <String, Object?>{'tgfPayload': payload},
    ),
  )!;
}

PiecePainter _painterFor(NativeMillSnapshotBoardView view) {
  return PiecePainter(
    placeAnimationValue: 1.0,
    moveAnimationValue: 1.0,
    removeAnimationValue: 1.0,
    pickUpAnimationValue: 1.0,
    putDownAnimationValue: 1.0,
    isPutDownAnimating: false,
    pieceImages: null,
    placeEffectAnimation: RadialPieceEffectAnimation(),
    removeEffectAnimation: ExplodePieceEffectAnimation(),
    nativeBoardView: view,
  );
}
