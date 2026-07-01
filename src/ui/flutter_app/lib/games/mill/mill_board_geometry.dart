// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/widgets.dart';

import 'mill_board_coordinate_maps.dart';

/// Shared Mill board geometry helpers for widgets that render or hit-test the
/// 24 node board without going through the legacy `GameController` painter.
abstract final class MillBoardGeometry {
  static const int nodeCount = 24;
  static const double defaultPaddingFraction = 0.08;
  static const double defaultHitRadiusCellFraction = 0.43;

  static Offset nodeOffset(
    int node,
    Size size, {
    double paddingFraction = defaultPaddingFraction,
  }) {
    final int? square = MillBoardCoordinateMaps.nodeToLegacySquare[node];
    assert(square != null, 'Mill node must map to a legacy square.');
    final int? gridIndex = MillBoardCoordinateMaps.squareToGridIndex[square];
    assert(gridIndex != null, 'Mill square must map to a legacy grid index.');

    final double side = size.shortestSide;
    final double padding = side * paddingFraction;
    final double cell = (side - padding * 2) / 6;
    final int column = gridIndex! % 7;
    final int row = gridIndex ~/ 7;
    final double dx = (size.width - side) / 2 + padding + column * cell;
    final double dy = (size.height - side) / 2 + padding + row * cell;
    return Offset(dx, dy);
  }

  static int nodeFromPosition(
    Offset position,
    Size size, {
    double paddingFraction = defaultPaddingFraction,
    double hitRadiusCellFraction = defaultHitRadiusCellFraction,
  }) {
    final double side = size.shortestSide;
    final double padding = side * paddingFraction;
    final double cell = (side - padding * 2) / 6;
    final double hitRadius = cell * hitRadiusCellFraction;
    final double hitRadiusSquared = hitRadius * hitRadius;
    int closestNode = -1;
    double closestDistanceSquared = double.infinity;

    for (int node = 0; node < nodeCount; node++) {
      final Offset center = nodeOffset(
        node,
        size,
        paddingFraction: paddingFraction,
      );
      final double dx = position.dx - center.dx;
      final double dy = position.dy - center.dy;
      final double distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < closestDistanceSquared) {
        closestDistanceSquared = distanceSquared;
        closestNode = node;
      }
    }

    if (closestDistanceSquared <= hitRadiusSquared) {
      return closestNode;
    }
    return -1;
  }
}
