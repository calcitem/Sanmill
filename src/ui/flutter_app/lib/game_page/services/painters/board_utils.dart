// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// board_utils.dart

part of '../../../game_page/services/painters/painters.dart';

/// The names of the rows
const List<String> verticalNotations = <String>[
  '7',
  '6',
  '5',
  '4',
  '3',
  '2',
  '1'
];

/// The names of the columns
const List<String> horizontalNotations = <String>[
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g'
];

/// The padding applied to the actual mill field
double get boardMargin => AppTheme.boardPadding;

/// Calculates the position of the given point
Offset pointFromIndex(int index, Size size) {
  final double row = (index ~/ 7).toDouble();
  final double column = index % 7;
  return offsetFromPointWithInnerSize(Offset(column, row), size);
}

/// Calculates the index of the given point
int indexFromPoint(Offset point) {
  return (point.dy * 7 + point.dx).toInt();
}

/// Calculates the square of the given point
int? squareFromPoint(Offset point) {
  return indexToSquare[indexFromPoint(point)];
}

Offset pointFromSquare(int square, Size size) {
  return pointFromIndex(squareToIndex[square]!, size);
}

/// Calculates the pressed point
///
/// Finds the nearest logical board point to the tap position taking the
/// current inner-ring scaling into account. This guarantees correct hit
/// detection even when the inner ring has been resized.
Offset pointFromOffset(Offset offset, double dimension) {
  // Build a square Size as used for painting.
  final Size size = Size(dimension, dimension);

  // One grid unit in canvas coordinates (outer ring reference).
  final double unitDistance = (dimension - boardMargin * 2) / 6;
  // Accept taps roughly within half a unit distance from a point.
  final double threshold = unitDistance * 0.5;

  Offset? nearestPoint;
  double nearestDistance = double.infinity;

  // Iterate over all 24 logical points, compute their canvas position with the
  // same scaling used for painting, then find the closest one.
  for (final Offset gridPt in points) {
    final Offset canvasPt = offsetFromPointWithInnerSize(gridPt, size);
    final double dist = (offset - canvasPt).distance;
    if (dist < nearestDistance) {
      nearestDistance = dist;
      nearestPoint = gridPt;
    }
  }

  // If the tap is too far from any point, return an invalid value (e.g. Offset(-1,-1)).
  if (nearestPoint == null || nearestDistance > threshold) {
    return const Offset(-1, -1);
  }

  // Round to ensure integer grid coordinates.
  return nearestPoint.round();
}

/// Calculates the offset for the given position
Offset offsetFromPoint(Offset point, Size size) =>
    (point * (size.width - boardMargin * 2) / 6) +
    Offset(boardMargin, boardMargin);

/// Calculates the offset for the given position with adjustable inner ring size
/// This function ensures equal distance between outer-middle and middle-inner rings
Offset offsetFromPointWithInnerSize(Offset point, Size size) {
  // Inner ring size factor (distance from center relative to original inner distance which is 1 grid unit).
  // Range: 1.0-1.5 with 0.05 step increments.
  final double innerRingSize = DB().displaySettings.boardInnerRingSize;

  // Center of the board in canvas coordinates.
  final Offset center = Offset(size.width / 2, size.height / 2);
  // One grid distance in canvas units.
  final double unitDistance = (size.width - boardMargin * 2) / 6;

  // Convert board point to canvas position using the default mapping (no scaling).
  final Offset originalPos =
      (point * unitDistance) + Offset(boardMargin, boardMargin);
  final Offset vectorFromCenter = originalPos - center;

  // Determine the ring index in the original 7×7 grid.
  final int ringOriginal = (point.dx - 3).abs().toInt().clamp(0, 3) >
          (point.dy - 3).abs().toInt().clamp(0, 3)
      ? (point.dx - 3).abs().toInt()
      : (point.dy - 3).abs().toInt();
  // ringOriginal will be 0 (center), 1 (inner), 2 (middle) or 3 (outer).
  if (ringOriginal == 0) {
    // Center point (should not occur for valid board points) – return as-is.
    return originalPos;
  }

  // Target radial lengths (in grid units) after scaling.
  const double targetOuter = 3.0; // keep outer ring unchanged
  final double targetInner = innerRingSize; // user-defined (1.0-1.5)
  final double targetMiddle =
      (targetOuter + targetInner) / 2.0; // ensure equal spacing

  double targetLen;
  switch (ringOriginal) {
    case 1:
      targetLen = targetInner;
      break;
    case 2:
      targetLen = targetMiddle;
      break;
    case 3:
    default:
      targetLen = targetOuter;
      break;
  }

  // Compute scale factor to convert original vector length (ringOriginal) to targetLen.
  final double scaleFactor = targetLen / ringOriginal;
  final Offset scaledVector = vectorFromCenter * scaleFactor;

  return center + scaledVector;
}

Offset offsetFromPoint2(Offset point, Size size) =>
    (point * (size.width - boardMargin * 2) / 6) +
    Offset(boardMargin, boardMargin);

double offsetFromInt(int point, Size size) =>
    (point * (size.width - boardMargin * 2) / 6) + boardMargin;

/// List of points on the board.
const List<Offset> points = <Offset>[
  // ignore: use_named_constants
  Offset(0, 0), // 0
  Offset(0, 3), // 1
  Offset(0, 6), // 2
  Offset(1, 1), // 3
  Offset(1, 3), // 4
  Offset(1, 5), // 5
  Offset(2, 2), // 6
  Offset(2, 3), // 7
  Offset(2, 4), // 8
  Offset(3, 0), // 9
  Offset(3, 1), // 10
  Offset(3, 2), // 11
  Offset(3, 4), // 12
  Offset(3, 5), // 13
  Offset(3, 6), // 14
  Offset(4, 2), // 15
  Offset(4, 3), // 16
  Offset(4, 4), // 17
  Offset(5, 1), // 18
  Offset(5, 3), // 19
  Offset(5, 5), // 20
  Offset(6, 0), // 21
  Offset(6, 3), // 22
  Offset(6, 6), // 23
];

extension _PathExtension on Path {
  void addLine(Offset p1, Offset p2) {
    moveTo(p1.dx, p1.dy);
    lineTo(p2.dx, p2.dy);
  }
}

extension _OffsetExtension on Offset {
  Offset round() => Offset(dx.roundToDouble(), dy.roundToDouble());
}

double deviceWidth(BuildContext context) {
  return MediaQuery.of(context).orientation == Orientation.portrait
      ? MediaQuery.of(context).size.width
      : MediaQuery.of(context).size.height;
}

bool isTablet(BuildContext context) {
  return deviceWidth(context) >= 600;
}

/// Map engine's coordinate notation to board index
int? coordinatesToIndex(int x, int y) {
  // Convert engine coordinates to board index
  // First convert from engine (x,y) to square
  final int square = makeSquare(x, y);

  // Then convert from square to board index
  return squareToIndex[square];
}
