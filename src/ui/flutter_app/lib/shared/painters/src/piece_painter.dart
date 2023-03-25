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

part of '../painters.dart';

@immutable
class PiecePaintParam {
  const PiecePaintParam({
    required this.piece,
    required this.pos,
    required this.animated,
    required this.diameter,
  });

  final Piece piece;
  final Offset pos;
  final bool animated;
  final double diameter;
}

class PiecePainter extends StatefulWidget {
  const PiecePainter({super.key});

  @override
  PiecePainterState createState() => PiecePainterState();
}

class PiecePainterState extends State<PiecePainter>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _animation;

  @override
  void initState() {
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _animation = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(_animationController);

    _animationController.addListener(() {
      setState(() {});
    });

    super.initState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiecePainting(animation: _animation),
    );
  }
}

class _PiecePainting extends CustomPainter {
  _PiecePainting({required this.animation});

  final Animation<Offset> animation;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width == size.height);
    final int? focusIndex = MillController().gameInstance.focusIndex;
    final int? blurIndex = MillController().gameInstance.blurIndex;

    final Path shadowPath = Path();
    final List<PiecePaintParam> piecesToDraw = <PiecePaintParam>[];

    final double pieceWidth = (size.width - AppTheme.boardPadding * 2) *
            DB().displaySettings.pieceWidth /
            6 -
        1;
    final double animatedPieceWidth = pieceWidth * animation.value.distance;

    // Draw pieces on board
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 7; col++) {
        final int index = row * 7 + col;

        final PieceColor pieceColor = MillController()
            .position
            .pieceOnGrid(index); // No Pieces when initial

        if (pieceColor == PieceColor.none) {
          continue;
        }

        final Offset pos = pointFromIndex(index, size);
        final bool animated = focusIndex == index;

        piecesToDraw.add(
          PiecePaintParam(
            piece: Piece(
              color: pieceColor,
              position: pos,
            ),
            pos: animated ? pos + animation.value : pos,
            animated: animated,
            diameter: pieceWidth,
          ),
        );

        shadowPath.addOval(
          Rect.fromCircle(
            center: pos,
            radius: (animated ? animatedPieceWidth : pieceWidth) / 2,
          ),
        );
      }
    }

    // Draw shadow of piece
    canvas.drawShadow(shadowPath, Colors.black, 2, true);

    // Draw the pieces
    for (final PiecePaintParam pieceParam in piecesToDraw) {
      final Piece pieceWidget = pieceParam.piece;

      final double pieceDiameter = pieceParam.animated
          ? pieceParam.diameter * animation.value.distance
          : pieceParam.diameter;

      canvas.save();
      canvas.translate(pieceParam.pos.dx - pieceDiameter / 2,
          pieceParam.pos.dy - pieceDiameter / 2);
      pieceWidget.paint(canvas, Size(pieceDiameter, pieceDiameter));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
