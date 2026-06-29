// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_board_geometry.dart';

void main() {
  group('MillBoardGeometry', () {
    test('maps every node center back to the same node', () {
      const Size boardSize = Size.square(320);

      for (int node = 0; node < MillBoardGeometry.nodeCount; node++) {
        final Offset center = MillBoardGeometry.nodeOffset(node, boardSize);

        expect(MillBoardGeometry.nodeFromPosition(center, boardSize), node);
      }
    });

    test('does not treat the board center as a legal node', () {
      const Size boardSize = Size.square(320);

      expect(
        MillBoardGeometry.nodeFromPosition(const Offset(160, 160), boardSize),
        -1,
      );
    });
  });
}
