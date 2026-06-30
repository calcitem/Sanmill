// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/services/transform/transform.dart';

void main() {
  group('GameRecorder.transformCoordinates', () {
    test('transforms setup FEN, moves, and board layouts together', () {
      const String setupFen =
          '********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes';
      const String afterWhite = 'O*******/********/********';
      const String afterBlack = 'O*******/********/@*******';
      final GameRecorder recorder = GameRecorder(
        setupPosition: setupFen,
        lastPositionWithRemove: setupFen,
      );

      recorder.appendMove(
        ExtMove('a7', side: PieceColor.white, boardLayout: afterWhite),
      );
      recorder.appendMove(
        ExtMove('d7', side: PieceColor.black, boardLayout: afterBlack),
      );

      recorder.transformCoordinates(TransformationType.rotate90);

      expect(
        recorder.setupPosition,
        transformFEN(setupFen, TransformationType.rotate90),
      );
      expect(
        recorder.lastPositionWithRemove,
        transformFEN(setupFen, TransformationType.rotate90),
      );
      expect(
        recorder.mainlineMoves[0].move,
        transformMoveNotation('a7', TransformationType.rotate90),
      );
      expect(
        recorder.mainlineMoves[0].boardLayout,
        transformFEN(afterWhite, TransformationType.rotate90),
      );
      expect(
        recorder.mainlineMoves[1].move,
        transformMoveNotation('d7', TransformationType.rotate90),
      );
      expect(
        recorder.mainlineMoves[1].boardLayout,
        transformFEN(afterBlack, TransformationType.rotate90),
      );
    });
  });
}
