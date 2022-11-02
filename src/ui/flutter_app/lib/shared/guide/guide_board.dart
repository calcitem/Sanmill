import 'package:flutter/material.dart';

import '../../services/mill/mill.dart';
import '../painters/painters.dart';
import 'guide_painter.dart';

class GuideBoard extends StatelessWidget {
  const GuideBoard({
    super.key,
    required this.pieceList,
    this.focusIndex,
    this.blurIndex,
  });

  final int? focusIndex;
  final int? blurIndex;
  final List<PieceColor> pieceList;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constrains) {
        final double dimension = constrains.maxWidth;

        return SizedBox.square(
          dimension: dimension,
          child: CustomPaint(
            painter: BoardPainter(),
            foregroundPainter: GuidePainter(
              focusIndex: focusIndex,
              blurIndex: blurIndex,
              pieceList: pieceList,
            ),
          ),
        );
      },
    );
  }
}
