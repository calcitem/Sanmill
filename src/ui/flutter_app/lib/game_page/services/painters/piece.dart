// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// piece.dart

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
