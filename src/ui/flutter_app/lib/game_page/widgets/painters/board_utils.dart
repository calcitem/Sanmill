// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

part of '../../../game_page/widgets/painters/painters.dart';

/// The names of the rows
const List<String> verticalNotations = <String>[
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g'
];

/// The names of the columns
const List<String> horizontalNotations = <String>[
  '7',
  '6',
  '5',
  '4',
  '3',
  '2',
  '1'
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
