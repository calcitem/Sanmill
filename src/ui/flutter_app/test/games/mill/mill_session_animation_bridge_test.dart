// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/mill_board_coordinate_maps.dart';
import 'package:sanmill/games/mill/mill_session_animation_bridge.dart';
import 'package:sanmill/games/mill/mill_types.dart';

void main() {
  group('MillSessionAnimationBridge.gridIndexForNode', () {
    test('maps board nodes to legacy 7x7 grid indices', () {
      // node -> legacy square -> grid index (see MillBoardCoordinateMaps).
      expect(MillSessionAnimationBridge.gridIndexForNode(0), 0); // sq 31
      expect(MillSessionAnimationBridge.gridIndexForNode(1), 3); // sq 24
      expect(MillSessionAnimationBridge.gridIndexForNode(16), 16); // sq 15
    });

    test('returns null for missing or out-of-range nodes', () {
      expect(MillSessionAnimationBridge.gridIndexForNode(null), isNull);
      expect(MillSessionAnimationBridge.gridIndexForNode(-1), isNull);
      expect(MillSessionAnimationBridge.gridIndexForNode(24), isNull);
    });
  });

  group('MillSessionAnimationBridge.formedMillAt', () {
    Uint8List occupancyWith(Map<int, int> pieces) {
      final Uint8List occ = Uint8List(24);
      pieces.forEach((int node, int color) => occ[node] = color);
      return occ;
    }

    test('detects a completed standard mill through the destination', () {
      final Uint8List occ = occupancyWith(<int, int>{0: 1, 1: 1, 2: 1});
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: occ,
          toNode: 2,
          moverByte: 1,
          hasDiagonalLines: false,
        ),
        isTrue,
      );
    });

    test('returns false when no line through the destination is complete', () {
      final Uint8List occ = occupancyWith(<int, int>{0: 1, 2: 1});
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: occ,
          toNode: 2,
          moverByte: 1,
          hasDiagonalLines: false,
        ),
        isFalse,
      );
    });

    test('returns false when the destination is not the mover colour', () {
      final Uint8List occ = occupancyWith(<int, int>{0: 1, 1: 1, 2: 1});
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: occ,
          toNode: 2,
          moverByte: 2,
          hasDiagonalLines: false,
        ),
        isFalse,
      );
    });

    test('diagonal lines only count when the rule is enabled', () {
      // Nodes 0, 8, 16 form a diagonal mill in the standard topology.
      final Uint8List occ = occupancyWith(<int, int>{0: 1, 8: 1, 16: 1});
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: occ,
          toNode: 16,
          moverByte: 1,
          hasDiagonalLines: false,
        ),
        isFalse,
      );
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: occ,
          toNode: 16,
          moverByte: 1,
          hasDiagonalLines: true,
        ),
        isTrue,
      );
    });

    test('guards against short occupancy buffers', () {
      expect(
        MillSessionAnimationBridge.formedMillAt(
          occupancy: Uint8List(10),
          toNode: 2,
          moverByte: 1,
          hasDiagonalLines: false,
        ),
        isFalse,
      );
    });

    // Sanity: every node referenced in the diagonal mill lines maps to a
    // valid grid index, so animation highlights never target a missing cell.
    test('placementTriggeredCaptureRemoval reads pending removal bytes', () {
      final Uint8List payload = Uint8List(30);
      payload[28] = 2;
      expect(
        MillSessionAnimationBridge.placementTriggeredCaptureRemoval(
          payload: payload,
          mover: PieceColor.white,
        ),
        isTrue,
      );
      expect(
        MillSessionAnimationBridge.placementTriggeredCaptureRemoval(
          payload: payload,
          mover: PieceColor.black,
        ),
        isFalse,
      );
    });

    test('all diagonal mill-line nodes map to grid indices', () {
      for (final List<int> line
          in MillBoardCoordinateMaps.diagonalMillNodeLines) {
        for (final int node in line) {
          expect(
            MillSessionAnimationBridge.gridIndexForNode(node),
            isNotNull,
            reason: 'node $node should map to a grid index',
          );
        }
      }
    });
  });
}
