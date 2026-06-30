// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_setup_position_controller.dart';
import 'package:sanmill/games/mill/mill_types.dart';

void main() {
  group('MillSetupPositionController.placingInHandCounts', () {
    test(
      'white to move mirrors black in-hand for equal placement progress',
      () {
        final ({int white, int black}) counts =
            MillSetupPositionController.placingInHandCounts(
              piecesCount: 9,
              placedCount: 3,
              sideToMove: PieceColor.white,
            );

        expect(counts.white, 6);
        expect(counts.black, 6);
      },
    );

    test('black to move gives white one fewer piece in hand', () {
      final ({int white, int black}) counts =
          MillSetupPositionController.placingInHandCounts(
            piecesCount: 9,
            placedCount: 3,
            sideToMove: PieceColor.black,
          );

      expect(counts.white, 5);
      expect(counts.black, 6);
    });
  });
}
