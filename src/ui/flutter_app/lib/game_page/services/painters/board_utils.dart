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
  return offsetFromPoint(Offset(column, row), size);
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
Offset pointFromOffset(Offset offset, double dimension) {
  final Offset point = (offset - Offset(boardMargin, boardMargin)) /
      ((dimension - boardMargin * 2) / 6);

  return point.round();
}

/// Calculates the offset for the given position
Offset offsetFromPoint(Offset point, Size size) =>
    (point * (size.width - boardMargin * 2) / 6) +
    Offset(boardMargin, boardMargin);

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
