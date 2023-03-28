import 'package:flutter/material.dart';

class PiecePaintStub {
  PiecePaintStub({required this.piece, required this.pos});
  final String piece;
  final Offset pos;
}

class PieceLayoutStub {
  PieceLayoutStub({
    required this.piece,
    required this.diameter,
    required this.selected,
    required this.x,
    required this.y,
    this.rotate = false,
  });
  //
  final String piece;
  final double diameter;
  final bool selected;
  final double x, y;
  final bool rotate;
}
