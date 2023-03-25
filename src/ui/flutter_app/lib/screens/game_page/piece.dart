// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

part of 'game_page.dart';

class Piece extends StatefulWidget {
  const Piece({
    super.key,
    required this.color,
    this.diameter = 30.0,
    this.animated = false,
  });
  final PieceColor color;
  final double diameter;
  final bool animated;

  @override
  PieceState createState() => PieceState();

  void paint(Canvas canvas, Size size) {
    final _PiecePainter painter = _PiecePainter(piece: this);
    painter.paint(canvas, size);
  }
}

class PieceState extends State<Piece> {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.diameter, widget.diameter),
      painter: _PiecePainter(piece: widget),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({required this.piece});
  final Piece piece;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final double pieceWidth = size.width;

    // Draw the piece
    paint.color = piece.color.pieceColor;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      piece.animated ? pieceWidth * 0.99 / 2 : pieceWidth / 2,
      paint,
    );

    // Draw Border of Piece
    paint.color = piece.color.borderColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      pieceWidth / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(_PiecePainter oldDelegate) =>
      piece.color != oldDelegate.piece.color ||
      piece.animated != oldDelegate.piece.animated;
}
