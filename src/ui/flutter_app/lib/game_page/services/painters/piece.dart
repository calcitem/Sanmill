// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

import 'dart:ui';

import '../mill.dart';

/// Piece Information
///
/// Holds parameters needed to paint each piece.
class Piece {
  const Piece({
    required this.pieceColor,
    required this.pos,
    required this.diameter,
    required this.index,
    this.squareAttribute,
    this.image,
  });

  /// The color of the piece.
  final PieceColor pieceColor;

  /// The position of the piece on the canvas.
  final Offset pos;

  /// The diameter of the piece.
  final double diameter;

  /// The index of the piece.
  final int index;

  final SquareAttribute? squareAttribute;
  final Image? image;
}
